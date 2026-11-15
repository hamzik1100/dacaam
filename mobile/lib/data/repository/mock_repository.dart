import 'dart:math' as math;

import '../../core/config/app_config.dart';
import '../../core/utils/enums.dart';
import '../../redux/actions.dart';
import '../api/api_client.dart';
import '../api/token_store.dart';
import '../mock/mock_data.dart';
import '../models/analytics.dart';
import '../../redux/states/customer_state.dart';
import '../models/app_notification.dart';
import '../models/customer.dart';
import '../models/dining_table.dart';
import '../models/finance.dart';
import '../models/menu.dart';
import '../models/order.dart';
import '../models/shift.dart';
import '../../redux/states/report_state.dart';
import 'dacaam_repository.dart';
import '../../redux/states/settings_state.dart';
import '../../redux/states/finance_state.dart';

/// Offline data source backed by [MockData].
///
/// Keeps the app fully usable with no backend — useful for design work, for
/// demos, and as the fallback when the API cannot be reached at launch.
class MockRepository implements DacaamRepository {
  MockRepository({
    this.latency = const Duration(milliseconds: 700),
    TokenStore? tokens,
  }) : tokens = tokens ?? MemoryTokenStore();

  /// Simulated round-trip. Real enough that skeleton states get exercised
  /// during development instead of flashing past.
  final Duration latency;

  final TokenStore tokens;

  final List<RestaurantOrder> _orders = List<RestaurantOrder>.of(
    MockData.orders,
  );
  final List<DraftOrder> _drafts = List<DraftOrder>.of(MockData.drafts);
  final List<MenuItem> _menu = List<MenuItem>.of(MockData.menuItems);
  final List<MenuCategory> _categories = List<MenuCategory>.of(
    MockData.categories,
  );
  final List<DiningTable> _tables = List<DiningTable>.of(MockData.tables);
  final List<Expense> _expenses = List<Expense>.of(MockData.expenses);
  final List<Account> _accounts = List<Account>.of(MockData.accounts);

  /// Three seeded accounts: one owing, one in credit, one square. Enough to
  /// exercise every branch the customer screens have — a debtor list, a wallet
  /// list, and a profile whose balance is zero.
  final List<Customer> _customers = <Customer>[
    Customer(
      id: 1,
      name: 'Cabdi Xasan',
      phone: '063 4567 001',
      creditLimit: 500000,
      balanceOwed: 185000,
      createdAt: DateTime.now().subtract(const Duration(days: 64)),
    ),
    Customer(
      id: 2,
      name: 'Sahra Maxamed',
      phone: '063 4567 002',
      creditLimit: 200000,
      balanceOwed: -75000,
      createdAt: DateTime.now().subtract(const Duration(days: 31)),
    ),
    Customer(
      id: 3,
      name: 'Maktabadda Nuur',
      phone: '063 4567 003',
      address: 'Suuqa Weyn',
      creditLimit: 1000000,
      createdAt: DateTime.now().subtract(const Duration(days: 12)),
    ),
  ];

  int _nextCustomerId = 4;
  int _nextLedgerId = 1;

  Future<void> _wait() => Future<void>.delayed(latency);

  @override
  Future<bool> restoreSession() async => (await tokens.read()) != null;

  /// Offline sign-in accepts any non-empty credentials and always returns the
  /// seeded admin.
  ///
  /// The screen is still shown rather than skipped: sign-in is part of the
  /// product, and designing or demoing it should not require a running
  /// backend. It never asks for a second factor — there is no server to
  /// verify one against, and a fake OTP prompt would teach the wrong thing.
  @override
  Future<SignInResult> signIn({
    required String restaurantCode,
    required String phone,
    required String password,
  }) async {
    await Future<void>.delayed(latency);

    // This class accepts any credentials by design — there is no server to
    // check them against, and a fake password prompt would teach the wrong
    // thing. That design is only safe while it cannot reach a shipped build,
    // so it refuses outright there rather than trusting every caller above to
    // have chosen the right repository.
    if (!AppConfig.allowOfflineData) {
      throw const ApiException(
        'This build has no server configured',
        statusCode: 401,
        code: 'unauthorized',
      );
    }

    if (restaurantCode.trim().isEmpty ||
        phone.trim().isEmpty ||
        password.isEmpty) {
      throw const ApiException(
        'Restaurant code, phone or password is incorrect',
        statusCode: 401,
        code: 'unauthorized',
      );
    }

    await tokens.write(
      StoredSession(
        token: 'offline-session',
        restaurantCode: restaurantCode.toUpperCase(),
        phone: phone,
      ),
    );

    return const SignInResult.session();
  }

  @override
  Future<SignInResult> verifyTwoFactor({
    required String challenge,
    required String code,
  }) async => const SignInResult.session();

  @override
  Future<void> signOut() => tokens.clear();

  /// Held in memory so the offline build behaves like the real one within a
  /// session: change a setting, navigate away, come back, it is still there.
  SettingsState _settings = const SettingsState();

  @override
  Future<SettingsState> saveSettings(SettingsState settings) async {
    await Future<void>.delayed(latency);
    _settings = settings;

    return _settings;
  }

  @override
  Future<BootstrapPayload> bootstrap() async {
    await Future<void>.delayed(latency);

    return BootstrapPayload(
      bootstrap: BootstrapSucceeded(
        restaurant: MockData.restaurant,
        user: MockData.currentUser,
        staff: MockData.users,
        categories: _categories,
        items: _menu,
        tables: _tables,
        orders: _orders,
        drafts: _drafts,
        expenses: _expenses,
        expenseCategories: MockData.expenseCategories,
        accounts: _accounts,
      ),
      dashboard: _dashboard(),
    );
  }

  @override
  Future<DashboardLoaded> dashboard() async {
    await Future<void>.delayed(const Duration(milliseconds: 420));

    return _dashboard();
  }

  DashboardLoaded _dashboard() => DashboardLoaded(
    date: DateTime.now(),
    sales: MockData.kpiSales,
    orders: MockData.kpiOrders,
    expenses: MockData.kpiExpenses,
    profit: MockData.kpiProfit,
    weekly: MockData.weeklySales(),
    previousWeekly: MockData.lastWeekSales,
    topItems: MockData.topItemsToday,
  );

  @override
  Future<ReportLoaded> reports(
    ReportRange range, {
    ReportFilters filters = const ReportFilters(),
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 420));

    // A single 7-day baseline scaled per range keeps every figure on the
    // screen internally consistent (profit == sales - expenses, and so on).
    final double f = _rangeFactor(range);
    final KpiValue sales = _scale(MockData.periodSales, f);
    final KpiValue expenses = _scale(MockData.periodExpenses, f);

    return ReportLoaded(
      sales: sales,
      orders: _scale(MockData.periodOrders, f, round: true),
      expenses: expenses,
      profit: KpiValue(
        value: sales.value - expenses.value,
        deltaPercent: MockData.periodProfit.deltaPercent,
      ),
      daily: _dailySeries(range, sales.value),
      hourly: MockData.salesByHour(),
      byCategory: MockData.categoryBreakdown,
      byPayment: _scaleSlices(MockData.paymentBreakdown, f),
      byWaiter: _scaleSlices(MockData.waiterBreakdown, f),
      byTable: _scaleSlices(MockData.waiterBreakdown, f),
      topItems: MockData.topItemsPeriod,
      lowItems: MockData.lowSellingPeriod,
      discounts: MockData.periodDiscounts * f,
      tax: MockData.periodTax * f,
      packaging: MockData.periodPackaging * f,
      completedOrders: (MockData.periodCompleted * f).round(),
      cancelledOrders: (MockData.periodCancelled * f).round(),
      draftOrders: (MockData.periodDrafts * f).round(),
      dineInOrders: (MockData.periodDineIn * f).round(),
      takeawayOrders: (MockData.periodTakeaway * f).round(),
      // No order in the offline dataset was put on a tab, so everything sold
      // was collected and cash equals sales. Left equal rather than given an
      // invented gap: a demo that shows uncollected money nobody can point at
      // teaches the figure wrong.
      cash: CashSummary(
        moneyIn: sales.value,
        moneyOut: expenses.value,
        net: sales.value - expenses.value,
      ),
      // These two are real, though — they come from the seeded customers.
      receivables: _customers
          .where((Customer c) => c.isDebtor)
          .fold<double>(0, (double s, Customer c) => s + c.balanceOwed),
      depositsHeld: _customers.fold<double>(
        0,
        (double s, Customer c) => s + c.wallet,
      ),
      // Real, like the two above it: what the seeded orders are still owed,
      // less anything a customer ledger is already carrying.
      unpaidOrders: _orders
          .where((RestaurantOrder o) => o.status != OrderStatus.cancelled)
          .fold<double>(0, (double s, RestaurantOrder o) {
            final double paid = o.payments.fold<double>(
              0,
              (double p, OrderPaymentEntry e) => p + e.amount,
            );
            final double owing = o.total - paid;

            return s + (owing > 0 && o.customerId == null ? owing : 0);
          }),
      topDebtors:
          (_customers.where((Customer c) => c.isDebtor).toList()
                ..sort(
                  (Customer a, Customer b) =>
                      b.balanceOwed.compareTo(a.balanceOwed),
                ))
              .map(
                (Customer c) => CustomerRank(
                  customerId: c.id,
                  name: c.name,
                  phone: c.phone,
                  balanceOwed: c.balanceOwed,
                  creditLimit: c.creditLimit,
                ),
              )
              .toList(),
    );
  }

  @override
  Future<RestaurantOrder> placeOrder(OrderRequest request) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));

    final int nextNumber = _orders.isEmpty
        ? 1001
        : _orders.map((RestaurantOrder o) => o.number).reduce(math.max) + 1;

    final DateTime now = DateTime.now();
    final String actor = MockData.currentUser.name;

    // Offline pricing mirrors CartTotals; the API is authoritative when live.
    final double subtotal = request.lines.fold<double>(
      0,
      (double sum, OrderLine l) => sum + l.total,
    );
    final double discount = request.discount.clamp(0, subtotal).toDouble();
    final bool packagingApplies =
        request.type == OrderType.takeaway &&
        request.lines.any((OrderLine l) => l.applyPackagingFee);
    final double packagingFee = packagingApplies
        ? request.settingsPackagingFee
        : 0;
    final double total =
        (subtotal - discount) * (1 + request.settingsTaxFraction) +
        packagingFee;

    final RestaurantOrder order = RestaurantOrder(
      id: nextNumber,
      number: nextNumber,
      restaurantId: MockData.restaurantId,
      type: request.type,
      status: OrderStatus.preparing,
      lines: List<OrderLine>.of(request.lines),
      createdAt: now,
      tableId: request.tableId,
      tableLabel: request.tableId == null
          ? null
          : 'Table ${request.tableId.toString().padLeft(2, '0')}',
      waiterName: _waiterName(request.waiterId) ?? actor.split(' ').first,
      customerName: request.customerName,
      customerPhone: request.customerPhone,
      guests: request.guests,
      discount: discount,
      taxRate: request.settingsTaxFraction,
      packagingFee: packagingFee,
      notes: request.notes,
      payments: <OrderPaymentEntry>[
        if (request.paymentMethod != null)
          OrderPaymentEntry(
            method: request.paymentMethod!,
            amount: total,
            reference: request.paymentReference,
            at: now,
          ),
      ],
      events: <OrderEvent>[
        OrderEvent(labelKey: 'orderCreated', at: now, byUser: actor),
        if (request.paymentMethod != null)
          OrderEvent(
            labelKey: 'paymentAdded',
            at: now,
            byUser: actor,
            newValue: request.paymentMethod!.label,
          ),
      ],
    );

    _orders.insert(0, order);

    return order;
  }

  @override
  Future<RestaurantOrder> order(int id) async =>
      _orders.firstWhere((RestaurantOrder o) => o.id == id);

  @override
  Future<RestaurantOrder> setOrderStatus(
    int orderId,
    OrderStatus status, {
    String? reason,
  }) async {
    final int index = _orders.indexWhere(
      (RestaurantOrder o) => o.id == orderId,
    );
    if (index == -1) {
      throw StateError('Order $orderId not found');
    }

    final RestaurantOrder updated = _orders[index].copyWith(
      status: status,
      cancelReason: status == OrderStatus.cancelled ? reason : null,
      events: <OrderEvent>[
        ..._orders[index].events,
        OrderEvent(
          labelKey: 'orderStatusChanged',
          at: DateTime.now(),
          byUser: MockData.currentUser.name,
          oldValue: _orders[index].status.name,
          newValue: status.name,
          reason: reason,
        ),
      ],
    );

    _orders[index] = updated;

    return updated;
  }

  // =========================================== offline write-through
  //
  // Everything below mutates in-memory copies of the seeded dataset. Nothing
  // persists past app restart — the point is that the UI behaves identically
  // with or without a backend, not that the offline build is a second
  // database.

  @override
  Future<RestaurantOrder> updateOrderItems(
    int orderId,
    List<OrderLine> lines, {
    double? discount,
    String? reason,
  }) async {
    final int index = _orders.indexWhere(
      (RestaurantOrder o) => o.id == orderId,
    );
    if (index == -1) throw _missing('Order');

    final RestaurantOrder current = _orders[index];
    final RestaurantOrder updated = RestaurantOrder(
      id: current.id,
      number: current.number,
      restaurantId: current.restaurantId,
      type: current.type,
      status: current.status,
      lines: List<OrderLine>.of(lines),
      createdAt: current.createdAt,
      tableId: current.tableId,
      tableLabel: current.tableLabel,
      waiterName: current.waiterName,
      customerName: current.customerName,
      customerPhone: current.customerPhone,
      guests: current.guests,
      discount: discount ?? current.discount,
      taxRate: current.taxRate,
      packagingFee: current.packagingFee,
      payments: current.payments,
      // Carried, not dropped. The server keeps both across an edit, and losing
      // them here made an edited order look like an unattached, settled one —
      // which quietly hid every rule that keys off either.
      customerId: current.customerId,
      paymentStatus: current.paymentStatus,
      notes: current.notes,
      events: <OrderEvent>[
        ...current.events,
        OrderEvent(
          labelKey: 'quantityChanged',
          at: DateTime.now(),
          byUser: MockData.currentUser.name,
          reason: reason,
        ),
      ],
    );

    _orders[index] = updated;

    return updated;
  }

  @override
  Future<RestaurantOrder> addPayment(
    int orderId, {
    required PaymentMethod method,
    required double amount,
    String reference = '',
  }) async {
    final int index = _orders.indexWhere(
      (RestaurantOrder o) => o.id == orderId,
    );
    if (index == -1) throw _missing('Order');

    final RestaurantOrder current = _orders[index];
    final RestaurantOrder updated = current.copyWith(
      events: <OrderEvent>[
        ...current.events,
        OrderEvent(
          labelKey: 'paymentAdded',
          at: DateTime.now(),
          byUser: MockData.currentUser.name,
          newValue: method.label,
        ),
      ],
    );

    _orders[index] = updated;

    return updated;
  }

  // --------------------------------------------------------------- drafts

  @override
  Future<List<DraftOrder>> drafts() async => List<DraftOrder>.of(_drafts);

  @override
  Future<DraftOrder> saveDraft(DraftRequest request) async {
    final int nextId = _drafts.isEmpty
        ? 1
        : _drafts.map((DraftOrder d) => d.id).reduce(math.max) + 1;

    final DraftOrder draft = DraftOrder(
      id: request.id ?? nextId,
      code: request.id == null
          ? 'D-$nextId'
          : _drafts.firstWhere((DraftOrder d) => d.id == request.id).code,
      restaurantId: MockData.restaurantId,
      customerName: request.customerName,
      customerPhone: request.customerPhone,
      type: request.type,
      lines: List<OrderLine>.of(request.lines),
      createdAt: DateTime.now(),
      notes: request.notes,
      waiterName: MockData.currentUser.name.split(' ').first,
      packagingApplied:
          request.type == OrderType.takeaway &&
          request.lines.any((OrderLine l) => l.applyPackagingFee),
    );

    final int index = _drafts.indexWhere((DraftOrder d) => d.id == draft.id);
    if (index == -1) {
      _drafts.insert(0, draft);
    } else {
      _drafts[index] = draft;
    }

    return draft;
  }

  @override
  Future<DraftOrder> cancelDraft(int id, String reason) async {
    final int i = _drafts.indexWhere((DraftOrder d) => d.id == id);
    if (i < 0) {
      throw const ApiException(
        'Draft not found',
        statusCode: 404,
        code: 'not_found',
      );
    }

    final DraftOrder was = _drafts[i];
    final DraftOrder cancelled = DraftOrder(
      id: was.id,
      code: was.code,
      restaurantId: was.restaurantId,
      customerName: was.customerName,
      customerPhone: was.customerPhone,
      type: was.type,
      lines: was.lines,
      createdAt: was.createdAt,
      notes: was.notes,
      tableLabel: was.tableLabel,
      waiterName: was.waiterName,
      packagingApplied: was.packagingApplied,
      status: DraftStatus.cancelled,
      cancelReason: reason,
    );

    // Replaced, not removed: the offline build has to behave like the real one
    // or it teaches the wrong thing about what cancelling does.
    _drafts[i] = cancelled;

    return cancelled;
  }

  @override
  Future<RestaurantOrder> convertDraft(
    int id, {
    PaymentMethod? method,
    OrderType? orderType,
    int? tableId,
    int? waiterId,
  }) async {
    final DraftOrder draft = _drafts.firstWhere(
      (DraftOrder d) => d.id == id,
      orElse: () => throw _missing('Draft'),
    );

    final RestaurantOrder order = await placeOrder(
      OrderRequest(
        type: draft.type,
        lines: draft.lines,
        customerName: draft.customerName,
        customerPhone: draft.customerPhone,
        notes: draft.notes,
        paymentMethod: method,
        settingsPackagingFee: 5000,
      ),
    );

    _drafts.removeWhere((DraftOrder d) => d.id == id);

    return order;
  }

  // ----------------------------------------------------------------- menu

  @override
  Future<MenuItem> saveMenuItem(MenuItem item, {String? reason}) async {
    final MenuItem saved = item.id <= 0
        ? MenuItem(
            id: _menu.isEmpty
                ? 1
                : _menu.map((MenuItem i) => i.id).reduce(math.max) + 1,
            restaurantId: MockData.restaurantId,
            categoryId: item.categoryId,
            name: item.name,
            price: item.price,
            description: item.description,
            emoji: item.emoji,
            available: item.available,
            applyPackagingFee: item.applyPackagingFee,
          )
        : item;

    final int index = _menu.indexWhere((MenuItem i) => i.id == saved.id);
    if (index == -1) {
      _menu.insert(0, saved);
    } else {
      _menu[index] = saved;
    }

    return saved;
  }

  @override
  Future<MenuItem> toggleMenuItem(int id) async {
    final int index = _menu.indexWhere((MenuItem i) => i.id == id);
    if (index == -1) throw _missing('Item');

    _menu[index] = _menu[index].copyWith(available: !_menu[index].available);

    return _menu[index];
  }

  @override
  Future<MenuItem> setMenuItemImage(int id, String? base64) async {
    await _wait();

    // No server to upload to, so the offline dataset says so rather than
    // pretending: a picture that appeared to save and then vanished on the
    // next launch would be worse than a refusal.
    throw const ApiException(
      'Photographs need the DACAAM server',
      statusCode: 0,
      code: 'offline',
    );
  }

  @override
  Future<void> deleteMenuItem(int id) async =>
      _menu.removeWhere((MenuItem i) => i.id == id);

  @override
  Future<List<MenuCategory>> saveCategory(MenuCategory category) async {
    final MenuCategory saved = category.id <= 0
        ? MenuCategory(
            id: _categories.isEmpty
                ? 1
                : _categories.map((MenuCategory c) => c.id).reduce(math.max) +
                      1,
            restaurantId: MockData.restaurantId,
            name: category.name,
            emoji: category.emoji,
            color: category.color,
            description: category.description,
            active: category.active,
            sortOrder: category.sortOrder,
          )
        : category;

    final int index = _categories.indexWhere(
      (MenuCategory c) => c.id == saved.id,
    );
    if (index == -1) {
      _categories.add(saved);
    } else {
      _categories[index] = saved;
    }

    return List<MenuCategory>.of(_categories);
  }

  @override
  Future<List<MenuCategory>> deleteCategory(int id) async {
    if (_menu.any((MenuItem i) => i.categoryId == id)) {
      throw const ApiException(
        'Move or delete the items in this category first',
        statusCode: 409,
        code: 'conflict',
      );
    }
    _categories.removeWhere((MenuCategory c) => c.id == id);

    return List<MenuCategory>.of(_categories);
  }

  // --------------------------------------------------------------- tables

  @override
  Future<List<DiningTable>> tables() async => List<DiningTable>.of(_tables);

  @override
  Future<List<DiningTable>> saveTable(DiningTable table) async {
    final DiningTable saved = table.id <= 0
        ? DiningTable(
            id: _tables.isEmpty
                ? 1
                : _tables.map((DiningTable t) => t.id).reduce(math.max) + 1,
            restaurantId: MockData.restaurantId,
            number: table.number,
            capacity: table.capacity,
            name: table.name,
          )
        : table;

    final int index = _tables.indexWhere((DiningTable t) => t.id == saved.id);
    if (index == -1) {
      _tables.add(saved);
    } else {
      _tables[index] = saved;
    }
    _tables.sort(
      (DiningTable a, DiningTable b) => a.number.compareTo(b.number),
    );

    return List<DiningTable>.of(_tables);
  }

  @override
  Future<List<DiningTable>> deleteTable(int id) async {
    _tables.removeWhere((DiningTable t) => t.id == id);

    return List<DiningTable>.of(_tables);
  }

  // ------------------------------------------------------------- expenses

  @override
  Future<List<Expense>> expenses() async => List<Expense>.of(_expenses);

  @override
  Future<List<Expense>> saveExpense(ExpenseRequest request) async {
    final int id =
        request.id ??
        (_expenses.isEmpty
            ? 1
            : _expenses.map((Expense e) => e.id).reduce(math.max) + 1);

    final Expense expense = Expense(
      id: id,
      restaurantId: MockData.restaurantId,
      name: request.name,
      amount: request.amount,
      categoryId: request.categoryId ?? 0,
      categoryName: _expenseCategoryName(request.categoryId),
      method: request.method,
      date: request.date ?? DateTime.now(),
      kind: request.kind,
      notes: request.notes,
      createdBy: MockData.currentUser.name,
      recurring: request.recurring,
    );

    final int index = _expenses.indexWhere((Expense e) => e.id == id);
    if (index == -1) {
      _expenses.insert(0, expense);
    } else {
      _expenses[index] = expense;
    }

    return List<Expense>.of(_expenses);
  }

  // ------------------------------------------------------------- shifts

  Shift? _openShift;
  final List<Shift> _shifts = <Shift>[];
  double? _lastClose;

  @override
  Future<ShiftStatus> currentShift() async => ShiftStatus(
    shift: _openShift,
    lastClose: _lastClose,
    accountId: 1,
    // The same shape the server sends: names, no balances. A demo that
    // handed over the figures would let the screen be built the wrong way
    // round, and blindness is the one property this cannot lose.
    accounts: const <CountableAccount>[
      // Both sides on both accounts, exactly as the server sends them.
      CountableAccount(
        id: 1,
        name: 'Sanduuqa',
        method: 'cash',
        received: 640000,
        paidOut: 15000,
      ),
      CountableAccount(id: 2, name: 'Zaad', method: 'zaad', received: 340000),
    ],
    expenses: const ShiftExpenses(
      total: 15000,
      items: <ShiftExpenseLine>[
        ShiftExpenseLine(name: 'Biyo', amount: 15000, method: 'cash'),
      ],
    ),
  );

  @override
  Future<ShiftStatus> openShift({
    required double openingFloat,
    String notes = '',
  }) async {
    _openShift = Shift(
      id: _shifts.length + 1,
      accountId: 1,
      accountName: 'Sanduuqa',
      openedBy: 'Demo',
      openedAt: DateTime.now(),
      openingFloat: openingFloat,
      previousClose: _lastClose,
      overnightDiff: _lastClose == null ? null : openingFloat - _lastClose!,
      notes: notes,
    );

    return currentShift();
  }

  @override
  Future<Shift> closeShift(
    int id, {
    required Map<int, double> counts,
    String reason = '',
  }) async {
    final Shift open = _openShift!;
    final double counted = counts.values.fold<double>(0, (double s, double v) => s + v);

    // The demo has no ledger, so "expected" is simply the float. What matters
    // is that the shape matches the real thing — a mock where the figures
    // appear before the count would let the screen be built the wrong way
    // round, and that is the one mistake this feature cannot survive.
    final double expected = open.openingFloat;

    final Shift closed = Shift(
      id: open.id,
      accountId: open.accountId,
      accountName: open.accountName,
      openedBy: open.openedBy,
      openedAt: open.openedAt,
      openingFloat: open.openingFloat,
      previousClose: open.previousClose,
      overnightDiff: open.overnightDiff,
      closedBy: 'Demo',
      closedAt: DateTime.now(),
      expectedClose: expected,
      countedClose: counted,
      variance: counted - expected,
      closeReason: reason.isEmpty ? null : reason,
      notes: open.notes,
      isOpen: false,
      accounts: counts.entries
          .map(
            (MapEntry<int, double> e) => ShiftCount(
              accountId: e.key,
              name: e.key == 1 ? 'Sanduuqa' : 'Zaad',
              method: e.key == 1 ? 'cash' : 'zaad',
              expected: e.key == 1 ? expected : 0,
              counted: e.value,
              variance: e.value - (e.key == 1 ? expected : 0),
            ),
          )
          .toList(),
    );

    _shifts.insert(0, closed);
    _openShift = null;
    _lastClose = counted;

    return closed;
  }

  @override
  Future<List<Shift>> shiftHistory() async => List<Shift>.of(_shifts);

  @override
  Future<ShiftDetail> shiftDetail(int id) async {
    final Shift found = _shifts.firstWhere(
      (Shift s) => s.id == id,
      orElse: () => _openShift!,
    );

    return ShiftDetail(
      shift: found,
      expected: found.expectedClose ?? found.openingFloat,
      accounts: found.accounts,
      expenses: const ShiftExpenses(
        total: 15000,
        items: <ShiftExpenseLine>[
          ShiftExpenseLine(name: 'Biyo', amount: 15000, method: 'cash'),
        ],
      ),
    );
  }
  @override
  Future<List<Expense>> cancelExpense(int id, String reason) async {
    // Marked, not removed — the demo has to behave like the real thing, or the
    // screen gets built against a list where cancelling makes rows disappear.
    for (int i = 0; i < _expenses.length; i++) {
      if (_expenses[i].id != id) continue;

      final Expense e = _expenses[i];
      _expenses[i] = Expense(
        id: e.id,
        restaurantId: e.restaurantId,
        name: e.name,
        amount: e.amount,
        categoryId: e.categoryId,
        categoryName: e.categoryName,
        method: e.method,
        date: e.date,
        kind: e.kind,
        notes: e.notes,
        createdBy: e.createdBy,
        recurring: e.recurring,
        cancelledAt: DateTime.now(),
        cancelReason: reason,
      );
    }

    return List<Expense>.of(_expenses);
  }

  String _expenseCategoryName(int? id) {
    for (final ExpenseCategory c in MockData.expenseCategories) {
      if (c.id == id) return c.name;
    }

    return '';
  }

  // ------------------------------------------------------------- accounts

  @override
  Future<List<Account>> accounts() async => List<Account>.of(_accounts);

  @override
  Future<List<AccountTransaction>> accountTransactions({
    AccountFilters filters = const AccountFilters(),
  }) async => const <AccountTransaction>[];

  @override
  Future<List<PaymentMethodRecord>> paymentMethods() async => _methods;

  List<PaymentMethodRecord> _methods = const <PaymentMethodRecord>[
    PaymentMethodRecord(id: 1, code: 'cash', name: 'Cash', isSystem: true),
    PaymentMethodRecord(id: 2, code: 'zaad', name: 'Zaad', isSystem: true),
    PaymentMethodRecord(id: 3, code: 'edahab', name: 'eDahab', isSystem: true),
    PaymentMethodRecord(id: 4, code: 'bank', name: 'Bank', isSystem: true),
  ];

  @override
  Future<List<PaymentMethodRecord>> savePaymentMethod({
    int? id,
    String? name,
    bool? isActive,
  }) async {
    await Future<void>.delayed(latency);

    if (id == null) {
      final int next =
          _methods.map((PaymentMethodRecord m) => m.id).reduce(math.max) + 1;
      _methods = <PaymentMethodRecord>[
        ..._methods,
        PaymentMethodRecord(
          id: next,
          code: (name ?? '').toLowerCase().replaceAll(
            RegExp(r'[^a-z0-9]+'),
            '_',
          ),
          name: name ?? '',
          sortOrder: 50,
        ),
      ];
    } else {
      _methods = _methods.map((PaymentMethodRecord m) {
        if (m.id != id) return m;

        return PaymentMethodRecord(
          id: m.id,
          code: m.code,
          name: name ?? m.name,
          isActive: isActive ?? m.isActive,
          isSystem: m.isSystem,
          sortOrder: m.sortOrder,
          accountCount: m.accountCount,
        );
      }).toList();
    }

    return _methods;
  }

  @override
  Future<List<PaymentMethodRecord>> removePaymentMethod(int id) =>
      savePaymentMethod(id: id, isActive: false);

  @override
  Future<List<Account>> saveAccount({
    int? id,
    String? name,
    String? method,
    double balance = 0,
    bool? isActive,
  }) async => _accounts;

  @override
  Future<List<Account>> removeAccount(int id) async => _accounts;

  @override
  Future<List<Account>> transfer({
    required int fromAccountId,
    required int toAccountId,
    required double amount,
    String description = '',
  }) async {
    final int from = _accounts.indexWhere((Account a) => a.id == fromAccountId);
    final int to = _accounts.indexWhere((Account a) => a.id == toAccountId);
    if (from == -1 || to == -1) throw _missing('Account');

    if (_accounts[from].balance < amount) {
      throw const ApiException(
        'Insufficient balance in the source account',
        statusCode: 422,
        code: 'unprocessable',
      );
    }

    _accounts[from] = _copyAccount(
      _accounts[from],
      _accounts[from].balance - amount,
    );
    _accounts[to] = _copyAccount(_accounts[to], _accounts[to].balance + amount);

    return List<Account>.of(_accounts);
  }

  // ------------------------------------------------------ notifications

  /// Two seeded messages, one unread, so the bell and the list have something
  /// to show while designing without a server.
  final List<AppNotification> _notifications = <AppNotification>[
    AppNotification(
      id: 1,
      title: 'Ku soo dhawoow DACAAM',
      body: 'Haddii su\'aal kaa jirto, Caawimaadda ka fiiri qaybta Kale.',
      sentAt: DateTime.now().subtract(const Duration(hours: 5)),
    ),
    AppNotification(
      id: 2,
      title: 'Lacag bixinta bisha',
      body: 'Fadlan lacagta bisha bixi ka hor 25-ka.',
      sentAt: DateTime.now().subtract(const Duration(days: 2)),
      kind: NotificationKind.warning,
      isRead: true,
    ),
  ];

  @override
  Future<List<AppNotification>> notifications() async {
    await _wait();

    return List<AppNotification>.of(_notifications);
  }

  @override
  Future<void> markNotificationRead(int id) async {
    final int i = _notifications.indexWhere((AppNotification n) => n.id == id);
    if (i != -1) _notifications[i] = _notifications[i].copyWith(isRead: true);
  }

  @override
  Future<void> markAllNotificationsRead() async {
    for (int i = 0; i < _notifications.length; i++) {
      _notifications[i] = _notifications[i].copyWith(isRead: true);
    }
  }

  @override
  Future<void> registerDevice(String token) async {
    // Nothing to register with. Silent rather than throwing: push is optional,
    // and a design session must not fail because there is no server.
  }
  // ---------------------------------------------------------- customers

  @override
  Future<List<Customer>> customers({
    String search = '',
    CustomerFilter filter = CustomerFilter.all,
  }) async {
    await _wait();

    final String q = search.trim().toLowerCase();

    return _customers.where((Customer c) {
      if (!c.isActive) return false;
      if (filter == CustomerFilter.debtors && c.balanceOwed <= 0) return false;
      if (filter == CustomerFilter.wallet && c.balanceOwed >= 0) return false;
      if (q.isEmpty) return true;

      return c.name.toLowerCase().contains(q) || c.phone.contains(q);
    }).toList()..sort((Customer a, Customer b) {
      final int byBalance = b.balanceOwed.compareTo(a.balanceOwed);

      return byBalance != 0 ? byBalance : a.name.compareTo(b.name);
    });
  }

  @override
  Future<Customer> customer(int id) async {
    await _wait();

    return _requireCustomer(id);
  }

  @override
  Future<Customer> saveCustomer(CustomerRequest request) async {
    await _wait();

    if (request.id == null) {
      final Customer created = Customer(
        id: _nextCustomerId++,
        name: request.name,
        phone: request.phone,
        address: request.address,
        notes: request.notes,
        creditLimit: request.creditLimit,
        createdAt: DateTime.now(),
      );
      _customers.add(created);

      return created;
    }

    final Customer before = _requireCustomer(request.id!);
    final Customer updated = Customer(
      id: before.id,
      name: request.name,
      phone: request.phone,
      address: request.address,
      notes: request.notes,
      creditLimit: request.creditLimit,
      // Not from the request: a balance is the sum of the ledger, never
      // something a form gets to state.
      balanceOwed: before.balanceOwed,
      isActive: request.isActive ?? before.isActive,
      createdAt: before.createdAt,
      ledger: before.ledger,
    );
    _replaceCustomer(updated);

    return updated;
  }

  @override
  Future<Customer> deactivateCustomer(int id) async {
    await _wait();

    final Customer c = _requireCustomer(id);
    if (c.balanceOwed != 0) {
      throw const ApiException(
        'Settle this customer\'s balance before closing the account',
        statusCode: 422,
        code: 'unprocessable',
      );
    }

    final Customer closed = Customer(
      id: c.id,
      name: c.name,
      phone: c.phone,
      address: c.address,
      notes: c.notes,
      creditLimit: c.creditLimit,
      balanceOwed: c.balanceOwed,
      isActive: false,
      createdAt: c.createdAt,
      ledger: c.ledger,
    );
    _replaceCustomer(closed);

    return closed;
  }

  @override
  Future<RestaurantOrder> attachOrderCustomer(
    int orderId, {
    required int customerId,
    required String reason,
  }) async {
    await _wait();

    final int i = _orders.indexWhere((RestaurantOrder o) => o.id == orderId);
    if (i == -1) throw _missing('Order');

    final RestaurantOrder o = _orders[i];
    final double paid = o.payments.fold<double>(
      0,
      (double s, OrderPaymentEntry p) => s + p.amount,
    );
    final double owing = o.total - paid;

    if (owing <= 0.001) {
      throw const ApiException(
        'This order is fully paid — there is nothing to put on an account',
        statusCode: 422,
        code: 'unprocessable',
      );
    }

    final Customer c = _requireCustomer(customerId);
    if (c.balanceOwed + owing > c.creditLimit + 0.001) {
      throw const ApiException(
        'This would go over their credit limit',
        statusCode: 422,
        code: 'unprocessable',
      );
    }

    _postLedger(
      customerId,
      LedgerKind.charge,
      owing,
      description: 'Dalab dayn loo rogay · Order #${o.number}',
      reason: reason,
    );

    _orders[i] = o.copyWith(
      customerId: customerId,
      customerName: c.name,
      paymentStatus: PaymentStatus.unpaid,
    );

    return _orders[i];
  }
  @override
  Future<Customer> payCustomer(
    int id, {
    required double amount,
    required PaymentMethod method,
    String description = '',
  }) async {
    await _wait();

    return _postLedger(
      id,
      LedgerKind.payment,
      -amount,
      method: method.api,
      description: description.isEmpty ? 'Dayn bixin' : description,
    );
  }

  @override
  Future<Customer> depositForCustomer(
    int id, {
    required double amount,
    required PaymentMethod method,
    String description = '',
  }) async {
    await _wait();

    return _postLedger(
      id,
      LedgerKind.deposit,
      -amount,
      method: method.api,
      description: description.isEmpty ? 'Lacag dhigasho' : description,
    );
  }

  @override
  Future<Customer> adjustCustomer(
    int id, {
    required double amount,
    required String reason,
  }) async {
    await _wait();

    return _postLedger(
      id,
      LedgerKind.adjustment,
      amount,
      description: 'Sixid gacan',
      reason: reason,
    );
  }

  /// Appends one entry and moves the balance with it.
  ///
  /// Mirrors the server's rule rather than approximating it: entries are only
  /// ever added, and the balance is whatever they sum to.
  Customer _postLedger(
    int id,
    LedgerKind kind,
    double amount, {
    String method = '',
    String description = '',
    String? reason,
  }) {
    final Customer c = _requireCustomer(id);
    final double after = c.balanceOwed + amount;

    final Customer moved = Customer(
      id: c.id,
      name: c.name,
      phone: c.phone,
      address: c.address,
      notes: c.notes,
      creditLimit: c.creditLimit,
      balanceOwed: after,
      isActive: c.isActive,
      createdAt: c.createdAt,
      ledger: <LedgerEntry>[
        LedgerEntry(
          id: _nextLedgerId++,
          kind: kind,
          amount: amount,
          balanceAfter: after,
          at: DateTime.now(),
          method: method,
          description: description,
          reason: reason,
        ),
        ...c.ledger,
      ],
    );
    _replaceCustomer(moved);

    return moved;
  }

  Customer _requireCustomer(int id) {
    for (final Customer c in _customers) {
      if (c.id == id) return c;
    }

    throw _missing('Customer');
  }

  void _replaceCustomer(Customer c) {
    final int i = _customers.indexWhere((Customer x) => x.id == c.id);
    if (i != -1) _customers[i] = c;
  }

  static Account _copyAccount(Account a, double balance) => Account(
    id: a.id,
    restaurantId: a.restaurantId,
    method: a.method,
    balance: balance,
    moneyIn: a.moneyIn,
    moneyOut: a.moneyOut,
  );

  static ApiException _missing(String what) =>
      ApiException('$what not found', statusCode: 404, code: 'not_found');

  // ----------------------------------------------------------- helpers

  String? _waiterName(int? waiterId) {
    if (waiterId == null) return null;
    for (final dynamic user in MockData.users) {
      if (user.id == waiterId) {
        return (user.name as String).split(' ').first;
      }
    }

    return null;
  }

  static double _rangeFactor(ReportRange range) => switch (range) {
    ReportRange.today => 0.143,
    ReportRange.sevenDays => 1,
    ReportRange.thirtyDays => 4.1,
    ReportRange.thisMonth => 3.4,
    ReportRange.lastMonth => 3.9,
    ReportRange.custom => 2.2,
  };

  static KpiValue _scale(KpiValue base, double f, {bool round = false}) {
    final double v = base.value * f;

    return KpiValue(
      value: round ? v.roundToDouble() : v,
      deltaPercent: base.deltaPercent,
    );
  }

  static List<BreakdownSlice> _scaleSlices(
    List<BreakdownSlice> base,
    double f,
  ) => base
      .map(
        (BreakdownSlice s) => BreakdownSlice(
          label: s.label,
          value: s.value * f,
          color: s.color,
          count: (s.count * f).round(),
        ),
      )
      .toList();

  /// Deterministic shape so the chart doesn't reshuffle on every rebuild.
  static List<SeriesPoint> _dailySeries(ReportRange range, double total) {
    if (range == ReportRange.today) return MockData.salesByHour();
    if (range == ReportRange.sevenDays) return MockData.weeklySales();

    final int days = switch (range) {
      ReportRange.thirtyDays => 30,
      ReportRange.thisMonth => DateTime.now().day,
      ReportRange.lastMonth => 30,
      _ => 14,
    };

    final DateTime end = DateTime.now();
    final List<double> weights = List<double>.generate(days, (int i) {
      // Weekend lift plus a gentle wave — reads like a real service pattern.
      final DateTime d = end.subtract(Duration(days: days - 1 - i));
      final double weekend = d.weekday >= 5 ? 1.35 : 1.0;

      return (0.85 + 0.3 * math.sin(i * 0.7)) * weekend;
    });
    final double sum = weights.fold<double>(0, (double s, double w) => s + w);

    return List<SeriesPoint>.generate(days, (int i) {
      final DateTime d = end.subtract(Duration(days: days - 1 - i));

      return SeriesPoint(
        label: '${d.day}',
        value: total * weights[i] / sum,
        date: d,
      );
    });
  }
}
