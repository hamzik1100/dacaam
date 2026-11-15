import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:redux/redux.dart';

import '../../core/i18n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/utils/enums.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/order.dart';
import '../../redux/actions.dart';
import '../../redux/app_state.dart';
import '../../redux/effects.dart';
import '../../redux/states/status.dart';
import '../../widgets/app_card.dart';
import '../../widgets/buttons.dart';
import '../../widgets/common.dart';
import '../../widgets/entrance.dart';
import '../../widgets/skeletons.dart';
import '../../widgets/states.dart';
import '../shell/main_shell.dart';
import 'order_details_sheet.dart';
import 'orders_filter_sheet.dart';

/// Every order in the restaurant, with the filters a manager actually needs.
class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  bool _searching = false;

  @override
  Widget build(BuildContext context) {
    return StoreConnector<AppState, _OrdersVm>(
      converter: _OrdersVm.from,
      builder: (BuildContext context, _OrdersVm vm) {
        return Scaffold(
          body: SafeArea(
            bottom: false,
            child: Column(
              children: <Widget>[
                _Header(
                  vm: vm,
                  searching: _searching,
                  onToggleSearch: () {
                    setState(() => _searching = !_searching);
                    if (!_searching) vm.onSearch('');
                  },
                ),
                if (_searching)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.gutter,
                      0,
                      AppSpacing.gutter,
                      AppSpacing.md,
                    ),
                    child: AppSearchField(
                      hint: context.t('search'),
                      initialValue: vm.query,
                      onChanged: vm.onSearch,
                    ),
                  ),
                ChipSelector<OrderStatus?>(
                  // Preparing and Ready are gone. An order is completed the
                  // moment it is paid or put on an account, so nothing ever
                  // reached them — two chips that always read zero. The enum
                  // keeps both so orders recorded under the old flow still
                  // display their real status.
                  values: const <OrderStatus?>[
                    null,
                    OrderStatus.pending,
                    OrderStatus.completed,
                    OrderStatus.cancelled,
                  ],
                  selected: vm.statusFilter,
                  labelOf: (OrderStatus? s) =>
                      s == null ? context.t('all') : context.t(s.labelKey),
                  colorOf: (OrderStatus? s) => s?.color ?? AppColors.primary,
                  countOf: vm.countOf,
                  onSelected: vm.onStatusFilter,
                ),
                const SizedBox(height: AppSpacing.md),
                Expanded(
                  child: switch (vm.status) {
                    Status.error => ErrorStateView(
                      message: vm.error,
                      onRetry: vm.onRefresh,
                    ),
                    Status.idle || Status.loading => const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: AppSpacing.gutter,
                      ),
                      child: ListSkeleton(hasThumb: false),
                    ),
                    Status.ready => _OrderList(vm: vm),
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

class _Header extends StatelessWidget {
  const _Header({
    required this.vm,
    required this.searching,
    required this.onToggleSearch,
  });

  final _OrdersVm vm;
  final bool searching;
  final VoidCallback onToggleSearch;

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
                  context.t('navOrders'),
                  style: context.texts.headlineSmall,
                ),
                Text(
                  '${vm.visible.length} ${context.t('items').toLowerCase()}',
                  style: context.texts.bodySmall,
                ),
              ],
            ),
          ),
          SoftIconButton(
            icon: Icons.tune_rounded,
            badgeCount: vm.activeFilterCount,
            onPressed: () => showOrdersFilterSheet(context),
          ),
          const SizedBox(width: AppSpacing.sm),
          SoftIconButton(
            icon: searching ? Icons.close_rounded : Icons.search_rounded,
            onPressed: onToggleSearch,
          ),
        ],
      ),
    );
  }
}

class _OrderList extends StatelessWidget {
  const _OrderList({required this.vm});

  final _OrdersVm vm;

  @override
  Widget build(BuildContext context) {
    if (vm.visible.isEmpty) {
      return EmptyState(
        icon: Icons.receipt_long_rounded,
        title: context.t('noOrdersTitle'),
        message: context.t('noOrdersBody'),
        actionLabel: context.t('createNewOrder'),
        onAction: vm.onNewOrder,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        0,
        AppSpacing.gutter,
        AppSpacing.xxl,
      ),
      itemCount: vm.visible.length,
      itemBuilder: (BuildContext context, int i) {
        final RestaurantOrder o = vm.visible[i];
        return Entrance(
          index: i,
          child: Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: OrderCard(order: o),
          ),
        );
      },
    );
  }
}

/// Shared order row — also used by the drafts and table screens.
class OrderCard extends StatelessWidget {
  const OrderCard({super.key, required this.order});

  final RestaurantOrder order;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;

    return AppCard(
      onTap: () => showOrderDetailsSheet(context, order.id),
      padding: const EdgeInsets.all(AppSpacing.md + 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                Fmt.orderNo(order.number),
                style: context.texts.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              // The order number keeps its natural width; the chip and the
              // table label share what's left and ellipsize rather than
              // overflow. No Spacer here — it would claim the same flex space
              // these two need.
              Flexible(
                child: StatusChip(
                  label: context.t(order.type.labelKey),
                  color: order.type.tint,
                  icon: order.type.icon,
                  dense: true,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  order.tableLabel ?? '',
                  textAlign: TextAlign.end,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.texts.titleSmall?.copyWith(
                    color: palette.subtext,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: <Widget>[
              Icon(
                Icons.person_outline_rounded,
                size: 14,
                color: palette.subtext,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  // Who bought it comes first when there is a name. On a list
                  // of takeaways the waiter is nearly always the same person,
                  // and the customer is what somebody is actually scanning for
                  // — most of all when they are chasing a debt.
                  order.customerName.isNotEmpty
                      ? order.customerName
                      : '${context.t('waiter')}: ${order.waiterName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.texts.bodySmall,
                ),
              ),
              Text(
                Fmt.relative(order.createdAt, context.lang),
                style: context.texts.bodySmall?.copyWith(fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  Fmt.money(order.total),
                  style: context.texts.titleLarge?.copyWith(
                    color: order.status == OrderStatus.cancelled
                        ? palette.subtext
                        : AppColors.primary,
                    fontSize: 16,
                    decoration: order.status == OrderStatus.cancelled
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                ),
              ),
              // An unpaid order is completed and outstanding at once, so the
              // money chip sits beside the kitchen one rather than replacing
              // it. Absent when there is nothing owed.
              if (!order.paymentStatus.isSettled &&
                  order.status != OrderStatus.cancelled) ...<Widget>[
                StatusChip(
                  label: context.t(order.paymentStatus.labelKey),
                  color: order.paymentStatus.color,
                ),
                const SizedBox(width: AppSpacing.xs),
              ],
              StatusChip(
                label: context.t(order.status.labelKey),
                color: order.status.color,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------- viewmodel

class _OrdersVm {
  const _OrdersVm({
    required this.status,
    required this.visible,
    required this.error,
    required this.onRefresh,
    required this.statusFilter,
    required this.activeFilterCount,
    required this.query,
    required this.countOf,
    required this.onStatusFilter,
    required this.onSearch,
    required this.onNewOrder,
  });

  factory _OrdersVm.from(Store<AppState> store) {
    final AppState s = store.state;
    return _OrdersVm(
      status: s.orders.status,
      visible: s.orders.visible,
      error: s.dashboard.error,
      onRefresh: () => Effects.bootstrap(store),
      statusFilter: s.orders.filters.status,
      activeFilterCount: s.orders.filters.activeCount,
      query: s.orders.filters.query,
      countOf: s.orders.countByStatus,
      onStatusFilter: (OrderStatus? st) =>
          store.dispatch(OrderStatusFilterChanged(st)),
      onSearch: (String q) => store.dispatch(OrderSearchChanged(q)),
      onNewOrder: () => store.dispatch(
        TabSelected(
          shellIndexOf(
            'navPos',
            store.state.auth.user?.permissions ?? const <Permission>{},
          ),
        ),
      ),
    );
  }

  final Status status;
  final List<RestaurantOrder> visible;
  final String? error;
  final Future<void> Function() onRefresh;
  final OrderStatus? statusFilter;
  final int activeFilterCount;
  final String query;
  final int Function(OrderStatus?) countOf;
  final ValueChanged<OrderStatus?> onStatusFilter;
  final ValueChanged<String> onSearch;
  final VoidCallback onNewOrder;
}
