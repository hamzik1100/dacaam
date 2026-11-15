import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:redux/redux.dart';

import '../../core/i18n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/utils/enums.dart';
import '../../core/utils/formatters.dart';
import '../../data/api/api_client.dart';
import '../../data/models/customer.dart';
import '../../redux/actions.dart';
import '../../redux/app_state.dart';
import '../../redux/effects.dart';
import '../../widgets/app_card.dart';
import '../../widgets/skeletons.dart';
import '../../widgets/states.dart';
import '../orders/order_details_sheet.dart';
import 'customer_money_sheet.dart';
import 'customer_sheet.dart';

/// One customer: what they owe, what they may still put on the tab, and every
/// movement that got them there.
///
/// The ledger is shown in full and never edited. A correction appears as a new
/// line, so reading top to bottom explains the balance rather than presenting a
/// number nobody can account for.
class CustomerProfileScreen extends StatelessWidget {
  const CustomerProfileScreen({super.key, required this.customerId});

  final int customerId;

  @override
  Widget build(BuildContext context) {
    return StoreConnector<AppState, _Vm>(
      converter: (Store<AppState> store) => _Vm.from(store, customerId),
      onInit: (Store<AppState> store) =>
          Effects.loadCustomer(store, customerId),
      onDispose: (Store<AppState> store) =>
          store.dispatch(const CustomerProfileCleared()),
      builder: (BuildContext context, _Vm vm) {
        final Customer? c = vm.customer;

        return Scaffold(
          appBar: AppBar(
            title: Text(c?.name ?? context.t('customer')),
            actions: <Widget>[
              if (c != null && vm.canEdit)
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert_rounded),
                  onSelected: (String action) async {
                    if (action == 'edit') {
                      await showCustomerSheet(context, existing: c);
                    } else {
                      await _close(context, vm, c);
                    }
                  },
                  itemBuilder: (BuildContext context) =>
                      <PopupMenuEntry<String>>[
                        PopupMenuItem<String>(
                          value: 'edit',
                          child: Text(context.t('edit')),
                        ),
                        if (vm.canDelete)
                          PopupMenuItem<String>(
                            value: 'close',
                            child: Text(
                              context.t('closeCustomer'),
                              style: const TextStyle(color: AppColors.danger),
                            ),
                          ),
                      ],
                ),
            ],
          ),
          body: c == null
              ? const Padding(
                  padding: EdgeInsets.all(AppSpacing.gutter),
                  child: ListSkeleton(rows: 6),
                )
              : RefreshIndicator(
                  onRefresh: vm.onRefresh,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.gutter,
                      AppSpacing.md,
                      AppSpacing.gutter,
                      AppSpacing.xxxl,
                    ),
                    children: <Widget>[
                      _BalanceCard(customer: c),
                      const SizedBox(height: AppSpacing.md),
                      if (vm.canEdit) _Actions(vm: vm, customer: c),
                      const SizedBox(height: AppSpacing.lg),
                      Text(context.t('ledger'), style: context.texts.titleMedium),
                      const SizedBox(height: AppSpacing.sm),
                      if (c.ledger.isEmpty)
                        EmptyState(
                          icon: Icons.receipt_long_rounded,
                          title: context.t('noLedger'),
                          message: context.t('noLedgerBody'),
                          compact: true,
                        )
                      else
                        ...c.ledger.map(
                          (LedgerEntry e) => _LedgerRow(entry: e),
                        ),
                    ],
                  ),
                ),
        );
      },
    );
  }

  Future<void> _close(BuildContext context, _Vm vm, Customer c) async {
    if (c.balanceOwed != 0) {
      // Two different obstacles, and calling both "debt" was wrong: a customer
      // in credit owes nothing — the restaurant is holding *their* money and
      // has to hand it back before the account can be closed.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            c.isDebtor
                ? context.t('closeCustomerBlocked')
                : context.t('closeCustomerRefund'),
          ),
          backgroundColor: AppColors.danger,
        ),
      );

      return;
    }

    final bool? yes = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(context.t('closeCustomer')),
        content: Text(context.t('closeCustomerConfirm')),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.t('goBack')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.t('confirm')),
          ),
        ],
      ),
    );

    if (yes != true || !context.mounted) return;

    final NavigatorState navigator = Navigator.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    try {
      await vm.onClose();
      navigator.pop();
    } on ApiException catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: AppColors.danger),
      );
    }
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.customer});

  final Customer customer;

  @override
  Widget build(BuildContext context) {
    final bool owing = customer.isDebtor;
    final Color tint = owing
        ? AppColors.danger
        : (customer.wallet > 0 ? AppColors.success : AppColors.info);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            owing
                ? context.t('owesYou')
                : (customer.wallet > 0
                      ? context.t('youHold')
                      : context.t('settled')),
            style: context.texts.labelMedium?.copyWith(
              color: context.palette.subtext,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            Fmt.money(owing ? customer.balanceOwed : customer.wallet),
            style: context.texts.displaySmall?.copyWith(color: tint),
          ),

          const SizedBox(height: AppSpacing.md),
          const Divider(height: 1),
          const SizedBox(height: AppSpacing.md),

          Row(
            children: <Widget>[
              Expanded(
                child: _Stat(
                  label: context.t('creditLimit'),
                  value: Fmt.money(customer.creditLimit),
                ),
              ),
              Expanded(
                child: _Stat(
                  label: context.t('creditAvailable'),
                  value: Fmt.money(customer.creditAvailable),
                  // Nothing left to lend is worth seeing before the till
                  // refuses the next order rather than after.
                  tint: customer.creditAvailable == 0 && customer.creditLimit > 0
                      ? AppColors.danger
                      : null,
                ),
              ),
            ],
          ),

          // Their deposit and their credit are different kinds of money and
          // are kept apart above; this is the one figure that combines them,
          // and it is the only one the till actually tests an order against.
          if (customer.wallet > 0) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            _Stat(
              label: context.t('spendable'),
              value: Fmt.money(customer.spendable),
              tint: AppColors.info,
            ),
          ],

          if (customer.phone.isNotEmpty || customer.address.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            Text(
              <String>[
                customer.phone,
                customer.address,
              ].where((String s) => s.isNotEmpty).join(' · '),
              style: context.texts.bodySmall?.copyWith(
                color: context.palette.subtext,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.tint});

  final String label;
  final String value;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: context.texts.labelSmall?.copyWith(
            color: context.palette.subtext,
          ),
        ),
        const SizedBox(height: 2),
        Text(value, style: context.texts.titleSmall?.copyWith(color: tint)),
      ],
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({required this.vm, required this.customer});

  final _Vm vm;
  final Customer customer;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: _ActionButton(
            icon: Icons.payments_rounded,
            label: context.t('takePayment'),
            tint: AppColors.success,
            // Nothing to repay when nothing is owed.
            onTap: customer.isDebtor
                ? () => showCustomerMoneySheet(
                    context,
                    customer: customer,
                    kind: LedgerKind.payment,
                  )
                : null,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _ActionButton(
            icon: Icons.savings_rounded,
            label: context.t('takeDeposit'),
            tint: AppColors.info,
            onTap: () => showCustomerMoneySheet(
              context,
              customer: customer,
              kind: LedgerKind.deposit,
            ),
          ),
        ),
        if (vm.canAdjust) ...<Widget>[
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: _ActionButton(
              icon: Icons.tune_rounded,
              label: context.t('adjustBalance'),
              tint: AppColors.secondary,
              onTap: () => showCustomerMoneySheet(
                context,
                customer: customer,
                kind: LedgerKind.adjustment,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.tint,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final Color tint;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Color color = onTap == null ? context.palette.subtext : tint;

    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      onTap: onTap,
      child: Column(
        children: <Widget>[
          Icon(icon, size: 20, color: color),
          const SizedBox(height: AppSpacing.xs),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            style: context.texts.labelSmall?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

class _LedgerRow extends StatelessWidget {
  const _LedgerRow({required this.entry});

  final LedgerEntry entry;

  @override
  Widget build(BuildContext context) {
    // Red adds to the debt, green reduces it — the same reading as the balance
    // above, so the two can never look like they disagree.
    final Color tint = entry.increasesDebt
        ? AppColors.danger
        : AppColors.success;

    // A line that came from an order opens it. The two records answer
    // different halves of the same question — the ledger says what it did to
    // the balance, the order says what was actually eaten — and a customer
    // disputing a charge needs the second one.
    final int? orderId = entry.sourceType == 'order' ? entry.sourceId : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        padding: const EdgeInsets.all(AppSpacing.md),
        onTap: orderId == null
            ? null
            : () => showOrderDetailsSheet(context, orderId),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: tint.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Icon(_icon(entry.kind), size: 16, color: tint),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        context.t(entry.kind.labelKey),
                        style: context.texts.titleSmall,
                      ),
                      Text(
                        Fmt.dateTime(entry.at, context.lang),
                        style: context.texts.labelSmall?.copyWith(
                          color: context.palette.subtext,
                        ),
                      ),
                      // For a line that came from a sale: which order, and
                      // whether that order has been paid. "Did I pay for that
                      // one?" is the question a customer actually asks, and
                      // the answer was nowhere on this screen.
                      if (entry.orderPaymentStatus != null) ...<Widget>[
                        const SizedBox(height: 4),
                        _OrderTag(entry: entry),
                      ],
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    Text(
                      '${entry.increasesDebt ? '+' : '−'}${Fmt.money(entry.amount.abs())}',
                      style: context.texts.titleSmall?.copyWith(color: tint),
                    ),
                    // Named, not just signed. This line used to print
                    // `balanceAfter.abs()`, so a deposit of 67,200 and a debt
                    // of 67,200 rendered identically — the one thing the
                    // column exists to tell apart. A bare minus sign would fix
                    // the arithmetic and still read as a typo, so the state is
                    // spelled out.
                    Text(
                      _balanceLabel(context, entry.balanceAfter),
                      style: context.texts.labelSmall?.copyWith(
                        color: context.palette.subtext,
                      ),
                    ),
                  ],
                ),
              ],
            ),

            if (entry.description.isNotEmpty ||
                entry.reason != null ||
                entry.createdBy.isNotEmpty) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              Text(
                <String>[
                  if (entry.description.isNotEmpty) entry.description,
                  if (entry.createdBy.isNotEmpty) entry.createdBy,
                ].join(' · '),
                style: context.texts.bodySmall?.copyWith(
                  color: context.palette.subtext,
                ),
              ),
              // The reason is set apart rather than run into the description:
              // on an adjustment it is the whole justification for the line.
              if (entry.reason != null)
                Text(
                  entry.reason!,
                  style: context.texts.bodySmall?.copyWith(
                    color: AppColors.secondary,
                    fontStyle: FontStyle.italic,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  /// "dayn 12,900" / "jeeb 67,200" / "eber".
  ///
  /// Positive is owed to the restaurant, negative is held for the customer —
  /// the server's convention, said out loud rather than left to a sign the
  /// reader has to remember the meaning of.
  static String _balanceLabel(BuildContext context, double balance) {
    if (balance.abs() < 0.005) return context.t('balanceNil');

    final String word = balance > 0
        ? context.t('balanceDebt')
        : context.t('balanceWallet');

    return '$word ${Fmt.money(balance.abs())}';
  }

  static IconData _icon(LedgerKind kind) => switch (kind) {
    LedgerKind.charge => Icons.restaurant_rounded,
    LedgerKind.payment => Icons.payments_rounded,
    LedgerKind.deposit => Icons.savings_rounded,
    LedgerKind.refund => Icons.undo_rounded,
    LedgerKind.adjustment => Icons.tune_rounded,
  };
}

/// "#1013 · Lama bixin" under a ledger line that came from an order.
///
/// A charge sitting on the account and the order behind it are two different
/// records, and they can legitimately disagree — the debt can be settled at the
/// till later, or the order voided entirely. Showing the order's own state here
/// is what lets a customer point at a line and be answered.
class _OrderTag extends StatelessWidget {
  const _OrderTag({required this.entry});

  final LedgerEntry entry;

  @override
  Widget build(BuildContext context) {
    final PaymentStatus status = entry.orderPaymentStatus!;
    final bool cancelled = entry.orderCancelled;

    final Color tint = cancelled ? context.palette.subtext : status.color;
    final String label = cancelled
        ? context.t('cancelled')
        : context.t(status.labelKey);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (entry.orderNumber != null) ...<Widget>[
          Text(
            Fmt.orderNo(entry.orderNumber!),
            style: context.texts.labelSmall?.copyWith(
              color: context.palette.subtext,
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: tint.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Text(
            label,
            style: context.texts.labelSmall?.copyWith(
              color: tint,
              fontSize: 10,
            ),
          ),
        ),
      ],
    );
  }
}
class _Vm {
  const _Vm({
    required this.customer,
    required this.canEdit,
    required this.canDelete,
    required this.canAdjust,
    required this.onRefresh,
    required this.onClose,
  });

  factory _Vm.from(Store<AppState> store, int id) {
    return _Vm(
      customer: store.state.customers.selected?.id == id
          ? store.state.customers.selected
          : store.state.customers.byId(id),
      canEdit: store.state.auth.can(Permission.customersEdit),
      canDelete: store.state.auth.can(Permission.customersDelete),
      canAdjust: store.state.auth.can(Permission.customersAdjust),
      onRefresh: () => Effects.loadCustomer(store, id),
      onClose: () => Effects.deactivateCustomer(store, id),
    );
  }

  final Customer? customer;
  final bool canEdit;
  final bool canDelete;
  final bool canAdjust;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onClose;
}
