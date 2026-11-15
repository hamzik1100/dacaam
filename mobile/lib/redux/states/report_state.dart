import 'package:flutter/foundation.dart';

import '../../core/utils/enums.dart';
import '../../data/models/analytics.dart';
import 'status.dart';

/// Cross-cutting filters for the Reports screen (§29).
///
/// Applied server-side to every section at once, so the KPI row, the charts
/// and the breakdowns can never disagree about what is being reported on.
@immutable
class ReportFilters {
  const ReportFilters({
    this.waiterName,
    this.orderType,
    this.tableId,
    this.categoryId,
    this.paymentMethod,
  });

  final String? waiterName;
  final OrderType? orderType;
  final int? tableId;
  final int? categoryId;
  final PaymentMethod? paymentMethod;

  int get activeCount => <Object?>[
    waiterName,
    orderType,
    tableId,
    categoryId,
    paymentMethod,
  ].where((Object? v) => v != null).length;

  bool get isEmpty => activeCount == 0;

  Map<String, dynamic> toQuery() => <String, dynamic>{
    if (waiterName != null) 'waiter': waiterName,
    if (orderType != null) 'order_type': orderType!.api,
    if (tableId != null) 'table_id': tableId,
    if (categoryId != null) 'category_id': categoryId,
    if (paymentMethod != null) 'payment_method': paymentMethod!.api,
  };

  ReportFilters copyWith({
    String? waiterName,
    bool clearWaiter = false,
    OrderType? orderType,
    bool clearType = false,
    int? tableId,
    bool clearTable = false,
    int? categoryId,
    bool clearCategory = false,
    PaymentMethod? paymentMethod,
    bool clearPayment = false,
  }) {
    return ReportFilters(
      waiterName: clearWaiter ? null : (waiterName ?? this.waiterName),
      orderType: clearType ? null : (orderType ?? this.orderType),
      tableId: clearTable ? null : (tableId ?? this.tableId),
      categoryId: clearCategory ? null : (categoryId ?? this.categoryId),
      paymentMethod: clearPayment
          ? null
          : (paymentMethod ?? this.paymentMethod),
    );
  }
}

@immutable
class ReportState {
  const ReportState({
    this.status = Status.idle,
    this.range = ReportRange.sevenDays,
    this.from,
    this.to,
    this.sales = const KpiValue(value: 0, deltaPercent: 0),
    this.orders = const KpiValue(value: 0, deltaPercent: 0),
    this.expenses = const KpiValue(value: 0, deltaPercent: 0),
    this.profit = const KpiValue(value: 0, deltaPercent: 0),
    this.daily = const <SeriesPoint>[],
    this.hourly = const <SeriesPoint>[],
    this.byCategory = const <BreakdownSlice>[],
    this.byPayment = const <BreakdownSlice>[],
    this.byWaiter = const <BreakdownSlice>[],
    this.byTable = const <BreakdownSlice>[],
    this.topItems = const <RankedItem>[],
    this.lowItems = const <RankedItem>[],
    this.filters = const ReportFilters(),
    this.discounts = 0,
    this.tax = 0,
    this.packaging = 0,
    this.completedOrders = 0,
    this.cancelledOrders = 0,
    this.draftOrders = 0,
    this.dineInOrders = 0,
    this.takeawayOrders = 0,
    this.cash = const CashSummary(),
    this.receivables = 0,
    this.depositsHeld = 0,
    this.unpaidOrders = 0,
    this.topCustomers = const <CustomerRank>[],
    this.topDebtors = const <CustomerRank>[],
    this.error,
  });

  final Status status;
  final ReportRange range;
  final DateTime? from;
  final DateTime? to;

  final KpiValue sales;
  final KpiValue orders;
  final KpiValue expenses;
  final KpiValue profit;

  final List<SeriesPoint> daily;
  final List<SeriesPoint> hourly;
  final List<BreakdownSlice> byCategory;
  final List<BreakdownSlice> byPayment;
  final List<BreakdownSlice> byWaiter;
  final List<BreakdownSlice> byTable;
  final List<RankedItem> topItems;
  final List<RankedItem> lowItems;
  final ReportFilters filters;

  final double discounts;
  final double tax;
  final double packaging;

  final int completedOrders;
  final int cancelledOrders;
  final int draftOrders;
  final int dineInOrders;
  final int takeawayOrders;

  /// Cash actually collected in the period, shown beside [sales] rather than
  /// in place of it.
  final CashSummary cash;

  /// The position right now, not a period figure: what is owed to the
  /// restaurant, and what it holds on behalf of customers.
  final double receivables;
  final double depositsHeld;

  /// Money owed on orders with nobody named against it — a walk-in who paid
  /// half, or an order that grew after it was settled. Shown because the
  /// alternative is a gap between what was sold and what can be accounted
  /// for, which is the shape money takes when it goes missing.
  final double unpaidOrders;

  final List<CustomerRank> topCustomers;
  final List<CustomerRank> topDebtors;

  final String? error;

  double get avgOrderValue =>
      orders.value == 0 ? 0 : sales.value / orders.value;

  double get grossSales => sales.value + discounts;

  /// The gap between what was sold and what was collected. Positive means the
  /// period sold more than it took in — credit, in one number.
  double get uncollected => sales.value - cash.net;

  ReportState copyWith({
    Status? status,
    ReportRange? range,
    DateTime? from,
    DateTime? to,
    KpiValue? sales,
    KpiValue? orders,
    KpiValue? expenses,
    KpiValue? profit,
    List<SeriesPoint>? daily,
    List<SeriesPoint>? hourly,
    List<BreakdownSlice>? byCategory,
    List<BreakdownSlice>? byPayment,
    List<BreakdownSlice>? byWaiter,
    List<BreakdownSlice>? byTable,
    List<RankedItem>? topItems,
    List<RankedItem>? lowItems,
    ReportFilters? filters,
    double? discounts,
    double? tax,
    double? packaging,
    int? completedOrders,
    int? cancelledOrders,
    int? draftOrders,
    int? dineInOrders,
    int? takeawayOrders,
    CashSummary? cash,
    double? receivables,
    double? depositsHeld,
    double? unpaidOrders,
    List<CustomerRank>? topCustomers,
    List<CustomerRank>? topDebtors,
    String? error,
  }) {
    return ReportState(
      status: status ?? this.status,
      range: range ?? this.range,
      from: from ?? this.from,
      to: to ?? this.to,
      sales: sales ?? this.sales,
      orders: orders ?? this.orders,
      expenses: expenses ?? this.expenses,
      profit: profit ?? this.profit,
      daily: daily ?? this.daily,
      hourly: hourly ?? this.hourly,
      byCategory: byCategory ?? this.byCategory,
      byPayment: byPayment ?? this.byPayment,
      byWaiter: byWaiter ?? this.byWaiter,
      byTable: byTable ?? this.byTable,
      topItems: topItems ?? this.topItems,
      lowItems: lowItems ?? this.lowItems,
      filters: filters ?? this.filters,
      discounts: discounts ?? this.discounts,
      tax: tax ?? this.tax,
      packaging: packaging ?? this.packaging,
      completedOrders: completedOrders ?? this.completedOrders,
      cancelledOrders: cancelledOrders ?? this.cancelledOrders,
      draftOrders: draftOrders ?? this.draftOrders,
      dineInOrders: dineInOrders ?? this.dineInOrders,
      takeawayOrders: takeawayOrders ?? this.takeawayOrders,
      cash: cash ?? this.cash,
      receivables: receivables ?? this.receivables,
      depositsHeld: depositsHeld ?? this.depositsHeld,
      unpaidOrders: unpaidOrders ?? this.unpaidOrders,
      topCustomers: topCustomers ?? this.topCustomers,
      topDebtors: topDebtors ?? this.topDebtors,
      error: error,
    );
  }
}
