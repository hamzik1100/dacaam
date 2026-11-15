import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:redux/redux.dart';

import '../../core/i18n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/utils/enums.dart';
import '../../core/utils/formatters.dart';
import '../../data/api/api_client.dart';
import '../../data/models/order.dart';
import '../../redux/actions.dart';
import '../../redux/app_state.dart';
import '../../redux/effects.dart';
import '../shell/main_shell.dart';
import '../../widgets/app_card.dart';
import 'convert_draft_sheet.dart';
import '../../widgets/buttons.dart';
import '../../widgets/common.dart';
import '../../widgets/entrance.dart';
import '../../widgets/states.dart';
import '../pos/order_success_screen.dart';

/// Parked orders that have not become sales yet.
///
/// Drafts deliberately stay out of every KPI, report and account balance until
/// checkout completes — that separation is the whole point of the module.
class DraftsScreen extends StatelessWidget {
  const DraftsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return StoreConnector<AppState, _DraftsVm>(
      converter: _DraftsVm.from,
      builder: (BuildContext context, _DraftsVm vm) {
        return Scaffold(
          appBar: AppBar(title: Text(context.t('draftOrders'))),
          body: RefreshIndicator(
            onRefresh: vm.onRefresh,
            color: AppColors.primary,
            child: vm.drafts.isEmpty
                ? Stack(
                    children: <Widget>[
                      // A scrollable is needed for pull-to-refresh to work on
                      // an otherwise empty screen.
                      ListView(),
                      EmptyState(
                        icon: Icons.edit_note_rounded,
                        title: context.t('noDrafts'),
                        message: context.t('noDraftsBody'),
                      ),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(AppSpacing.gutter),
                    itemCount: vm.drafts.length,
                    itemBuilder: (BuildContext context, int i) {
                      final DraftOrder draft = vm.drafts[i];

                      return Entrance(
                        index: i,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.md),
                          child: _DraftCard(
                            draft: draft,
                            canConvert: vm.canConvert,
                            onConvert: () => _convert(context, vm, draft),
                            onCancel: () => _cancel(context, vm, draft),
                            // Only while it is still a draft. Once it has
                            // become an order, or been voided, the server
                            // refuses — and a button that can only fail is
                            // worse than no button.
                            onEdit: draft.status == DraftStatus.draft
                                ? () => _edit(context, vm, draft)
                                : null,
                          ),
                        ),
                      );
                    },
                  ),
          ),
        );
      },
    );
  }

  Future<void> _convert(
    BuildContext context,
    _DraftsVm vm,
    DraftOrder draft,
  ) async {
    final ConvertChoice? choice = await showConvertDraftSheet(context, draft);

    if (choice == null || !context.mounted) return;

    try {
      final RestaurantOrder order = await vm.onConvert(draft.id, choice);
      if (!context.mounted) return;

      Navigator.of(context).push(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => OrderSuccessScreen(order: order),
        ),
      );
    } on ApiException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// Puts the draft back into the cart so it can be changed.
  ///
  /// A customer rings and wants two more of something. The alternative is
  /// cancelling the ticket and keying the whole order again, which is how a
  /// line gets dropped.
  Future<void> _edit(
    BuildContext context,
    _DraftsVm vm,
    DraftOrder draft,
  ) async {
    // The cart may already hold a sale somebody is in the middle of. Loading
    // over it without asking would throw their work away.
    if (vm.cartHasItems) {
      final bool? replace = await showDialog<bool>(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          title: Text(context.t('cartNotEmpty')),
          content: Text(context.t('replaceCartWithDraft')),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.t('goBack')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.t('confirm')),
            ),
          ],
        ),
      );

      if (replace != true || !context.mounted) return;
    }

    vm.onEditDraft(draft);

    // All the way back to the shell, then onto the till tab.
    //
    // A single pop only returned to whatever pushed this screen — usually
    // the More menu — leaving somebody who asked to edit an order looking
    // at a list of settings and wondering what happened.
    if (!context.mounted) return;

    Navigator.of(context).popUntil((Route<dynamic> r) => r.isFirst);
    vm.onGoToPos();
  }

  Future<void> _cancel(
    BuildContext context,
    _DraftsVm vm,
    DraftOrder draft,
  ) async {
    final TextEditingController reason = TextEditingController();

    final String? why = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(context.t('cancelDraftTitle')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('#${draft.code} · ${draft.customerName}'),
            const SizedBox(height: AppSpacing.md),
            Text(
              context.t('cancelDraftBody'),
              style: context.texts.bodySmall?.copyWith(
                color: context.palette.subtext,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: reason,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: context.t('cancelDraftHint'),
              ),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.t('goBack')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            // Refused here and again by the API: §46 rejects a cancellation
            // with no reason, and a blank one in the trail is worse than none.
            onPressed: () {
              if (reason.text.trim().length < 3) return;
              Navigator.pop(context, reason.text.trim());
            },
            child: Text(context.t('cancelOrder')),
          ),
        ],
      ),
    );

    reason.dispose();

    if (why == null || !context.mounted) return;

    try {
      await vm.onCancel(draft.id, why);
    } on ApiException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

class _DraftsVm {
  const _DraftsVm({
    required this.drafts,
    required this.canConvert,
    required this.onRefresh,
    required this.onConvert,
    required this.onCancel,
    required this.cartHasItems,
    required this.onEditDraft,
    required this.onGoToPos,
  });

  factory _DraftsVm.from(Store<AppState> store) {
    return _DraftsVm(
      drafts: store.state.drafts.drafts,
      canConvert: store.state.auth.can(Permission.ordersCreate),
      onRefresh: () => Effects.refreshDrafts(store),
      onConvert: (int id, ConvertChoice c) => Effects.convertDraft(
        store,
        id,
        method: c.method,
        orderType: c.type,
        tableId: c.tableId,
        waiterId: c.waiterId,
      ),
      onCancel: (int id, String reason) =>
          Effects.cancelDraft(store, id, reason),
      cartHasItems: store.state.cart.lines.isNotEmpty,
      onEditDraft: (DraftOrder d) =>
          store.dispatch(DraftLoadedIntoCart(d)),
      onGoToPos: () => store.dispatch(
        TabSelected(
          shellIndexOf(
            'navPos',
            store.state.auth.user?.permissions ?? const <Permission>{},
          ),
        ),
      ),
    );
  }

  final List<DraftOrder> drafts;
  final bool canConvert;
  final Future<void> Function() onRefresh;
  final Future<RestaurantOrder> Function(int, ConvertChoice) onConvert;
  final Future<void> Function(int, String) onCancel;

  /// Whether the cart already holds a sale in progress.
  final bool cartHasItems;

  /// Loads a draft into the cart for editing.
  final void Function(DraftOrder) onEditDraft;

  /// Switches the shell to the till tab.
  final VoidCallback onGoToPos;
}

class _DraftCard extends StatelessWidget {
  const _DraftCard({
    required this.draft,
    required this.canConvert,
    required this.onConvert,
    required this.onCancel,
    this.onEdit,
  });

  final DraftOrder draft;
  final bool canConvert;
  final VoidCallback onConvert;
  final VoidCallback onCancel;

  /// Null once the draft has become an order or been voided.
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                '#${draft.code}',
                style: context.texts.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              StatusChip(
                label: context.t(draft.type.labelKey),
                color: draft.type.tint,
                icon: draft.type.icon,
                dense: true,
              ),
              const Spacer(),
              StatusChip(
                label: context.t(
                  draft.status == DraftStatus.draft
                      ? 'draft'
                      : draft.status.name,
                ),
                color: draft.status.color,
                dense: true,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          DetailRow(
            label: context.t('customer'),
            value: draft.customerName,
            icon: Icons.person_rounded,
            dense: true,
          ),
          if (draft.customerPhone.isNotEmpty)
            DetailRow(
              label: context.t('phone'),
              value: draft.customerPhone,
              icon: Icons.phone_rounded,
              dense: true,
            ),
          if (draft.tableLabel != null)
            DetailRow(
              label: context.t('table'),
              value: draft.tableLabel!,
              icon: Icons.table_restaurant_rounded,
              dense: true,
            ),
          DetailRow(
            label: context.t('waiter'),
            value: draft.waiterName,
            icon: Icons.badge_rounded,
            dense: true,
          ),
          const SizedBox(height: AppSpacing.sm),
          const DashedDivider(),
          const SizedBox(height: AppSpacing.sm),
          ...draft.lines.map(
            (OrderLine l) => Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(
                children: <Widget>[
                  Text(l.emoji, style: const TextStyle(fontSize: 13)),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      '${l.name} × ${l.quantity}',
                      style: context.texts.bodyMedium,
                    ),
                  ),
                  Text(Fmt.number(l.total), style: context.texts.titleSmall),
                ],
              ),
            ),
          ),
          if (draft.packagingApplied) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: <Widget>[
                const Icon(
                  Icons.inventory_2_rounded,
                  size: 13,
                  color: AppColors.secondary,
                ),
                const SizedBox(width: 5),
                Text(
                  context.t('packagingFee'),
                  style: context.texts.bodySmall?.copyWith(
                    color: AppColors.secondary,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Row(
            children: <Widget>[
              // Somali relative times are long ("45 daqiiqo ka hor"); the
              // amount keeps its space and the timestamp gives way.
              Flexible(
                child: Text(
                  Fmt.relative(draft.createdAt, context.lang),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.texts.bodySmall?.copyWith(fontSize: 11),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              const Spacer(),
              Text(
                Fmt.money(draft.subtotal),
                style: context.texts.titleLarge?.copyWith(
                  fontSize: 16,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          // A refused draft explains itself rather than sitting there as a
          // status nobody can account for a week later.
          if (draft.cancelReason != null) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(context.t('reason'), style: context.texts.labelSmall),
                  Text(draft.cancelReason!, style: context.texts.bodyMedium),
                ],
              ),
            ),
          ],

          // Nothing to do with a draft that is finished either way: converted
          // ones became orders, refused ones are closed.
          if (draft.status != DraftStatus.completed &&
              draft.status != DraftStatus.cancelled) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            Row(
              children: <Widget>[
                if (onEdit != null) ...<Widget>[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onEdit,
                      icon: const Icon(Icons.edit_rounded, size: 17),
                      label: Text(
                        context.t('edit'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 44),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                ],
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onCancel,
                    icon: const Icon(Icons.block_rounded, size: 17),
                    label: Text(
                      context.t('cancelOrder'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 44),
                      foregroundColor: AppColors.danger,
                      side: const BorderSide(color: AppColors.danger),
                    ),
                  ),
                ),
              ],
            ),

            // Converting is what happens to almost every draft, so it gets the
            // full width below rather than a third of a row shared with two
            // exceptions.
            if (canConvert) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              GradientButton(
                label: context.t('convert'),
                icon: Icons.check_rounded,
                height: 46,
                onPressed: onConvert,
              ),
            ],
          ],
        ],
      ),
    );
  }
}
