import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:redux/redux.dart';

import '../../core/i18n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/utils/enums.dart';
import '../../core/utils/formatters.dart';
import '../../data/api/api_client.dart';
import '../../data/models/finance.dart';
import '../../redux/app_state.dart';
import '../../redux/effects.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_sheet.dart';
import '../../widgets/buttons.dart';

/// Manages the ways a restaurant takes money, and the accounts behind them.
///
/// Both were hardcoded until now: four methods in a database ENUM, and exactly
/// one account each. A shop with two banks could not represent the second, and
/// a shop that started accepting a new wallet had to wait for a release.
class PaymentMethodsScreen extends StatelessWidget {
  const PaymentMethodsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return StoreConnector<AppState, _Vm>(
      converter: _Vm.from,
      onInit: (Store<AppState> store) => Effects.refreshPaymentMethods(store),
      builder: (BuildContext context, _Vm vm) {
        return Scaffold(
          appBar: AppBar(title: Text(context.t('accountsPayments'))),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.gutter,
              AppSpacing.md,
              AppSpacing.gutter,
              AppSpacing.xxxl,
            ),
            children: <Widget>[
              _Header(
                title: context.t('paymentMethod'),
                onAdd: vm.canManage ? () => _addMethod(context, vm) : null,
              ),
              ...vm.methods.map(
                (PaymentMethodRecord m) =>
                    _MethodRow(record: m, vm: vm, canManage: vm.canManage),
              ),

              const SizedBox(height: AppSpacing.xl),

              _Header(
                title: context.t('accounts'),
                onAdd: vm.canManage ? () => _addAccount(context, vm) : null,
              ),
              ...vm.accounts.map(
                (Account a) =>
                    _AccountRow(account: a, vm: vm, canManage: vm.canManage),
              ),
            ],
          ),
        );
      },
    );
  }

  // ------------------------------------------------------------- methods

  Future<void> _addMethod(BuildContext context, _Vm vm) async {
    final String? name = await _askName(
      context,
      title: context.t('newPaymentMethod'),
      hint: context.t('paymentMethodHint'),
    );

    if (name == null || !context.mounted) return;
    await _run(context, () => vm.onSaveMethod(null, name, null));
  }

  // ------------------------------------------------------------ accounts

  Future<void> _addAccount(BuildContext context, _Vm vm) async {
    final _AccountDraft? draft = await showAppSheet<_AccountDraft>(
      context,
      builder: (BuildContext context) => _AccountSheet(methods: vm.methods),
    );

    if (draft == null || !context.mounted) return;
    await _run(
      context,
      () => vm.onSaveAccount(null, draft.name, draft.method, draft.balance),
    );
  }

  static Future<String?> _askName(
    BuildContext context, {
    required String title,
    required String hint,
    String initial = '',
  }) async {
    final TextEditingController c = TextEditingController(text: initial);

    final String? out = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.t('goBack')),
          ),
          FilledButton(
            onPressed: () {
              if (c.text.trim().isEmpty) return;
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

  /// Surfaces the server's refusal rather than letting the row silently snap
  /// back — "a built-in method cannot be removed" is the whole answer.
  static Future<void> _run(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    try {
      await action();
    } on ApiException catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: AppColors.danger),
      );
    }
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title, this.onAdd});

  final String title;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(title, style: context.texts.titleMedium)),
          if (onAdd != null)
            OutlinedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded, size: 17),
              label: Text(context.t('addItem')),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 36),
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary),
              ),
            ),
        ],
      ),
    );
  }
}

class _MethodRow extends StatelessWidget {
  const _MethodRow({
    required this.record,
    required this.vm,
    required this.canManage,
  });

  final PaymentMethodRecord record;
  final _Vm vm;
  final bool canManage;

  @override
  Widget build(BuildContext context) {
    final PaymentMethod m = record.asMethod;

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
                color: m.color.withValues(alpha: record.isActive ? 0.12 : 0.05),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Icon(
                m.icon,
                size: 18,
                color: record.isActive ? m.color : context.palette.subtext,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    record.name,
                    style: context.texts.titleSmall?.copyWith(
                      color: record.isActive ? null : context.palette.subtext,
                    ),
                  ),
                  Text(
                    <String>[
                      record.code,
                      if (record.isSystem) context.t('builtIn'),
                      if (!record.isActive) context.t('inactive'),
                    ].join(' · '),
                    style: context.texts.bodySmall?.copyWith(
                      color: context.palette.subtext,
                    ),
                  ),
                ],
              ),
            ),
            if (canManage)
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded, size: 19),
                onSelected: (String action) async {
                  if (action == 'rename') {
                    final String? name = await PaymentMethodsScreen._askName(
                      context,
                      title: context.t('edit'),
                      hint: context.t('paymentMethodHint'),
                      initial: record.name,
                    );
                    if (name == null || !context.mounted) return;
                    await PaymentMethodsScreen._run(
                      context,
                      () => vm.onSaveMethod(record.id, name, null),
                    );
                  } else if (action == 'toggle') {
                    await PaymentMethodsScreen._run(
                      context,
                      () => vm.onSaveMethod(record.id, null, !record.isActive),
                    );
                  } else {
                    await PaymentMethodsScreen._run(
                      context,
                      () => vm.onRemoveMethod(record.id),
                    );
                  }
                },
                itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                  PopupMenuItem<String>(
                    value: 'rename',
                    child: Text(context.t('edit')),
                  ),
                  // Built-ins can be renamed but never switched off: every
                  // restaurant takes cash, and the seeded accounts point here.
                  if (!record.isSystem)
                    PopupMenuItem<String>(
                      value: 'toggle',
                      child: Text(
                        record.isActive
                            ? context.t('deactivate')
                            : context.t('activate'),
                      ),
                    ),
                  if (!record.isSystem && record.isActive)
                    PopupMenuItem<String>(
                      value: 'remove',
                      child: Text(
                        context.t('delete'),
                        style: const TextStyle(color: AppColors.danger),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({
    required this.account,
    required this.vm,
    required this.canManage,
  });

  final Account account;
  final _Vm vm;
  final bool canManage;

  @override
  Widget build(BuildContext context) {
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
                color: account.method.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Icon(
                account.method.icon,
                size: 18,
                color: account.method.color,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(account.name, style: context.texts.titleSmall),
                  Text(
                    account.method.label,
                    style: context.texts.bodySmall?.copyWith(
                      color: context.palette.subtext,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              Fmt.money(account.balance),
              style: context.texts.titleSmall?.copyWith(
                color: AppColors.primary,
              ),
            ),
            if (canManage)
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded, size: 19),
                onSelected: (String action) async {
                  if (action == 'rename') {
                    final String? name = await PaymentMethodsScreen._askName(
                      context,
                      title: context.t('edit'),
                      hint: context.t('accountNameHint'),
                      initial: account.name,
                    );
                    if (name == null || !context.mounted) return;
                    await PaymentMethodsScreen._run(
                      context,
                      () => vm.onSaveAccount(account.id, name, null, 0),
                    );
                  } else {
                    await PaymentMethodsScreen._run(
                      context,
                      () => vm.onRemoveAccount(account.id),
                    );
                  }
                },
                itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                  PopupMenuItem<String>(
                    value: 'rename',
                    child: Text(context.t('edit')),
                  ),
                  PopupMenuItem<String>(
                    value: 'close',
                    child: Text(
                      context.t('closeAccount'),
                      style: const TextStyle(color: AppColors.danger),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _AccountDraft {
  const _AccountDraft(this.name, this.method, this.balance);

  final String name;
  final String method;
  final double balance;
}

class _AccountSheet extends StatefulWidget {
  const _AccountSheet({required this.methods});

  final List<PaymentMethodRecord> methods;

  @override
  State<_AccountSheet> createState() => _AccountSheetState();
}

class _AccountSheetState extends State<_AccountSheet> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _balance = TextEditingController();
  String? _method;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _balance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<PaymentMethodRecord> active = widget.methods
        .where((PaymentMethodRecord m) => m.isActive)
        .toList();

    return AppSheet(
      title: context.t('newAccount'),
      footer: GradientButton(
        label: context.t('save'),
        height: 50,
        onPressed: () {
          if (_name.text.trim().isEmpty) {
            setState(() => _error = context.t('required'));

            return;
          }
          if (_method == null) {
            setState(() => _error = context.t('paymentMethodRequired'));

            return;
          }

          Navigator.of(context).pop(
            _AccountDraft(
              _name.text.trim(),
              _method!,
              double.tryParse(_balance.text.replaceAll(',', '')) ?? 0,
            ),
          );
        },
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(context.t('name'), style: context.texts.titleSmall),
          const SizedBox(height: AppSpacing.xs),
          TextField(
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(hintText: context.t('accountNameHint')),
          ),

          const SizedBox(height: AppSpacing.lg),
          Text(context.t('paymentMethod'), style: context.texts.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: active.map((PaymentMethodRecord m) {
              return ChoiceChip(
                label: Text(m.name),
                selected: _method == m.code,
                onSelected: (_) => setState(() => _method = m.code),
              );
            }).toList(),
          ),

          const SizedBox(height: AppSpacing.lg),
          Text(context.t('openingBalance'), style: context.texts.titleSmall),
          const SizedBox(height: AppSpacing.xs),
          TextField(
            controller: _balance,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              prefixText: '${Fmt.prefix}  ',
              hintText: '0',
              // Recorded as an adjustment, not conjured: money already in a
              // drawer has to enter the ledger somewhere.
              helperText: context.t('openingBalanceHint'),
            ),
          ),

          if (_error != null) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            Text(
              _error!,
              style: context.texts.bodySmall?.copyWith(color: AppColors.danger),
            ),
          ],
        ],
      ),
    );
  }
}

class _Vm {
  const _Vm({
    required this.methods,
    required this.accounts,
    required this.canManage,
    required this.onSaveMethod,
    required this.onRemoveMethod,
    required this.onSaveAccount,
    required this.onRemoveAccount,
  });

  factory _Vm.from(Store<AppState> store) {
    return _Vm(
      methods: store.state.accounts.methods,
      accounts: store.state.accounts.accounts,
      canManage: store.state.auth.can(Permission.accountsManage),
      onSaveMethod: (int? id, String? name, bool? active) =>
          Effects.savePaymentMethod(
            store,
            id: id,
            name: name,
            isActive: active,
          ),
      onRemoveMethod: (int id) => Effects.removePaymentMethod(store, id),
      onSaveAccount: (int? id, String? name, String? method, double balance) =>
          Effects.saveAccount(
            store,
            id: id,
            name: name,
            method: method,
            balance: balance,
          ),
      onRemoveAccount: (int id) => Effects.removeAccount(store, id),
    );
  }

  final List<PaymentMethodRecord> methods;
  final List<Account> accounts;
  final bool canManage;
  final Future<void> Function(int?, String?, bool?) onSaveMethod;
  final Future<void> Function(int) onRemoveMethod;
  final Future<void> Function(int?, String?, String?, double) onSaveAccount;
  final Future<void> Function(int) onRemoveAccount;
}
