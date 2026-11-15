import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:redux/redux.dart';

import '../../core/i18n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/app_notification.dart';
import '../../redux/app_state.dart';
import '../../redux/effects.dart';
import '../../widgets/app_card.dart';
import '../../widgets/states.dart';

/// Messages from DACAAM, newest first.
///
/// Opening the screen does not mark everything read — a list that clears itself
/// the moment it is glanced at loses the one thing an unread mark is for. Each
/// message is marked when it is opened, and there is a button for the rest.
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return StoreConnector<AppState, _Vm>(
      converter: _Vm.from,
      onInit: (Store<AppState> store) => Effects.loadNotifications(store),
      builder: (BuildContext context, _Vm vm) {
        return Scaffold(
          appBar: AppBar(
            title: Text(context.t('notifications')),
            actions: <Widget>[
              if (vm.unread > 0)
                TextButton(
                  onPressed: vm.onReadAll,
                  child: Text(context.t('markAllRead')),
                ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: vm.onRefresh,
            child: vm.messages.isEmpty
                ? ListView(
                    // A scrollable is needed for pull-to-refresh to work on an
                    // empty list.
                    children: <Widget>[
                      SizedBox(
                        height: MediaQuery.of(context).size.height * 0.6,
                        child: EmptyState(
                          icon: Icons.notifications_none_rounded,
                          title: context.t('noNotifications'),
                          message: context.t('noNotificationsBody'),
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.gutter,
                      AppSpacing.md,
                      AppSpacing.gutter,
                      AppSpacing.xxxl,
                    ),
                    itemCount: vm.messages.length,
                    itemBuilder: (BuildContext context, int i) => _Row(
                      message: vm.messages[i],
                      onTap: () => vm.onRead(vm.messages[i].id),
                    ),
                  ),
          ),
        );
      },
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.message, required this.onTap});

  final AppNotification message;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        onTap: message.isRead ? null : onTap,
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: message.kind.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Icon(message.kind.icon, size: 17, color: message.kind.color),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          message.title,
                          style: context.texts.titleSmall?.copyWith(
                            fontWeight: message.isRead
                                ? FontWeight.w500
                                : FontWeight.w700,
                          ),
                        ),
                      ),
                      // The unread mark, and the tap target that clears it.
                      if (!message.isRead)
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(message.body, style: context.texts.bodySmall),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    Fmt.relative(message.sentAt, context.lang),
                    style: context.texts.labelSmall?.copyWith(
                      color: context.palette.subtext,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Vm {
  const _Vm({
    required this.messages,
    required this.unread,
    required this.onRefresh,
    required this.onRead,
    required this.onReadAll,
  });

  factory _Vm.from(Store<AppState> store) => _Vm(
    messages: store.state.notifications.messages,
    unread: store.state.notifications.unread,
    onRefresh: () => Effects.loadNotifications(store),
    onRead: (int id) => Effects.markNotificationRead(store, id),
    onReadAll: () => Effects.markAllNotificationsRead(store),
  );

  final List<AppNotification> messages;
  final int unread;
  final Future<void> Function() onRefresh;
  final void Function(int id) onRead;
  final VoidCallback onReadAll;
}
