import 'package:flutter/foundation.dart';

import '../../data/models/app_notification.dart';

@immutable
class NotificationState {
  const NotificationState({this.messages = const <AppNotification>[]});

  final List<AppNotification> messages;

  int get unread =>
      messages.where((AppNotification n) => !n.isRead).length;

  /// The newest unread message, which is what the banner shows on sign-in.
  /// Null when there is nothing waiting.
  AppNotification? get latestUnread {
    for (final AppNotification n in messages) {
      if (!n.isRead) return n;
    }

    return null;
  }

  NotificationState copyWith({List<AppNotification>? messages}) =>
      NotificationState(messages: messages ?? this.messages);
}