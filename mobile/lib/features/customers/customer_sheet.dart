import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:redux/redux.dart';

import '../../core/i18n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/utils/formatters.dart';
import '../../data/api/api_client.dart';
import '../../data/models/customer.dart';
import '../../data/repository/dacaam_repository.dart';
import '../../redux/app_state.dart';
import '../../redux/effects.dart';
import '../../widgets/app_sheet.dart';
import '../../widgets/buttons.dart';

/// Creates a customer, or edits one. Returns the saved record.
Future<Customer?> showCustomerSheet(
  BuildContext context, {
  Customer? existing,
}) {
  return showAppSheet<Customer>(
    context,
    builder: (BuildContext context) => _CustomerSheet(existing: existing),
  );
}

class _CustomerSheet extends StatefulWidget {
  const _CustomerSheet({this.existing});

  final Customer? existing;

  @override
  State<_CustomerSheet> createState() => _CustomerSheetState();
}

class _CustomerSheetState extends State<_CustomerSheet> {
  late final TextEditingController _name = TextEditingController(
    text: widget.existing?.name ?? '',
  );
  late final TextEditingController _phone = TextEditingController(
    text: widget.existing?.phone ?? '',
  );
  late final TextEditingController _address = TextEditingController(
    text: widget.existing?.address ?? '',
  );
  late final TextEditingController _notes = TextEditingController(
    text: widget.existing?.notes ?? '',
  );
  late final TextEditingController _limit = TextEditingController(
    text: (widget.existing?.creditLimit ?? 0) == 0
        ? ''
        : Fmt.editable(widget.existing!.creditLimit),
  );
  final TextEditingController _reason = TextEditingController();

  String? _error;
  bool _saving = false;

  /// A changed credit limit is the field an auditor asks about, so the reason
  /// box only appears when that is what moved.
  bool get _limitChanged {
    final Customer? c = widget.existing;
    if (c == null) return false;

    return (double.tryParse(_limit.text.replaceAll(',', '')) ?? 0) !=
        c.creditLimit;
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    _notes.dispose();
    _limit.dispose();
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StoreConnector<AppState, Store<AppState>>(
      converter: (Store<AppState> store) => store,
      builder: (BuildContext context, Store<AppState> store) {
        return AppSheet(
          title: widget.existing == null
              ? context.t('addCustomer')
              : context.t('editCustomer'),
          footer: GradientButton(
            label: context.t('save'),
            height: 50,
            loading: _saving,
            onPressed: _saving ? null : () => _save(store),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _Field(
                label: context.t('customerName'),
                controller: _name,
                hint: context.t('customerNameHint'),
                autofocus: widget.existing == null,
                capitalise: true,
              ),
              _Field(
                label: context.t('phone'),
                controller: _phone,
                hint: context.t('customerPhoneHint'),
                keyboard: TextInputType.phone,
              ),
              _Field(
                label: context.t('creditLimit'),
                controller: _limit,
                hint: '0',
                // decimal: true so a limit like 2.5 is typable — the same trap
                // the tax rate fell into.
                keyboard: const TextInputType.numberWithOptions(decimal: true),
                prefix: '${Fmt.prefix}  ',
                helper: context.t('creditLimitHelp'),
                onChanged: (_) => setState(() {}),
              ),
              _Field(
                label: context.t('customerAddress'),
                controller: _address,
                hint: '',
                capitalise: true,
              ),
              _Field(
                label: context.t('customerNotes'),
                controller: _notes,
                hint: '',
                lines: 2,
              ),

              if (_limitChanged)
                _Field(
                  label: context.t('reason'),
                  controller: _reason,
                  hint: context.t('adjustReasonHint'),
                  capitalise: true,
                ),

              if (_error != null) ...<Widget>[
                const SizedBox(height: AppSpacing.sm),
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

  Future<void> _save(Store<AppState> store) async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = context.t('required'));

      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final Customer saved = await Effects.saveCustomer(
        store,
        CustomerRequest(
          id: widget.existing?.id,
          name: _name.text.trim(),
          phone: _phone.text.trim(),
          address: _address.text.trim(),
          notes: _notes.text.trim(),
          creditLimit: double.tryParse(_limit.text.replaceAll(',', '')) ?? 0,
          reason: _reason.text.trim().isEmpty ? null : _reason.text.trim(),
        ),
      );

      if (mounted) Navigator.of(context).pop(saved);
    } on ApiException catch (e) {
      // The server owns the rules this sheet cannot check — a phone already on
      // another account, most of all — so its message is the one shown.
      setState(() {
        _saving = false;
        _error = e.fields.values.isNotEmpty ? e.fields.values.first : e.message;
      });
    }
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    required this.hint,
    this.keyboard,
    this.prefix,
    this.helper,
    this.autofocus = false,
    this.capitalise = false,
    this.lines = 1,
    this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final String hint;
  final TextInputType? keyboard;
  final String? prefix;
  final String? helper;
  final bool autofocus;
  final bool capitalise;
  final int lines;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(label, style: context.texts.titleSmall),
          const SizedBox(height: AppSpacing.xs),
          TextField(
            controller: controller,
            autofocus: autofocus,
            keyboardType: keyboard,
            maxLines: lines,
            onChanged: onChanged,
            textCapitalization: capitalise
                ? TextCapitalization.words
                : TextCapitalization.none,
            decoration: InputDecoration(
              hintText: hint,
              prefixText: prefix,
              helperText: helper,
            ),
          ),
        ],
      ),
    );
  }
}
