import 'dart:ui';

/// A single point on a time series (one day, one hour, one month).
class SeriesPoint {
  const SeriesPoint({required this.label, required this.value, this.date});

  final String label;
  final double value;
  final DateTime? date;
}

/// A ranked menu item for "Top Selling".
class RankedItem {
  const RankedItem({
    required this.itemId,
    required this.name,
    required this.quantity,
    required this.revenue,
    this.emoji = '🍽️',
    this.imageUrl,
  });

  final int itemId;
  final String name;
  final int quantity;
  final double revenue;
  final String emoji;
  final String? imageUrl;
}

/// One wedge of a donut chart / one row of a breakdown list.
class BreakdownSlice {
  const BreakdownSlice({
    required this.label,
    required this.value,
    required this.color,
    this.count = 0,
  });

  final String label;
  final double value;
  final Color color;
  final int count;
}

/// Money that actually moved in the period.
///
/// Reported next to sales, never instead of them. Sales is what was sold, this
/// is what was collected, and with credit in play the two are different numbers
/// — showing only one of them is how a month of unpaid tabs reads as a good
/// month.
class CashSummary {
  const CashSummary({
    this.moneyIn = 0,
    this.moneyOut = 0,
    this.net = 0,
    this.fromCustomers = 0,
  });

  final double moneyIn;
  final double moneyOut;
  final double net;

  /// The part of [moneyIn] that was old debt being settled rather than new
  /// trade.
  final double fromCustomers;

  /// Cash taken for today's trade: everything collected less the repayments.
  double get fromTrade {
    final double v = moneyIn - fromCustomers;

    return v > 0 ? v : 0;
  }
}

/// A customer in a report ranking — either by what they bought or by what they
/// owe, depending on which list it came from.
class CustomerRank {
  const CustomerRank({
    required this.customerId,
    required this.name,
    this.phone = '',
    this.orders = 0,
    this.spent = 0,
    this.balanceOwed = 0,
    this.creditLimit = 0,
    this.lastPaid,
  });

  final int customerId;
  final String name;
  final String phone;
  final int orders;
  final double spent;
  final double balanceOwed;
  final double creditLimit;

  /// When they last paid anything. Null means never, which is the row a
  /// manager most wants to see.
  final DateTime? lastPaid;
}

/// KPI value plus its period-over-period movement.
class KpiValue {
  const KpiValue({required this.value, required this.deltaPercent});

  final double value;
  final double deltaPercent;

  bool get isUp => deltaPercent >= 0;
}
