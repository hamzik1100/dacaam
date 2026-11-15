import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';

import '../../core/i18n/app_strings.dart';
import '../../redux/app_state.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/utils/enums.dart';
import '../../core/utils/formatters.dart';
import '../../data/api/api_client.dart';
import '../../data/models/finance.dart';
import '../../data/repository/dacaam_repository.dart';
import '../../widgets/app_sheet.dart';
import '../../widgets/buttons.dart';

/// Record or correct an expense.
///
/// Editing an existing one asks for a reason: the amount and the payment
/// method both move a real account balance, and a changed figure with no
/// explanation is exactly what an auditor stops on.
Future<void> showExpenseSheet(
  BuildContext context, {
  Expense? expense,
  required List<ExpenseCategory> categories,
  required Future<void> Function(ExpenseRequest) onSave,
  Future<void> Function(int, String)? onCancel,
}) {
  return showAppSheet<void>(
    context,
    builder: (BuildContext context) => _ExpenseSheet(
      expense: expense,
      categories: categories,
      onSave: onSave,
      onCancel: onCancel,
    ),
  );
}

class _ExpenseSheet extends StatefulWidget {
  const _ExpenseSheet({
    this.expense,
    required this.categories,
    required this.onSave,
    this.onCancel,
  });

  final Expense? expense;
  final List<ExpenseCategory> categories;
  final Future<void> Function(ExpenseRequest) onSave;
  final Future<void> Function(int, String)? onCancel;

  @override
  State<_ExpenseSheet> createState() => _ExpenseSheetState();
}

class _ExpenseSheetState extends State<_ExpenseSheet> {
  late final TextEditingController _name = TextEditingController(
    text: widget.expense?.name ?? '',
  );
  late final TextEditingController _amount = TextEditingController(
    text: widget.expense == null
        ? ''
        : widget.expense!.amount.toStringAsFixed(0),
  );
  late final TextEditingController _notes = TextEditingController(
    text: widget.expense?.notes ?? '',
  );
  final TextEditingController _reason = TextEditingController();

  late ExpenseKind _kind = widget.expense?.kind ?? ExpenseKind.daily;
  late PaymentMethod _method = widget.expense?.method ?? PaymentMethod.cash;
  late int? _categoryId = widget.expense?.categoryId == 0
      ? null
      : widget.expense?.categoryId;
  late DateTime _date = widget.expense?.date ?? DateTime.now();
  late bool _recurring = widget.expense?.recurring ?? false;

  bool _busy = false;
  Map<String, String> _errors = <String, String>{};
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _notes.dispose();
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isNew = widget.expense == null;

    // A voided entry is history. The server refuses to edit one, so the sheet
    // should not offer to — a form that saves into a 409 is worse than no form.
    final bool alreadyCancelled = widget.expense?.isCancelled ?? false;

    final List<ExpenseCategory> options = widget.categories
        .where((ExpenseCategory c) => c.kind == _kind)
        .toList();

    return AppSheet(
      title: isNew ? context.t('addExpense2') : context.t('editExpense'),
      footer: Row(
        children: <Widget>[
          if (widget.onCancel != null && !isNew && !alreadyCancelled) ...<Widget>[
            Expanded(
              child: OutlinedButton(
                onPressed: _busy ? null : _cancel,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 50),
                  foregroundColor: AppColors.danger,
                  side: const BorderSide(color: AppColors.danger),
                ),
                child: Text(context.t('cancelExpense')),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
          ],
          Expanded(
            flex: 2,
            child: GradientButton(
              label: context.t('save'),
              icon: Icons.check_rounded,
              height: 50,
              loading: _busy,
              onPressed: alreadyCancelled ? null : _save,
            ),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (alreadyCancelled) ...<Widget>[
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    context.t('expenseCancelled'),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.danger,
                    ),
                  ),
                  if (widget.expense!.cancelReason.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 4),
                    Text(
                      widget.expense!.cancelReason,
                      style: TextStyle(
                        fontSize: 13,
                        color: context.palette.subtext,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
          TextField(
            controller: _name,
            enabled: !_busy,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: context.t('name'),
              errorText: _errors['name'],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          TextField(
            controller: _amount,
            enabled: !_busy,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: context.t('amount'),
              prefixText: '${Fmt.prefix}  ',
              errorText: _errors['amount'],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),

          Text(context.t('orderTypeLabel'), style: context.texts.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: ExpenseKind.values.map((ExpenseKind k) {
              final bool selected = k == _kind;

              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.sm),
                  child: _Choice(
                    label: k == ExpenseKind.daily
                        ? context.t('today')
                        : context.t('thisMonth'),
                    selected: selected,
                    color: AppColors.violet,
                    onTap: () => setState(() {
                      _kind = k;
                      // A daily category makes no sense on a monthly expense.
                      _categoryId = null;
                    }),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: AppSpacing.xl),

          Text(context.t('category'), style: context.texts.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: options.map((ExpenseCategory c) {
              final bool selected = c.id == _categoryId;

              return _Choice(
                label: c.name,
                icon: c.icon,
                selected: selected,
                color: c.color,
                onTap: () =>
                    setState(() => _categoryId = selected ? null : c.id),
              );
            }).toList(),
          ),
          const SizedBox(height: AppSpacing.xl),

          Text(context.t('paymentMethod'), style: context.texts.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: StoreProvider.of<AppState>(context, listen: false)
                .state
                .accounts
                .pickable
                .map((PaymentMethod m) {
                  return _Choice(
                    label: m.label,
                    icon: m.icon,
                    selected: m == _method,
                    color: m.color,
                    onTap: () => setState(() => _method = m),
                  );
                })
                .toList(),
          ),
          const SizedBox(height: AppSpacing.xl),

          InkWell(
            onTap: _busy ? null : _pickDate,
            borderRadius: AppRadius.card,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.calendar_today_rounded,
                    size: 17,
                    color: context.palette.subtext,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      context.t('date'),
                      style: context.texts.titleSmall,
                    ),
                  ),
                  Text(
                    Fmt.date(_date, context.lang),
                    style: context.texts.titleSmall?.copyWith(
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),

          SwitchListTile.adaptive(
            value: _recurring,
            onChanged: _busy
                ? null
                : (bool v) => setState(() => _recurring = v),
            contentPadding: EdgeInsets.zero,
            title: Text(
              context.t('recurring'),
              style: context.texts.titleSmall,
            ),
            subtitle: Text(
              context.t('recurringHint'),
              style: context.texts.bodySmall,
            ),
            activeThumbColor: Colors.white,
            activeTrackColor: AppColors.primary,
          ),

          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _notes,
            enabled: !_busy,
            maxLines: 2,
            decoration: InputDecoration(labelText: context.t('notes')),
          ),

          if (!isNew) ...<Widget>[
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _reason,
              enabled: !_busy,
              decoration: InputDecoration(
                labelText: context.t('reason'),
                hintText: context.t('optional'),
              ),
            ),
          ],

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

  Future<void> _pickDate() async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _date,
      // Nobody records an expense for next year, and a fat-fingered date
      // silently lands the spend in the wrong reporting period.
      firstDate: DateTime(now.year - 2),
      lastDate: now,
    );

    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    if (_busy) return;

    final String name = _name.text.trim();
    final double amount =
        double.tryParse(_amount.text.replaceAll(',', '')) ?? 0;

    setState(() {
      _errors = <String, String>{
        if (name.isEmpty) 'name': context.t('required'),
        if (amount <= 0) 'amount': context.t('required'),
      };
      _error = null;
    });
    if (_errors.isNotEmpty) return;

    setState(() => _busy = true);

    try {
      await widget.onSave(
        ExpenseRequest(
          id: widget.expense?.id,
          name: name,
          amount: amount,
          kind: _kind,
          method: _method,
          categoryId: _categoryId,
          date: _date,
          notes: _notes.text.trim(),
          recurring: _recurring,
          reason: _reason.text.trim().isEmpty ? null : _reason.text.trim(),
        ),
      );

      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errors = e.fields;
        _error = e.fields.isEmpty ? e.message : null;
      });
    }
  }

  /// Voids the expense. It is never deleted.
  ///
  /// The reason is asked for before anything happens, not after, because the
  /// server refuses without one — and a spinner that ends in a validation
  /// error reads as a bug rather than as a question.
  Future<void> _cancel() async {
    final String? reason = await _askReason();

    if (reason == null || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await widget.onCancel!(widget.expense!.id, reason);
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    }
  }

  Future<String?> _askReason() async {
    final TextEditingController controller = TextEditingController();

    final String? out = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(context.t('cancelExpense')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              context.t('cancelExpenseNote'),
              style: TextStyle(fontSize: 13, color: context.palette.subtext),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: controller,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(hintText: context.t('reasonHint')),
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
            onPressed: () {
              // Matches the server, which wants at least three characters. A
              // reason of "x" answers nothing a year from now.
              if (controller.text.trim().length < 3) return;
              Navigator.pop(context, controller.text.trim());
            },
            child: Text(context.t('confirm')),
          ),
        ],
      ),
    );

    controller.dispose();

    return out;
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? color : context.palette.card,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm + 2,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(
              color: selected ? color : context.palette.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              if (icon != null) ...<Widget>[
                Icon(
                  icon,
                  size: 15,
                  color: selected ? Colors.white : context.palette.subtext,
                ),
                const SizedBox(width: 5),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.texts.titleSmall?.copyWith(
                    color: selected ? Colors.white : context.palette.subtext,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
