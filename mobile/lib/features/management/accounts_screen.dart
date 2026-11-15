import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:redux/redux.dart';

import '../../core/i18n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/utils/enums.dart';
import '../../core/utils/formatters.dart';
import '../../data/api/api_client.dart';
import '../../data/models/analytics.dart';
import '../../data/models/finance.dart';
import '../../redux/app_state.dart';
import '../../redux/effects.dart';
import '../../widgets/app_card.dart';
import '../../redux/states/finance_state.dart';
import '../../widgets/app_sheet.dart';
import 'account_filter_sheet.dart';
import '../../widgets/buttons.dart';
import '../../widgets/charts.dart';
import '../../widgets/common.dart';
import '../../widgets/entrance.dart';

/// Where the money sits and where today's money came from.
class AccountsScreen extends StatelessWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return StoreConnector<AppState, _AccountsVm>(
      converter: _AccountsVm.from,
      // Movements are not in the bootstrap payload — they are only wanted when
      // this screen is open, and there can be a great many of them.
      onInit: (Store<AppState> store) => Effects.loadTransactions(store),
      builder: (BuildContext context, _AccountsVm vm) {
        return Scaffold(
          appBar: AppBar(
            title: Text(context.t('accountsPayments')),
            actions: <Widget>[
              if (vm.canManage && vm.accounts.length > 1)
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.gutter),
                  child: Material(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(12),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => showAppSheet<void>(
                        context,
                        builder: (BuildContext context) => _TransferSheet(
                          accounts: vm.accounts,
                          onTransfer: vm.onTransfer,
                        ),
                      ),
                      child: const SizedBox(
                        width: 38,
                        height: 38,
                        child: Icon(
                          Icons.swap_horiz_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.gutter,
              0,
              AppSpacing.gutter,
              AppSpacing.xxxl,
            ),
            children: <Widget>[
              Entrance(
                index: 0,
                child: GradientCard(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Text(
                        'Total Balance',
                        style: TextStyle(color: Colors.white70, fontSize: 12.5),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        Fmt.money(vm.totalBalance),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.8,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Row(
                        children: <Widget>[
                          const Icon(
                            Icons.arrow_downward_rounded,
                            color: Colors.white,
                            size: 15,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${context.t('today')}  ${Fmt.money(vm.todayIn)}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              SectionHeader(title: context.t('accountsPayments')),
              ...List<Widget>.generate(vm.accounts.length, (int i) {
                final Account a = vm.accounts[i];
                return Entrance(
                  index: i + 1,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: AppCard(
                      child: Row(
                        children: <Widget>[
                          IconBadge(
                            icon: a.method.icon,
                            color: a.method.color,
                            size: 44,
                            iconSize: 21,
                            radius: 13,
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Text(a.name, style: context.texts.titleMedium),
                                const SizedBox(height: 3),
                                Row(
                                  children: <Widget>[
                                    _Flow(
                                      icon: Icons.south_west_rounded,
                                      value: a.moneyIn,
                                      color: AppColors.success,
                                    ),
                                    const SizedBox(width: AppSpacing.md),
                                    _Flow(
                                      icon: Icons.north_east_rounded,
                                      value: a.moneyOut,
                                      color: AppColors.danger,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          // Balances run to seven or eight digits; scale the
                          // figure down before it collides with the label.
                          Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerRight,
                              child: Text(
                                Fmt.money(a.balance),
                                maxLines: 1,
                                style: context.texts.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
              const SizedBox(height: AppSpacing.md),
              Entrance(
                index: 5,
                child: AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      SectionHeader(title: context.t('paymentBreakdown')),
                      DonutBreakdown(
                        slices: vm.todaySlices,
                        formatValue: Fmt.compact,
                        centerValue: Fmt.compact(vm.todayIn),
                        centerLabel: context.t('today'),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: AppSpacing.xl),

              // The movements themselves. Balances answer "how much"; this
              // answers "where did it come from", which is the question a
              // manager reconciling the till actually has.
              Row(
                children: <Widget>[
                  Expanded(
                    child: SectionHeader(title: context.t('transactions')),
                  ),
                  _FilterButton(
                    count: vm.filters.activeCount,
                    onTap: () => _filter(context, vm),
                  ),
                ],
              ),

              if (vm.transactions.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
                  child: Column(
                    children: <Widget>[
                      Icon(
                        Icons.receipt_long_rounded,
                        size: 34,
                        color: context.palette.subtext,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        context.t('noTransactions'),
                        style: context.texts.titleSmall,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        context.t('noTransactionsBody'),
                        textAlign: TextAlign.center,
                        style: context.texts.bodySmall?.copyWith(
                          color: context.palette.subtext,
                        ),
                      ),
                    ],
                  ),
                )
              else
                ...vm.transactions.map(
                  (AccountTransaction t) => _TransactionRow(entry: t),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _filter(BuildContext context, _AccountsVm vm) async {
    final AccountFilters? next = await showAccountFilterSheet(
      context,
      vm.filters,
      vm.accounts,
    );

    if (next != null) await vm.onFilter(next);
  }
}

class _FilterButton extends StatelessWidget {
  const _FilterButton({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool on = count > 0;

    return OutlinedButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.tune_rounded, size: 17),
      // The count is what tells the user the list is narrowed — without it a
      // filtered view and an empty account look the same.
      label: Text(
        on ? '${context.t('filters')} · $count' : context.t('filters'),
      ),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 38),
        foregroundColor: on ? AppColors.primary : null,
        side: BorderSide(
          color: on ? AppColors.primary : context.palette.border,
        ),
      ),
    );
  }
}

class _TransactionRow extends StatelessWidget {
  const _TransactionRow({required this.entry});

  final AccountTransaction entry;

  @override
  Widget build(BuildContext context) {
    final bool out = entry.kind == TransactionKind.moneyOut;
    final Color tint = switch (entry.kind) {
      TransactionKind.moneyIn => AppColors.success,
      TransactionKind.moneyOut => AppColors.danger,
      TransactionKind.transfer => AppColors.info,
      TransactionKind.adjustment => AppColors.secondary,
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: <Widget>[
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: tint.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Icon(
                switch (entry.kind) {
                  TransactionKind.moneyIn => Icons.south_west_rounded,
                  TransactionKind.moneyOut => Icons.north_east_rounded,
                  TransactionKind.transfer => Icons.swap_horiz_rounded,
                  TransactionKind.adjustment => Icons.tune_rounded,
                },
                size: 17,
                color: tint,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    entry.description.isEmpty
                        ? context.t(entry.kind.labelKey)
                        : entry.description,
                    style: context.texts.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    Fmt.dateTime(entry.at, context.lang),
                    style: context.texts.bodySmall?.copyWith(
                      color: context.palette.subtext,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              '${out ? '−' : '+'} ${Fmt.money(entry.amount)}',
              style: context.texts.titleSmall?.copyWith(color: tint),
            ),
          ],
        ),
      ),
    );
  }
}

class _Flow extends StatelessWidget {
  const _Flow({required this.icon, required this.value, required this.color});

  final IconData icon;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 2),
        Text(
          Fmt.compact(value),
          style: context.texts.labelSmall?.copyWith(color: color),
        ),
      ],
    );
  }
}

/// Move money between the restaurant's own accounts — the cash drawer being
/// banked, a Zaad balance cashed out. Both legs land in the ledger.
class _TransferSheet extends StatefulWidget {
  const _TransferSheet({required this.accounts, required this.onTransfer});

  final List<Account> accounts;
  final Future<void> Function(int, int, double, String) onTransfer;

  @override
  State<_TransferSheet> createState() => _TransferSheetState();
}

class _TransferSheetState extends State<_TransferSheet> {
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _description = TextEditingController();

  late int _fromId = widget.accounts.first.id;
  late int _toId = widget.accounts.length > 1
      ? widget.accounts[1].id
      : widget.accounts.first.id;

  bool _busy = false;
  String? _amountError;
  String? _error;

  Account get _from =>
      widget.accounts.firstWhere((Account a) => a.id == _fromId);

  @override
  void dispose() {
    _amount.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppSheet(
      title: context.t('transfer'),
      footer: GradientButton(
        label: context.t('transfer'),
        icon: Icons.swap_horiz_rounded,
        loading: _busy,
        onPressed: _submit,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(context.t('from'), style: context.texts.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          _AccountPicker(
            accounts: widget.accounts,
            selectedId: _fromId,
            onSelected: (int id) => setState(() {
              _fromId = id;
              // Sending money to the account it came from is never what was
              // meant; move the destination out of the way.
              if (_toId == id) {
                _toId = widget.accounts
                    .firstWhere((Account a) => a.id != id)
                    .id;
              }
            }),
          ),
          const SizedBox(height: AppSpacing.lg),
          Center(
            child: Icon(
              Icons.arrow_downward_rounded,
              color: context.palette.subtext,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(context.t('to'), style: context.texts.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          _AccountPicker(
            accounts: widget.accounts
                .where((Account a) => a.id != _fromId)
                .toList(),
            selectedId: _toId,
            onSelected: (int id) => setState(() => _toId = id),
          ),
          const SizedBox(height: AppSpacing.xl),
          TextField(
            controller: _amount,
            enabled: !_busy,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: context.t('amount'),
              prefixText: '${Fmt.prefix}  ',
              helperText:
                  '${context.t('balance')}: ${Fmt.money(_from.balance)}',
              errorText: _amountError,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          TextField(
            controller: _description,
            enabled: !_busy,
            decoration: InputDecoration(
              labelText: '${context.t('notes')} (${context.t('optional')})',
            ),
          ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: AppSpacing.lg),
            Text(
              _error!,
              style: context.texts.bodyMedium?.copyWith(
                color: AppColors.danger,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _submit() async {
    if (_busy) return;

    final double amount =
        double.tryParse(_amount.text.replaceAll(',', '')) ?? 0;

    if (amount <= 0) {
      setState(() => _amountError = context.t('required'));

      return;
    }
    // The API refuses an overdraft too; catching it here saves a round trip
    // and reads as an answer rather than a rejection.
    if (amount > _from.balance) {
      setState(() => _amountError = context.t('insufficientBalance'));

      return;
    }

    setState(() {
      _busy = true;
      _amountError = null;
      _error = null;
    });

    try {
      await widget.onTransfer(_fromId, _toId, amount, _description.text.trim());
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    }
  }
}

class _AccountPicker extends StatelessWidget {
  const _AccountPicker({
    required this.accounts,
    required this.selectedId,
    required this.onSelected,
  });

  final List<Account> accounts;
  final int selectedId;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: accounts.map((Account a) {
        final bool selected = a.id == selectedId;

        return Material(
          color: selected ? a.method.color : context.palette.card,
          borderRadius: BorderRadius.circular(AppRadius.md),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => onSelected(a.id),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm + 2,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(
                  color: selected ? a.method.color : context.palette.border,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    a.method.icon,
                    size: 16,
                    color: selected ? Colors.white : a.method.color,
                  ),
                  const SizedBox(width: 6),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        a.name,
                        style: context.texts.titleSmall?.copyWith(
                          color: selected ? Colors.white : context.palette.text,
                        ),
                      ),
                      Text(
                        Fmt.compact(a.balance),
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
        );
      }).toList(),
    );
  }
}

class _AccountsVm {
  const _AccountsVm({
    required this.accounts,
    required this.totalBalance,
    required this.todayIn,
    required this.todaySlices,
    required this.canManage,
    required this.onTransfer,
    required this.transactions,
    required this.filters,
    required this.onFilter,
  });

  factory _AccountsVm.from(Store<AppState> store) {
    final AppState s = store.state;
    return _AccountsVm(
      accounts: s.accounts.accounts,
      transactions: s.accounts.transactions,
      filters: s.accounts.filters,
      onFilter: (AccountFilters f) =>
          Effects.loadTransactions(store, filters: f),
      totalBalance: s.accounts.totalBalance,
      todayIn: s.accounts.todayIn,
      canManage: s.auth.can(Permission.accountsManage),
      onTransfer: (int from, int to, double amount, String description) =>
          Effects.transfer(
            store,
            fromAccountId: from,
            toAccountId: to,
            amount: amount,
            description: description,
          ),
      todaySlices: s.accounts.accounts
          .map(
            (Account a) => BreakdownSlice(
              label: a.name,
              value: a.moneyIn,
              color: a.method.color,
            ),
          )
          .toList(),
    );
  }

  final List<Account> accounts;
  final double totalBalance;
  final double todayIn;
  final List<BreakdownSlice> todaySlices;
  final bool canManage;
  final Future<void> Function(int, int, double, String) onTransfer;
  final List<AccountTransaction> transactions;
  final AccountFilters filters;
  final Future<void> Function(AccountFilters) onFilter;
}
