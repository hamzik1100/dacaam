import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/enums.dart';
import '../models/app_notification.dart';
import '../models/analytics.dart';
import '../models/dining_table.dart';
import '../models/customer.dart';
import '../models/finance.dart';
import '../models/menu.dart';
import '../models/order.dart';
import '../models/restaurant.dart';
import '../models/shift.dart';

/// JSON → domain models.
///
/// Kept out of the model classes so the models stay transport-agnostic, and
/// every accessor is defensive: a field the server stops sending degrades to a
/// sensible default instead of crashing a POS mid-service.
class Api {
  const Api._();

  // ------------------------------------------------------------ scalars

  static Map<String, dynamic> map(dynamic value) =>
      value is Map ? value.cast<String, dynamic>() : <String, dynamic>{};

  static List<Map<String, dynamic>> list(dynamic value) =>
      value is List ? value.map(map).toList() : const <Map<String, dynamic>>[];

  static int int_(dynamic value, [int fallback = 0]) => switch (value) {
    int v => v,
    double v => v.round(),
    String v => int.tryParse(v) ?? fallback,
    _ => fallback,
  };

  static int? intOrNull(dynamic value) => value == null ? null : int_(value, 0);

  static double double_(dynamic value, [double fallback = 0]) =>
      switch (value) {
        double v => v,
        int v => v.toDouble(),
        String v => double.tryParse(v) ?? fallback,
        _ => fallback,
      };

  /// Null stays null.
  ///
  /// A shift that is still open sends no expected total at all, and
  /// defaulting that to zero would render a drawer the system believes is
  /// empty. Absent and zero are different answers.
  static double? doubleOrNull(dynamic value) =>
      value == null ? null : double_(value, 0);

  static String string(dynamic value, [String fallback = '']) =>
      value == null ? fallback : '$value';

  static String? stringOrNull(dynamic value) =>
      value == null || '$value'.isEmpty ? null : '$value';

  static bool bool_(dynamic value, [bool fallback = false]) => switch (value) {
    bool v => v,
    int v => v != 0,
    String v => v == '1' || v.toLowerCase() == 'true',
    _ => fallback,
  };

  static DateTime dateTime(dynamic value) =>
      DateTime.tryParse('$value')?.toLocal() ?? DateTime.now();

  /// Like [dateTime], but null stays null.
  ///
  /// The difference matters wherever absence is the meaning: a cancelled_at of
  /// null says the expense still counts, and falling back to "now" would mark
  /// every live entry as voided this instant.
  static DateTime? dateTimeOrNull(dynamic value) =>
      value == null ? null : DateTime.tryParse('$value')?.toLocal();

  /// `#F97316` → Color. Falls back to the brand orange on anything unexpected.
  static Color color(dynamic value, [Color fallback = AppColors.primary]) {
    final String hex = string(value).replaceAll('#', '').trim();
    if (hex.length != 6) return fallback;
    final int? parsed = int.tryParse('FF$hex', radix: 16);

    return parsed == null ? fallback : Color(parsed);
  }

  // ------------------------------------------------------------ tenancy

  static Restaurant restaurant(Map<String, dynamic> json) => Restaurant(
    id: int_(json['id']),
    slug: string(json['slug']),
    name: string(json['name']),
    phone: string(json['phone']),
    address: string(json['address']),
    isOpen: bool_(json['is_open'], true),
    subscriptionStatus: string(json['status'], 'active'),
    logoEmoji: string(json['logo_emoji'], '🍽️'),
  );

  static AppUser user(Map<String, dynamic> json) {
    final UserRole role = UserRole.fromApi(stringOrNull(json['role']));
    final List<dynamic> codes = json['permissions'] is List
        ? json['permissions'] as List<dynamic>
        : const <dynamic>[];

    // A user with no explicit grants still gets their role's defaults, so the
    // shell never renders an empty navigation bar.
    final Set<Permission> permissions = codes.isEmpty
        ? Permission.forRole(role)
        : Permission.fromCodes(codes.map((dynamic c) => '$c'));

    return AppUser(
      id: int_(json['id']),
      restaurantId: int_(json['restaurant_id']),
      name: string(json['name']),
      phone: string(json['phone']),
      role: role,
      permissions: permissions,
      active: bool_(json['is_active'], true),
    );
  }

  // ---------------------------------------------------------- catalogue

  static MenuCategory category(Map<String, dynamic> json) => MenuCategory(
    id: int_(json['id']),
    restaurantId: int_(json['restaurant_id']),
    name: string(json['name']),
    emoji: string(json['emoji'], '🍽️'),
    color: color(json['color']),
    description: string(json['description']),
    active: bool_(json['is_active'], true),
    sortOrder: int_(json['sort_order']),
  );

  static MenuItem menuItem(Map<String, dynamic> json) => MenuItem(
    id: int_(json['id']),
    restaurantId: int_(json['restaurant_id']),
    categoryId: int_(json['category_id']),
    name: string(json['name']),
    price: double_(json['price']),
    description: string(json['description']),
    imageUrl: stringOrNull(json['image_url']),
    emoji: string(json['emoji'], '🍽️'),
    available: bool_(json['is_available'], true),
    applyPackagingFee: bool_(json['apply_packaging_fee'], true),
    sortOrder: int_(json['sort_order']),
  );

  static DiningTable table(Map<String, dynamic> json) => DiningTable(
    id: int_(json['id']),
    restaurantId: int_(json['restaurant_id']),
    number: int_(json['table_number']),
    capacity: int_(json['capacity'], 4),
    name: string(json['name']),
    status: TableStatus.fromApi(stringOrNull(json['status'])),
    currentOrderId: intOrNull(json['current_order_id']),
    active: bool_(json['is_active'], true),
  );

  // ------------------------------------------------------------- orders

  static OrderLine orderLine(Map<String, dynamic> json) => OrderLine(
    itemId: int_(json['menu_item_id']),
    name: string(json['item_name']),
    unitPrice: double_(json['unit_price']),
    quantity: int_(json['quantity'], 1),
    emoji: string(json['emoji'], '🍽️'),
    imageUrl: stringOrNull(json['image_url']),
    applyPackagingFee: bool_(json['apply_packaging_fee'], true),
    notes: string(json['notes']),
  );

  static OrderPaymentEntry payment(Map<String, dynamic> json) =>
      OrderPaymentEntry(
        method: PaymentMethod.fromApi(stringOrNull(json['method'])),
        amount: double_(json['amount']),
        reference: string(json['reference']),
        at: json['created_at'] == null ? null : dateTime(json['created_at']),
      );

  /// Audit rows double as an order's timeline; `action` maps onto the same
  /// translation keys the mock timeline used, so the UI is unchanged.
  static OrderEvent orderEvent(Map<String, dynamic> json) => OrderEvent(
    labelKey: _eventKey(string(json['action'])),
    at: dateTime(json['created_at']),
    byUser: string(json['user_name']),
    oldValue: stringOrNull(json['old_value']),
    newValue: stringOrNull(json['new_value']),
    reason: stringOrNull(json['reason']),
  );

  static const Map<String, String> _eventKeys = <String, String>{
    'order_created': 'orderCreated',
    'item_added': 'itemAdded',
    'quantity_changed': 'quantityChanged',
    'payment_added': 'paymentAdded',
    'order_status_changed': 'orderStatusChanged',
  };

  static String _eventKey(String action) => _eventKeys[action] ?? action;

  static RestaurantOrder order(Map<String, dynamic> json) {
    return RestaurantOrder(
      id: int_(json['id']),
      number: int_(json['order_number']),
      restaurantId: int_(json['restaurant_id']),
      type: OrderType.fromApi(stringOrNull(json['order_type'])),
      status: OrderStatus.fromApi(stringOrNull(json['status'])),
      lines: list(json['items']).map(orderLine).toList(),
      createdAt: dateTime(json['created_at']),
      tableId: intOrNull(json['table_id']),
      tableLabel: stringOrNull(json['table_label']),
      waiterName: string(json['waiter_name']),
      customerName: string(json['customer_name']),
      customerPhone: string(json['customer_phone']),
      guests: int_(json['guests']),
      discount: double_(json['discount']),
      // The API states the rate as a percent; the model works in fractions.
      taxRate: double_(json['tax_rate']) / 100,
      packagingFee: double_(json['packaging_fee']),
      payments: list(json['payments']).map(payment).toList(),
      events: list(json['events']).map(orderEvent).toList(),
      cancelReason: stringOrNull(json['cancel_reason']),
      notes: string(json['notes']),
      customerId: intOrNull(json['customer_id']),
      paymentStatus: PaymentStatus.fromApi(stringOrNull(json['payment_status'])),
      isLocked: bool_(json['is_locked']),
      serverSubtotal: double_(json['subtotal']),
      serverTaxAmount: double_(json['tax_amount']),
      serverTotal: double_(json['total']),
    );
  }

  static DraftOrder draft(Map<String, dynamic> json) => DraftOrder(
    id: int_(json['id']),
    code: string(json['code']),
    restaurantId: int_(json['restaurant_id']),
    customerName: string(json['customer_name']),
    customerPhone: string(json['customer_phone']),
    type: OrderType.fromApi(stringOrNull(json['order_type'])),
    lines: list(json['items']).map(orderLine).toList(),
    createdAt: dateTime(json['created_at']),
    notes: string(json['notes']),
    tableId: intOrNull(json['table_id']),
    tableLabel: stringOrNull(json['table_label']),
    waiterName: string(json['waiter_name']),
    packagingApplied: bool_(json['packaging_applied']),
    status: DraftStatus.fromApi(stringOrNull(json['status'])),
    cancelReason: stringOrNull(json['cancel_reason']),
  );

  // ------------------------------------------------------------ finance

  static const Map<String, IconData> _expenseIcons = <String, IconData>{
    'local_grocery_store': Icons.local_grocery_store_rounded,
    'cleaning_services': Icons.cleaning_services_rounded,
    'local_shipping': Icons.local_shipping_rounded,
    'home_work': Icons.home_work_rounded,
    'groups': Icons.groups_rounded,
    'bolt': Icons.bolt_rounded,
    'receipt': Icons.receipt_rounded,
  };

  static ExpenseCategory expenseCategory(Map<String, dynamic> json) =>
      ExpenseCategory(
        id: int_(json['id']),
        name: string(json['name']),
        icon: _expenseIcons[string(json['icon'])] ?? Icons.receipt_rounded,
        color: color(json['color'], AppColors.violet),
        kind: ExpenseKind.fromApi(stringOrNull(json['kind'])),
      );

  static Expense expense(Map<String, dynamic> json) => Expense(
    id: int_(json['id']),
    restaurantId: int_(json['restaurant_id']),
    name: string(json['name']),
    amount: double_(json['amount']),
    categoryId: int_(json['expense_category_id']),
    categoryName: string(json['category_name']),
    method: PaymentMethod.fromApi(stringOrNull(json['method'])),
    date: dateTime(json['expense_date']),
    kind: ExpenseKind.fromApi(stringOrNull(json['kind'])),
    notes: string(json['notes']),
    createdBy: string(json['created_by']),
    recurring: bool_(json['is_recurring']),
    cancelledAt: dateTimeOrNull(json['cancelled_at']),
    cancelReason: string(json['cancel_reason']),
  );

  static Shift shift(dynamic raw) {
    final Map<String, dynamic> json = map(raw);

    return Shift(
      id: int_(json['id']),
      accountId: int_(json['account_id']),
      accountName: string(json['account_name']),
      openedBy: string(json['opened_by']),
      openedAt: dateTime(json['opened_at']),
      openingFloat: double_(json['opening_float']),
      previousClose: doubleOrNull(json['previous_close']),
      overnightDiff: doubleOrNull(json['overnight_diff']),
      closedBy: string(json['closed_by']),
      closedAt: dateTimeOrNull(json['closed_at']),
      // Absent while the shift is open. Not defaulted to zero: the
      // difference between "not told" and "nothing" is the whole control.
      expectedClose: doubleOrNull(json['expected_close']),
      countedClose: doubleOrNull(json['counted_close']),
      variance: doubleOrNull(json['variance']),
      closeReason: json['close_reason'] == null
          ? null
          : string(json['close_reason']),
      ordersOutside: int_(json['orders_outside']),
      notes: string(json['notes']),
      isOpen: bool_(json['is_open'], true),
      accounts: list(json['accounts']).map(shiftCount).toList(),
    );
  }

  static ShiftCount shiftCount(Map<String, dynamic> json) => ShiftCount(
    accountId: int_(json['account_id']),
    name: string(json['name']),
    method: string(json['method']),
    expected: double_(json['expected']),
    counted: double_(json['counted']),
    variance: double_(json['variance']),
  );

  static ShiftMovement shiftMovement(Map<String, dynamic> json) => ShiftMovement(
    kind: string(json['kind']),
    description: string(json['description']),
    amount: double_(json['amount']),
    at: dateTime(json['created_at']),
  );

  static ShiftDetail shiftDetail(Map<String, dynamic> json) => ShiftDetail(
    shift: shift(json['shift']),
    expected: double_(json['expected']),
    accounts: list(json['accounts']).map(shiftCount).toList(),
    expenses: shiftExpenses(json['expenses']),
    movements: list(json['movements']).map(shiftMovement).toList(),
  );
  static CountableAccount countableAccount(dynamic raw) {
    final Map<String, dynamic> json = map(raw);

    return CountableAccount(
      id: int_(json['id']),
      name: string(json['name']),
      method: string(json['method']),
      // Null only from a server older than this build. Zero is a real answer
      // — an account that genuinely took nothing — so the two are kept apart.
      received: doubleOrNull(json['received']),
      paidOut: double_(json['paid_out']),
    );
  }

  static ShiftExpenses shiftExpenses(dynamic raw) {
    final Map<String, dynamic> json = map(raw);

    return ShiftExpenses(
      total: double_(json['total']),
      items: list(json['items'])
          .map(
            (Map<String, dynamic> e) => ShiftExpenseLine(
              name: string(e['name']),
              amount: double_(e['amount']),
              method: string(e['method']),
            ),
          )
          .toList(),
    );
  }

  static PaymentMethodRecord paymentMethod(dynamic raw) {
    final Map<String, dynamic> json = map(raw);

    return PaymentMethodRecord(
      id: int_(json['id']),
      code: string(json['code']),
      name: string(json['name']),
      isActive: bool_(json['is_active'], true),
      isSystem: bool_(json['is_system']),
      sortOrder: int_(json['sort_order']),
      accountCount: int_(json['account_count']),
    );
  }

  static AccountTransaction accountTransaction(Map<String, dynamic> json) =>
      AccountTransaction(
        id: int_(json['id']),
        accountId: int_(json['account_id']),
        kind: switch (string(json['kind'])) {
          'money_out' => TransactionKind.moneyOut,
          'transfer' => TransactionKind.transfer,
          'adjustment' => TransactionKind.adjustment,
          _ => TransactionKind.moneyIn,
        },
        amount: double_(json['amount']),
        at: dateTime(json['created_at']),
        description: string(json['description']),
      );

  static Account account(Map<String, dynamic> json) => Account(
    id: int_(json['id']),
    restaurantId: int_(json['restaurant_id']),
    method: PaymentMethod.fromApi(stringOrNull(json['method'])),
    balance: double_(json['balance']),
    moneyIn: double_(json['money_in']),
    moneyOut: double_(json['money_out']),
  );

  static AppNotification notification(dynamic raw) {
    final Map<String, dynamic> json = map(raw);

    return AppNotification(
      id: int_(json['id']),
      title: string(json['title']),
      body: string(json['body']),
      sentAt: dateTime(json['sent_at']),
      kind: NotificationKind.fromApi(stringOrNull(json['kind'])),
      isRead: bool_(json['is_read']),
    );
  }

  // ---------------------------------------------------------- customers

  static Customer customer(dynamic raw) {
    final Map<String, dynamic> json = map(raw);

    return Customer(
      id: int_(json['id']),
      name: string(json['name']),
      phone: string(json['phone']),
      address: string(json['address']),
      notes: string(json['notes']),
      creditLimit: double_(json['credit_limit']),
      balanceOwed: double_(json['balance_owed']),
      isActive: bool_(json['is_active'], true),
      createdAt: json['created_at'] == null ? null : dateTime(json['created_at']),
      // Present on the profile endpoint, absent from the list.
      ledger: list(json['ledger']).map(Api.ledgerEntry).toList(),
    );
  }

  static LedgerEntry ledgerEntry(dynamic raw) {
    final Map<String, dynamic> json = map(raw);

    return LedgerEntry(
      id: int_(json['id']),
      kind: LedgerKind.fromApi(stringOrNull(json['kind'])),
      amount: double_(json['amount']),
      balanceAfter: double_(json['balance_after']),
      at: dateTime(json['created_at']),
      method: string(json['method']),
      description: string(json['description']),
      sourceType: string(json['source_type']),
      sourceId: json['source_id'] == null ? null : int_(json['source_id']),
      reason: stringOrNull(json['reason']),
      createdBy: string(json['created_by']),
      orderNumber: intOrNull(json['order_number']),
      // Null stays null: a deposit has no order, and defaulting it to `paid`
      // would put a green tick on a line that never was a sale.
      orderPaymentStatus: json['payment_status'] == null
          ? null
          : PaymentStatus.fromApi(stringOrNull(json['payment_status'])),
      orderCancelled: string(json['order_status']) == 'cancelled',
    );
  }

  static CashSummary cashSummary(dynamic raw) {
    final Map<String, dynamic> json = map(raw);

    return CashSummary(
      moneyIn: double_(json['money_in']),
      moneyOut: double_(json['money_out']),
      net: double_(json['net']),
      fromCustomers: double_(json['from_customers']),
    );
  }

  /// Serves both report rankings: `top_customers` fills orders and spent,
  /// `top_debtors` fills the balance and last payment, and the absent half of
  /// either simply stays at its default.
  static CustomerRank customerRank(dynamic raw) {
    final Map<String, dynamic> json = map(raw);

    return CustomerRank(
      customerId: int_(json['id']),
      name: string(json['name']),
      phone: string(json['phone']),
      orders: int_(json['orders']),
      spent: double_(json['spent']),
      balanceOwed: double_(json['balance_owed']),
      creditLimit: double_(json['credit_limit']),
      lastPaid: json['last_paid'] == null ? null : dateTime(json['last_paid']),
    );
  }

  // ---------------------------------------------------------- analytics

  static KpiValue kpi(dynamic value) {
    final Map<String, dynamic> json = map(value);

    return KpiValue(
      value: double_(json['value']),
      deltaPercent: double_(json['delta_percent']),
    );
  }

  static SeriesPoint seriesPoint(Map<String, dynamic> json) => SeriesPoint(
    label: string(json['label']),
    value: double_(json['value']),
    date: json['date'] == null ? null : DateTime.tryParse('${json['date']}'),
  );

  static RankedItem rankedItem(Map<String, dynamic> json) => RankedItem(
    itemId: int_(json['menu_item_id']),
    name: string(json['name']),
    quantity: int_(json['quantity']),
    revenue: double_(json['revenue']),
    emoji: string(json['emoji'], '🍽️'),
  );

  /// Series without a server-side colour (payments, waiters) borrow the shared
  /// chart palette by position, so the same label keeps the same colour.
  static BreakdownSlice slice(Map<String, dynamic> json, int index) =>
      BreakdownSlice(
        label: string(json['label']),
        value: double_(json['value']),
        count: int_(json['count']),
        color: json['color'] != null
            ? color(json['color'])
            : AppColors.series[index % AppColors.series.length],
      );

  static List<BreakdownSlice> slices(dynamic value) {
    final List<Map<String, dynamic>> rows = list(value);

    return <BreakdownSlice>[
      for (int i = 0; i < rows.length; i++) slice(rows[i], i),
    ];
  }
}
