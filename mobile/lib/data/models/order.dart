import '../../core/utils/enums.dart';
import 'menu.dart';

/// A line on an order or in the cart.
///
/// Price is snapshotted at `unitPrice` — a later menu price change must never
/// rewrite the value of an order that already happened.
class OrderLine {
  const OrderLine({
    required this.itemId,
    required this.name,
    required this.unitPrice,
    required this.quantity,
    this.emoji = '🍽️',
    this.imageUrl,
    this.applyPackagingFee = true,
    this.notes = '',
  });

  factory OrderLine.fromMenuItem(MenuItem item, {int quantity = 1}) {
    return OrderLine(
      itemId: item.id,
      name: item.name,
      unitPrice: item.price,
      quantity: quantity,
      emoji: item.emoji,
      imageUrl: item.imageUrl,
      applyPackagingFee: item.applyPackagingFee,
    );
  }

  final int itemId;
  final String name;
  final double unitPrice;
  final int quantity;
  final String emoji;
  final String? imageUrl;
  final bool applyPackagingFee;
  final String notes;

  double get total => unitPrice * quantity;

  OrderLine copyWith({int? quantity, String? notes}) {
    return OrderLine(
      itemId: itemId,
      name: name,
      unitPrice: unitPrice,
      quantity: quantity ?? this.quantity,
      emoji: emoji,
      imageUrl: imageUrl,
      applyPackagingFee: applyPackagingFee,
      notes: notes ?? this.notes,
    );
  }
}

class OrderPaymentEntry {
  const OrderPaymentEntry({
    required this.method,
    required this.amount,
    this.reference = '',
    this.at,
  });

  final PaymentMethod method;
  final double amount;
  final String reference;
  final DateTime? at;
}

/// One row of an order's audit trail. Rendered as a timeline in Order Details.
class OrderEvent {
  const OrderEvent({
    required this.labelKey,
    required this.at,
    required this.byUser,
    this.oldValue,
    this.newValue,
    this.reason,
  });

  final String labelKey;
  final DateTime at;
  final String byUser;
  final String? oldValue;
  final String? newValue;
  final String? reason;

  bool get hasDiff => oldValue != null || newValue != null;
}

class RestaurantOrder {
  const RestaurantOrder({
    required this.id,
    required this.number,
    required this.restaurantId,
    required this.type,
    required this.status,
    required this.lines,
    required this.createdAt,
    this.tableId,
    this.tableLabel,
    this.waiterName = '',
    this.customerName = '',
    this.customerPhone = '',
    this.guests = 0,
    this.discount = 0,
    this.taxRate = 0,
    this.packagingFee = 0,
    this.payments = const <OrderPaymentEntry>[],
    this.events = const <OrderEvent>[],
    this.cancelReason,
    this.notes = '',
    this.customerId,
    this.paymentStatus = PaymentStatus.paid,
    this.isLocked = false,
    this.serverSubtotal,
    this.serverTaxAmount,
    this.serverTotal,
  });

  final int id;
  final int number;
  final int restaurantId;
  final OrderType type;
  final OrderStatus status;
  final List<OrderLine> lines;
  final DateTime createdAt;
  final int? tableId;
  final String? tableLabel;
  final String waiterName;
  final String customerName;
  final String customerPhone;
  final int guests;
  final double discount;
  final double taxRate;
  final double packagingFee;
  final List<OrderPaymentEntry> payments;
  final List<OrderEvent> events;
  final String? cancelReason;
  final String notes;

  /// The account this order was put on, when it went on one.
  ///
  /// Separate from [customerName], which is free text somebody typed at the
  /// till. Only an id means a real account with a ledger behind it.
  final int? customerId;

  /// Whether the money has actually arrived.
  ///
  /// Defaults to paid because that is what every order was before credit
  /// existed, and an old order re-read from a server that does not send the
  /// field must not suddenly look like a debt.
  final PaymentStatus paymentStatus;

  /// The evening this order belongs to has been counted and closed.
  ///
  /// Nothing about it can move any more: the drawer was counted against
  /// this total, the difference was explained by somebody who put their
  /// name to it, and editing now would quietly make that reconciliation
  /// untrue. The server refuses; this is so the app does not offer.
  final bool isLocked;

  /// Totals as the API stated them.
  ///
  /// The server is authoritative on money: it recomputes from stored menu
  /// prices at order time and rounds to two places. Recomputing here would
  /// usually agree, but "usually" is not good enough for a receipt — so when
  /// the server has spoken, we show exactly what it said, and only fall back
  /// to local arithmetic for orders built offline from a cart.
  final double? serverSubtotal;
  final double? serverTaxAmount;
  final double? serverTotal;

  double get subtotal =>
      serverSubtotal ??
      lines.fold<double>(0, (double sum, OrderLine l) => sum + l.total);

  double get taxAmount => serverTaxAmount ?? (subtotal - discount) * taxRate;

  double get total =>
      serverTotal ?? (subtotal - discount + taxAmount + packagingFee);

  int get itemCount =>
      lines.fold<int>(0, (int sum, OrderLine l) => sum + l.quantity);

  PaymentMethod? get primaryPayment =>
      payments.isEmpty ? null : payments.first.method;

  RestaurantOrder copyWith({
    OrderStatus? status,
    List<OrderEvent>? events,
    String? cancelReason,
    int? customerId,
    String? customerName,
    PaymentStatus? paymentStatus,
    bool? isLocked,
  }) {
    return RestaurantOrder(
      id: id,
      number: number,
      restaurantId: restaurantId,
      type: type,
      status: status ?? this.status,
      lines: lines,
      createdAt: createdAt,
      tableId: tableId,
      tableLabel: tableLabel,
      waiterName: waiterName,
      customerName: customerName ?? this.customerName,
      customerPhone: customerPhone,
      guests: guests,
      discount: discount,
      taxRate: taxRate,
      packagingFee: packagingFee,
      payments: payments,
      events: events ?? this.events,
      cancelReason: cancelReason ?? this.cancelReason,
      notes: notes,
      customerId: customerId ?? this.customerId,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      isLocked: isLocked ?? this.isLocked,
      serverSubtotal: serverSubtotal,
      serverTaxAmount: serverTaxAmount,
      serverTotal: serverTotal,
    );
  }
}

/// An order parked before checkout. Drafts are deliberately *not* sales: no
/// report, KPI or account balance counts them until checkout completes.
class DraftOrder {
  const DraftOrder({
    required this.id,
    required this.code,
    required this.restaurantId,
    required this.customerName,
    required this.type,
    required this.lines,
    required this.createdAt,
    this.customerPhone = '',
    this.notes = '',
    this.tableId,
    this.tableLabel,
    this.waiterName = '',
    this.packagingApplied = false,
    this.status = DraftStatus.draft,
    this.cancelReason,
  });

  final int id;
  final String code;
  final int restaurantId;
  final String customerName;
  final String customerPhone;
  final OrderType type;
  final List<OrderLine> lines;
  final DateTime createdAt;
  final String notes;

  /// Which table it is parked against.
  ///
  /// The label alone reads well but cannot be sent back, so editing a draft
  /// used to drop the table and make the cashier pick it again.
  final int? tableId;
  final String? tableLabel;
  final String waiterName;
  final bool packagingApplied;
  final DraftStatus status;

  /// Why the customer walked away. Null unless the draft was refused.
  final String? cancelReason;

  double get subtotal =>
      lines.fold<double>(0, (double sum, OrderLine l) => sum + l.total);

  int get itemCount =>
      lines.fold<int>(0, (int sum, OrderLine l) => sum + l.quantity);
}
