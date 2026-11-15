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
import '../../data/models/dining_table.dart';
import '../../data/models/order.dart';
import '../../data/models/restaurant.dart';
import '../../redux/actions.dart';
import '../../redux/app_state.dart';
import '../management/shift_screen.dart';
import '../../redux/effects.dart';
import '../../redux/states/pos_state.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_sheet.dart';
import '../../widgets/buttons.dart';
import '../../widgets/common.dart';
import '../customers/customer_picker_sheet.dart';
import 'order_success_screen.dart';

/// Two-step checkout: order details, then payment.
///
/// Splitting it keeps each step to one screenful on a phone and lets the
/// Dine In / Takeaway rules (table requirement, packaging fee) resolve before
/// any money is discussed.
Future<void> showCheckoutSheet(BuildContext context) {
  return showAppSheet<void>(
    context,
    builder: (BuildContext context) => const _CheckoutSheet(),
  );
}

class _CheckoutSheet extends StatefulWidget {
  const _CheckoutSheet();

  @override
  State<_CheckoutSheet> createState() => _CheckoutSheetState();
}

class _CheckoutSheetState extends State<_CheckoutSheet> {
  int _step = 0;
  bool _placing = false;
  String? _error;

  final TextEditingController _customerName = TextEditingController();
  final TextEditingController _customerPhone = TextEditingController();
  final TextEditingController _reference = TextEditingController();
  final TextEditingController _discount = TextEditingController();

  @override
  void dispose() {
    _customerName.dispose();
    _customerPhone.dispose();
    _reference.dispose();
    _discount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StoreConnector<AppState, _CheckoutVm>(
      converter: _CheckoutVm.from,
      builder: (BuildContext context, _CheckoutVm vm) {
        final bool isDetails = _step == 0;

        return AppSheet(
          title: isDetails ? context.t('checkout') : context.t('payment'),
          subtitle: isDetails
              ? context.t('orderSummary')
              : Fmt.money(vm.totals.total),
          trailing: isDetails
              ? null
              : IconButton(
                  onPressed: () => setState(() => _step = 0),
                  icon: const Icon(Icons.arrow_back_rounded, size: 20),
                  style: IconButton.styleFrom(
                    backgroundColor: context.palette.muted,
                    minimumSize: const Size(38, 38),
                  ),
                ),
          footer: isDetails
              ? GradientButton(
                  label: context.t('payment'),
                  icon: Icons.arrow_forward_rounded,
                  onPressed: () => _goToPayment(vm),
                )
              : GradientButton(
                  label: context.t('placeOrder'),
                  icon: Icons.check_rounded,
                  loading: _placing,
                  onPressed: () => _place(vm),
                  trailing: Text(
                    Fmt.money(vm.totals.total),
                    style: context.texts.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
          child: isDetails ? _detailsStep(vm) : _paymentStep(vm),
        );
      },
    );
  }

  // ------------------------------------------------------------- step one

  Widget _detailsStep(_CheckoutVm vm) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(context.t('orderType'), style: context.texts.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: OrderType.values.map((OrderType type) {
            final bool selected = vm.orderType == type;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  right: type == OrderType.dineIn ? AppSpacing.md : 0,
                ),
                child: _TypeCard(
                  type: type,
                  selected: selected,
                  onTap: () {
                    setState(() => _error = null);
                    vm.onOrderType(type);
                  },
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: AppSpacing.xl),

        if (vm.orderType == OrderType.dineIn) ...<Widget>[
          Row(
            children: <Widget>[
              Text(context.t('table'), style: context.texts.titleMedium),
              if (vm.requireTable)
                Text(
                  ' *',
                  style: context.texts.titleMedium?.copyWith(
                    color: AppColors.danger,
                  ),
                )
              else
                Text(
                  '  ${context.t('optional')}',
                  style: context.texts.bodySmall,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          _TableGrid(
            tables: vm.tables,
            selectedId: vm.tableId,
            onSelected: (int id) {
              setState(() => _error = null);
              vm.onTable(vm.tableId == id ? null : id);
            },
          ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: <Widget>[
                const Icon(
                  Icons.error_outline_rounded,
                  size: 15,
                  color: AppColors.danger,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _error!,
                    style: context.texts.bodySmall?.copyWith(
                      color: AppColors.danger,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.xl),
          if (vm.guestCountEnabled) ...<Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    context.t('guests'),
                    style: context.texts.titleMedium,
                  ),
                ),
                QuantityStepper(
                  quantity: vm.guests,
                  onIncrement: () => vm.onGuests(vm.guests + 1),
                  onDecrement: () =>
                      vm.onGuests(vm.guests > 0 ? vm.guests - 1 : 0),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
          ],
        ] else ...<Widget>[
          Text(context.t('customer'), style: context.texts.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _customerName,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(hintText: context.t('name')),
            onChanged: (String v) => vm.onCustomer(name: v),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _customerPhone,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              hintText: '${context.t('phone')} (${context.t('optional')})',
            ),
            onChanged: (String v) => vm.onCustomer(phone: v),
          ),
          if (vm.totals.packaging > 0) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            AppCard(
              elevated: false,
              color: AppColors.secondary.withValues(alpha: 0.10),
              borderColor: AppColors.secondary.withValues(alpha: 0.3),
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: <Widget>[
                  const Icon(
                    Icons.inventory_2_rounded,
                    size: 18,
                    color: AppColors.secondary,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      context.t('packagingFee'),
                      style: context.texts.titleSmall,
                    ),
                  ),
                  Text(
                    Fmt.money(vm.totals.packaging),
                    style: context.texts.titleSmall,
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.xl),
        ],

        Text(context.t('waiter'), style: context.texts.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        _WaiterPicker(
          staff: vm.staff,
          selectedId: vm.waiterId,
          onSelected: vm.onWaiter,
        ),
        const SizedBox(height: AppSpacing.xl),

        Text(context.t('discount'), style: context.texts.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: _discount,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            hintText: '0',
            prefixText: '${vm.currencyPrefix}  ',
          ),
          onChanged: (String v) =>
              vm.onDiscount(double.tryParse(v.replaceAll(',', '')) ?? 0),
        ),
        const SizedBox(height: AppSpacing.lg),
        _SummaryCard(vm: vm),
      ],
    );
  }

  // ------------------------------------------------------------- step two

  Widget _paymentStep(_CheckoutVm vm) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (vm.canUseCustomers) ...<Widget>[
          Text(context.t('customer'), style: context.texts.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          _AccountCard(vm: vm, onPick: () => _pickCustomer(vm)),
          if (vm.customer != null) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            _ModePicker(vm: vm, total: vm.totals.total),
          ],
          const SizedBox(height: AppSpacing.xl),
        ],

        // A sale on the tab or out of a deposit moves no money across the
        // counter now, so there is no till to choose. Showing one would record
        // cash that nobody handed over.
        if (vm.paymentMode == PaymentMode.cash) ...<Widget>[
          Text(context.t('paymentMethod'), style: context.texts.titleMedium),
          const SizedBox(height: AppSpacing.md),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            crossAxisSpacing: AppSpacing.md,
            mainAxisSpacing: AppSpacing.md,
            childAspectRatio: 2.5,
            children: StoreProvider.of<AppState>(context, listen: false)
                .state
                .accounts
                .pickable
                .map((PaymentMethod m) {
                  final bool selected = vm.paymentMethod == m;
                  return _PaymentCard(
                    method: m,
                    selected: selected,
                    onTap: () => vm.onPayment(method: m),
                  );
                })
                .toList(),
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
        Text(context.t('amountDue'), style: context.texts.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        AppCard(
          elevated: false,
          color: AppColors.primary.withValues(alpha: 0.08),
          borderColor: AppColors.primary.withValues(alpha: 0.25),
          child: Row(
            children: <Widget>[
              const IconBadge(
                icon: Icons.payments_rounded,
                color: AppColors.primary,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  Fmt.money(vm.totals.total),
                  style: context.texts.headlineSmall?.copyWith(
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (vm.paymentMode == PaymentMode.cash &&
            vm.paymentMethod != PaymentMethod.cash) ...<Widget>[
          const SizedBox(height: AppSpacing.xl),
          Text(context.t('reference'), style: context.texts.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _reference,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(hintText: context.t('referenceHint')),
            onChanged: (String v) => vm.onPayment(reference: v),
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
        _SummaryCard(vm: vm, expanded: true),
      ],
    );
  }

  // --------------------------------------------------------------- actions

  Future<void> _pickCustomer(_CheckoutVm vm) async {
    final CustomerChoice? choice = await showCustomerPicker(context);
    if (choice == null || !mounted) return;

    if (choice.isWalkIn) {
      vm.onAccount(clear: true);

      return;
    }

    final Customer picked = choice.customer!;

    // Opens on the mode that fits what the account can actually do: money on
    // deposit spends itself first, and an account with no credit left has no
    // business defaulting to credit.
    vm.onAccount(
      customerId: picked.id,
      mode: picked.wallet > 0
          ? PaymentMode.wallet
          : (picked.creditAvailable > 0 ? PaymentMode.credit : PaymentMode.cash),
    );
  }

  void _goToPayment(_CheckoutVm vm) {
    // Client-side mirror of the API rule; the server re-checks on submit.
    if (vm.orderType == OrderType.dineIn &&
        vm.requireTable &&
        vm.tableId == null) {
      setState(() => _error = context.t('tableRequired'));
      return;
    }
    setState(() {
      _error = null;
      _step = 1;
    });
  }

  Future<void> _place(_CheckoutVm vm) async {
    if (_placing) return;
    setState(() => _placing = true);

    try {
      final RestaurantOrder order = await vm.placeOrder();
      if (!mounted) return;

      final NavigatorState navigator = Navigator.of(context);
      navigator.pop();
      navigator.push(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => OrderSuccessScreen(order: order),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _placing = false);

      // Nothing can be sold before the till is opened. That is the rule, not a
      // fault — so it gets a message that says what has to happen, and an
      // action for whoever is allowed to do it. A waiter is not, which is why
      // the button only appears for someone who can.
      if (e.code == 'shift_required') {
        final bool canOpen = StoreProvider.of<AppState>(
          context,
          listen: false,
        ).state.auth.can(Permission.shiftsManage);

        // The navigator is captured now rather than reached for later. A
        // snackbar action outlives the widget that showed it — the sheet can be
        // closed while the message is still on screen — and `Navigator.of` on a
        // dead context throws when the button is finally pressed.
        final NavigatorState navigator = Navigator.of(context, rootNavigator: true);
        final String openLabel = context.t('openTill');

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            backgroundColor: AppColors.danger,
            duration: const Duration(seconds: 6),
            action: canOpen
                ? SnackBarAction(
                    label: openLabel,
                    textColor: Colors.white,
                    onPressed: () => navigator.push(
                      MaterialPageRoute<void>(
                        builder: (_) => const ShiftScreen(),
                      ),
                    ),
                  )
                : null,
          ),
        );

        return;
      }

      // Server-side validation wins: if it rejects the order, the staff member
      // needs the reason, not a success animation.
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

// ------------------------------------------------------------------ pieces

class _TypeCard extends StatelessWidget {
  const _TypeCard({
    required this.type,
    required this.selected,
    required this.onTap,
  });

  final OrderType type;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color tint = AppColors.primary;
    return AnimatedContainer(
      duration: AppMotion.fast,
      decoration: BoxDecoration(
        color: selected
            ? tint.withValues(alpha: context.isDark ? 0.20 : 0.09)
            : context.palette.card,
        borderRadius: AppRadius.card,
        border: Border.all(
          color: selected ? tint : context.palette.border,
          width: selected ? 1.5 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              vertical: AppSpacing.lg,
              horizontal: AppSpacing.md,
            ),
            child: Column(
              children: <Widget>[
                Icon(
                  type.icon,
                  size: 24,
                  color: selected ? tint : context.palette.subtext,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  context.t(type.labelKey),
                  style: context.texts.titleSmall?.copyWith(
                    color: selected ? tint : context.palette.text,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TableGrid extends StatelessWidget {
  const _TableGrid({
    required this.tables,
    required this.selectedId,
    required this.onSelected,
  });

  final List<DiningTable> tables;
  final int? selectedId;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: tables.map((DiningTable t) {
        final bool selected = t.id == selectedId;
        final bool busy = t.status == TableStatus.occupied && !selected;
        return Opacity(
          opacity: busy ? 0.45 : 1,
          child: Material(
            color: selected ? AppColors.primary : context.palette.card,
            borderRadius: BorderRadius.circular(AppRadius.md),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: busy ? null : () => onSelected(t.id),
              child: Container(
                width: 74,
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(
                    color: selected
                        ? AppColors.primary
                        : context.palette.border,
                  ),
                ),
                child: Column(
                  children: <Widget>[
                    Text(
                      t.number.toString().padLeft(2, '0'),
                      style: context.texts.titleMedium?.copyWith(
                        color: selected ? Colors.white : context.palette.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Icon(
                          Icons.person_rounded,
                          size: 11,
                          color: selected
                              ? Colors.white70
                              : context.palette.subtext,
                        ),
                        Text(
                          '${t.capacity}',
                          style: context.texts.labelSmall?.copyWith(
                            color: selected
                                ? Colors.white70
                                : context.palette.subtext,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _WaiterPicker extends StatelessWidget {
  const _WaiterPicker({
    required this.staff,
    required this.selectedId,
    required this.onSelected,
  });

  final List<AppUser> staff;
  final int? selectedId;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: staff.length,
        separatorBuilder: (BuildContext context, int i) =>
            const SizedBox(width: AppSpacing.sm),
        itemBuilder: (BuildContext context, int i) {
          final AppUser u = staff[i];
          final bool selected = u.id == selectedId;
          return Material(
            color: selected ? AppColors.primary : context.palette.card,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => onSelected(u.id),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  border: Border.all(
                    color: selected
                        ? AppColors.primary
                        : context.palette.border,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    CircleAvatar(
                      radius: 13,
                      backgroundColor: selected
                          ? Colors.white24
                          : context.palette.muted,
                      child: Text(
                        u.initials,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: selected
                              ? Colors.white
                              : context.palette.subtext,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      u.name.split(' ').first,
                      style: context.texts.titleSmall?.copyWith(
                        color: selected ? Colors.white : context.palette.text,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The account the sale is going on, or an invitation to choose one.
class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.vm, required this.onPick});

  final _CheckoutVm vm;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final Customer? c = vm.customer;

    if (c == null) {
      return AppCard(
        padding: const EdgeInsets.all(AppSpacing.md),
        onTap: onPick,
        child: Row(
          children: <Widget>[
            Icon(
              Icons.person_search_rounded,
              size: 20,
              color: context.palette.subtext,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                context.t('walkIn'),
                style: context.texts.titleSmall?.copyWith(
                  color: context.palette.subtext,
                ),
              ),
            ),
            Text(
              context.t('selectCustomer'),
              style: context.texts.labelMedium?.copyWith(
                color: AppColors.primary,
              ),
            ),
          ],
        ),
      );
    }

    return AppCard(
      elevated: false,
      color: AppColors.primary.withValues(alpha: 0.08),
      borderColor: AppColors.primary.withValues(alpha: 0.25),
      padding: const EdgeInsets.all(AppSpacing.md),
      onTap: onPick,
      child: Row(
        children: <Widget>[
          const IconBadge(
            icon: Icons.person_rounded,
            color: AppColors.primary,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  c.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.texts.titleSmall,
                ),
                // Both figures, always: the person at the till needs to know
                // what is already owed before adding to it.
                Text(
                  <String>[
                    if (c.balanceOwed > 0)
                      '${context.t('owesYou')} ${Fmt.money(c.balanceOwed)}',
                    if (c.wallet > 0)
                      '${context.t('walletBalance')} ${Fmt.money(c.wallet)}',
                    if (c.creditLimit > 0)
                      '${context.t('creditAvailable')} ${Fmt.money(c.creditAvailable)}',
                  ].join(' · '),
                  style: context.texts.labelSmall?.copyWith(
                    color: context.palette.subtext,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.swap_horiz_rounded, size: 18),
        ],
      ),
    );
  }
}

/// Pay now, on the tab, or out of the deposit — and what each one means for
/// this particular order.
class _ModePicker extends StatelessWidget {
  const _ModePicker({required this.vm, required this.total});

  final _CheckoutVm vm;
  final double total;

  @override
  Widget build(BuildContext context) {
    final Customer c = vm.customer!;

    // One boundary for both modes, because the server has one: the deposit is
    // spent first either way, and the order is refused only when what is left
    // would carry the customer past their credit limit.
    final bool overLimit =
        vm.paymentMode != PaymentMode.cash && total > c.spendable;

    // Not a refusal — the deposit covers part and the rest goes on the tab.
    // Worth saying out loud so nobody believes a deposit was enough when it
    // was not.
    final bool shortWallet =
        !overLimit && vm.paymentMode != PaymentMode.cash && total > c.wallet;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: PaymentMode.values.map((PaymentMode mode) {
            return ChoiceChip(
              label: Text(context.t(mode.labelKey)),
              selected: vm.paymentMode == mode,
              onSelected: (_) =>
                  vm.onAccount(customerId: c.id, mode: mode),
            );
          }).toList(),
        ),

        // Stated before the order is placed rather than after the server
        // refuses it: over the limit is a conversation with the customer, not
        // an error message.
        if (overLimit) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          _Note(
            // With the figure, not just the verdict: "over the limit" leaves
            // the cashier to work out how much can go through, and they are
            // standing in front of the customer while they do it.
            text: context.tp('overCreditLimitBy', <String, String>{
              'n': Fmt.money(c.spendable),
            }),
            color: AppColors.danger,
            icon: Icons.block_rounded,
          ),
        ] else if (shortWallet) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          _Note(
            text: context.t('walletShortfall'),
            color: AppColors.secondary,
            icon: Icons.info_outline_rounded,
          ),
        ],
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.text, required this.color, required this.icon});

  final String text;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 16, color: color),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: context.texts.bodySmall?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentCard extends StatelessWidget {
  const _PaymentCard({
    required this.method,
    required this.selected,
    required this.onTap,
  });

  final PaymentMethod method;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: AppMotion.fast,
      decoration: BoxDecoration(
        color: selected
            ? method.color.withValues(alpha: context.isDark ? 0.22 : 0.10)
            : context.palette.card,
        borderRadius: AppRadius.card,
        border: Border.all(
          color: selected ? method.color : context.palette.border,
          width: selected ? 1.5 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Row(
              children: <Widget>[
                Icon(method.icon, size: 20, color: method.color),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    method.label,
                    style: context.texts.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (selected)
                  Icon(
                    Icons.check_circle_rounded,
                    size: 17,
                    color: method.color,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.vm, this.expanded = false});

  final _CheckoutVm vm;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final CartTotals t = vm.totals;
    return AppCard(
      color: context.palette.muted,
      elevated: false,
      child: Column(
        children: <Widget>[
          if (expanded) ...<Widget>[
            ...vm.lines.map(
              (OrderLine l) => DetailRow(
                label: '${l.name} × ${l.quantity}',
                value: Fmt.number(l.total),
                dense: true,
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: DashedDivider(),
            ),
          ],
          DetailRow(
            label: context.t('subtotal'),
            value: Fmt.money(t.subtotal),
            dense: true,
          ),
          if (t.discount > 0)
            DetailRow(
              label: context.t('discount'),
              value: '- ${Fmt.money(t.discount)}',
              valueColor: AppColors.danger,
              dense: true,
            ),
          if (vm.taxEnabled)
            DetailRow(
              label: context.t('tax'),
              value: Fmt.money(t.tax),
              dense: true,
            ),
          if (t.packaging > 0)
            DetailRow(
              label: context.t('packagingFee'),
              value: Fmt.money(t.packaging),
              dense: true,
            ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: DashedDivider(),
          ),
          DetailRow(
            label: context.t('total'),
            value: Fmt.money(t.total),
            bold: true,
            valueColor: AppColors.primary,
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------- viewmodel

class _CheckoutVm {
  const _CheckoutVm({
    required this.orderType,
    required this.tableId,
    required this.waiterId,
    required this.guests,
    required this.lines,
    required this.totals,
    required this.tables,
    required this.staff,
    required this.paymentMethod,
    required this.customer,
    required this.paymentMode,
    required this.canUseCustomers,
    required this.onAccount,
    required this.requireTable,
    required this.guestCountEnabled,
    required this.taxEnabled,
    required this.currencyPrefix,
    required this.onOrderType,
    required this.onTable,
    required this.onWaiter,
    required this.onGuests,
    required this.onDiscount,
    required this.onCustomer,
    required this.onPayment,
    required this.placeOrder,
  });

  factory _CheckoutVm.from(Store<AppState> store) {
    final AppState s = store.state;
    return _CheckoutVm(
      orderType: s.cart.orderType,
      tableId: s.cart.tableId,
      waiterId: s.cart.waiterId,
      guests: s.cart.guests,
      lines: s.cart.lines,
      totals: s.cartTotals,
      tables: s.tables.selectable,
      staff: s.restaurant.staff,
      paymentMethod: s.cart.paymentMethod,
      customer: s.customers.byId(s.cart.customerId),
      paymentMode: s.cart.paymentMode,
      canUseCustomers: s.auth.can(Permission.customersView),
      onAccount: ({int? customerId, PaymentMode? mode, bool clear = false}) =>
          store.dispatch(
            CartCustomerAttached(
              customerId: customerId,
              mode: mode,
              clear: clear,
            ),
          ),
      requireTable: s.settings.requireTableForDineIn,
      guestCountEnabled: s.settings.guestCountEnabled,
      taxEnabled: s.settings.taxEnabled,
      currencyPrefix: s.settings.currencyPrefix,
      onOrderType: (OrderType t) => store.dispatch(CartOrderTypeChanged(t)),
      onTable: (int? id) => store.dispatch(CartTableSelected(id)),
      onWaiter: (int id) => store.dispatch(CartWaiterSelected(id)),
      onGuests: (int g) => store.dispatch(CartGuestsChanged(g)),
      onDiscount: (double d) => store.dispatch(CartDiscountChanged(d)),
      onCustomer: ({String? name, String? phone}) =>
          store.dispatch(CartCustomerChanged(name: name, phone: phone)),
      onPayment: ({PaymentMethod? method, String? reference}) => store.dispatch(
        CartPaymentChanged(method: method, reference: reference),
      ),
      placeOrder: () => Effects.placeOrder(store),
    );
  }

  final OrderType orderType;
  final int? tableId;
  final int? waiterId;
  final int guests;
  final List<OrderLine> lines;
  final CartTotals totals;
  final List<DiningTable> tables;
  final List<AppUser> staff;
  final PaymentMethod paymentMethod;

  /// The account this sale is going on, resolved from the loaded list. Null
  /// is a walk-in.
  final Customer? customer;
  final PaymentMode paymentMode;
  final bool canUseCustomers;
  final bool requireTable;
  final bool guestCountEnabled;
  final bool taxEnabled;
  final String currencyPrefix;

  final ValueChanged<OrderType> onOrderType;
  final ValueChanged<int?> onTable;
  final ValueChanged<int> onWaiter;
  final ValueChanged<int> onGuests;
  final ValueChanged<double> onDiscount;
  final void Function({String? name, String? phone}) onCustomer;
  final void Function({PaymentMethod? method, String? reference}) onPayment;
  final void Function({int? customerId, PaymentMode? mode, bool clear})
  onAccount;
  final Future<RestaurantOrder> Function() placeOrder;
}
