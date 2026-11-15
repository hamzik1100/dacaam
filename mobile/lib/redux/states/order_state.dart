import 'package:flutter/foundation.dart';

import '../../core/utils/enums.dart';
import '../../data/models/order.dart';
import 'status.dart';

/// Date presets used by the Orders filter sheet.
enum OrderDateRange { today, yesterday, thisWeek, thisMonth, all }

@immutable
class OrderFilters {
  const OrderFilters({
    this.status,
    this.type,
    this.dateRange = OrderDateRange.all,
    this.waiterName,
    this.tableId,
    this.paymentMethod,
    this.query = '',
  });

  /// `null` == the "All" tab.
  final OrderStatus? status;
  final OrderType? type;
  final OrderDateRange dateRange;
  final String? waiterName;
  final int? tableId;
  final PaymentMethod? paymentMethod;
  final String query;

  /// Everything except the status tab and free-text search — that's what the
  /// filter button badge counts.
  int get activeCount {
    int n = 0;
    if (type != null) n++;
    if (dateRange != OrderDateRange.all) n++;
    if (waiterName != null) n++;
    if (tableId != null) n++;
    if (paymentMethod != null) n++;
    return n;
  }

  OrderFilters copyWith({
    OrderStatus? status,
    bool clearStatus = false,
    OrderType? type,
    bool clearType = false,
    OrderDateRange? dateRange,
    String? waiterName,
    bool clearWaiter = false,
    int? tableId,
    bool clearTable = false,
    PaymentMethod? paymentMethod,
    bool clearPayment = false,
    String? query,
  }) {
    return OrderFilters(
      status: clearStatus ? null : (status ?? this.status),
      type: clearType ? null : (type ?? this.type),
      dateRange: dateRange ?? this.dateRange,
      waiterName: clearWaiter ? null : (waiterName ?? this.waiterName),
      tableId: clearTable ? null : (tableId ?? this.tableId),
      paymentMethod: clearPayment
          ? null
          : (paymentMethod ?? this.paymentMethod),
      query: query ?? this.query,
    );
  }
}

@immutable
class OrderState {
  const OrderState({
    this.status = Status.idle,
    this.orders = const <RestaurantOrder>[],
    this.filters = const OrderFilters(),
    this.lastPlacedOrderId,
  });

  final Status status;
  final List<RestaurantOrder> orders;
  final OrderFilters filters;

  /// Set right after checkout so the success screen can look the order up.
  final int? lastPlacedOrderId;

  RestaurantOrder? byId(int? id) {
    if (id == null) return null;
    for (final RestaurantOrder o in orders) {
      if (o.id == id) return o;
    }
    return null;
  }

  List<RestaurantOrder> get visible {
    final DateTime now = DateTime.now();
    final String q = filters.query.trim().toLowerCase();

    return orders.where((RestaurantOrder o) {
      if (filters.status != null && o.status != filters.status) return false;
      if (filters.type != null && o.type != filters.type) return false;
      if (filters.waiterName != null && o.waiterName != filters.waiterName) {
        return false;
      }
      if (filters.tableId != null && o.tableId != filters.tableId) return false;
      if (filters.paymentMethod != null &&
          o.primaryPayment != filters.paymentMethod) {
        return false;
      }
      if (!_inRange(o.createdAt, now, filters.dateRange)) return false;
      if (q.isNotEmpty) {
        final bool hit =
            o.number.toString().contains(q) ||
            o.waiterName.toLowerCase().contains(q) ||
            o.customerName.toLowerCase().contains(q) ||
            (o.tableLabel ?? '').toLowerCase().contains(q);
        if (!hit) return false;
      }
      return true;
    }).toList();
  }

  static bool _inRange(DateTime at, DateTime now, OrderDateRange range) {
    final DateTime startOfToday = DateTime(now.year, now.month, now.day);
    switch (range) {
      case OrderDateRange.all:
        return true;
      case OrderDateRange.today:
        return !at.isBefore(startOfToday);
      case OrderDateRange.yesterday:
        final DateTime startOfYesterday = startOfToday.subtract(
          const Duration(days: 1),
        );
        return !at.isBefore(startOfYesterday) && at.isBefore(startOfToday);
      case OrderDateRange.thisWeek:
        final DateTime monday = startOfToday.subtract(
          Duration(days: now.weekday - 1),
        );
        return !at.isBefore(monday);
      case OrderDateRange.thisMonth:
        return !at.isBefore(DateTime(now.year, now.month));
    }
  }

  int countByStatus(OrderStatus? s) => s == null
      ? orders.length
      : orders.where((RestaurantOrder o) => o.status == s).length;

  OrderState copyWith({
    Status? status,
    List<RestaurantOrder>? orders,
    OrderFilters? filters,
    int? lastPlacedOrderId,
  }) {
    return OrderState(
      status: status ?? this.status,
      orders: orders ?? this.orders,
      filters: filters ?? this.filters,
      lastPlacedOrderId: lastPlacedOrderId ?? this.lastPlacedOrderId,
    );
  }
}

@immutable
class DraftState {
  const DraftState({
    this.status = Status.idle,
    this.drafts = const <DraftOrder>[],
  });

  final Status status;
  final List<DraftOrder> drafts;

  int get openCount =>
      drafts.where((DraftOrder d) => d.status == DraftStatus.draft).length;

  DraftState copyWith({Status? status, List<DraftOrder>? drafts}) {
    return DraftState(
      status: status ?? this.status,
      drafts: drafts ?? this.drafts,
    );
  }
}
