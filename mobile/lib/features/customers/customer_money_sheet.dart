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
import '../../redux/app_state.dart';
import '../../redux/effects.dart';
import '../../widgets/app_sheet.dart';
import '../../widgets/buttons.dart';

/// Takes a repayment, a deposit, or a hand adjustment.
///
/// One sheet for all three because the shape is identical — an amount, and
/// where it came from — and the differences are worth stating in one place:
/// an adjustment moves no cash so it asks for a reason instead of a method,
/// and a repayment is capped at what is actually owed.
Future<void> showCustomerMoneySheet(
  BuildContext context, {
  required Customer customer,
  required LedgerKind kind,
}) {
  return showAppSheet<void>(
    context,
    builder: (BuildContext context) =>
        _MoneySheet(customer: customer, kind: kind),
  );
}

class _MoneySheet extends StatefulWidget {
  const _MoneySheet({required this.customer, required this.kind});

  final Customer customer;
  final LedgerKind kind;

  @override
  State<_MoneySheet> createState() => _MoneySheetState();
}

class _MoneySheetState extends State<_MoneySheet> {
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _note = TextEditingController();
  final TextEditingController _reason = TextEditingController();

  PaymentMethod _method = PaymentMethod.cash;
  String? _error;
  bool _saving = false;

  bool get _isAdjustment => widget.kind == LedgerKind.adjustment;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StoreConnector<AppState, List<PaymentMethod>>(
      converter: (Store<AppState> store) => store.state.accounts.pickable,
      builder: (BuildContext context, List<PaymentMethod> methods) {
        return AppSheet(
          title: switch (widget.kind) {
            LedgerKind.payment => context.t('takePayment'),
            LedgerKind.deposit => context.t('takeDeposit'),
            _ => context.t('adjustBalance'),
          },
          subtitle: widget.customer.name,
          footer: GradientButton(
            label: context.t('save'),
            height: 50,
            loading: _saving,
            onPressed: _saving ? null : _submit,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (widget.kind == LedgerKind.payment)
                _Owing(customer: widget.customer),

              Text(context.t('amount'), style: context.texts.titleSmall),
              const SizedBox(height: AppSpacing.xs),
              TextField(
                controller: _amount,
                autofocus: true,
                keyboardType: TextInputType.numberWithOptions(
                  decimal: true,
                  // An adjustment is the one figure that can legitimately be
                  // negative — that is how a debt gets forgiven.
                  signed: _isAdjustment,
                ),
                decoration: InputDecoration(
                  prefixText: '${Fmt.prefix}  ',
                  hintText: '0',
                  helperText: _isAdjustment
                      ? context.t('adjustBalanceHelp')
                      : context.t('paymentAmountHint'),
                  helperMaxLines: 2,
                ),
              ),

              if (!_isAdjustment) ...<Widget>[
                const SizedBox(height: AppSpacing.lg),
                Text(
                  context.t('paymentMethod'),
                  style: context.texts.titleSmall,
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: methods.map((PaymentMethod m) {
                    return ChoiceChip(
                      avatar: Icon(m.icon, size: 16, color: m.color),
                      label: Text(m.label),
                      selected: _method == m,
                      onSelected: (_) => setState(() => _method = m),
                    );
                  }).toList(),
                ),

                const SizedBox(height: AppSpacing.lg),
                Text(context.t('notes'), style: context.texts.titleSmall),
                const SizedBox(height: AppSpacing.xs),
                TextField(
                  controller: _note,
                  textCapitalization: TextCapitalization.sentences,
                ),
              ] else ...<Widget>[
                const SizedBox(height: AppSpacing.lg),
                Text(context.t('reason'), style: context.texts.titleSmall),
                const SizedBox(height: AppSpacing.xs),
                TextField(
                  controller: _reason,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: context.t('adjustReasonHint'),
                  ),
                ),
              ],

              if (_error != null) ...<Widget>[
                const SizedBox(height: AppSpacing.md),
                Text(
                  _error!,
                  style: context.texts.bodySmall?.copyWith(
                    color: AppColors.danger,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Future<void> _submit() async {
    final double amount =
        double.tryParse(_amount.text.replaceAll(',', '').trim()) ?? 0;

    if (_isAdjustment ? amount == 0 : amount <= 0) {
      setState(() => _error = context.t('required'));

      return;
    }

    if (_isAdjustment && _reason.text.trim().length < 3) {
      setState(() => _error = context.t('required'));

      return;
    }

    // Paying more than is owed would tip the account into credit without
    // anybody meaning to. A deposit is how you do that on purpose.
    if (widget.kind == LedgerKind.payment &&
        amount > widget.customer.balanceOwed) {
      setState(
        () => _error = context.tp('amountTooLarge', <String, String>{
          'n': Fmt.money(widget.customer.balanceOwed),
        }),
      );

      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final Store<AppState> store = StoreProvider.of<AppState>(
      context,
      listen: false,
    );
    final NavigatorState navigator = Navigator.of(context);

    try {
      await Effects.postCustomerMoney(
        store,
        widget.customer.id,
        kind: widget.kind,
        amount: amount,
        method: _method,
        description: _note.text.trim(),
        reason: _reason.text.trim(),
      );

      navigator.pop();
    } on ApiException catch (e) {
      setState(() {
        _saving = false;
        _error = e.fields.values.isNotEmpty ? e.fields.values.first : e.message;
      });
    }
  }
}

class _Owing extends StatelessWidget {
  const _Owing({required this.customer});

  final Customer customer;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.danger.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Row(
          children: <Widget>[
            const Icon(
              Icons.error_outline_rounded,
              size: 18,
              color: AppColors.danger,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                context.t('owesYou'),
                style: context.texts.bodySmall,
              ),
            ),
            Text(
              Fmt.money(customer.balanceOwed),
              style: context.texts.titleSmall?.copyWith(
                color: AppColors.danger,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
