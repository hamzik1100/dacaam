import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:redux/redux.dart';

import '../../core/i18n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/utils/enums.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/dining_table.dart';
import '../../data/models/order.dart';
import '../../data/models/restaurant.dart';
import '../../redux/app_state.dart';
import '../../widgets/app_sheet.dart';
import '../../widgets/buttons.dart';

/// What the counter chose when turning a draft into a real order.
class ConvertChoice {
  const ConvertChoice({
    required this.type,
    required this.method,
    this.tableId,
    this.waiterId,
  });

  final OrderType type;
  final PaymentMethod method;
  final int? tableId;
  final int? waiterId;
}

/// Asks for everything the order needs that the draft does not already settle.
///
/// A draft is parked before any of this is known — the customer has not said
/// whether they are eating in, no table has been given to them, and nobody has
/// paid. Converting used to send the draft's stored values straight through,
/// which failed validation the moment a dine-in draft had no table. So this is
/// asked here, at the counter, when the answers actually exist.
Future<ConvertChoice?> showConvertDraftSheet(
  BuildContext context,
  DraftOrder draft,
) {
  return showAppSheet<ConvertChoice>(
    context,
    builder: (BuildContext context) => _ConvertSheet(draft: draft),
  );
}

class _ConvertSheet extends StatefulWidget {
  const _ConvertSheet({required this.draft});

  final DraftOrder draft;

  @override
  State<_ConvertSheet> createState() => _ConvertSheetState();
}

class _ConvertSheetState extends State<_ConvertSheet> {
  late OrderType _type = widget.draft.type;
  int? _tableId;
  int? _waiterId;
  PaymentMethod? _method;
  String? _error;

  @override
  Widget build(BuildContext context) {
    return StoreConnector<AppState, _ConvertVm>(
      converter: _ConvertVm.from,
      builder: (BuildContext context, _ConvertVm vm) {
        final bool dineIn = _type == OrderType.dineIn;

        return AppSheet(
          title: context.t('convert'),
          subtitle: widget.draft.customerName,
          footer: GradientButton(
            label: context.t('placeOrder'),
            height: 50,
            onPressed: () => _submit(context, vm),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(context.t('orderType'), style: context.texts.titleSmall),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: <Widget>[
                  Expanded(
                    child: _TypeTile(
                      label: context.t('dineIn'),
                      icon: Icons.restaurant_rounded,
                      selected: dineIn,
                      onTap: () => setState(() => _type = OrderType.dineIn),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: _TypeTile(
                      label: context.t('takeaway'),
                      icon: Icons.takeout_dining_rounded,
                      selected: !dineIn,
                      onTap: () => setState(() {
                        _type = OrderType.takeaway;
                        // A takeaway holds no table — the orders table has a
                        // CHECK that says so, and the server clears it too.
                        _tableId = null;
                      }),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: AppSpacing.lg),

              if (dineIn) ...<Widget>[
                Text(
                  '${context.t('table')}${vm.requireTable ? ' *' : ''}',
                  style: context.texts.titleSmall,
                ),
                const SizedBox(height: AppSpacing.sm),
                _Picker<DiningTable>(
                  items: vm.freeTables,
                  selectedId: _tableId,
                  idOf: (DiningTable t) => t.id,
                  labelOf: (DiningTable t) => t.label,
                  empty: context.t('noFreeTables'),
                  onSelected: (int? id) => setState(() => _tableId = id),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(context.t('waiter'), style: context.texts.titleSmall),
                const SizedBox(height: AppSpacing.sm),
                _Picker<AppUser>(
                  items: vm.staff,
                  selectedId: _waiterId,
                  idOf: (AppUser u) => u.id,
                  labelOf: (AppUser u) => u.name,
                  empty: '—',
                  onSelected: (int? id) => setState(() => _waiterId = id),
                ),
              ] else if (vm.packagingFeeEnabled && vm.packagingFee > 0)
                // Shown rather than sprung on them at the total: the fee is a
                // consequence of choosing takeaway, so it belongs next to it.
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.secondary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Row(
                    children: <Widget>[
                      const Icon(
                        Icons.inventory_2_rounded,
                        size: 18,
                        color: AppColors.secondary,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          context.t('packagingFee'),
                          style: context.texts.bodyMedium,
                        ),
                      ),
                      Text(
                        Fmt.money(vm.packagingFee),
                        style: context.texts.titleSmall?.copyWith(
                          color: AppColors.secondary,
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: AppSpacing.lg),
              Text(context.t('paymentMethod'), style: context.texts.titleSmall),
              const SizedBox(height: AppSpacing.sm),
              ...StoreProvider.of<AppState>(
                context,
                listen: false,
              ).state.accounts.pickable.map(
                (PaymentMethod m) => SheetOptionTile(
                  label: m.label,
                  icon: m.icon,
                  tint: m.color,
                  selected: _method == m,
                  onTap: () => setState(() => _method = m),
                ),
              ),

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

  void _submit(BuildContext context, _ConvertVm vm) {
    if (_type == OrderType.dineIn && vm.requireTable && _tableId == null) {
      setState(() => _error = context.t('tableRequired'));

      return;
    }

    if (_method == null) {
      setState(() => _error = context.t('paymentMethodRequired'));

      return;
    }

    Navigator.of(context).pop(
      ConvertChoice(
        type: _type,
        method: _method!,
        tableId: _type == OrderType.dineIn ? _tableId : null,
        waiterId: _waiterId,
      ),
    );
  }
}

class _TypeTile extends StatelessWidget {
  const _TypeTile({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.10)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: selected ? AppColors.primary : context.palette.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          children: <Widget>[
            Icon(
              icon,
              size: 22,
              color: selected ? AppColors.primary : context.palette.subtext,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              label,
              style: context.texts.titleSmall?.copyWith(
                color: selected ? AppColors.primary : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Picker<T> extends StatelessWidget {
  const _Picker({
    required this.items,
    required this.selectedId,
    required this.idOf,
    required this.labelOf,
    required this.empty,
    required this.onSelected,
  });

  final List<T> items;
  final int? selectedId;
  final int Function(T) idOf;
  final String Function(T) labelOf;
  final String empty;
  final ValueChanged<int?> onSelected;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Text(
        empty,
        style: context.texts.bodySmall?.copyWith(
          color: context.palette.subtext,
        ),
      );
    }

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: items.map((T item) {
        final bool on = idOf(item) == selectedId;

        return ChoiceChip(
          label: Text(labelOf(item)),
          selected: on,
          onSelected: (_) => onSelected(on ? null : idOf(item)),
        );
      }).toList(),
    );
  }
}

class _ConvertVm {
  const _ConvertVm({
    required this.freeTables,
    required this.staff,
    required this.requireTable,
    required this.packagingFee,
    required this.packagingFeeEnabled,
  });

  factory _ConvertVm.from(Store<AppState> store) {
    final AppState s = store.state;

    return _ConvertVm(
      // An occupied table cannot take a second order, so offering it would
      // only produce a refusal one tap later.
      freeTables: s.tables.tables
          .where((DiningTable t) => t.status == TableStatus.available)
          .toList(),
      staff: s.restaurant.staff,
      requireTable: s.settings.requireTableForDineIn,
      packagingFee: s.settings.packagingFee,
      packagingFeeEnabled: s.settings.packagingFeeEnabled,
    );
  }

  final List<DiningTable> freeTables;
  final List<AppUser> staff;
  final bool requireTable;
  final double packagingFee;
  final bool packagingFeeEnabled;
}
