import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// The handset's end of the push pipe.
///
/// Firebase does one job here: it wakes the app when a message arrives and the
/// app is not running. Everything else — what the message says, who has read
/// it, what the bell shows — is DACAAM's own API and MySQL.
///
/// Three arrival paths, and they are genuinely different:
///
///   - **App closed or backgrounded.** Android itself draws the notification
///     from the `notification` block Firebase delivered. No Dart runs, which is
///     why the title and body are sent by the server rather than composed here.
///   - **App open.** Android draws nothing, on the grounds that the user is
///     already looking at the app. That would mean a message arriving in front
///     of somebody silently, so [_showLocal] draws it.
///   - **Tapped.** Whichever path it came by, the tap hands the payload back so
///     the app can open the right screen.
class PushService {
  PushService._();

  static final PushService instance = PushService._();

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    // Must match the channel_id the server sends, or Android files the message
    // under a default channel the user cannot silence separately.
    'dacaam_messages',
    'DACAAM',
    description: 'Fariimaha DACAAM',
    importance: Importance.high,
  );

  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  bool _started = false;

  /// Whatever token this handset currently holds, or null when push is
  /// unavailable — no Play Services, or permission refused.
  String? token;

  /// Called when a message arrives while the app is running, so the UI can
  /// refresh the bell without waiting for the next poll.
  VoidCallback? onMessage;

  /// Starts Firebase and asks for the notification permission.
  ///
  /// Every failure is caught and swallowed. A handset without Google Play
  /// Services — some Huawei models, some very cheap Androids — cannot do push
  /// at all, and that must degrade to "no notifications" rather than to an app
  /// that will not open.
  Future<void> start() async {
    if (_started) return;
    _started = true;

    try {
      await Firebase.initializeApp();

      // Android 13+ requires this to be granted before anything is shown.
      // Declining is a normal answer, and the in-app list still works.
      await FirebaseMessaging.instance.requestPermission();

      await _local.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );

      await _local
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(_channel);

      token = await FirebaseMessaging.instance.getToken();

      // Android reissues tokens — on reinstall, on restore to a new handset,
      // occasionally on its own. Without this the server would keep pushing at
      // an address that stopped existing.
      FirebaseMessaging.instance.onTokenRefresh.listen((String fresh) {
        token = fresh;
        onTokenChanged?.call(fresh);
      });

      FirebaseMessaging.onMessage.listen(_showLocal);
    } catch (e) {
      debugPrint('[dacaam] push unavailable: $e');
    }
  }

  /// Fired when Android hands out a new token, so it can be re-registered.
  void Function(String token)? onTokenChanged;

  Future<void> _showLocal(RemoteMessage message) async {
    onMessage?.call();

    final RemoteNotification? notification = message.notification;
    if (notification == null) return;

    await _local.show(
      id: notification.hashCode,
      title: notification.title,
      body: notification.body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
    );
  }
}
