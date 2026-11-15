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
import '../../data/repository/dacaam_repository.dart';
import '../../redux/actions.dart';
import '../../redux/app_state.dart';
import '../../redux/states/pos_state.dart';
import '../../redux/effects.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_sheet.dart';
import '../../widgets/buttons.dart';
import '../../widgets/common.dart';

/// Parks the current cart as a draft.
///
/// A draft is not a sale — nothing here reaches reports, KPIs or account
/// balances. The customer name is the one required field, because a parked
/// order nobody can put a name to cannot be handed back to anyone.
Future<bool?> showSaveDraftSheet(BuildContext context) {
  return showAppSheet<bool>(
    context,
    builder: (BuildContext context) => const _SaveDraftSheet(),
  );
}

class _SaveDraftSheet extends StatefulWidget {
  const _SaveDraftSheet();

  @override
  State<_SaveDraftSheet> createState() => _SaveDraftSheetState();
}

class _SaveDraftSheetState extends State<_SaveDraftSheet> {
  // Filled from the cart, which carries them when this is a draft being
  // changed. Asking again for a name the app already knows is how a
  // customer ends up renamed to a blank on the second save.
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _notes;

  @override
  void initState() {
    super.initState();

    final CartState cart = StoreProvider.of<AppState>(
      context,
      listen: false,
    ).state.cart;

    _name = TextEditingController(text: cart.customerName);
    _phone = TextEditingController(text: cart.customerPhone);
    _notes = TextEditingController(text: cart.notes);
  }

  bool _busy = false;
  String? _nameError;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StoreConnector<AppState, _SaveDraftVm>(
      converter: _SaveDraftVm.from,
      builder: (BuildContext context, _SaveDraftVm vm) {
        return AppSheet(
          // Says which of the two it is. "Save as draft" over an order that
          // already exists reads as though a second one is about to appear.
          title: context.t(
            vm.editingDraftId == null ? 'saveAsDraft' : 'updateDraft',
          ),
          subtitle: context.tp('itemsCount', <String, String>{
            'n': '${vm.itemCount}',
          }),
          footer: GradientButton(
            label: context.t('save'),
            icon: Icons.bookmark_add_rounded,
            loading: _busy,
            onPressed: () => _save(vm),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              TextField(
                controller: _name,
                autofocus: true,
                enabled: !_busy,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: context.t('customer'),
                  errorText: _nameError,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              TextField(
                controller: _phone,
                enabled: !_busy,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: '${context.t('phone')} (${context.t('optional')})',
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              TextField(
                controller: _notes,
                enabled: !_busy,
                maxLines: 2,
                decoration: InputDecoration(labelText: context.t('notes')),
              ),
              const SizedBox(height: AppSpacing.xl),

              AppCard(
                color: context.palette.muted,
                elevated: false,
                child: Column(
                  children: <Widget>[
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
                    DetailRow(
                      label: context.t('subtotal'),
                      value: Fmt.money(vm.subtotal),
                      bold: true,
                      valueColor: AppColors.primary,
                    ),
                  ],
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
      },
    );
  }

  Future<void> _save(_SaveDraftVm vm) async {
    if (_busy) return;

    final String name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = context.t('required'));

      return;
    }

    setState(() {
      _busy = true;
      _nameError = null;
      _error = null;
    });

    try {
      await vm.onSave(
        DraftRequest(
          // The draft this cart came from, when it came from one. Without
          // it a customer who rang back to change their order would end up
          // with two tickets and a kitchen serving both.
          id: vm.editingDraftId,
          customerName: name,
          customerPhone: _phone.text.trim(),
          type: vm.orderType,
          tableId: vm.tableId,
          lines: vm.lines,
          notes: _notes.text.trim(),
        ),
      );

      vm.onClearCart();
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _nameError = e.fields['customer_name'];
        _error = e.fields.isEmpty ? e.message : null;
      });
    }
  }
}

class _SaveDraftVm {
  const _SaveDraftVm({
    required this.lines,
    required this.itemCount,
    required this.subtotal,
    required this.orderType,
    required this.tableId,
    required this.editingDraftId,
    required this.onSave,
    required this.onClearCart,
  });

  factory _SaveDraftVm.from(Store<AppState> store) {
    final AppState s = store.state;

    return _SaveDraftVm(
      lines: s.cart.lines,
      itemCount: s.cart.itemCount,
      subtotal: s.cartTotals.subtotal,
      orderType: s.cart.orderType,
      tableId: s.cart.tableId,
      editingDraftId: s.cart.editingDraftId,
      onSave: (DraftRequest r) => Effects.saveDraft(store, r),
      onClearCart: () => store.dispatch(const CartCleared()),
    );
  }

  final List<OrderLine> lines;
  final int itemCount;
  final double subtotal;
  final OrderType orderType;
  final int? tableId;

  /// The parked order being changed, or null for a new one.
  final int? editingDraftId;
  final Future<void> Function(DraftRequest) onSave;
  final VoidCallback onClearCart;
}
