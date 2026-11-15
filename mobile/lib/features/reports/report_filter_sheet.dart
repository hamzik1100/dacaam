import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:redux/redux.dart';

import '../../core/i18n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/utils/enums.dart';
import '../../data/models/dining_table.dart';
import '../../data/models/menu.dart';
import '../../data/models/restaurant.dart';
import '../../redux/app_state.dart';
import '../../redux/effects.dart';
import '../../redux/states/report_state.dart';
import '../../widgets/app_sheet.dart';
import '../../widgets/buttons.dart';

Future<void> showReportFilterSheet(BuildContext context) {
  return showAppSheet<void>(
    context,
    builder: (BuildContext context) => const _ReportFilterSheet(),
  );
}

/// Cross-cutting report filters (§29).
///
/// Edited locally and committed on Apply, so a half-built filter never causes
/// the report behind the sheet to reload three times.
class _ReportFilterSheet extends StatefulWidget {
  const _ReportFilterSheet();

  @override
  State<_ReportFilterSheet> createState() => _ReportFilterSheetState();
}

class _ReportFilterSheetState extends State<_ReportFilterSheet> {
  ReportFilters? _draft;

  @override
  Widget build(BuildContext context) {
    return StoreConnector<AppState, _FilterVm>(
      converter: _FilterVm.from,
      builder: (BuildContext context, _FilterVm vm) {
        final ReportFilters f = _draft ??= vm.filters;

        return AppSheet(
          title: context.t('filters'),
          trailing: TextButton(
            onPressed: () => setState(() => _draft = const ReportFilters()),
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
                title: context.t('waiter'),
                child: _Chips<String?>(
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
                title: context.t('orderType'),
                child: _Chips<OrderType?>(
                  values: <OrderType?>[null, ...OrderType.values],
                  selected: f.orderType,
                  labelOf: (OrderType? t) =>
                      t == null ? context.t('all') : context.t(t.labelKey),
                  onSelected: (OrderType? t) => setState(
                    () => _draft = t == null
                        ? f.copyWith(clearType: true)
                        : f.copyWith(orderType: t),
                  ),
                ),
              ),
              _Group(
                title: context.t('category'),
                child: _Chips<int?>(
                  values: <int?>[
                    null,
                    ...vm.categories.map((MenuCategory c) => c.id),
                  ],
                  selected: f.categoryId,
                  labelOf: (int? id) => id == null
                      ? context.t('all')
                      : vm.categories
                            .firstWhere((MenuCategory c) => c.id == id)
                            .name,
                  onSelected: (int? id) => setState(
                    () => _draft = id == null
                        ? f.copyWith(clearCategory: true)
                        : f.copyWith(categoryId: id),
                  ),
                ),
              ),
              _Group(
                title: context.t('table'),
                child: _Chips<int?>(
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
                child: _Chips<PaymentMethod?>(
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
              if (!f.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Row(
                    children: <Widget>[
                      Icon(
                        Icons.info_outline_rounded,
                        size: 15,
                        color: context.palette.subtext,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          context.t('filteredExpensesNote'),
                          style: context.texts.bodySmall,
                        ),
                      ),
                    ],
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

class _Chips<T> extends StatelessWidget {
  const _Chips({
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
    required this.categories,
    required this.tables,
    required this.onApply,
  });

  factory _FilterVm.from(Store<AppState> store) {
    final AppState s = store.state;

    return _FilterVm(
      filters: s.reports.filters,
      waiterNames: s.restaurant.staff
          .map((AppUser u) => u.name.split(' ').first)
          .toSet()
          .toList(),
      categories: s.categories.categories,
      tables: s.tables.selectable,
      onApply: (ReportFilters f) => Effects.changeReportFilters(store, f),
    );
  }

  final ReportFilters filters;
  final List<String> waiterNames;
  final List<MenuCategory> categories;
  final List<DiningTable> tables;
  final ValueChanged<ReportFilters> onApply;
}
