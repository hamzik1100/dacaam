import 'dart:ui' show Color;

import '../../core/config/app_config.dart';
import '../../core/utils/enums.dart';
import '../../redux/actions.dart';
import '../../redux/states/report_state.dart';
import '../../redux/states/settings_state.dart';
import '../api/api_client.dart';
import '../api/dacaam_api.dart';
import '../api/mappers.dart';
import '../api/token_store.dart';
import '../models/app_notification.dart';
import '../models/analytics.dart';
import '../../redux/states/customer_state.dart';
import '../models/customer.dart';
import '../models/dining_table.dart';
import '../models/finance.dart';
import '../models/menu.dart';
import '../models/order.dart';
import '../models/shift.dart';
import '../models/restaurant.dart';
import 'dacaam_repository.dart';
import '../../redux/states/finance_state.dart';

/// Live data source backed by the PHP REST API.
class ApiRepository implements DacaamRepository {
  ApiRepository({DacaamApi? api, TokenStore? tokens})
    : api = api ?? DacaamApi(ApiClient()),
      tokens = tokens ?? PrefsTokenStore();

  final DacaamApi api;
  final TokenStore tokens;

  String _restaurantCode = AppConfig.restaurantCode;

  @override
  Future<bool> restoreSession() async {
    final StoredSession? stored = await tokens.read();
    if (stored == null) return false;

    api.client.token = stored.token;
    _restaurantCode = stored.restaurantCode;

    try {
      // Cheapest possible proof the token is still good: expired, revoked and
      // password-changed sessions all fail here rather than mid-service.
      await api.me();

      return true;
    } on ApiException catch (e) {
      if (e.isUnauthorized || e.isForbidden) {
        api.client.clearSession();
        await tokens.clear();

        return false;
      }
      // A network blip is not a signal to sign the user out; keep the token
      // and let the caller decide (offline fallback, retry).
      rethrow;
    }
  }

  @override
  Future<SignInResult> signIn({
    required String restaurantCode,
    required String phone,
    required String password,
  }) async {
    api.client.clearSession();
    _restaurantCode = restaurantCode;

    final Map<String, dynamic> json = await api.login(
      restaurantCode: restaurantCode,
      phone: phone,
      password: password,
    );

    return _resultFrom(json, phone);
  }

  @override
  Future<SignInResult> verifyTwoFactor({
    required String challenge,
    required String code,
  }) async {
    final Map<String, dynamic> json = await api.verifyTwoFactor(
      challenge: challenge,
      code: code,
    );

    return _resultFrom(json, '');
  }

  Future<SignInResult> _resultFrom(
    Map<String, dynamic> json,
    String phone,
  ) async {
    if (Api.bool_(json['requires_two_factor'])) {
      return SignInResult.twoFactorRequired(
        challenge: Api.string(json['challenge']),
        userName: Api.string(json['user_name']),
        restaurantName: Api.string(json['restaurant_name']),
      );
    }

    await tokens.write(
      StoredSession(
        token: Api.string(json['token']),
        restaurantCode: _restaurantCode,
        phone: phone.isEmpty
            ? Api.string(Api.map(json['user'])['phone'])
            : phone,
      ),
    );

    return SignInResult.session(
      mustChangePassword: Api.bool_(json['must_change_password']),
      mustEnrolTwoFactor: Api.bool_(json['must_enrol_two_factor']),
    );
  }

  @override
  Future<void> signOut() async {
    await api.logout();
    await tokens.clear();
  }

  @override
  Future<BootstrapPayload> bootstrap() async {
    final Map<String, dynamic> json = await api.bootstrap();

    final Restaurant restaurant = Api.restaurant(Api.map(json['restaurant']));
    final AppUser user = Api.user(Api.map(json['user']));

    return BootstrapPayload(
      bootstrap: BootstrapSucceeded(
        restaurant: restaurant,
        user: user,
        staff: Api.list(json['staff']).map(Api.user).toList(),
        categories: Api.list(json['categories']).map(Api.category).toList(),
        items: Api.list(json['menu_items']).map(Api.menuItem).toList(),
        tables: Api.list(json['tables']).map(Api.table).toList(),
        orders: Api.list(json['orders']).map(Api.order).toList(),
        drafts: Api.list(json['drafts']).map(Api.draft).toList(),
        expenses: Api.list(json['expenses']).map(Api.expense).toList(),
        expenseCategories: Api.list(
          json['expense_categories'],
        ).map(Api.expenseCategory).toList(),
        accounts: Api.list(json['accounts']).map(Api.account).toList(),
        tillOpen: Api.bool_(json['till_open']),
      ),
      dashboard: _dashboardFrom(Api.map(json['dashboard'])),
      settings: _settingsFrom(Api.map(json['settings'])),
    );
  }

  @override
  Future<DashboardLoaded> dashboard() async =>
      _dashboardFrom(await api.dashboard());

  @override
  Future<ReportLoaded> reports(
    ReportRange range, {
    ReportFilters filters = const ReportFilters(),
  }) async {
    final Map<String, dynamic> json = await api.reportSummary(
      _rangeKey(range),
      filters: filters.toQuery(),
    );

    return ReportLoaded(
      sales: Api.kpi(json['sales']),
      orders: Api.kpi(json['orders']),
      expenses: Api.kpi(json['expenses']),
      profit: Api.kpi(json['profit']),
      daily: Api.list(json['daily']).map(Api.seriesPoint).toList(),
      hourly: Api.list(json['hourly']).map(Api.seriesPoint).toList(),
      byCategory: Api.slices(json['by_category']),
      byPayment: Api.slices(json['by_payment']),
      byWaiter: Api.slices(json['by_waiter']),
      byTable: Api.slices(json['by_table']),
      topItems: Api.list(json['top_items']).map(Api.rankedItem).toList(),
      lowItems: Api.list(json['low_items']).map(Api.rankedItem).toList(),
      discounts: Api.double_(json['discounts']),
      tax: Api.double_(json['tax']),
      packaging: Api.double_(json['packaging']),
      completedOrders: Api.int_(json['completed_orders']),
      cancelledOrders: Api.int_(json['cancelled_orders']),
      draftOrders: Api.int_(json['draft_orders']),
      dineInOrders: Api.int_(json['dine_in_orders']),
      takeawayOrders: Api.int_(json['takeaway_orders']),
      cash: Api.cashSummary(json['cash']),
      receivables: Api.double_(json['receivables']),
      depositsHeld: Api.double_(json['deposits_held']),
      unpaidOrders: Api.double_(json['unpaid_orders']),
      topCustomers: Api.list(json['top_customers']).map(Api.customerRank).toList(),
      topDebtors: Api.list(json['top_debtors']).map(Api.customerRank).toList(),
    );
  }

  @override
  Future<RestaurantOrder> placeOrder(OrderRequest request) async =>
      Api.order(await api.createOrder(request.toJson()));

  @override
  Future<RestaurantOrder> order(int id) async => Api.order(await api.order(id));

  @override
  Future<RestaurantOrder> setOrderStatus(
    int orderId,
    OrderStatus status, {
    String? reason,
  }) async =>
      Api.order(await api.setOrderStatus(orderId, status, reason: reason));

  @override
  Future<RestaurantOrder> updateOrderItems(
    int orderId,
    List<OrderLine> lines, {
    double? discount,
    String? reason,
  }) async => Api.order(
    await api.updateOrderItems(orderId, <String, dynamic>{
      'items': lines
          .map(
            (OrderLine l) => <String, dynamic>{
              'menu_item_id': l.itemId,
              'quantity': l.quantity,
            },
          )
          .toList(),
      'discount': ?discount,
      if (reason != null && reason.isNotEmpty) 'reason': reason,
    }),
  );

  @override
  Future<RestaurantOrder> addPayment(
    int orderId, {
    required PaymentMethod method,
    required double amount,
    String reference = '',
  }) async => Api.order(
    await api.addPayment(
      orderId,
      method: method,
      amount: amount,
      reference: reference,
    ),
  );

  // --------------------------------------------------------------- drafts

  @override
  Future<List<DraftOrder>> drafts() async =>
      Api.list(await api.drafts()).map(Api.draft).toList();

  @override
  Future<DraftOrder> saveDraft(DraftRequest request) async {
    final Map<String, dynamic> json = request.id == null
        ? await api.createDraft(request.toJson())
        : await api.updateDraft(request.id!, request.toJson());

    return Api.draft(json);
  }

  @override
  Future<DraftOrder> cancelDraft(int id, String reason) async =>
      Api.draft(await api.cancelDraft(id, reason));

  @override
  Future<RestaurantOrder> convertDraft(
    int id, {
    PaymentMethod? method,
    OrderType? orderType,
    int? tableId,
    int? waiterId,
  }) async => Api.order(
    await api.convertDraft(
      id,
      method: method,
      orderType: orderType,
      tableId: tableId,
      waiterId: waiterId,
    ),
  );

  // ----------------------------------------------------------------- menu

  @override
  Future<MenuItem> saveMenuItem(MenuItem item, {String? reason}) async {
    final Map<String, dynamic> payload = <String, dynamic>{
      'category_id': item.categoryId,
      'name': item.name,
      'price': item.price,
      'description': item.description,
      'emoji': item.emoji,
      'is_available': item.available,
      'apply_packaging_fee': item.applyPackagingFee,
      if (reason != null && reason.isNotEmpty) 'reason': reason,
    };

    // A negative id is the sentinel the editor uses for "not saved yet".
    final Map<String, dynamic> json = item.id <= 0
        ? await api.createMenuItem(payload)
        : await api.updateMenuItem(item.id, payload);

    return Api.menuItem(json);
  }

  @override
  Future<MenuItem> toggleMenuItem(int id) async =>
      Api.menuItem(await api.toggleMenuItem(id));

  @override
  Future<MenuItem> setMenuItemImage(int id, String? base64) async =>
      Api.menuItem(
        base64 == null
            ? await api.deleteMenuImage(id)
            : await api.uploadMenuImage(id, base64),
      );

  @override
  Future<void> deleteMenuItem(int id) => api.deleteMenuItem(id);

  @override
  Future<List<MenuCategory>> saveCategory(MenuCategory category) async {
    final Map<String, dynamic> payload = <String, dynamic>{
      'name': category.name,
      'description': category.description,
      'emoji': category.emoji,
      'color': _hex(category.color),
      'is_active': category.active,
      'sort_order': category.sortOrder,
    };

    if (category.id <= 0) {
      await api.createCategory(payload);
    } else {
      await api.updateCategory(category.id, payload);
    }

    return Api.list(await api.categories()).map(Api.category).toList();
  }

  @override
  Future<List<MenuCategory>> deleteCategory(int id) async {
    await api.deleteCategory(id);

    return Api.list(await api.categories()).map(Api.category).toList();
  }

  // --------------------------------------------------------------- tables

  @override
  Future<List<DiningTable>> tables() async =>
      Api.list(await api.tables()).map(Api.table).toList();

  @override
  Future<List<DiningTable>> saveTable(DiningTable table) async {
    final Map<String, dynamic> payload = <String, dynamic>{
      'table_number': table.number,
      'capacity': table.capacity,
      'name': table.name,
      'status': table.status.api,
      'is_active': table.active,
    };

    if (table.id <= 0) {
      payload.remove('status'); // a new table is always available
      await api.createTable(payload);
    } else {
      await api.updateTable(table.id, payload);
    }

    return tables();
  }

  @override
  Future<List<DiningTable>> deleteTable(int id) async {
    await api.deleteTable(id);

    return tables();
  }

  // ------------------------------------------------------------- expenses

  @override
  Future<List<Expense>> expenses() async =>
      Api.list(await api.expenses()).map(Api.expense).toList();

  @override
  Future<List<Expense>> saveExpense(ExpenseRequest request) async {
    if (request.id == null) {
      await api.createExpense(request.toJson());
    } else {
      await api.updateExpense(request.id!, request.toJson());
    }

    return expenses();
  }

  // ------------------------------------------------------------- shifts

  @override
  Future<ShiftStatus> currentShift() async {
    final Map<String, dynamic> json = await api.currentShift();

    return ShiftStatus(
      shift: json['shift'] == null ? null : Api.shift(json['shift']),
      lastClose: Api.doubleOrNull(json['last_close']),
      accountId: Api.intOrNull(json['account_id']),
      accounts: Api.list(json['accounts'])
          .map(Api.countableAccount)
          .toList(),
      expenses: Api.shiftExpenses(json['expenses']),
    );
  }

  @override
  Future<ShiftStatus> openShift({
    required double openingFloat,
    String notes = '',
  }) async {
    await api.openShift(openingFloat: openingFloat, notes: notes);

    // Re-read rather than trusting the create response: the caller wants the
    // same shape every other path produces, including what the previous shift
    // left behind.
    return currentShift();
  }

  @override
  Future<Shift> closeShift(
    int id, {
    required Map<int, double> counts,
    String reason = '',
  }) async {
    return Api.shift(await api.closeShift(id, counts: counts, reason: reason));
  }

  @override
  Future<List<Shift>> shiftHistory() async =>
      (await api.shiftHistory()).map(Api.shift).toList();

  @override
  Future<ShiftDetail> shiftDetail(int id) async =>
      Api.shiftDetail(await api.shift(id));
  @override
  Future<List<Expense>> cancelExpense(int id, String reason) async {
    await api.cancelExpense(id, reason);

    // Re-read rather than patching the one row: the cancellation put money
    // back into an account, and the list the caller gets should agree with
    // what the server now believes.
    return expenses();
  }

  // ------------------------------------------------------------- accounts

  @override
  Future<List<Account>> accounts() async =>
      Api.list(await api.accounts()).map(Api.account).toList();

  @override
  Future<List<AccountTransaction>> accountTransactions({
    AccountFilters filters = const AccountFilters(),
  }) async => Api.list(
    await api.accountTransactions(
      accountId: filters.accountId,
      kind: filters.kind?.api,
      range: filters.range == null ? null : _rangeKey(filters.range!),
      search: filters.search.isEmpty ? null : filters.search,
    ),
  ).map(Api.accountTransaction).toList();

  @override
  Future<List<PaymentMethodRecord>> paymentMethods() async =>
      Api.list(await api.paymentMethods()).map(Api.paymentMethod).toList();

  @override
  Future<List<PaymentMethodRecord>> savePaymentMethod({
    int? id,
    String? name,
    bool? isActive,
  }) async {
    if (id == null) {
      await api.createPaymentMethod(name ?? '');
    } else {
      await api.updatePaymentMethod(id, name: name, isActive: isActive);
    }

    return paymentMethods();
  }

  @override
  Future<List<PaymentMethodRecord>> removePaymentMethod(int id) async {
    await api.deletePaymentMethod(id);

    return paymentMethods();
  }

  @override
  Future<List<Account>> saveAccount({
    int? id,
    String? name,
    String? method,
    double balance = 0,
    bool? isActive,
  }) async {
    if (id == null) {
      await api.createAccount(
        name: name ?? '',
        method: method ?? 'cash',
        balance: balance,
      );
    } else {
      await api.updateAccount(id, name: name, isActive: isActive);
    }

    return accounts();
  }

  @override
  Future<List<Account>> removeAccount(int id) async {
    await api.deleteAccount(id);

    return accounts();
  }

  @override
  Future<List<Account>> transfer({
    required int fromAccountId,
    required int toAccountId,
    required double amount,
    String description = '',
  }) async {
    await api.transfer(
      fromAccountId: fromAccountId,
      toAccountId: toAccountId,
      amount: amount,
      description: description,
    );

    return accounts();
  }

  // ------------------------------------------------------ notifications

  @override
  Future<List<AppNotification>> notifications() async =>
      Api.list(await api.notifications()).map(Api.notification).toList();

  @override
  Future<void> markNotificationRead(int id) => api.markNotificationRead(id);

  @override
  Future<void> markAllNotificationsRead() => api.markAllNotificationsRead();

  @override
  Future<void> registerDevice(String token) => api.registerDevice(token);

  // ---------------------------------------------------------- customers

  @override
  Future<List<Customer>> customers({
    String search = '',
    CustomerFilter filter = CustomerFilter.all,
  }) async => Api.list(
    await api.customers(
      search: search.isEmpty ? null : search,
      filter: filter.api,
    ),
  ).map(Api.customer).toList();

  @override
  Future<Customer> customer(int id) async => Api.customer(await api.customer(id));

  @override
  Future<Customer> saveCustomer(CustomerRequest request) async =>
      Api.customer(await api.saveCustomer(request.toJson(), id: request.id));

  @override
  Future<Customer> deactivateCustomer(int id) async {
    await api.deleteCustomer(id);

    // The delete returns the deactivated row, but the profile wants the ledger
    // with it — closing an account is exactly when somebody reads the history.
    return customer(id);
  }

  @override
  Future<RestaurantOrder> attachOrderCustomer(
    int orderId, {
    required int customerId,
    required String reason,
  }) async => Api.order(
    await api.attachOrderCustomer(orderId, customerId, reason),
  );

  @override
  Future<Customer> payCustomer(
    int id, {
    required double amount,
    required PaymentMethod method,
    String description = '',
  }) => _post(id, 'payment', amount, method, description);

  @override
  Future<Customer> depositForCustomer(
    int id, {
    required double amount,
    required PaymentMethod method,
    String description = '',
  }) => _post(id, 'deposit', amount, method, description);

  @override
  Future<Customer> adjustCustomer(
    int id, {
    required double amount,
    required String reason,
  }) async {
    await api.customerLedgerPost(id, 'adjust', <String, dynamic>{
      'amount': amount,
      'reason': reason,
    });

    return customer(id);
  }

  /// Posts money and returns the customer *with* their ledger.
  ///
  /// The endpoints answer with the customer alone; re-reading the profile is
  /// what puts the new entry in front of whoever just took the money, which is
  /// the only proof they have that it landed.
  Future<Customer> _post(
    int id,
    String kind,
    double amount,
    PaymentMethod method,
    String description,
  ) async {
    await api.customerLedgerPost(id, kind, <String, dynamic>{
      'amount': amount,
      'method': method.api,
      if (description.isNotEmpty) 'description': description,
    });

    return customer(id);
  }

  // ----------------------------------------------------------- settings

  @override
  Future<SettingsState> saveSettings(SettingsState settings) async {
    // theme_mode is deliberately absent: the same account runs on a bright
    // counter tablet and a dim phone, so the theme belongs to the device and
    // _settingsFrom never reads it back.
    final Map<String, dynamic> saved = await api
        .updateSettings(<String, dynamic>{
          'language': settings.language == AppLanguage.english ? 'en' : 'so',
          'currency_prefix': settings.currencyPrefix,
          'tax_rate': settings.taxRate,
          'tax_enabled': settings.taxEnabled,
          'packaging_fee_enabled': settings.packagingFeeEnabled,
          'packaging_fee': settings.packagingFee,
          'require_table_for_dine_in': settings.requireTableForDineIn,
          'guest_count_enabled': settings.guestCountEnabled,
        });

    // The endpoint answers with `{restaurant: {...}, settings: {...}}`, so the
    // settings row has to be reached into. Reading the envelope itself finds
    // no tax_rate, no language, nothing — and _settingsFrom quietly falls back
    // to its defaults, which then overwrite the change the user just made.
    return _settingsFrom(
      Api.map(saved['settings'] ?? saved),
    ).copyWith(themeMode: settings.themeMode);
  }

  static String _hex(Color color) =>
      '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  // ----------------------------------------------------------- helpers

  DashboardLoaded _dashboardFrom(Map<String, dynamic> json) {
    final List<SeriesPoint> weekly = Api.list(
      json['weekly'],
    ).map(Api.seriesPoint).toList();

    return DashboardLoaded(
      date: DateTime.tryParse('${json['date']}') ?? DateTime.now(),
      sales: Api.kpi(json['sales']),
      orders: Api.kpi(json['orders']),
      expenses: Api.kpi(json['expenses']),
      profit: Api.kpi(json['profit']),
      weekly: weekly,
      previousWeekly: Api.list(
        json['previous_weekly'],
      ).map((Map<String, dynamic> p) => Api.double_(p['value'])).toList(),
      topItems: Api.list(json['top_items']).map(Api.rankedItem).toList(),
    );
  }

  SettingsState _settingsFrom(Map<String, dynamic> json) {
    if (json.isEmpty) return const SettingsState();

    return SettingsState(
      language: Api.string(json['language']) == 'en'
          ? AppLanguage.english
          : AppLanguage.somali,
      currencyPrefix: Api.string(json['currency_prefix'], 'SLSH'),
      taxRate: Api.double_(json['tax_rate'], 5),
      taxEnabled: Api.bool_(json['tax_enabled']),
      packagingFeeEnabled: Api.bool_(json['packaging_fee_enabled'], true),
      packagingFee: Api.double_(json['packaging_fee'], 5000),
      requireTableForDineIn: Api.bool_(json['require_table_for_dine_in'], true),
      guestCountEnabled: Api.bool_(json['guest_count_enabled'], true),
    );
    // Theme mode stays a device preference rather than a server setting: the
    // same account may be on a bright counter tablet and a dim phone.
  }

  static String _rangeKey(ReportRange range) => switch (range) {
    ReportRange.today => 'today',
    ReportRange.sevenDays => '7_days',
    ReportRange.thirtyDays => '30_days',
    ReportRange.thisMonth => 'this_month',
    ReportRange.lastMonth => 'last_month',
    ReportRange.custom => 'custom',
  };
}
