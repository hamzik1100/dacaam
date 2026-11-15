import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// A message from DACAAM to the people running it.
///
/// Sent from the Super Admin dashboard to everyone, to one restaurant, or to
/// one person. The app only ever reads them.
@immutable
class AppNotification {
  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.sentAt,
    this.kind = NotificationKind.info,
    this.isRead = false,
  });

  final int id;
  final String title;
  final String body;
  final DateTime sentAt;
  final NotificationKind kind;
  final bool isRead;

  AppNotification copyWith({bool? isRead}) => AppNotification(
    id: id,
    title: title,
    body: body,
    sentAt: sentAt,
    kind: kind,
    isRead: isRead ?? this.isRead,
  );
}

/// How loudly the message asks to be looked at. Drives colour and icon only —
/// nothing about it changes delivery.
enum NotificationKind {
  info('info'),
  warning('warning'),
  urgent('urgent');

  const NotificationKind(this.api);

  final String api;

  static NotificationKind fromApi(String? value) =>
      NotificationKind.values.firstWhere(
        (NotificationKind k) => k.api == value,
        orElse: () => NotificationKind.info,
      );

  Color get color => switch (this) {
    NotificationKind.info => AppColors.info,
    NotificationKind.warning => AppColors.secondary,
    NotificationKind.urgent => AppColors.danger,
  };

  IconData get icon => switch (this) {
    NotificationKind.info => Icons.info_outline_rounded,
    NotificationKind.warning => Icons.warning_amber_rounded,
    NotificationKind.urgent => Icons.priority_high_rounded,
  };
}
