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
import '../../data/models/restaurant.dart';
import '../../redux/app_state.dart';
import '../../redux/effects.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_sheet.dart';
import '../../widgets/buttons.dart';
import '../../widgets/common.dart';
import '../../widgets/food_thumb.dart';
import '../customers/customer_picker_sheet.dart';
import '../customers/customer_profile_screen.dart';
import 'order_edit_sheet.dart';
import 'receipt.dart';

Future<void> showOrderDetailsSheet(BuildContext context, int orderId) {
  return showAppSheet<void>(
    context,
    builder: (BuildContext context) => _OrderDetailsSheet(orderId: orderId),
  );
}

/// Full order record: header, lines, money breakdown, payment, and the audit
/// timeline that answers "who changed what, and why".
class _OrderDetailsSheet extends StatelessWidget {
  const _OrderDetailsSheet({required this.orderId});

  final int orderId;

  @override
  Widget build(BuildContext context) {
    return StoreConnector<AppState, _DetailsVm>(
      converter: (Store<AppState> store) => _DetailsVm.from(store, orderId),
      // The list endpoint omits history, so the sheet asks for the full record
      // as it opens. Until it lands the sheet shows what the list had.
      onInit: (Store<AppState> store) => Effects.loadOrder(store, orderId),
      builder: (BuildContext context, _DetailsVm vm) {
        final RestaurantOrder? o = vm.order;
        if (o == null) return const SizedBox.shrink();

        return AppSheet(
          title: Fmt.orderNo(o.number),
          subtitle: Fmt.dateTime(o.createdAt, context.lang),
          footer: _Actions(vm: vm, order: o),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // Wrap, not Row: with the payment chip there can be four of
              // these, and on a narrow phone in Somali they do not fit on one
              // line — a chip that overflows the edge is a fact nobody reads.
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: <Widget>[
                  StatusChip(
                    label: context.t(o.status.labelKey),
                    color: o.status.color,
                  ),
                  StatusChip(
                    label: context.t(o.type.labelKey),
                    color: o.type.tint,
                    icon: o.type.icon,
                  ),
                  // Completed and unpaid are now separate facts: the kitchen
                  // is finished, the money has not arrived. Shown only when
                  // something is outstanding — a "Paid" chip on every paid
                  // order is noise on the ninety-nine that were.
                  if (!o.paymentStatus.isSettled)
                    StatusChip(
                      label: context.t(o.paymentStatus.labelKey),
                      color: o.paymentStatus.color,
                      icon: Icons.account_balance_wallet_rounded,
                    ),
                  // Only when the order actually has a trail. A chip that is
                  // always there says nothing; one that appears means this
                  // order was touched after it was rung up.
                  if (o.events.isNotEmpty)
                    StatusChip(
                      label:
                          '${context.t('orderHistory')} · ${o.events.length}',
                      color: AppColors.info,
                      icon: Icons.history_rounded,
                    ),
                ],
              ),
              if (o.cancelReason != null) ...<Widget>[
                const SizedBox(height: AppSpacing.md),
                AppCard(
                  elevated: false,
                  color: AppColors.danger.withValues(alpha: 0.08),
                  borderColor: AppColors.danger.withValues(alpha: 0.25),
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Icon(
                        Icons.block_rounded,
                        size: 17,
                        color: AppColors.danger,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              context.t('reason'),
                              style: context.texts.labelSmall,
                            ),
                            Text(
                              o.cancelReason!,
                              style: context.texts.titleSmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),

              // ---- meta ----
              AppCard(
                child: Column(
                  children: <Widget>[
                    if (o.tableLabel != null)
                      DetailRow(
                        label: context.t('table'),
                        value: o.tableLabel!,
                        icon: Icons.table_restaurant_rounded,
                      ),
                    if (o.waiterName.isNotEmpty)
                      DetailRow(
                        label: context.t('waiter'),
                        value: o.waiterName,
                        icon: Icons.badge_rounded,
                      ),
                    if (o.guests > 0)
                      DetailRow(
                        label: context.t('guests'),
                        value: '${o.guests}',
                        icon: Icons.groups_rounded,
                      ),
                    if (o.customerName.isNotEmpty)
                      // Tappable only when there is an account behind the name.
                      // A name typed at the till is just text on a ticket and
                      // has no profile to open; offering the tap anyway would
                      // promise a screen that cannot exist.
                      if (o.customerId != null)
                        InkWell(
                          onTap: () => Navigator.of(context).push<void>(
                            MaterialPageRoute<void>(
                              builder: (_) => CustomerProfileScreen(
                                customerId: o.customerId!,
                              ),
                            ),
                          ),
                          child: DetailRow(
                            label: context.t('customer'),
                            value: '${o.customerName}  ›',
                            icon: Icons.person_rounded,
                          ),
                        )
                      else
                        DetailRow(
                          label: context.t('customer'),
                          value: o.customerName,
                          icon: Icons.person_rounded,
                        ),
                    if (o.customerPhone.isNotEmpty)
                      DetailRow(
                        label: context.t('phone'),
                        value: o.customerPhone,
                        icon: Icons.phone_rounded,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              // ---- lines ----
              SectionHeader(title: context.t('items')),
              ...o.lines.map(
                (OrderLine l) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Row(
                    children: <Widget>[
                      FoodThumb(
                        emoji: l.emoji,
                        imageUrl: l.imageUrl,
                        size: 42,
                        radius: 11,
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Text(l.name, style: context.texts.titleSmall),
                            Text(
                              '${Fmt.number(l.unitPrice)} × ${l.quantity}',
                              style: context.texts.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      Text(
                        Fmt.number(l.total),
                        style: context.texts.titleSmall,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // ---- money ----
              AppCard(
                color: context.palette.muted,
                elevated: false,
                child: Column(
                  children: <Widget>[
                    DetailRow(
                      label: context.t('subtotal'),
                      value: Fmt.money(o.subtotal),
                      dense: true,
                    ),
                    if (o.discount > 0)
                      DetailRow(
                        label: context.t('discount'),
                        value: '- ${Fmt.money(o.discount)}',
                        valueColor: AppColors.danger,
                        dense: true,
                      ),
                    if (o.taxAmount > 0)
                      DetailRow(
                        label: context.t('tax'),
                        value: Fmt.money(o.taxAmount),
                        dense: true,
                      ),
                    if (o.packagingFee > 0)
                      DetailRow(
                        label: context.t('packagingFee'),
                        value: Fmt.money(o.packagingFee),
                        dense: true,
                      ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                      child: DashedDivider(),
                    ),
                    DetailRow(
                      label: context.t('total'),
                      value: Fmt.money(o.total),
                      bold: true,
                      valueColor: AppColors.primary,
                    ),
                  ],
                ),
              ),

              if (o.payments.isNotEmpty) ...<Widget>[
                const SizedBox(height: AppSpacing.lg),
                SectionHeader(title: context.t('payment')),
                ...o.payments.map(
                  (OrderPaymentEntry p) => AppCard(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Row(
                      children: <Widget>[
                        IconBadge(icon: p.method.icon, color: p.method.color),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Text(
                                p.method.label,
                                style: context.texts.titleSmall,
                              ),
                              if (p.reference.isNotEmpty)
                                Text(
                                  p.reference,
                                  style: context.texts.bodySmall,
                                ),
                            ],
                          ),
                        ),
                        Text(
                          Fmt.money(p.amount),
                          style: context.texts.titleSmall,
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              if (o.events.isNotEmpty) ...<Widget>[
                const SizedBox(height: AppSpacing.lg),
                SectionHeader(title: context.t('orderHistory')),
                _Timeline(events: o.events),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Vertical audit timeline. Every entry names the actor; entries that changed
/// a value show old → new plus the reason that was required to make it.
class _Timeline extends StatelessWidget {
  const _Timeline({required this.events});

  final List<OrderEvent> events;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;

    return Column(
      children: List<Widget>.generate(events.length, (int i) {
        final OrderEvent e = events[i];
        final bool last = i == events.length - 1;

        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Column(
                children: <Widget>[
                  Container(
                    width: 10,
                    height: 10,
                    margin: const EdgeInsets.only(top: 5),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: last ? AppColors.primary : palette.border,
                      border: Border.all(
                        color: last ? AppColors.primary : palette.border,
                        width: 2,
                      ),
                    ),
                  ),
                  if (!last)
                    Expanded(child: Container(width: 2, color: palette.border)),
                ],
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(bottom: last ? 0 : AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              context.t(e.labelKey),
                              style: context.texts.titleSmall,
                            ),
                          ),
                          Text(
                            Fmt.time(e.at),
                            style: context.texts.bodySmall?.copyWith(
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${context.t('changedBy')}: ${e.byUser}',
                        style: context.texts.bodySmall?.copyWith(
                          fontSize: 11.5,
                        ),
                      ),
                      if (e.hasDiff) ...<Widget>[
                        const SizedBox(height: AppSpacing.sm),
                        Row(
                          children: <Widget>[
                            if (e.oldValue != null) ...<Widget>[
                              _ValuePill(
                                text: e.oldValue!,
                                color: AppColors.danger,
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                ),
                                child: Icon(
                                  Icons.arrow_forward_rounded,
                                  size: 13,
                                  color: palette.subtext,
                                ),
                              ),
                            ],
                            if (e.newValue != null)
                              Flexible(
                                child: _ValuePill(
                                  text: e.newValue!,
                                  color: AppColors.success,
                                ),
                              ),
                          ],
                        ),
                      ],
                      if (e.reason != null) ...<Widget>[
                        const SizedBox(height: 5),
                        Text(
                          '${context.t('reason')}: ${e.reason}',
                          style: context.texts.bodySmall?.copyWith(
                            fontStyle: FontStyle.italic,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}

class _ValuePill extends StatelessWidget {
  const _ValuePill({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: context.isDark ? 0.20 : 0.10),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Status transitions available on this order, gated by permission.
class _Actions extends StatelessWidget {
  const _Actions({required this.vm, required this.order});

  final _DetailsVm vm;
  final RestaurantOrder order;

  @override
  Widget build(BuildContext context) {
    final bool cancelled = order.status == OrderStatus.cancelled;

    // A completed order still offers Edit and Print. Orders complete the moment
    // they are paid, so gating edit on "still open" hid the button on nearly
    // every order — and a mistake noticed just after payment is exactly the one
    // staff need to fix. Cancelled is the only genuinely finished state.
    //
    // A locked order is the other one: its shift has been counted and signed
    // off, so the server refuses every change. Offering a button that can only
    // fail is worse than not offering it — the reason goes on screen instead.
    if (cancelled || order.isLocked || !vm.canEdit) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (order.isLocked) ...<Widget>[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: context.palette.muted,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.lock_rounded,
                    size: 16,
                    color: context.palette.subtext,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      context.t('shiftClosedLocked'),
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: context.palette.subtext,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          OutlinedButton.icon(
            onPressed: () => _printReceipt(context, order),
            icon: const Icon(Icons.print_rounded, size: 18),
            label: Text(context.t('printReceipt')),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 46),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 50),
            ),
            child: Text(context.t('close')),
          ),
        ],
      );
    }

    if (order.status == OrderStatus.completed) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _edit(context, order.id),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: Text(context.t('editItems')),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 46),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              OutlinedButton(
                onPressed: () => _printReceipt(context, order),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(52, 46),
                  padding: EdgeInsets.zero,
                ),
                child: const Icon(Icons.print_rounded, size: 18),
              ),
            ],
          ),

          // A mistake found after payment is exactly the case that needs
          // voiding. The reason is mandatory, and any money already taken
          // leaves the till as a refund the Accounts screen shows.
          if (vm.canCancel) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              onPressed: () => _cancel(context),
              icon: const Icon(Icons.block_rounded, size: 18),
              label: Text(context.t('cancelOrder')),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 46),
                foregroundColor: AppColors.danger,
                side: const BorderSide(color: AppColors.danger),
              ),
            ),
          ],

          const SizedBox(height: AppSpacing.sm),
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 50),
            ),
            child: Text(context.t('close')),
          ),
        ],
      );
    }

    // One step, not three. The kitchen queue was dropped when orders started
    // completing on payment, so an open order has exactly one place to go.
    // An order still sitting in `preparing` or `ready` from the old flow lands
    // here too and can be finished the same way.
    const OrderStatus next = OrderStatus.completed;
    const String nextKey = 'markCompleted';

    final double outstanding = order.total - vm.paid;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // Money first: an order that is still owed for should not be closed by
        // reflex, and the outstanding figure is the thing staff need to see.
        if (outstanding > 0.001 && vm.canEdit && !order.isLocked) ...<Widget>[
          OutlinedButton.icon(
            onPressed: () => _takePayment(context, vm, outstanding),
            icon: const Icon(Icons.payments_rounded, size: 18),
            label: Text(
              '${context.t('addPayment')}  ·  ${Fmt.money(outstanding)}',
            ),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 46),
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.primary),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        // Editing sits above the status row: changing what was ordered is a
        // correction, not a step forward through the order's life.
        Row(
          children: <Widget>[
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _edit(context, order.id),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: Text(context.t('editItems')),
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 46)),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            // Customers lose receipts, and staff are asked for another copy
            // long after checkout — reprinting must not mean re-ringing.
            OutlinedButton(
              onPressed: () => _printReceipt(context, order),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(52, 46),
                padding: EdgeInsets.zero,
              ),
              child: const Icon(Icons.print_rounded, size: 18),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: <Widget>[
            if (vm.canCancel)
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _cancel(context),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 50),
                    foregroundColor: AppColors.danger,
                    side: const BorderSide(color: AppColors.danger),
                  ),
                  child: Text(context.t('cancelOrder')),
                ),
              ),
            if (vm.canCancel) const SizedBox(width: AppSpacing.md),
            Expanded(
              flex: 2,
              child: GradientButton(
                label: context.t(nextKey),
                height: 50,
                onPressed: () {
                  vm.onStatus(next, null);
                  Navigator.of(context).pop();
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Opens the edit sheet, then asks for the balance if the edit created one.
  ///
  /// Adding two dishes to a paid order leaves it owing money. Before this, the
  /// sheet simply closed and the order sat there `partial` until somebody
  /// noticed — and when they did, nothing recorded how the rest was settled.
  /// Asking straight away is both the natural moment and the only one where
  /// the payment method is still known.
  Future<void> _edit(BuildContext context, int orderId) async {
    await showOrderEditSheet(context, orderId);
    if (!context.mounted) return;

    // Re-read after the edit: the view model captured in this closure predates
    // it and still holds the old total.
    final Store<AppState> store = StoreProvider.of<AppState>(
      context,
      listen: false,
    );
    final _DetailsVm fresh = _DetailsVm.from(store, orderId);
    final RestaurantOrder? order = fresh.order;
    if (order == null) return;

    final double outstanding = order.total - fresh.paid;
    if (outstanding <= 0.001 || !fresh.canEdit || order.isLocked) return;

    // Skip only when the order genuinely went onto the customer's account:
    // there the balance moved to their ledger, and asking for cash would take
    // the money twice.
    //
    // Having a customer attached is not that test. A regular customer who paid
    // cash at the till has their name on the order and nothing on their ledger,
    // and the extra from an edit is owed at the counter exactly like a
    // walk-in's. Keying off the id alone silently skipped every one of them.
    // A till payment against the order is what tells the two apart; a wallet
    // payment does not count, because that money came off the deposit.
    final bool onAccount =
        order.customerId != null &&
        !order.payments.any(
          (OrderPaymentEntry p) => p.method.api != 'wallet',
        );
    if (!onAccount && order.customerId == null) {
      // A walk-in who has not settled. Paying is one answer; naming who is
      // carrying it is the other, and until now only the first existed — which
      // is how an order ends up owed by nobody.
      await _askPayOrAccount(context, fresh, order, outstanding);

      return;
    }

    if (onAccount) {
      // Not silence, and not a payment form either. The extra went onto the
      // customer's account, which is the whole point of a tab — but nothing on
      // screen said so, and "wax baa lagu daray" told the cashier what changed
      // without telling them what it meant for the money. This says where it
      // went and offers the till as the other option.
      await _askAccountOrCash(context, fresh, order, outstanding);

      return;
    }

    await _takePayment(context, fresh, outstanding);
  }

  /// Owing, with nobody named. Take the money, or put it on somebody's tab.
  Future<void> _askPayOrAccount(
    BuildContext context,
    _DetailsVm vm,
    RestaurantOrder order,
    double outstanding,
  ) async {
    final String? choice = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(context.t('balanceOutstanding')),
        content: Text(
          context.tp('balanceOutstandingBody', <String, String>{
            'n': Fmt.money(outstanding),
          }),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, 'account'),
            child: Text(context.t('putOnAccount')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'pay'),
            child: Text(context.t('payNow')),
          ),
        ],
      ),
    );

    if (choice == null || !context.mounted) return;

    if (choice == 'pay') {
      await _takePayment(context, vm, outstanding);

      return;
    }

    await _putOnAccount(context, order);
  }

  /// Picks who carries it, asks why, and moves the balance onto their ledger.
  Future<void> _putOnAccount(BuildContext context, RestaurantOrder order) async {
    final CustomerChoice? picked = await showCustomerPicker(context);
    if (picked == null || picked.isWalkIn || !context.mounted) return;

    final String? reason = await _askReason(context);
    if (reason == null || !context.mounted) return;

    final Store<AppState> store = StoreProvider.of<AppState>(
      context,
      listen: false,
    );
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    try {
      await Effects.attachOrderCustomer(
        store,
        order.id,
        customerId: picked.customer!.id,
        reason: reason,
      );
    } on ApiException catch (e) {
      // The credit limit and closed accounts are both refused server-side, and
      // the cashier needs to hear which.
      messenger.showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: AppColors.danger),
      );
    }
  }

  Future<String?> _askReason(BuildContext context) async {
    final TextEditingController c = TextEditingController();

    final String? out = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(context.t('reason')),
        content: TextField(
          controller: c,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(hintText: context.t('editReasonHint')),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.t('goBack')),
          ),
          FilledButton(
            onPressed: () {
              if (c.text.trim().length < 3) return;
              Navigator.pop(context, c.text.trim());
            },
            child: Text(context.t('save')),
          ),
        ],
      ),
    );

    c.dispose();

    return out;
  }

  /// The extra is on the account. Leave it there, or take it now.
  Future<void> _askAccountOrCash(
    BuildContext context,
    _DetailsVm vm,
    RestaurantOrder order,
    double outstanding,
  ) async {
    final bool? payNow = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(context.t('addedToAccount')),
        content: Text(
          context.tp('addedToAccountBody', <String, String>{
            'n': Fmt.money(outstanding),
            'name': order.customerName.isEmpty
                ? context.t('customer')
                : order.customerName,
          }),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.t('leaveOnAccount')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.t('payNow')),
          ),
        ],
      ),
    );

    if (payNow != true || !context.mounted) return;

    // Safe to take at the till now: a payment against an order that was
    // charged to a customer also posts a repayment on their ledger, so the
    // debt this edit just created comes straight back off.
    await _takePayment(context, vm, outstanding);
  }

  Future<void> _takePayment(
    BuildContext context,
    _DetailsVm vm,
    double outstanding,
  ) async {
    final TextEditingController amount = TextEditingController(
      text: outstanding.toStringAsFixed(0),
    );
    final TextEditingController reference = TextEditingController();
    PaymentMethod method = PaymentMethod.cash;

    final bool? confirmed = await showAppSheet<bool>(
      context,
      builder: (BuildContext sheetContext) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setState) => AppSheet(
          title: context.t('addPayment'),
          subtitle: '${context.t('outstanding')}: ${Fmt.money(outstanding)}',
          footer: GradientButton(
            label: context.t('save'),
            icon: Icons.check_rounded,
            onPressed: () => Navigator.of(context).pop(true),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                context.t('paymentMethod'),
                style: context.texts.titleMedium,
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: StoreProvider.of<AppState>(context, listen: false)
                    .state
                    .accounts
                    .pickable
                    .map((PaymentMethod m) {
                      final bool selected = m == method;

                      return GestureDetector(
                        onTap: () => setState(() => method = m),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                            vertical: AppSpacing.sm + 2,
                          ),
                          decoration: BoxDecoration(
                            color: selected ? m.color : context.palette.card,
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                            border: Border.all(
                              color: selected
                                  ? m.color
                                  : context.palette.border,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Icon(
                                m.icon,
                                size: 15,
                                color: selected ? Colors.white : m.color,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                m.label,
                                style: context.texts.titleSmall?.copyWith(
                                  color: selected
                                      ? Colors.white
                                      : context.palette.subtext,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    })
                    .toList(),
              ),
              const SizedBox(height: AppSpacing.xl),
              TextField(
                controller: amount,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: context.t('amount'),
                  prefixText: '${Fmt.prefix}  ',
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              TextField(
                controller: reference,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: context.t('reference'),
                  hintText: context.t('referenceHint'),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final double value = double.tryParse(amount.text.replaceAll(',', '')) ?? 0;
    final String ref = reference.text.trim();
    amount.dispose();
    reference.dispose();

    if (!(confirmed ?? false) || value <= 0 || !context.mounted) return;

    try {
      await vm.onPayment(method, value, ref);
    } on ApiException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _printReceipt(
    BuildContext context,
    RestaurantOrder order,
  ) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final Store<AppState> store = StoreProvider.of<AppState>(
      context,
      listen: false,
    );
    final Restaurant? restaurant = store.state.restaurant.restaurant;
    if (restaurant == null) return;

    try {
      await Receipt.print(order, restaurant, store.state.settings.language);
    } on Exception catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: AppColors.danger),
      );
    }
  }

  Future<void> _cancel(BuildContext context) async {
    final TextEditingController reason = TextEditingController();
    final String? result = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(context.t('cancelOrder')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(context.t('cancelReasonRequired')),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: reason,
              autofocus: true,
              maxLines: 2,
              decoration: InputDecoration(hintText: context.t('reason')),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.t('cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () {
              // A cancellation without a reason is rejected here and again by
              // the API — the audit log must never contain a blank reason.
              if (reason.text.trim().isEmpty) return;
              Navigator.pop(context, reason.text.trim());
            },
            child: Text(context.t('confirm')),
          ),
        ],
      ),
    );
    reason.dispose();

    if (result != null && context.mounted) {
      vm.onStatus(OrderStatus.cancelled, result);
      Navigator.of(context).pop();
    }
  }
}

// ----------------------------------------------------------------- viewmodel

class _DetailsVm {
  const _DetailsVm({
    required this.order,
    required this.paid,
    required this.canEdit,
    required this.canCancel,
    required this.onStatus,
    required this.onPayment,
  });

  factory _DetailsVm.from(Store<AppState> store, int orderId) {
    final AppState s = store.state;
    final RestaurantOrder? order = s.orders.byId(orderId);

    return _DetailsVm(
      order: order,
      paid: order == null
          ? 0
          : order.payments.fold<double>(
              0,
              (double sum, OrderPaymentEntry p) => sum + p.amount,
            ),
      canEdit: s.auth.can(Permission.ordersEdit),
      canCancel: s.auth.can(Permission.ordersCancel),
      onStatus: (OrderStatus status, String? reason) =>
          Effects.updateOrderStatus(store, orderId, status, reason: reason),
      onPayment: (PaymentMethod method, double amount, String reference) =>
          Effects.addPayment(
            store,
            orderId,
            method: method,
            amount: amount,
            reference: reference,
          ),
    );
  }

  final RestaurantOrder? order;

  /// What has been taken so far — the difference against the total is what the
  /// Add Payment button offers.
  final double paid;
  final bool canEdit;
  final bool canCancel;
  final void Function(OrderStatus, String?) onStatus;
  final Future<void> Function(PaymentMethod, double, String) onPayment;
}
