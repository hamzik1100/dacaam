import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Dine In / Takeaway. Drives table requirements and packaging fees.
enum OrderType {
  dineIn('dine_in'),
  takeaway('takeaway');

  const OrderType(this.api);

  final String api;

  static OrderType fromApi(String? value) =>
      value == 'takeaway' ? OrderType.takeaway : OrderType.dineIn;

  String get labelKey => this == OrderType.dineIn ? 'dineIn' : 'takeaway';

  IconData get icon => this == OrderType.dineIn
      ? Icons.restaurant_rounded
      : Icons.shopping_bag_rounded;

  Color get tint =>
      this == OrderType.dineIn ? AppColors.violet : AppColors.info;
}

enum OrderStatus {
  pending('pending'),
  preparing('preparing'),
  ready('ready'),
  completed('completed'),
  cancelled('cancelled');

  const OrderStatus(this.api);

  final String api;

  static OrderStatus fromApi(String? value) => OrderStatus.values.firstWhere(
    (OrderStatus s) => s.api == value,
    orElse: () => OrderStatus.pending,
  );

  String get labelKey => name;

  Color get color => switch (this) {
    OrderStatus.pending => AppColors.secondary,
    OrderStatus.preparing => AppColors.primary,
    OrderStatus.ready => AppColors.info,
    OrderStatus.completed => AppColors.success,
    OrderStatus.cancelled => AppColors.danger,
  };

  bool get isOpen =>
      this == OrderStatus.pending ||
      this == OrderStatus.preparing ||
      this == OrderStatus.ready;
}

/// Whether an order's money has arrived, which is now a separate question from
/// whether the food has.
///
/// A credit order is `completed` and `unpaid` at the same time: the kitchen is
/// finished and the restaurant is owed. Folding the two together is what makes
/// a month of credit read as a month of takings.
enum PaymentStatus {
  unpaid('unpaid'),
  partial('partial'),
  paid('paid');

  const PaymentStatus(this.api);

  final String api;

  static PaymentStatus fromApi(String? value) => PaymentStatus.values.firstWhere(
    (PaymentStatus s) => s.api == value,
    // Absent means an order from before credit existed, and those were paid.
    orElse: () => PaymentStatus.paid,
  );

  String get labelKey => switch (this) {
    PaymentStatus.unpaid => 'unpaid',
    PaymentStatus.partial => 'partlyPaid',
    PaymentStatus.paid => 'paid',
  };

  Color get color => switch (this) {
    PaymentStatus.unpaid => AppColors.danger,
    PaymentStatus.partial => AppColors.secondary,
    PaymentStatus.paid => AppColors.success,
  };

  bool get isSettled => this == PaymentStatus.paid;
}

/// How the customer is settling up at checkout.
enum PaymentMode {
  cash('cash'),
  credit('credit'),
  wallet('wallet');

  const PaymentMode(this.api);

  final String api;

  String get labelKey => switch (this) {
    PaymentMode.cash => 'payNow',
    PaymentMode.credit => 'onCredit',
    PaymentMode.wallet => 'fromWallet',
  };
}

enum DraftStatus {
  draft('draft'),
  pending('pending'),
  completed('completed'),
  cancelled('cancelled');

  const DraftStatus(this.api);

  final String api;

  static DraftStatus fromApi(String? value) => DraftStatus.values.firstWhere(
    (DraftStatus s) => s.api == value,
    orElse: () => DraftStatus.draft,
  );

  Color get color => switch (this) {
    DraftStatus.draft => AppColors.subtextLight,
    DraftStatus.pending => AppColors.secondary,
    DraftStatus.completed => AppColors.success,
    DraftStatus.cancelled => AppColors.danger,
  };
}

/// A way the restaurant takes money.
///
/// Not an enum any more. Methods are rows on the server now — a shop that
/// starts accepting a new mobile wallet adds it in Settings, and an enum could
/// not represent one the app was not compiled with. The four below stay as
/// constants because every restaurant is seeded with them and because code
/// elsewhere names them directly.
///
/// Identity is the [api] code: two instances with the same code are the same
/// method regardless of what they are called, which is what lets a renamed
/// method still match the payments already recorded against it.
@immutable
class PaymentMethod {
  const PaymentMethod(this.api, this.label, this.icon, this.color);

  static const PaymentMethod cash = PaymentMethod(
    'cash',
    'Cash',
    Icons.payments_rounded,
    AppColors.success,
  );
  static const PaymentMethod zaad = PaymentMethod(
    'zaad',
    'Zaad',
    Icons.smartphone_rounded,
    AppColors.info,
  );
  static const PaymentMethod edahab = PaymentMethod(
    'edahab',
    'eDahab',
    Icons.phone_iphone_rounded,
    AppColors.secondary,
  );
  static const PaymentMethod bank = PaymentMethod(
    'bank',
    'Bank',
    Icons.account_balance_rounded,
    AppColors.violet,
  );

  /// The seeded four. Used where no server list is to hand — filter sheets on
  /// the offline dataset, and as the fallback before the first load.
  static const List<PaymentMethod> builtIn = <PaymentMethod>[
    cash,
    zaad,
    edahab,
    bank,
  ];

  final String api;
  final String label;
  final IconData icon;
  final Color color;

  /// A method the app was not built with. The icon and colour are derived from
  /// the code so they stay the same between launches — a wallet that changes
  /// colour every restart looks like a different wallet.
  factory PaymentMethod.custom(String code, String name) {
    const List<IconData> icons = <IconData>[
      Icons.account_balance_wallet_rounded,
      Icons.credit_card_rounded,
      Icons.savings_rounded,
      Icons.currency_exchange_rounded,
      Icons.qr_code_2_rounded,
    ];
    const List<Color> colors = <Color>[
      AppColors.violet,
      AppColors.teal,
      AppColors.info,
      AppColors.secondary,
      AppColors.primary,
    ];

    final int seed = code.codeUnits.fold<int>(0, (int a, int b) => a + b);

    return PaymentMethod(
      code,
      name.isEmpty ? code : name,
      icons[seed % icons.length],
      colors[seed % colors.length],
    );
  }

  /// Resolves a stored code. An unknown one keeps its identity rather than
  /// silently becoming Cash — a Zaad payment displayed as Cash is a
  /// reconciliation error nobody would think to look for.
  static PaymentMethod fromApi(String? value) {
    if (value == null || value.isEmpty) return cash;

    for (final PaymentMethod m in builtIn) {
      if (m.api == value) return m;
    }

    return PaymentMethod.custom(value, value);
  }

  @override
  bool operator ==(Object other) => other is PaymentMethod && other.api == api;

  @override
  int get hashCode => api.hashCode;

  @override
  String toString() => 'PaymentMethod($api)';
}

enum TableStatus {
  available('available'),
  occupied('occupied'),
  reserved('reserved'),
  disabled('disabled');

  const TableStatus(this.api);

  final String api;

  static TableStatus fromApi(String? value) => TableStatus.values.firstWhere(
    (TableStatus s) => s.api == value,
    orElse: () => TableStatus.available,
  );

  Color get color => switch (this) {
    TableStatus.available => AppColors.success,
    TableStatus.occupied => AppColors.primary,
    TableStatus.reserved => AppColors.info,
    TableStatus.disabled => AppColors.subtextLight,
  };
}

enum ExpenseKind {
  daily('daily'),
  monthly('monthly');

  const ExpenseKind(this.api);

  final String api;

  static ExpenseKind fromApi(String? value) =>
      value == 'monthly' ? ExpenseKind.monthly : ExpenseKind.daily;
}

/// Coarse role. Fine-grained control lives in [Permission] sets on the user.
enum UserRole {
  admin('admin'),
  operator('operator'),
  waiter('waiter');

  const UserRole(this.api);

  final String api;

  static UserRole fromApi(String? value) => UserRole.values.firstWhere(
    (UserRole r) => r.api == value,
    orElse: () => UserRole.waiter,
  );
}

/// Module-scoped permissions. The shell and every action button reads these,
/// so a Waiter simply never sees Reports or Users.
///
/// [code] is the wire format (`module.action`) shared with the API's
/// `permissions` table — the two lists must stay identical or the UI and the
/// server will disagree about what a role can do.
enum Permission {
  ordersView('orders.view'),
  ordersCreate('orders.create'),
  ordersEdit('orders.edit'),
  ordersCancel('orders.cancel'),
  ordersDelete('orders.delete'),
  menuView('menu.view'),
  menuCreate('menu.create'),
  menuEdit('menu.edit'),
  menuDelete('menu.delete'),
  expensesView('expenses.view'),
  expensesCreate('expenses.create'),
  expensesEdit('expenses.edit'),
  expensesDelete('expenses.delete'),
  reportsView('reports.view'),
  reportsExport('reports.export'),
  usersView('users.view'),
  usersCreate('users.create'),
  usersEdit('users.edit'),
  usersDelete('users.delete'),
  tablesView('tables.view'),
  tablesManage('tables.manage'),
  accountsView('accounts.view'),
  accountsManage('accounts.manage'),
  settingsView('settings.view'),
  settingsManage('settings.manage'),
  auditView('audit.view'),
  // Two, not one. `manage` opens and closes a till; `view` carries the
  // expected total and the history. Whoever counts the drawer holds only
  // the first, so the number they are meant to reach is not on their screen.
  shiftsView('shifts.view'),
  shiftsManage('shifts.manage'),
  customersView('customers.view'),
  customersCreate('customers.create'),
  customersEdit('customers.edit'),
  customersDelete('customers.delete'),
  // Taking money, kept apart from editing the record. Correcting a spelling
  // and accepting a repayment are different acts of trust.
  customersPayment('customers.payment'),
  // Separate from edit on purpose: changing a name is clerical, moving a
  // balance by hand is the one action that can make a debt vanish with no sale
  // behind it.
  customersAdjust('customers.adjust');

  const Permission(this.code);

  final String code;

  static final Map<String, Permission> _byCode = <String, Permission>{
    for (final Permission p in Permission.values) p.code: p,
  };

  /// Unknown codes are dropped rather than throwing: a newer server may know
  /// permissions this build does not, and that must not break sign-in.
  static Set<Permission> fromCodes(Iterable<String> codes) => <Permission>{
    for (final String code in codes)
      if (_byCode[code] != null) _byCode[code]!,
  };

  static Set<Permission> forRole(UserRole role) => switch (role) {
    UserRole.admin => Permission.values.toSet(),
    UserRole.operator => <Permission>{
      ordersView,
      ordersCreate,
      ordersEdit,
      ordersCancel,
      menuView,
      menuCreate,
      menuEdit,
      expensesView,
      expensesCreate,
      reportsView,
      tablesView,
      tablesManage,
      accountsView,
      settingsView,
      customersView,
      customersCreate,
      customersEdit,
      customersPayment,
    },
    UserRole.waiter => <Permission>{
      ordersView,
      ordersCreate,
      menuView,
      tablesView,
    },
  };
}

enum ReportRange {
  today,
  sevenDays,
  thirtyDays,
  thisMonth,
  lastMonth,
  custom;

  String get labelKey => switch (this) {
    ReportRange.today => 'today',
    ReportRange.sevenDays => 'sevenDays',
    ReportRange.thirtyDays => 'thirtyDays',
    ReportRange.thisMonth => 'thisMonth',
    ReportRange.lastMonth => 'lastMonth',
    ReportRange.custom => 'customRange',
  };
}

enum AppLanguage {
  somali('so'),
  english('en');

  const AppLanguage(this.code);

  final String code;
}
