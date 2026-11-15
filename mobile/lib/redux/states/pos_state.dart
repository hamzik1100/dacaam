import 'package:flutter/foundation.dart';

import '../../core/utils/enums.dart';
import '../../data/models/menu.dart';
import '../../data/models/order.dart';
import 'settings_state.dart';

/// Browsing state for the POS menu tab. Kept separate from [CartState] so
/// searching never touches the cart and vice-versa.
@immutable
class PosState {
  const PosState({this.query = '', this.categoryId, this.tabIndex = 0});

  final String query;

  /// `null` == the "All" chip.
  final int? categoryId;

  /// 0 = Menu, 1 = Cart.
  final int tabIndex;

  List<MenuItem> filter(List<MenuItem> items) {
    final String q = query.trim().toLowerCase();
    return items.where((MenuItem i) {
      final bool byCategory = categoryId == null || i.categoryId == categoryId;
      final bool byQuery = q.isEmpty || i.name.toLowerCase().contains(q);
      return byCategory && byQuery;
    }).toList();
  }

  PosState copyWith({
    String? query,
    int? categoryId,
    bool clearCategory = false,
    int? tabIndex,
  }) {
    return PosState(
      query: query ?? this.query,
      categoryId: clearCategory ? null : (categoryId ?? this.categoryId),
      tabIndex: tabIndex ?? this.tabIndex,
    );
  }
}

@immutable
class CartState {
  const CartState({
    this.lines = const <OrderLine>[],
    this.orderType = OrderType.dineIn,
    this.tableId,
    this.waiterId,
    this.guests = 0,
    this.discount = 0,
    this.customerName = '',
    this.customerPhone = '',
    this.notes = '',
    this.paymentMethod = PaymentMethod.cash,
    this.paymentReference = '',
    this.customerId,
    this.paymentMode = PaymentMode.cash,
    this.editingDraftId,
  });

  final List<OrderLine> lines;
  final OrderType orderType;
  final int? tableId;
  final int? waiterId;
  final int guests;
  final double discount;
  final String customerName;
  final String customerPhone;
  final String notes;
  final PaymentMethod paymentMethod;
  final String paymentReference;

  /// The account this sale goes on, when it goes on one. Null is a walk-in,
  /// and [customerName] stays what it always was — free text for the ticket.
  final int? customerId;

  /// Pay now, put it on the tab, or take it out of their deposit. Only [cash]
  /// works without a [customerId], which the checkout enforces before it lets
  /// the button through.
  final PaymentMode paymentMode;

  /// The parked order this cart is a working copy of.
  ///
  /// Null for an ordinary sale. When it is set, saving updates that draft
  /// instead of parking a second one — a customer who rings back to change
  /// their order should end up with one ticket, not two.
  final int? editingDraftId;

  bool get isEditingDraft => editingDraftId != null;

  bool get isEmpty => lines.isEmpty;

  int get itemCount =>
      lines.fold<int>(0, (int sum, OrderLine l) => sum + l.quantity);

  int indexOfItem(int itemId) =>
      lines.indexWhere((OrderLine l) => l.itemId == itemId);

  int quantityOf(int itemId) {
    final int i = indexOfItem(itemId);
    return i == -1 ? 0 : lines[i].quantity;
  }

  CartState copyWith({
    List<OrderLine>? lines,
    int? editingDraftId,
    bool clearEditingDraft = false,
    OrderType? orderType,
    int? tableId,
    bool clearTable = false,
    int? waiterId,
    int? guests,
    double? discount,
    String? customerName,
    String? customerPhone,
    String? notes,
    PaymentMethod? paymentMethod,
    String? paymentReference,
    int? customerId,
    bool clearCustomer = false,
    PaymentMode? paymentMode,
  }) {
    return CartState(
      lines: lines ?? this.lines,
      orderType: orderType ?? this.orderType,
      tableId: clearTable ? null : (tableId ?? this.tableId),
      waiterId: waiterId ?? this.waiterId,
      guests: guests ?? this.guests,
      discount: discount ?? this.discount,
      customerName: customerName ?? this.customerName,
      customerPhone: customerPhone ?? this.customerPhone,
      notes: notes ?? this.notes,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      paymentReference: paymentReference ?? this.paymentReference,
      customerId: clearCustomer ? null : (customerId ?? this.customerId),
      // Dropping the customer drops the modes that need one, so a cleared
      // picker can never leave the cart trying to charge a tab nobody owns.
      paymentMode: clearCustomer
          ? PaymentMode.cash
          : (paymentMode ?? this.paymentMode),
      editingDraftId: clearEditingDraft
          ? null
          : (editingDraftId ?? this.editingDraftId),
    );
  }
}

/// Money maths for a cart, in one place.
///
/// Business rules encoded here (mirrored by the API in Phase 2):
/// * Discount comes off the subtotal before tax.
/// * Tax only applies when enabled in Settings.
/// * The packaging fee is charged per portion on a takeaway: twenty plates go
///   into twenty containers, so twenty fees. It was one flat charge for the
///   whole order, which meant the restaurant bought nineteen boxes it never
///   billed for.
@immutable
class CartTotals {
  const CartTotals({
    required this.subtotal,
    required this.discount,
    required this.tax,
    required this.packaging,
    required this.total,
  });

  factory CartTotals.of(CartState cart, SettingsState settings) {
    return CartTotals.fromLines(
      lines: cart.lines,
      orderType: cart.orderType,
      discount: cart.discount,
      settings: settings,
    );
  }

  factory CartTotals.fromLines({
    required List<OrderLine> lines,
    required OrderType orderType,
    required double discount,
    required SettingsState settings,
  }) {
    final double subtotal = lines.fold<double>(
      0,
      (double sum, OrderLine l) => sum + l.total,
    );
    final double cappedDiscount = discount.clamp(0, subtotal).toDouble();
    final double taxable = subtotal - cappedDiscount;
    final double tax = taxable * settings.taxFraction;

    // Portions, not lines. Each one goes into its own container, and this
    // has to match Pricing::quote on the server exactly — the app showing
    // one total while the server charges another is worse than either
    // number being wrong on its own.
    final int packagedUnits = lines
        .where((OrderLine l) => l.applyPackagingFee)
        .fold<int>(0, (int sum, OrderLine l) => sum + l.quantity);

    final bool packagingApplies =
        orderType == OrderType.takeaway &&
        settings.packagingFeeEnabled &&
        packagedUnits > 0;
    final double packaging =
        packagingApplies ? settings.packagingFee * packagedUnits : 0;

    return CartTotals(
      subtotal: subtotal,
      discount: cappedDiscount,
      tax: tax,
      packaging: packaging,
      total: taxable + tax + packaging,
    );
  }

  final double subtotal;
  final double discount;
  final double tax;
  final double packaging;
  final double total;
}
