import '../core/utils/enums.dart';
import '../data/models/customer.dart';
import '../data/models/dining_table.dart';
import '../data/models/menu.dart';
import '../data/models/order.dart';
import '../data/models/shift.dart';
import 'actions.dart';
import 'app_state.dart';
import 'states/auth_state.dart';
import 'states/finance_state.dart';
import 'states/menu_state.dart';
import 'states/order_state.dart';
import 'states/pos_state.dart';
import 'states/status.dart';

/// Root reducer.
///
/// Written as one dispatch on the action type rather than
/// `combineReducers` per slice: a handful of actions (checkout, most notably)
/// legitimately have to move several slices at once, and doing that in one
/// place keeps those transitions atomic and readable.
AppState appReducer(AppState state, dynamic action) {
  return switch (action) {
    BootstrapStarted() => state.copyWith(
      auth: state.auth.copyWith(status: Status.loading),
      dashboard: state.dashboard.copyWith(status: Status.loading),
      menu: state.menu.copyWith(status: Status.loading),
      orders: state.orders.copyWith(status: Status.loading),
      booted: false,
    ),

    BootstrapSucceeded() => _bootstrapped(state, action),

    BootstrapFailed() => state.copyWith(
      booted: true,
      auth: state.auth.copyWith(status: Status.error),
      dashboard: state.dashboard.copyWith(
        status: Status.error,
        error: action.message,
      ),
      menu: state.menu.copyWith(status: Status.error),
      orders: state.orders.copyWith(status: Status.error),
    ),

    // Everything is dropped except what the login form should remember: the
    // restaurant code and phone are not secrets, and retyping a restaurant
    // code every shift is exactly the friction that gets a POS abandoned.
    SignedOut() => AppState(
      auth: AuthState(
        stage: AuthStage.signedOut,
        restaurantSlug: state.auth.restaurantSlug,
        phone: state.auth.phone,
      ),
    ),

    SessionRestoreFailed() => state.copyWith(
      auth: AuthState(
        stage: AuthStage.signedOut,
        restaurantSlug: action.restaurantCode.isEmpty
            ? state.auth.restaurantSlug
            : action.restaurantCode,
        phone: action.phone.isEmpty ? state.auth.phone : action.phone,
      ),
    ),

    SessionLocked() => state.copyWith(
      booted: true,
      auth: state.auth.copyWith(
        stage: AuthStage.locked,
        status: Status.ready,
        pendingUserName: action.userName,
        restaurantSlug: action.restaurantCode.isEmpty
            ? state.auth.restaurantSlug
            : action.restaurantCode,
        clearError: true,
      ),
    ),

    SignInStarted() => state.copyWith(
      auth: state.auth.copyWith(
        submitting: true,
        clearError: true,
        fieldErrors: const <String, String>{},
      ),
    ),

    SignInFailed() => state.copyWith(
      auth: state.auth.copyWith(
        submitting: false,
        error: action.message,
        fieldErrors: action.fields,
      ),
    ),

    TwoFactorRequired() => state.copyWith(
      auth: state.auth.copyWith(
        stage: AuthStage.awaitingTwoFactor,
        submitting: false,
        challenge: action.challenge,
        pendingUserName: action.userName,
        pendingRestaurantName: action.restaurantName,
        clearError: true,
        fieldErrors: const <String, String>{},
      ),
    ),

    TwoFactorCancelled() => state.copyWith(
      auth: state.auth.copyWith(
        stage: AuthStage.signedOut,
        submitting: false,
        clearChallenge: true,
        clearError: true,
      ),
    ),

    // Still not `signedIn`: that happens when bootstrap delivers the user, so
    // the shell never renders before it has someone to render it for.
    SignInSucceeded() => state.copyWith(
      auth: state.auth.copyWith(
        submitting: false,
        clearChallenge: true,
        clearError: true,
        restaurantSlug: action.restaurantCode.isEmpty
            ? state.auth.restaurantSlug
            : action.restaurantCode,
        phone: action.phone.isEmpty ? state.auth.phone : action.phone,
        mustChangePassword: action.mustChangePassword,
        mustEnrolTwoFactor: action.mustEnrolTwoFactor,
      ),
    ),

    SecurityObligationResolved() => state.copyWith(
      auth: state.auth.copyWith(
        mustChangePassword: action.passwordChanged
            ? false
            : state.auth.mustChangePassword,
        mustEnrolTwoFactor: action.twoFactorEnrolled
            ? false
            : state.auth.mustEnrolTwoFactor,
      ),
    ),

    TabSelected() => state.copyWith(activeTab: action.index),

    // ---------------------------------------------------------- settings
    LanguageChanged() => state.copyWith(
      settings: state.settings.copyWith(language: action.language),
    ),

    ThemeModeChanged() => state.copyWith(
      settings: state.settings.copyWith(themeMode: action.mode),
    ),

    SettingToggled() => state.copyWith(
      settings: state.settings.copyWith(
        taxEnabled: action.taxEnabled,
        packagingFeeEnabled: action.packagingFeeEnabled,
        requireTableForDineIn: action.requireTableForDineIn,
        guestCountEnabled: action.guestCountEnabled,
      ),
    ),

    SettingValueChanged() => state.copyWith(
      settings: state.settings.copyWith(
        taxRate: action.taxRate,
        packagingFee: action.packagingFee,
        currencyPrefix: action.currencyPrefix,
      ),
    ),

    SettingsLoaded() => state.copyWith(
      // Theme mode is intentionally not overwritten — it belongs to the
      // device, not the restaurant record.
      settings: action.settings.copyWith(themeMode: state.settings.themeMode),
    ),

    // --------------------------------------------------------- dashboard
    DashboardLoadStarted() => state.copyWith(
      dashboard: state.dashboard.copyWith(status: Status.loading),
    ),

    DashboardLoaded() => state.copyWith(
      dashboard: state.dashboard.copyWith(
        status: Status.ready,
        date: action.date,
        sales: action.sales,
        orders: action.orders,
        expenses: action.expenses,
        profit: action.profit,
        weekly: action.weekly,
        previousWeekly: action.previousWeekly,
        topItems: action.topItems,
      ),
    ),

    // --------------------------------------------------------------- POS
    PosTabChanged() => state.copyWith(
      pos: state.pos.copyWith(tabIndex: action.index),
    ),

    PosSearchChanged() => state.copyWith(
      pos: state.pos.copyWith(query: action.query),
    ),

    PosCategorySelected() => state.copyWith(
      pos: action.categoryId == null
          ? state.pos.copyWith(clearCategory: true)
          : state.pos.copyWith(categoryId: action.categoryId),
    ),

    // -------------------------------------------------------------- cart
    CartItemAdded() => state.copyWith(
      cart: _addToCart(state.cart, action.item, action.quantity),
    ),

    CartItemIncremented() => state.copyWith(
      cart: _changeQuantity(state.cart, action.itemId, 1),
    ),

    CartItemDecremented() => state.copyWith(
      cart: _changeQuantity(state.cart, action.itemId, -1),
    ),

    CartItemRemoved() => state.copyWith(
      cart: state.cart.copyWith(
        lines: state.cart.lines
            .where((OrderLine l) => l.itemId != action.itemId)
            .toList(),
      ),
    ),

    DraftLoadedIntoCart() => state.copyWith(
      cart: CartState(
        lines: action.draft.lines,
        orderType: action.draft.type,
        tableId: action.draft.tableId,
        customerName: action.draft.customerName,
        customerPhone: action.draft.customerPhone,
        notes: action.draft.notes,
        // What makes the next save an update rather than a second ticket.
        editingDraftId: action.draft.id,
      ),
      // Straight to the cart: they came here to change what is in it.
      pos: state.pos.copyWith(tabIndex: 1),
    ),

    CartCleared() => state.copyWith(cart: const CartState()),

    CartOrderTypeChanged() => state.copyWith(
      cart: action.type == OrderType.takeaway
          // Takeaway never carries a table — enforced here so a stale table id
          // can't survive a type switch and reach the API.
          ? state.cart.copyWith(
              orderType: action.type,
              clearTable: true,
              guests: 0,
            )
          : state.cart.copyWith(orderType: action.type),
    ),

    CartTableSelected() => state.copyWith(
      cart: action.tableId == null
          ? state.cart.copyWith(clearTable: true)
          : state.cart.copyWith(tableId: action.tableId),
    ),

    CartWaiterSelected() => state.copyWith(
      cart: state.cart.copyWith(waiterId: action.waiterId),
    ),

    CartGuestsChanged() => state.copyWith(
      cart: state.cart.copyWith(guests: action.guests),
    ),

    CartDiscountChanged() => state.copyWith(
      cart: state.cart.copyWith(discount: action.discount),
    ),

    CartCustomerChanged() => state.copyWith(
      cart: state.cart.copyWith(
        customerName: action.name,
        customerPhone: action.phone,
        notes: action.notes,
      ),
    ),

    CartPaymentChanged() => state.copyWith(
      cart: state.cart.copyWith(
        paymentMethod: action.method,
        paymentReference: action.reference,
      ),
    ),

    CartCustomerAttached() => state.copyWith(
      cart: action.clear
          ? state.cart.copyWith(clearCustomer: true)
          : state.cart.copyWith(
              customerId: action.customerId,
              paymentMode: action.mode,
            ),
    ),

    OrderPlaced() => _placeOrder(state, action),

    // ------------------------------------------------------------ orders
    OrderStatusFilterChanged() => state.copyWith(
      orders: state.orders.copyWith(
        filters: action.status == null
            ? state.orders.filters.copyWith(clearStatus: true)
            : state.orders.filters.copyWith(status: action.status),
      ),
    ),

    OrderFiltersChanged() => state.copyWith(
      orders: state.orders.copyWith(filters: action.filters),
    ),

    OrderSearchChanged() => state.copyWith(
      orders: state.orders.copyWith(
        filters: state.orders.filters.copyWith(query: action.query),
      ),
    ),

    OrderStatusUpdated() => _updateOrderStatus(state, action),

    // -------------------------------------------------------------- menu
    MenuTabChanged() => state.copyWith(
      menu: state.menu.copyWith(tabIndex: action.index),
    ),

    MenuSearchChanged() => state.copyWith(
      menu: state.menu.copyWith(query: action.query),
    ),

    MenuCategoryFilterChanged() => state.copyWith(
      menu: action.categoryId == null
          ? state.menu.copyWith(clearCategoryFilter: true)
          : state.menu.copyWith(categoryFilter: action.categoryId),
    ),

    MenuItemAvailabilityToggled() => state.copyWith(
      menu: state.menu.copyWith(
        items: state.menu.items
            .map(
              (MenuItem i) => i.id == action.itemId
                  ? i.copyWith(available: !i.available)
                  : i,
            )
            .toList(),
      ),
    ),

    MenuItemSaved() => state.copyWith(
      menu: state.menu.copyWith(
        items: _upsertItem(state.menu.items, action.item),
      ),
    ),

    MenuItemDeleted() => state.copyWith(
      menu: state.menu.copyWith(
        items: state.menu.items
            .where((MenuItem i) => i.id != action.itemId)
            .toList(),
      ),
      cart: state.cart.copyWith(
        lines: state.cart.lines
            .where((OrderLine l) => l.itemId != action.itemId)
            .toList(),
      ),
    ),

    // ------------------------------------------------- server-side lists
    CategoriesLoaded() => state.copyWith(
      categories: state.categories.copyWith(categories: action.categories),
    ),

    TablesLoaded() => state.copyWith(
      tables: state.tables.copyWith(tables: action.tables),
    ),

    DraftsLoaded() => state.copyWith(
      drafts: state.drafts.copyWith(drafts: action.drafts),
    ),

    ShiftStatusLoaded() => state.copyWith(
      shifts: state.shifts.copyWith(till: action.till),
    ),

    ShiftHistoryLoaded() => state.copyWith(
      shifts: state.shifts.copyWith(history: action.shifts),
    ),

    ShiftClosed() => state.copyWith(
      shifts: state.shifts.copyWith(
        lastClosed: action.shift,
        history: <Shift>[action.shift, ...state.shifts.history],
      ),
    ),

    ShiftRevealDismissed() => state.copyWith(
      shifts: state.shifts.copyWith(clearLastClosed: true),
    ),
    ExpensesLoaded() => state.copyWith(
      expenses: state.expenses.copyWith(expenses: action.expenses),
    ),

    AccountsLoaded() => state.copyWith(
      accounts: state.accounts.copyWith(accounts: action.accounts),
    ),

    PaymentMethodsLoaded() => state.copyWith(
      accounts: state.accounts.copyWith(methods: action.methods),
    ),

    TransactionsLoaded() => state.copyWith(
      accounts: state.accounts.copyWith(
        transactions: action.transactions,
        filters: action.filters,
      ),
    ),

    NotificationsLoaded() => state.copyWith(
      notifications: state.notifications.copyWith(messages: action.messages),
    ),

    // --------------------------------------------------------- customers
    CustomersLoaded() => state.copyWith(
      customers: state.customers.copyWith(
        status: Status.ready,
        customers: action.customers,
        // A profile already open is refreshed from the list, so a payment
        // taken elsewhere shows on the row behind the sheet. Its ledger is
        // kept: list rows do not carry one.
        selected: _restated(state.customers.selected, action.customers),
      ),
    ),

    CustomerProfileLoaded() => state.copyWith(
      customers: state.customers.copyWith(
        selected: action.customer,
        selectedStatus: Status.ready,
        customers: state.customers.customers
            .map((Customer c) => c.id == action.customer.id ? action.customer : c)
            .toList(),
      ),
    ),

    CustomerProfileCleared() => state.copyWith(
      customers: state.customers.copyWith(
        clearSelected: true,
        selectedStatus: Status.idle,
      ),
    ),

    CustomerQueryChanged() => state.copyWith(
      customers: state.customers.copyWith(
        status: Status.loading,
        filter: action.filter,
        search: action.search,
      ),
    ),

    OrdersLoaded() => state.copyWith(
      orders: state.orders.copyWith(orders: action.orders),
    ),

    OrderUpdated() => state.copyWith(
      orders: state.orders.copyWith(
        orders: state.orders.orders
            .map(
              (RestaurantOrder o) => o.id == action.order.id ? action.order : o,
            )
            .toList(),
      ),
    ),

    // ---------------------------------------------------------- expenses
    ExpenseKindChanged() => state.copyWith(
      expenses: state.expenses.copyWith(kind: action.kind),
    ),

    // ----------------------------------------------------------- reports
    ReportRangeChanged() => state.copyWith(
      reports: state.reports.copyWith(
        range: action.range,
        from: action.from,
        to: action.to,
        status: Status.loading,
      ),
    ),

    ReportLoadStarted() => state.copyWith(
      reports: state.reports.copyWith(status: Status.loading),
    ),

    ReportFiltersChanged() => state.copyWith(
      reports: state.reports.copyWith(
        filters: action.filters,
        status: Status.loading,
      ),
    ),

    ReportLoaded() => state.copyWith(
      reports: state.reports.copyWith(
        status: Status.ready,
        sales: action.sales,
        orders: action.orders,
        expenses: action.expenses,
        profit: action.profit,
        daily: action.daily,
        hourly: action.hourly,
        byCategory: action.byCategory,
        byPayment: action.byPayment,
        byWaiter: action.byWaiter,
        byTable: action.byTable,
        topItems: action.topItems,
        lowItems: action.lowItems,
        discounts: action.discounts,
        tax: action.tax,
        packaging: action.packaging,
        completedOrders: action.completedOrders,
        cancelledOrders: action.cancelledOrders,
        draftOrders: action.draftOrders,
        dineInOrders: action.dineInOrders,
        takeawayOrders: action.takeawayOrders,
        cash: action.cash,
        receivables: action.receivables,
        depositsHeld: action.depositsHeld,
        unpaidOrders: action.unpaidOrders,
        topCustomers: action.topCustomers,
        topDebtors: action.topDebtors,
      ),
    ),

    _ => state,
  };
}

// ------------------------------------------------------------------ helpers

AppState _bootstrapped(AppState state, BootstrapSucceeded a) {
  return state.copyWith(
    // One bit, so the POS can explain itself to somebody who cannot read
    // the shift endpoint.
    shifts: state.shifts.copyWith(tillOpenHint: a.tillOpen),
    booted: true,
    auth: state.auth.copyWith(
      stage: AuthStage.signedIn,
      status: Status.ready,
      user: a.user,
      restaurant: a.restaurant,
      restaurantSlug: a.restaurant.slug,
      phone: a.user.phone,
      submitting: false,
      clearChallenge: true,
      clearError: true,
    ),
    restaurant: RestaurantState(
      status: Status.ready,
      restaurant: a.restaurant,
      staff: a.staff,
    ),
    categories: CategoryState(status: Status.ready, categories: a.categories),
    menu: state.menu.copyWith(status: Status.ready, items: a.items),
    tables: TableState(status: Status.ready, tables: a.tables),
    orders: state.orders.copyWith(status: Status.ready, orders: a.orders),
    drafts: DraftState(status: Status.ready, drafts: a.drafts),
    expenses: ExpenseState(
      status: Status.ready,
      expenses: a.expenses,
      categories: a.expenseCategories,
    ),
    accounts: AccountState(status: Status.ready, accounts: a.accounts),
    // The default waiter is whoever is signed in, so a waiter taking their own
    // orders never has to pick themselves from a list.
    cart: state.cart.copyWith(waiterId: a.user.id),
  );
}

/// Re-reads the open profile's balance from a freshly loaded list.
///
/// Only the balance-bearing fields come across; the ledger stays as it was,
/// because a list row has none and overwriting it would empty the history the
/// user is looking at.
Customer? _restated(Customer? selected, List<Customer> loaded) {
  if (selected == null) return null;

  for (final Customer c in loaded) {
    if (c.id == selected.id) return c.copyWith(ledger: selected.ledger);
  }

  return selected;
}

CartState _addToCart(CartState cart, MenuItem item, int quantity) {
  final int index = cart.indexOfItem(item.id);
  final List<OrderLine> lines = List<OrderLine>.of(cart.lines);
  if (index == -1) {
    lines.add(OrderLine.fromMenuItem(item, quantity: quantity));
  } else {
    lines[index] = lines[index].copyWith(
      quantity: lines[index].quantity + quantity,
    );
  }
  return cart.copyWith(lines: lines);
}

CartState _changeQuantity(CartState cart, int itemId, int delta) {
  final int index = cart.indexOfItem(itemId);
  if (index == -1) return cart;
  final List<OrderLine> lines = List<OrderLine>.of(cart.lines);
  final int next = lines[index].quantity + delta;
  if (next <= 0) {
    lines.removeAt(index);
  } else {
    lines[index] = lines[index].copyWith(quantity: next);
  }
  return cart.copyWith(lines: lines);
}

List<MenuItem> _upsertItem(List<MenuItem> items, MenuItem item) {
  final int index = items.indexWhere((MenuItem i) => i.id == item.id);
  final List<MenuItem> next = List<MenuItem>.of(items);
  if (index == -1) {
    next.insert(0, item);
  } else {
    next[index] = item;
  }
  return next;
}

/// Checkout: append the order, occupy the table, reset the cart.
AppState _placeOrder(AppState state, OrderPlaced a) {
  final List<RestaurantOrder> orders = <RestaurantOrder>[
    a.order,
    ...state.orders.orders,
  ];

  final List<DiningTable> tables = a.order.tableId == null
      ? state.tables.tables
      : state.tables.tables
            .map(
              (DiningTable t) => t.id == a.order.tableId
                  ? t.copyWith(
                      status: TableStatus.occupied,
                      currentOrderId: a.order.id,
                    )
                  : t,
            )
            .toList();

  return state.copyWith(
    orders: state.orders.copyWith(
      orders: orders,
      lastPlacedOrderId: a.order.id,
    ),
    tables: state.tables.copyWith(tables: tables),
    // Keep the waiter selection so the next order for the same shift is one
    // tap shorter; everything else resets.
    cart: CartState(waiterId: state.cart.waiterId),
    pos: state.pos.copyWith(tabIndex: 0),
  );
}

AppState _updateOrderStatus(AppState state, OrderStatusUpdated a) {
  final List<RestaurantOrder> orders = state.orders.orders.map((
    RestaurantOrder o,
  ) {
    if (o.id != a.orderId) return o;
    return o.copyWith(
      status: a.status,
      cancelReason: a.status == OrderStatus.cancelled ? a.reason : null,
      events: <OrderEvent>[
        ...o.events,
        OrderEvent(
          labelKey: 'orderStatusChanged',
          at: DateTime.now(),
          byUser: a.byUser,
          oldValue: o.status.name,
          newValue: a.status.name,
          reason: a.reason,
        ),
      ],
    );
  }).toList();

  // Completing or cancelling a dine-in order frees its table.
  final RestaurantOrder? target = state.orders.byId(a.orderId);
  final bool releasesTable = target?.tableId != null && !a.status.isOpen;
  final List<DiningTable> tables = !releasesTable
      ? state.tables.tables
      : state.tables.tables
            .map(
              (DiningTable t) => t.id == target!.tableId
                  ? DiningTable(
                      id: t.id,
                      restaurantId: t.restaurantId,
                      number: t.number,
                      capacity: t.capacity,
                      name: t.name,
                      status: TableStatus.available,
                      active: t.active,
                    )
                  : t,
            )
            .toList();

  return state.copyWith(
    orders: state.orders.copyWith(orders: orders),
    tables: state.tables.copyWith(tables: tables),
  );
}
