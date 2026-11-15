import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:redux/redux.dart';

import '../../core/i18n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/utils/enums.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/analytics.dart';
import '../../redux/app_state.dart';
import '../../redux/effects.dart';
import '../../data/api/api_client.dart';
import '../../redux/states/report_state.dart';
import '../../redux/states/status.dart';
import '../../widgets/app_card.dart';
import '../../widgets/buttons.dart';
import '../../widgets/charts.dart';
import '../../widgets/common.dart';
import '../../widgets/entrance.dart';
import '../../widgets/food_thumb.dart';
import '../../widgets/kpi_card.dart';
import '../../widgets/skeletons.dart';
import '../../widgets/app_sheet.dart';
import '../../widgets/states.dart';
import '../customers/customer_profile_screen.dart';
import 'report_filter_sheet.dart';

/// Analytics module: sales, product, financial and order reporting over a
/// selectable period.
class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return StoreConnector<AppState, _ReportsVm>(
      converter: _ReportsVm.from,
      builder: (BuildContext context, _ReportsVm vm) {
        return Scaffold(
          body: SafeArea(
            bottom: false,
            child: Column(
              children: <Widget>[
                _Header(vm: vm),
                ChipSelector<ReportRange>(
                  values: ReportRange.values,
                  selected: vm.range,
                  labelOf: (ReportRange r) => context.t(r.labelKey),
                  onSelected: (ReportRange r) => r == ReportRange.custom
                      ? _pickCustomRange(context, vm)
                      : vm.onRange(r),
                ),
                const SizedBox(height: AppSpacing.md),
                Expanded(
                  child: switch (vm.status) {
                    Status.error => ErrorStateView(
                      onRetry: () => vm.onRange(vm.range),
                    ),
                    Status.idle || Status.loading => const DashboardSkeleton(),
                    Status.ready => _Body(vm: vm),
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// The Custom chip opens a range picker rather than selecting a fixed span —
  /// "custom" with no dates would just be a seventh preset.
  Future<void> _pickCustomRange(BuildContext context, _ReportsVm vm) async {
    final DateTime now = DateTime.now();
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: now,
      initialDateRange: vm.report.from != null && vm.report.to != null
          ? DateTimeRange(start: vm.report.from!, end: vm.report.to!)
          : DateTimeRange(
              start: now.subtract(const Duration(days: 13)),
              end: now,
            ),
    );

    if (picked == null || !context.mounted) return;

    vm.onCustomRange(picked.start, picked.end);
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.vm});

  final _ReportsVm vm;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        AppSpacing.md,
        AppSpacing.gutter,
        AppSpacing.lg,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  context.t('navReports'),
                  style: context.texts.headlineSmall,
                ),
                Text(vm.periodLabel(context), style: context.texts.bodySmall),
              ],
            ),
          ),
          SoftIconButton(
            icon: Icons.tune_rounded,
            badgeCount: vm.filters.activeCount,
            onPressed: () => showReportFilterSheet(context),
          ),
          if (vm.canExport) ...<Widget>[
            const SizedBox(width: AppSpacing.sm),
            SoftIconButton(
              icon: Icons.ios_share_rounded,
              onPressed: () => _export(context),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _export(BuildContext context) async {
    final String? type = await showAppSheet<String>(
      context,
      builder: (BuildContext context) => AppSheet(
        title: context.t('export'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SheetOptionTile(
              label: context.t('navOrders'),
              icon: Icons.receipt_long_rounded,
              selected: false,
              onTap: () => Navigator.of(context).pop('orders'),
            ),
            SheetOptionTile(
              label: context.t('items'),
              icon: Icons.restaurant_menu_rounded,
              selected: false,
              onTap: () => Navigator.of(context).pop('items'),
            ),
            SheetOptionTile(
              label: context.t('expenses'),
              icon: Icons.account_balance_wallet_rounded,
              selected: false,
              onTap: () => Navigator.of(context).pop('expenses'),
            ),
          ],
        ),
      ),
    );

    if (type == null || !context.mounted) return;

    final Store<AppState> store = StoreProvider.of<AppState>(
      context,
      listen: false,
    );

    try {
      final File file = await Effects.exportReport(store, type: type);
      if (!context.mounted) return;

      await showDialog<void>(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          title: Text(context.t('export')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(context.t('exportSaved'), style: context.texts.bodyMedium),
              const SizedBox(height: AppSpacing.md),
              SelectableText(
                file.path,
                style: context.texts.bodySmall?.copyWith(fontSize: 11),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () async {
                final String csv = await Effects.exportReportCsv(
                  store,
                  type: type,
                );
                await Clipboard.setData(ClipboardData(text: csv));
                if (context.mounted) Navigator.pop(context);
              },
              child: Text(context.t('copy')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.t('done')),
            ),
          ],
        ),
      );
    } on ApiException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.vm});

  final _ReportsVm vm;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        0,
        AppSpacing.gutter,
        AppSpacing.xxxl,
      ),
      children: <Widget>[
        Entrance(index: 0, child: _Kpis(vm: vm)),
        const SizedBox(height: AppSpacing.lg),
        Entrance(index: 1, child: _SalesOverview(vm: vm)),
        const SizedBox(height: AppSpacing.lg),
        Entrance(index: 2, child: _CategoryCard(vm: vm)),
        const SizedBox(height: AppSpacing.lg),
        Entrance(index: 3, child: _FinancialCard(vm: vm)),
        const SizedBox(height: AppSpacing.lg),
        Entrance(index: 3, child: _CashCard(vm: vm)),
        const SizedBox(height: AppSpacing.lg),
        if (vm.report.topDebtors.isNotEmpty) ...<Widget>[
          Entrance(index: 4, child: _DebtorsCard(vm: vm)),
          const SizedBox(height: AppSpacing.lg),
        ],
        Entrance(index: 4, child: _OrderAnalyticsCard(vm: vm)),
        const SizedBox(height: AppSpacing.lg),
        Entrance(index: 5, child: _PaymentCard(vm: vm)),
        const SizedBox(height: AppSpacing.lg),
        Entrance(index: 6, child: _WaiterCard(vm: vm)),
        const SizedBox(height: AppSpacing.lg),
        Entrance(index: 7, child: _TableSalesCard(vm: vm)),
        const SizedBox(height: AppSpacing.lg),
        Entrance(index: 8, child: _TopItemsCard(vm: vm)),
        const SizedBox(height: AppSpacing.lg),
        Entrance(index: 9, child: _LowItemsCard(vm: vm)),
        const SizedBox(height: AppSpacing.lg),
        Entrance(index: 10, child: _HourlyCard(vm: vm)),
      ],
    );
  }
}

class _Kpis extends StatelessWidget {
  const _Kpis({required this.vm});

  final _ReportsVm vm;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: KpiCard(
                label: context.t('totalSales'),
                value: vm.report.sales.value,
                deltaPercent: vm.report.sales.deltaPercent,
                format: Fmt.moneyCompact,
                icon: Icons.trending_up_rounded,
                tint: AppColors.primary,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: KpiCard(
                label: context.t('totalOrders'),
                value: vm.report.orders.value,
                deltaPercent: vm.report.orders.deltaPercent,
                format: (double v) => Fmt.number(v.round()),
                icon: Icons.receipt_long_rounded,
                tint: AppColors.secondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: <Widget>[
            Expanded(
              child: KpiCard(
                label: context.t('totalExpenses'),
                value: vm.report.expenses.value,
                deltaPercent: vm.report.expenses.deltaPercent,
                format: Fmt.moneyCompact,
                icon: Icons.receipt_rounded,
                tint: AppColors.violet,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: KpiCard(
                label: context.t('netProfit'),
                value: vm.report.profit.value,
                deltaPercent: vm.report.profit.deltaPercent,
                format: Fmt.moneyCompact,
                icon: Icons.savings_rounded,
                tint: AppColors.success,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SalesOverview extends StatelessWidget {
  const _SalesOverview({required this.vm});

  final _ReportsVm vm;

  @override
  Widget build(BuildContext context) {
    final List<SeriesPoint> daily = vm.report.daily;
    if (daily.isEmpty) return const SizedBox.shrink();

    final List<String> labels = daily.length == 7
        ? Fmt.weekdayLabels(context.lang)
        : daily.map((SeriesPoint p) => p.label).toList();

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SectionHeader(
            title: context.t('salesOverview'),
            trailing: Text(
              Fmt.moneyCompact(vm.report.sales.value),
              style: context.texts.titleMedium?.copyWith(
                color: AppColors.primary,
              ),
            ),
          ),
          SalesBarChart(
            points: daily,
            labels: labels,
            barWidth: daily.length > 14 ? 6 : 16,
            labelInterval: daily.length > 14 ? 5 : 1,
          ),
        ],
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({required this.vm});

  final _ReportsVm vm;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SectionHeader(title: context.t('salesByCategory')),
          DonutBreakdown(slices: vm.report.byCategory),
        ],
      ),
    );
  }
}

class _FinancialCard extends StatelessWidget {
  const _FinancialCard({required this.vm});

  final _ReportsVm vm;

  @override
  Widget build(BuildContext context) {
    final ReportState r = vm.report;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SectionHeader(title: context.t('financialSummary')),
          DetailRow(
            label: context.t('grossSales'),
            value: Fmt.money(r.grossSales),
          ),
          DetailRow(
            label: context.t('discount'),
            value: '- ${Fmt.money(r.discounts)}',
            valueColor: AppColors.danger,
          ),
          DetailRow(label: context.t('tax'), value: Fmt.money(r.tax)),
          DetailRow(
            label: context.t('packagingFee'),
            value: Fmt.money(r.packaging),
          ),
          DetailRow(
            label: context.t('totalSales'),
            value: Fmt.money(r.sales.value),
          ),
          DetailRow(
            label: context.t('totalExpenses'),
            value: '- ${Fmt.money(r.expenses.value)}',
            valueColor: AppColors.danger,
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: DashedDivider(),
          ),
          DetailRow(
            label: context.t('netProfit'),
            value: Fmt.money(r.profit.value),
            bold: true,
            valueColor: AppColors.success,
          ),
        ],
      ),
    );
  }
}

/// What was actually collected, next to what was sold.
///
/// The card above this one is accrual: a sale counts the moment the food goes
/// out, whether or not anybody paid. This one is cash. Both are true, and a
/// restaurant selling on credit is misled by either one alone — which is why
/// they sit next to each other rather than one replacing the other.
class _CashCard extends StatelessWidget {
  const _CashCard({required this.vm});

  final _ReportsVm vm;

  @override
  Widget build(BuildContext context) {
    final ReportState r = vm.report;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SectionHeader(title: context.t('cashCollected')),
          DetailRow(
            label: context.t('bookSales'),
            value: Fmt.money(r.sales.value),
          ),
          DetailRow(label: context.t('cashIn'), value: Fmt.money(r.cash.moneyIn)),
          DetailRow(
            label: context.t('cashOut'),
            value: '- ${Fmt.money(r.cash.moneyOut)}',
            valueColor: AppColors.danger,
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: DashedDivider(),
          ),
          DetailRow(
            label: context.t('netCash'),
            value: Fmt.money(r.cash.net),
            bold: true,
            valueColor: AppColors.success,
          ),

          // Only worth showing once credit is actually in use; on a
          // cash-only restaurant these are all zero and just noise.
          if (r.cash.fromCustomers > 0 || r.receivables > 0) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            DetailRow(
              label: context.t('fromDebtRepayment'),
              value: Fmt.money(r.cash.fromCustomers),
            ),
            DetailRow(
              label: context.t('fromTrade'),
              value: Fmt.money(r.cash.fromTrade),
            ),
          ],

          const SizedBox(height: AppSpacing.sm),
          DetailRow(
            label: context.t('receivables'),
            value: Fmt.money(r.receivables),
            valueColor: r.receivables > 0 ? AppColors.danger : null,
          ),
          DetailRow(
            label: context.t('depositsHeld'),
            value: Fmt.money(r.depositsHeld),
          ),
          // Only when there is some. A restaurant where every order is settled
          // should not be shown a permanent zero labelled as a problem — but
          // one shilling here is a shilling sold that nobody is carrying, and
          // that has to be on the page rather than left as the unexplained
          // difference between sales and cash.
          if (r.unpaidOrders > 0)
            DetailRow(
              label: context.t('unpaidOrders'),
              value: Fmt.money(r.unpaidOrders),
              valueColor: AppColors.secondary,
            ),

          const SizedBox(height: AppSpacing.sm),
          Text(
            context.t('accrualNote'),
            style: context.texts.bodySmall?.copyWith(
              color: context.palette.subtext,
            ),
          ),
        ],
      ),
    );
  }
}

/// Who owes the most, right now — not scoped to the report period, because a
/// debt from March is still a debt in August.
class _DebtorsCard extends StatelessWidget {
  const _DebtorsCard({required this.vm});

  final _ReportsVm vm;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SectionHeader(
            title: context.t('topDebtors'),
            trailing: Text(
              Fmt.moneyCompact(vm.report.receivables),
              style: context.texts.titleMedium?.copyWith(
                color: AppColors.danger,
              ),
            ),
          ),
          ...vm.report.topDebtors.map((CustomerRank d) {
            return InkWell(
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      CustomerProfileScreen(customerId: d.customerId),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            d.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.texts.bodyMedium,
                          ),
                          // Never having paid is the thing a manager is
                          // looking for, so it is stated rather than left as
                          // an absent date.
                          Text(
                            d.lastPaid == null
                                ? context.t('neverPaid')
                                : '${context.t('lastPaid')} ${Fmt.date(d.lastPaid!, context.lang)}',
                            style: context.texts.labelSmall?.copyWith(
                              color: d.lastPaid == null
                                  ? AppColors.danger
                                  : context.palette.subtext,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      Fmt.money(d.balanceOwed),
                      style: context.texts.titleSmall?.copyWith(
                        color: AppColors.danger,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _OrderAnalyticsCard extends StatelessWidget {
  const _OrderAnalyticsCard({required this.vm});

  final _ReportsVm vm;

  @override
  Widget build(BuildContext context) {
    final ReportState r = vm.report;
    final int typeTotal = r.dineInOrders + r.takeawayOrders;
    final double dineInShare = typeTotal == 0 ? 0 : r.dineInOrders / typeTotal;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SectionHeader(title: context.t('orderAnalytics')),
          Row(
            children: <Widget>[
              Expanded(
                child: MiniStat(
                  label: context.t('totalOrders'),
                  value: Fmt.number(r.orders.value.round()),
                  icon: Icons.receipt_long_rounded,
                ),
              ),
              Expanded(
                child: MiniStat(
                  label: context.t('avgOrderValue'),
                  value: Fmt.moneyCompact(r.avgOrderValue),
                  icon: Icons.calculate_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: <Widget>[
              Expanded(
                child: MiniStat(
                  label: context.t('completedOrders'),
                  value: '${r.completedOrders}',
                  color: AppColors.success,
                  icon: Icons.check_circle_rounded,
                ),
              ),
              Expanded(
                child: MiniStat(
                  label: context.t('cancelledOrders'),
                  value: '${r.cancelledOrders}',
                  color: AppColors.danger,
                  icon: Icons.cancel_rounded,
                ),
              ),
              Expanded(
                child: MiniStat(
                  label: context.t('draftOrders'),
                  value: '${r.draftOrders}',
                  color: AppColors.secondary,
                  icon: Icons.edit_note_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(context.t('dineInVsTakeaway'), style: context.texts.titleSmall),
          const SizedBox(height: AppSpacing.md),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: dineInShare),
              duration: AppMotion.chart,
              curve: Curves.easeOutCubic,
              builder: (BuildContext context, double v, _) {
                return Row(
                  children: <Widget>[
                    Expanded(
                      flex: (v * 1000).round().clamp(1, 999),
                      child: Container(height: 10, color: AppColors.violet),
                    ),
                    Expanded(
                      flex: ((1 - v) * 1000).round().clamp(1, 999),
                      child: Container(height: 10, color: AppColors.info),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: <Widget>[
              _LegendDot(
                color: AppColors.violet,
                label: '${context.t('dineIn')} · ${r.dineInOrders}',
              ),
              const SizedBox(width: AppSpacing.lg),
              _LegendDot(
                color: AppColors.info,
                label: '${context.t('takeaway')} · ${r.takeawayOrders}',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: context.texts.bodySmall),
      ],
    );
  }
}

class _PaymentCard extends StatelessWidget {
  const _PaymentCard({required this.vm});

  final _ReportsVm vm;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SectionHeader(title: context.t('paymentBreakdown')),
          DonutBreakdown(
            slices: vm.report.byPayment,
            formatValue: Fmt.compact,
            centerValue: Fmt.compact(vm.report.sales.value),
            centerLabel: context.t('total'),
          ),
        ],
      ),
    );
  }
}

class _WaiterCard extends StatelessWidget {
  const _WaiterCard({required this.vm});

  final _ReportsVm vm;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SectionHeader(title: context.t('salesByWaiter')),
          BreakdownBars(
            slices: vm.report.byWaiter,
            formatValue: Fmt.moneyCompact,
          ),
        ],
      ),
    );
  }
}

class _TableSalesCard extends StatelessWidget {
  const _TableSalesCard({required this.vm});

  final _ReportsVm vm;

  @override
  Widget build(BuildContext context) {
    if (vm.report.byTable.isEmpty) return const SizedBox.shrink();

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SectionHeader(title: context.t('salesByTable')),
          BreakdownBars(
            slices: vm.report.byTable,
            formatValue: Fmt.moneyCompact,
          ),
        ],
      ),
    );
  }
}

/// What is not selling. Just as actionable as the top sellers, and the only
/// place a manager finds out an item is dead stock.
class _LowItemsCard extends StatelessWidget {
  const _LowItemsCard({required this.vm});

  final _ReportsVm vm;

  @override
  Widget build(BuildContext context) {
    if (vm.report.lowItems.isEmpty) return const SizedBox.shrink();

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SectionHeader(title: context.t('lowSellingItems')),
          ...vm.report.lowItems.map(
            (RankedItem item) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Row(
                children: <Widget>[
                  FoodThumb(
                    emoji: item.emoji,
                    size: 34,
                    radius: 9,
                    tint: AppColors.subtextLight,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.texts.titleSmall,
                    ),
                  ),
                  Text(
                    '${item.quantity} ${context.t('sold')}',
                    style: context.texts.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopItemsCard extends StatelessWidget {
  const _TopItemsCard({required this.vm});

  final _ReportsVm vm;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SectionHeader(title: context.t('topSellingItems')),
          ...List<Widget>.generate(vm.report.topItems.length, (int i) {
            final RankedItem item = vm.report.topItems[i];
            return Padding(
              padding: EdgeInsets.only(
                bottom: i == vm.report.topItems.length - 1 ? 0 : AppSpacing.md,
              ),
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: 18,
                    child: Text('${i + 1}', style: context.texts.labelMedium),
                  ),
                  FoodThumb(
                    emoji: item.emoji,
                    imageUrl: item.imageUrl,
                    size: 38,
                    radius: 10,
                    tint: AppColors.series[i % AppColors.series.length],
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.texts.titleSmall,
                        ),
                        Text(
                          '${item.quantity} ${context.t('sold')}',
                          style: context.texts.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  Text(
                    Fmt.moneyCompact(item.revenue),
                    style: context.texts.titleSmall,
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _HourlyCard extends StatelessWidget {
  const _HourlyCard({required this.vm});

  final _ReportsVm vm;

  @override
  Widget build(BuildContext context) {
    final List<SeriesPoint> hourly = vm.report.hourly;
    if (hourly.isEmpty) return const SizedBox.shrink();

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SectionHeader(title: context.t('salesByHour')),
          SalesLineChart(
            points: hourly,
            labels: hourly
                .map((SeriesPoint p) => p.label.substring(0, 2))
                .toList(),
            height: 160,
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------- viewmodel

class _ReportsVm {
  const _ReportsVm({
    required this.status,
    required this.report,
    required this.range,
    required this.filters,
    required this.canExport,
    required this.onRange,
    required this.onCustomRange,
  });

  factory _ReportsVm.from(Store<AppState> store) {
    final AppState s = store.state;
    return _ReportsVm(
      status: s.reports.status,
      report: s.reports,
      range: s.reports.range,
      filters: s.reports.filters,
      canExport: s.auth.can(Permission.reportsExport),
      onRange: (ReportRange r) => Effects.changeReportRange(store, r),
      onCustomRange: (DateTime from, DateTime to) => Effects.changeReportRange(
        store,
        ReportRange.custom,
        from: from,
        to: to,
      ),
    );
  }

  final Status status;
  final ReportState report;
  final ReportRange range;
  final ReportFilters filters;
  final bool canExport;
  final ValueChanged<ReportRange> onRange;
  final void Function(DateTime, DateTime) onCustomRange;

  /// Human date span for the selected preset.
  String periodLabel(BuildContext context) {
    final DateTime now = DateTime.now();
    final (DateTime from, DateTime to) = switch (range) {
      ReportRange.today => (now, now),
      ReportRange.sevenDays => (now.subtract(const Duration(days: 6)), now),
      ReportRange.thirtyDays => (now.subtract(const Duration(days: 29)), now),
      ReportRange.thisMonth => (DateTime(now.year, now.month), now),
      ReportRange.lastMonth => (
        DateTime(now.year, now.month - 1),
        DateTime(now.year, now.month, 0),
      ),
      ReportRange.custom => (
        report.from ?? now.subtract(const Duration(days: 13)),
        report.to ?? now,
      ),
    };
    if (range == ReportRange.today) return Fmt.date(now, context.lang);
    return Fmt.dateRange(from, to, context.lang);
  }
}
