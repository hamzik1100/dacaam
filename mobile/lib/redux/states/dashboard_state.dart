import 'package:flutter/foundation.dart';

import '../../data/models/analytics.dart';
import 'status.dart';

@immutable
class DashboardState {
  const DashboardState({
    this.status = Status.idle,
    this.date,
    this.sales = const KpiValue(value: 0, deltaPercent: 0),
    this.orders = const KpiValue(value: 0, deltaPercent: 0),
    this.expenses = const KpiValue(value: 0, deltaPercent: 0),
    this.profit = const KpiValue(value: 0, deltaPercent: 0),
    this.weekly = const <SeriesPoint>[],
    this.previousWeekly = const <double>[],
    this.topItems = const <RankedItem>[],
    this.error,
  });

  final Status status;
  final DateTime? date;
  final KpiValue sales;
  final KpiValue orders;
  final KpiValue expenses;
  final KpiValue profit;
  final List<SeriesPoint> weekly;
  final List<double> previousWeekly;
  final List<RankedItem> topItems;
  final String? error;

  double get weekTotal =>
      weekly.fold<double>(0, (double s, SeriesPoint p) => s + p.value);

  double get previousWeekTotal =>
      previousWeekly.fold<double>(0, (double s, double v) => s + v);

  double get weekDeltaPercent {
    final double prev = previousWeekTotal;
    if (prev == 0) return 0;
    return ((weekTotal - prev) / prev) * 100;
  }

  DashboardState copyWith({
    Status? status,
    DateTime? date,
    KpiValue? sales,
    KpiValue? orders,
    KpiValue? expenses,
    KpiValue? profit,
    List<SeriesPoint>? weekly,
    List<double>? previousWeekly,
    List<RankedItem>? topItems,
    String? error,
  }) {
    return DashboardState(
      status: status ?? this.status,
      date: date ?? this.date,
      sales: sales ?? this.sales,
      orders: orders ?? this.orders,
      expenses: expenses ?? this.expenses,
      profit: profit ?? this.profit,
      weekly: weekly ?? this.weekly,
      previousWeekly: previousWeekly ?? this.previousWeekly,
      topItems: topItems ?? this.topItems,
      error: error,
    );
  }
}
