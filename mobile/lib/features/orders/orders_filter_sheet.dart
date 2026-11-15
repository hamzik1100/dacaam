import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:redux/redux.dart';

import '../../core/i18n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/utils/enums.dart';
import '../../data/models/dining_table.dart';
import '../../data/models/restaurant.dart';
import '../../redux/actions.dart';
import '../../redux/app_state.dart';
import '../../redux/states/order_state.dart';
import '../../widgets/app_sheet.dart';
import '../../widgets/buttons.dart';

Future<void> showOrdersFilterSheet(BuildContext context) {
  return showAppSheet<void>(
    context,
    builder: (BuildContext context) => const _OrdersFilterSheet(),
  );
}

/// Filters are edited locally and committed on Apply, so a half-built filter
/// never causes the list behind the sheet to thrash.
class _OrdersFilterSheet extends StatefulWidget {
  const _OrdersFilterSheet();

  @override
  State<_OrdersFilterSheet> createState() => _OrdersFilterSheetState();
}

class _OrdersFilterSheetState extends State<_OrdersFilterSheet> {
  OrderFilters? _draft;

  @override
  Widget build(BuildContext context) {
    return StoreConnector<AppState, _FilterVm>(
      converter: _FilterVm.from,
      builder: (BuildContext context, _FilterVm vm) {
        final OrderFilters f = _draft ??= vm.filters;

        return AppSheet(
          title: context.t('filters'),
          trailing: TextButton(
            onPressed: () => setState(
              () => _draft = OrderFilters(status: f.status, query: f.query),
            ),
            child: Text(context.t('reset')),
          ),
          footer: GradientButton(
            label: context.t('apply'),
            icon: Icons.filter_alt_rounded,
            onPressed: () {
              vm.onApply(f);
              Navigator.of(context).pop();
            },
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _Group(
                title: context.t('date'),
                child: _WrapChips<OrderDateRange>(
                  values: OrderDateRange.values,
                  selected: f.dateRange,
                  labelOf: (OrderDateRange r) => context.t(switch (r) {
                    OrderDateRange.today => 'today',
                    OrderDateRange.yesterday => 'yesterday',
                    OrderDateRange.thisWeek => 'thisWeek',
                    OrderDateRange.thisMonth => 'thisMonth',
                    OrderDateRange.all => 'all',
                  }),
                  onSelected: (OrderDateRange r) =>
                      setState(() => _draft = f.copyWith(dateRange: r)),
                ),
              ),
              _Group(
                title: context.t('orderType'),
                child: _WrapChips<OrderType?>(
                  values: <OrderType?>[null, ...OrderType.values],
                  selected: f.type,
                  labelOf: (OrderType? t) =>
                      t == null ? context.t('all') : context.t(t.labelKey),
                  onSelected: (OrderType? t) => setState(
                    () => _draft = t == null
                        ? f.copyWith(clearType: true)
                        : f.copyWith(type: t),
                  ),
                ),
              ),
              _Group(
                title: context.t('waiter'),
                child: _WrapChips<String?>(
                  values: <String?>[null, ...vm.waiterNames],
                  selected: f.waiterName,
                  labelOf: (String? w) => w ?? context.t('all'),
                  onSelected: (String? w) => setState(
                    () => _draft = w == null
                        ? f.copyWith(clearWaiter: true)
                        : f.copyWith(waiterName: w),
                  ),
                ),
              ),
              _Group(
                title: context.t('table'),
                child: _WrapChips<int?>(
                  values: <int?>[
                    null,
                    ...vm.tables.map((DiningTable t) => t.id),
                  ],
                  selected: f.tableId,
                  labelOf: (int? id) => id == null
                      ? context.t('all')
                      : vm.tables
                            .firstWhere((DiningTable t) => t.id == id)
                            .label,
                  onSelected: (int? id) => setState(
                    () => _draft = id == null
                        ? f.copyWith(clearTable: true)
                        : f.copyWith(tableId: id),
                  ),
                ),
              ),
              _Group(
                title: context.t('paymentMethod'),
                child: _WrapChips<PaymentMethod?>(
                  values: <PaymentMethod?>[
                    null,
                    ...StoreProvider.of<AppState>(
                      context,
                      listen: false,
                    ).state.accounts.pickable,
                  ],
                  selected: f.paymentMethod,
                  labelOf: (PaymentMethod? m) => m?.label ?? context.t('all'),
                  onSelected: (PaymentMethod? m) => setState(
                    () => _draft = m == null
                        ? f.copyWith(clearPayment: true)
                        : f.copyWith(paymentMethod: m),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: context.texts.titleMedium),
          const SizedBox(height: AppSpacing.md),
          child,
        ],
      ),
    );
  }
}

class _WrapChips<T> extends StatelessWidget {
  const _WrapChips({
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onSelected,
  });

  final List<T> values;
  final T selected;
  final String Function(T) labelOf;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: values.map((T v) {
        final bool isSelected = v == selected;
        return Material(
          color: isSelected ? AppColors.primary : context.palette.card,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => onSelected(v),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.sm + 1,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.pill),
                border: Border.all(
                  color: isSelected
                      ? AppColors.primary
                      : context.palette.border,
                ),
              ),
              child: Text(
                labelOf(v),
                style: context.texts.titleSmall?.copyWith(
                  color: isSelected ? Colors.white : context.palette.subtext,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _FilterVm {
  const _FilterVm({
    required this.filters,
    required this.waiterNames,
    required this.tables,
    required this.onApply,
  });

  factory _FilterVm.from(Store<AppState> store) {
    final AppState s = store.state;
    return _FilterVm(
      filters: s.orders.filters,
      waiterNames: s.restaurant.waiters
          .map((AppUser u) => u.name.split(' ').first)
          .toList(),
      tables: s.tables.selectable,
      onApply: (OrderFilters f) => store.dispatch(OrderFiltersChanged(f)),
    );
  }

  final OrderFilters filters;
  final List<String> waiterNames;
  final List<DiningTable> tables;
  final ValueChanged<OrderFilters> onApply;
}
