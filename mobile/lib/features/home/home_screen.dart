import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:redux/redux.dart';

import '../../core/i18n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/utils/enums.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/analytics.dart';
import '../../data/models/order.dart';
import '../../data/models/restaurant.dart';
import '../../redux/actions.dart';
import '../../redux/app_state.dart';
import '../../redux/effects.dart';
import '../../redux/states/status.dart';
import '../../widgets/app_card.dart';
import '../../widgets/buttons.dart';
import '../../widgets/charts.dart';
import '../../widgets/common.dart';
import '../../widgets/entrance.dart';
import '../../widgets/food_thumb.dart';
import '../../widgets/kpi_card.dart';
import '../../widgets/skeletons.dart';
import '../../widgets/states.dart';
import '../customers/customers_screen.dart';
import '../notifications/notifications_screen.dart';
import '../management/drafts_screen.dart';
import '../management/expenses_screen.dart';
import '../management/tables_screen.dart';
import '../orders/order_details_sheet.dart';
import '../shell/main_shell.dart';

/// The restaurant's control centre: today's numbers, one-tap operations, the
/// weekly trend and the two lists an owner checks constantly.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return StoreConnector<AppState, _HomeVm>(
      converter: _HomeVm.from,
      builder: (BuildContext context, _HomeVm vm) {
        return Scaffold(
          body: SafeArea(
            bottom: false,
            child: Column(
              children: <Widget>[
                _Header(vm: vm),
                Expanded(
                  child: switch (vm.status) {
                    // The reason, when there is one. A dropped connection says so
                    // rather than showing the same generic failure as everything
                    // else — those are different problems with different fixes.
                    Status.error => ErrorStateView(
                      message: vm.error,
                      onRetry: vm.onRefresh,
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
}

// ------------------------------------------------------------------- header

class _Header extends StatelessWidget {
  const _Header({required this.vm});

  final _HomeVm vm;

  String _greetingKey() {
    final int h = DateTime.now().hour;
    if (h < 12) return 'goodMorning';
    if (h < 17) return 'goodAfternoon';
    return 'goodEvening';
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    final String firstName = (vm.user?.name ?? '').split(' ').first;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        AppSpacing.md,
        AppSpacing.gutter,
        AppSpacing.md,
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: AppColors.brand,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(
              child: Text(
                vm.restaurant?.logoEmoji ?? '🍽️',
                style: const TextStyle(fontSize: 21),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  vm.restaurant?.name ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.texts.titleLarge,
                ),
                const SizedBox(height: 1),
                Text(
                  '${context.t(_greetingKey())}, $firstName 👋',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.texts.bodySmall?.copyWith(
                    color: palette.subtext,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          SoftIconButton(
            icon: Icons.notifications_none_rounded,
            badgeCount: vm.unreadMessages,
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => const NotificationsScreen(),
              ),
            ),
          ),
        ],
      ),
    );
  }

}

// --------------------------------------------------------------------- body

class _Body extends StatelessWidget {
  const _Body({required this.vm});

  final _HomeVm vm;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: vm.onRefresh,
      color: AppColors.primary,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.gutter,
          0,
          AppSpacing.gutter,
          AppSpacing.xxxl,
        ),
        children: <Widget>[
          Entrance(index: 0, child: _DateBar(date: vm.date)),
          const SizedBox(height: AppSpacing.lg),
          Entrance(index: 1, child: _KpiGrid(vm: vm)),
          // Only once credit is in play. A cash-only restaurant has two zeroes
          // here, and a strip of zeroes is furniture.
          if (vm.receivables > 0 || vm.depositsHeld > 0) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            Entrance(index: 1, child: _CreditStrip(vm: vm)),
          ],
          const SizedBox(height: AppSpacing.xl),
          Entrance(index: 2, child: _QuickActions(vm: vm)),
          const SizedBox(height: AppSpacing.xl),
          Entrance(index: 3, child: _WeeklySalesCard(vm: vm)),
          const SizedBox(height: AppSpacing.lg),
          Entrance(index: 4, child: _TopSellingCard(vm: vm)),
          const SizedBox(height: AppSpacing.lg),
          Entrance(index: 5, child: _RecentOrdersCard(vm: vm)),
        ],
      ),
    );
  }
}

class _DateBar extends StatelessWidget {
  const _DateBar({required this.date});

  final DateTime? date;

  @override
  Widget build(BuildContext context) {
    final DateTime d = date ?? DateTime.now();
    return AppCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: <Widget>[
          Icon(
            Icons.calendar_today_rounded,
            size: 16,
            color: context.palette.subtext,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              '${context.t('today')}, ${Fmt.date(d, context.lang)}',
              style: context.texts.titleSmall,
            ),
          ),
          Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 20,
            color: context.palette.subtext,
          ),
        ],
      ),
    );
  }
}

class _KpiGrid extends StatelessWidget {
  const _KpiGrid({required this.vm});

  final _HomeVm vm;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: KpiCard(
                label: context.t('todaysSales'),
                value: vm.sales.value,
                deltaPercent: vm.sales.deltaPercent,
                format: Fmt.money,
                icon: Icons.trending_up_rounded,
                tint: AppColors.primary,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: KpiCard(
                label: context.t('todaysOrders'),
                value: vm.orders.value,
                deltaPercent: vm.orders.deltaPercent,
                format: (double v) => Fmt.number(v.round()),
                icon: Icons.shopping_bag_rounded,
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
                label: context.t('todaysExpenses'),
                value: vm.expenses.value,
                deltaPercent: vm.expenses.deltaPercent,
                format: Fmt.money,
                icon: Icons.receipt_rounded,
                tint: AppColors.violet,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: KpiCard(
                label: context.t('netProfit'),
                value: vm.profit.value,
                deltaPercent: vm.profit.deltaPercent,
                format: Fmt.money,
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

// ------------------------------------------------------------ quick actions

/// What the restaurant is owed, and what it holds that is not its own.
///
/// Deliberately apart from the KPI grid above: those are today's trading
/// figures, these are a standing position that does not reset at midnight.
/// Putting them in the same row would invite reading a debt as a day's takings.
class _CreditStrip extends StatelessWidget {
  const _CreditStrip({required this.vm});

  final _HomeVm vm;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      onTap: vm.canSeeCustomers
          ? () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(builder: (_) => const CustomersScreen()),
            )
          : null,
      child: Row(
        children: <Widget>[
          Expanded(
            child: _CreditFigure(
              icon: Icons.trending_up_rounded,
              label: context.t('receivables'),
              value: vm.receivables,
              tint: AppColors.danger,
            ),
          ),
          Container(
            width: 1,
            height: 34,
            color: context.palette.border,
            margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          ),
          Expanded(
            child: _CreditFigure(
              icon: Icons.savings_rounded,
              label: context.t('depositsHeld'),
              value: vm.depositsHeld,
              tint: AppColors.success,
            ),
          ),
          if (vm.canSeeCustomers)
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: context.palette.subtext,
            ),
        ],
      ),
    );
  }
}

class _CreditFigure extends StatelessWidget {
  const _CreditFigure({
    required this.icon,
    required this.label,
    required this.value,
    required this.tint,
  });

  final IconData icon;
  final String label;
  final double value;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(icon, size: 14, color: tint),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.texts.labelSmall?.copyWith(
                  color: context.palette.subtext,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          Fmt.money(value),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.texts.titleSmall?.copyWith(color: tint),
        ),
      ],
    );
  }
}

class _QuickAction {
  const _QuickAction({
    required this.labelKey,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String labelKey;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.vm});

  final _HomeVm vm;

  @override
  Widget build(BuildContext context) {
    final List<_QuickAction> actions = <_QuickAction>[
      _QuickAction(
        labelKey: 'newOrder',
        icon: Icons.add_shopping_cart_rounded,
        color: AppColors.primary,
        onTap: () => vm.onGoToTab('navPos'),
      ),
      _QuickAction(
        labelKey: 'draftOrders',
        icon: Icons.edit_note_rounded,
        color: AppColors.secondary,
        onTap: () => _push(context, const DraftsScreen()),
      ),
      _QuickAction(
        labelKey: 'tables',
        icon: Icons.table_restaurant_rounded,
        color: AppColors.info,
        onTap: () => _push(context, const TablesScreen()),
      ),
      _QuickAction(
        labelKey: 'addExpense',
        icon: Icons.account_balance_wallet_rounded,
        color: AppColors.violet,
        onTap: () => _push(context, const ExpensesScreen()),
      ),
      _QuickAction(
        labelKey: 'navReports',
        icon: Icons.insights_rounded,
        color: AppColors.success,
        onTap: () => vm.onGoToTab('navReports'),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionHeader(title: context.t('quickActions')),
        SizedBox(
          // Tall enough for a 38px badge plus two lines of Somali label —
          // "Ku dar Kharash" wraps where the English "Add Expense" does not.
          height: 102,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            padding: EdgeInsets.zero,
            itemCount: actions.length,
            separatorBuilder: (BuildContext context, int i) =>
                const SizedBox(width: AppSpacing.md),
            itemBuilder: (BuildContext context, int i) {
              final _QuickAction a = actions[i];
              return PressableScale(
                onTap: a.onTap,
                child: SizedBox(
                  width: 96,
                  child: AppCard(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        IconBadge(icon: a.icon, color: a.color),
                        const Spacer(),
                        Text(
                          context.t(a.labelKey),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: context.texts.labelMedium?.copyWith(
                            color: context.palette.text,
                            height: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  static void _push(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }
}

// -------------------------------------------------------------- weekly card

class _WeeklySalesCard extends StatefulWidget {
  const _WeeklySalesCard({required this.vm});

  final _HomeVm vm;

  @override
  State<_WeeklySalesCard> createState() => _WeeklySalesCardState();
}

class _WeeklySalesCardState extends State<_WeeklySalesCard> {
  int? _selected;

  @override
  Widget build(BuildContext context) {
    final _HomeVm vm = widget.vm;
    if (vm.weekly.isEmpty) return const SizedBox.shrink();

    final List<String> labels = Fmt.weekdayLabels(context.lang);
    final bool hasSelection =
        _selected != null && _selected! >= 0 && _selected! < vm.weekly.length;
    final SeriesPoint? point = hasSelection ? vm.weekly[_selected!] : null;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  context.t('weeklySales'),
                  style: context.texts.titleLarge,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: context.palette.muted,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      context.t('thisWeek'),
                      style: context.texts.labelMedium,
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 16,
                      color: context.palette.subtext,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              // Weekly totals reach eight figures in SLSH; scale down rather
              // than clip so the headline figure is never cut off.
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    Fmt.money(point?.value ?? vm.weekTotal),
                    maxLines: 1,
                    style: context.texts.headlineMedium?.copyWith(fontSize: 24),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: point == null
                    ? DeltaBadge(percent: vm.weekDelta)
                    : Text(
                        Fmt.weekday(point.date!, context.lang),
                        style: context.texts.labelMedium,
                      ),
              ),
            ],
          ),
          Text(
            point == null ? context.t('vsLastWeek') : context.t('todaysSales'),
            style: context.texts.bodySmall,
          ),
          const SizedBox(height: AppSpacing.lg),
          SalesLineChart(
            points: vm.weekly,
            labels: labels,
            onSelected: (int? i) {
              if (_selected != i) setState(() => _selected = i);
            },
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- top items

class _TopSellingCard extends StatelessWidget {
  const _TopSellingCard({required this.vm});

  final _HomeVm vm;

  static const List<Color> _rankColors = <Color>[
    AppColors.primary,
    AppColors.secondary,
    AppColors.info,
  ];

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        children: <Widget>[
          SectionHeader(
            title: context.t('topSellingItems'),
            actionLabel: context.t('viewAll'),
            onAction: () => vm.onGoToTab('navReports'),
          ),
          if (vm.topItems.isEmpty)
            EmptyState(
              icon: Icons.emoji_food_beverage_rounded,
              title: context.t('noData'),
              compact: true,
            )
          else
            ...List<Widget>.generate(vm.topItems.length.clamp(0, 3), (int i) {
              final RankedItem item = vm.topItems[i];
              final Color color = i < _rankColors.length
                  ? _rankColors[i]
                  : context.palette.subtext;
              return Padding(
                padding: EdgeInsets.only(
                  bottom: i == vm.topItems.length.clamp(0, 3) - 1
                      ? 0
                      : AppSpacing.md,
                ),
                child: Row(
                  children: <Widget>[
                    Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Center(
                        child: Text(
                          '${i + 1}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    FoodThumb(
                      emoji: item.emoji,
                      imageUrl: item.imageUrl,
                      size: 38,
                      radius: 10,
                      tint: color,
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
              );
            }),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------ recent orders

class _RecentOrdersCard extends StatelessWidget {
  const _RecentOrdersCard({required this.vm});

  final _HomeVm vm;

  @override
  Widget build(BuildContext context) {
    final List<RestaurantOrder> recent = vm.recentOrders;

    return AppCard(
      child: Column(
        children: <Widget>[
          SectionHeader(
            title: context.t('recentOrders'),
            actionLabel: context.t('viewAll'),
            onAction: () => vm.onGoToTab('navOrders'),
          ),
          if (recent.isEmpty)
            EmptyState(
              icon: Icons.receipt_long_rounded,
              title: context.t('noOrdersTitle'),
              message: context.t('noOrdersBody'),
              actionLabel: context.t('createNewOrder'),
              onAction: () => vm.onGoToTab('navPos'),
              compact: true,
            )
          else
            ...recent.map((RestaurantOrder o) {
              return InkWell(
                onTap: () => showOrderDetailsSheet(context, o.id),
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Row(
                              children: <Widget>[
                                Text(
                                  Fmt.orderNo(o.number),
                                  style: context.texts.titleSmall,
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                Flexible(
                                  child: Text(
                                    o.tableLabel == null
                                        ? context.t(o.type.labelKey)
                                        : '${context.t(o.type.labelKey)} · ${o.tableLabel}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: context.texts.bodySmall,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              Fmt.relative(o.createdAt, context.lang),
                              style: context.texts.bodySmall?.copyWith(
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        Fmt.number(o.total),
                        style: context.texts.titleSmall,
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Icon(
                        o.status == OrderStatus.completed
                            ? Icons.check_circle_rounded
                            : o.status == OrderStatus.cancelled
                            ? Icons.cancel_rounded
                            : Icons.schedule_rounded,
                        size: 18,
                        color: o.status.color,
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

// ----------------------------------------------------------------- viewmodel

class _HomeVm {
  const _HomeVm({
    required this.status,
    required this.restaurant,
    required this.user,
    required this.date,
    required this.sales,
    required this.orders,
    required this.expenses,
    required this.profit,
    required this.weekly,
    required this.weekTotal,
    required this.weekDelta,
    required this.topItems,
    required this.recentOrders,
    required this.openOrders,
    required this.unreadMessages,
    required this.error,
    required this.receivables,
    required this.depositsHeld,
    required this.canSeeCustomers,
    required this.onRefresh,
    required this.onGoToTab,
  });

  factory _HomeVm.from(Store<AppState> store) {
    final AppState s = store.state;
    final List<RestaurantOrder> recent = s.orders.orders.take(3).toList();

    return _HomeVm(
      status: s.dashboard.status,
      restaurant: s.restaurant.restaurant,
      user: s.auth.user,
      date: s.dashboard.date,
      sales: s.dashboard.sales,
      orders: s.dashboard.orders,
      expenses: s.dashboard.expenses,
      profit: s.dashboard.profit,
      weekly: s.dashboard.weekly,
      weekTotal: s.dashboard.weekTotal,
      weekDelta: s.dashboard.weekDeltaPercent,
      topItems: s.dashboard.topItems,
      recentOrders: recent,
      openOrders: s.orders.orders
          .where((RestaurantOrder o) => o.status.isOpen)
          .length,
      unreadMessages: s.notifications.unread,
      error: s.dashboard.error,
      // Position figures, not today's: what is owed does not reset at
      // midnight, so these come from the report slice rather than the
      // dashboard's daily numbers.
      receivables: s.reports.receivables,
      depositsHeld: s.reports.depositsHeld,
      canSeeCustomers: s.auth.can(Permission.customersView),
      onRefresh: () => Effects.refreshDashboard(store),
      onGoToTab: (String labelKey) => store.dispatch(
        TabSelected(
          shellIndexOf(
            labelKey,
            store.state.auth.user?.permissions ?? const <Permission>{},
          ),
        ),
      ),
    );
  }

  final Status status;
  final Restaurant? restaurant;
  final AppUser? user;
  final DateTime? date;
  final KpiValue sales;
  final KpiValue orders;
  final KpiValue expenses;
  final KpiValue profit;
  final List<SeriesPoint> weekly;
  final double weekTotal;
  final double weekDelta;
  final List<RankedItem> topItems;
  final List<RestaurantOrder> recentOrders;
  final int openOrders;

  /// Messages from DACAAM nobody has opened yet. The bell used to count open
  /// orders, which is a number the Orders tab already shows.
  final int unreadMessages;
  final String? error;
  final double receivables;
  final double depositsHeld;
  final bool canSeeCustomers;
  final Future<void> Function() onRefresh;
  final void Function(String labelKey) onGoToTab;
}
