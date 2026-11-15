import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:redux/redux.dart';

import '../core/config/app_config.dart';
import '../core/push/push_service.dart';
import '../core/security/app_lock.dart';
import '../core/utils/enums.dart';
import '../data/api/api_client.dart';
import '../data/api/dacaam_api.dart';
import '../data/models/app_notification.dart';
import '../data/models/customer.dart';
import '../data/models/dining_table.dart';
import '../data/models/menu.dart';
import '../data/models/order.dart';
import '../data/models/shift.dart';
import '../data/repository/api_repository.dart';
import '../data/repository/dacaam_repository.dart';
import '../data/repository/mock_repository.dart';
import 'actions.dart';
import 'app_state.dart';
import 'states/report_state.dart';
import 'states/settings_state.dart';
import 'states/customer_state.dart';
import 'states/finance_state.dart';

/// Async side effects.
///
/// Every effect goes through a [DacaamRepository], so the same code path
/// serves the offline dataset and the live REST API. Which one is in use is
/// decided once, at startup, from build-time configuration.
class Effects {
  const Effects._();

  static DacaamRepository _repository = AppConfig.useApi
      ? ApiRepository()
      : MockRepository();

  static DacaamRepository get repository => _repository;

  /// Swaps the data source. Used by tests and by the API-unreachable fallback.
  @visibleForTesting
  static set repository(DacaamRepository value) => _repository = value;

  /// The live API client, or null when running on the offline dataset.
  ///
  /// Security features — 2FA enrolment, session revocation, login history —
  /// have no meaning without a server to enforce them. Screens that need it
  /// check for null and say so, rather than miming the interaction against
  /// local state and teaching the user something untrue.
  static DacaamApi? get api {
    final DacaamRepository repo = _repository;

    return repo is ApiRepository ? repo.api : null;
  }

  // ------------------------------------------------------------- sign-in

  /// App launch: adopt a stored session if there is a usable one, otherwise
  /// show the login form.
  static Future<void> restoreSession(Store<AppState> store) async {
    try {
      if (await _repository.restoreSession()) {
        // A stored session is what makes this handset worth locking: without
        // the lock, whoever picks the phone up is already inside the till.
        // Checked before bootstrap so no data is fetched — let alone shown —
        // behind the prompt.
        if (await _lock.isEnabled() && await _lock.isAvailable()) {
          store.dispatch(
            SessionLocked(
              userName: store.state.auth.user?.name ?? '',
              restaurantCode: store.state.auth.restaurantSlug,
            ),
          );

          return;
        }

        await bootstrap(store);

        return;
      }
    } on ApiException catch (e) {
      // Unreachable server at launch. In development the offline dataset still
      // has a stored session to honour, so fall back rather than forcing a
      // sign-in nobody can complete without a network.
      //
      // Never in a shipped build. There the fallback meant an unreachable
      // server turned into a till that accepts any password and shows invented
      // takings — the same screen as a working one, which is the dangerous
      // part. A release build says it cannot reach the server instead.
      if (_repository is ApiRepository && AppConfig.allowOfflineData) {
        debugPrint('[dacaam] API unreachable (${e.message}); using local data');
        _repository = MockRepository();
        await restoreSession(store);

        return;
      }
    }

    store.dispatch(
      SessionRestoreFailed(
        restaurantCode: AppConfig.restaurantCode,
        phone: store.state.auth.phone,
      ),
    );
  }

  /// The handset's own face / fingerprint check, over a session that is
  /// already signed in.
  static final AppLock _lock = AppLock();

  static AppLock get lock => _lock;

  /// Answers the lock screen. A refusal leaves the session locked rather than
  /// signing anybody out — the password route is still on the same screen.
  static Future<bool> unlock(Store<AppState> store) async {
    if (!await _lock.authenticate()) return false;

    await bootstrap(store);

    return true;
  }

  /// Abandons the locked session and goes back to the password form. Used when
  /// somebody else needs the till, so the stored token has to go.
  static Future<void> signOutLocked(Store<AppState> store) async {
    await _repository.signOut();
    store.dispatch(const SignedOut());
  }

  static Future<void> signIn(
    Store<AppState> store, {
    required String restaurantCode,
    required String phone,
    required String password,
  }) async {
    store.dispatch(const SignInStarted());

    try {
      final SignInResult result = await _repository.signIn(
        restaurantCode: restaurantCode.trim().toUpperCase(),
        phone: phone.trim(),
        password: password,
      );

      await _completeSignIn(store, result, restaurantCode, phone);
    } on ApiException catch (e) {
      store.dispatch(SignInFailed(e.message, fields: e.fields));
    } catch (e) {
      store.dispatch(SignInFailed('$e'));
    }
  }

  static Future<void> verifyTwoFactor(
    Store<AppState> store, {
    required String code,
  }) async {
    final String? challenge = store.state.auth.challenge;
    if (challenge == null) {
      store.dispatch(const SignInFailed('Sign in again to request a new code'));

      return;
    }

    store.dispatch(const SignInStarted());

    try {
      final SignInResult result = await _repository.verifyTwoFactor(
        challenge: challenge,
        code: code.trim(),
      );

      await _completeSignIn(
        store,
        result,
        store.state.auth.restaurantSlug,
        store.state.auth.phone,
      );
    } on ApiException catch (e) {
      store.dispatch(SignInFailed(e.message, fields: e.fields));
    }
  }

  static Future<void> _completeSignIn(
    Store<AppState> store,
    SignInResult result,
    String restaurantCode,
    String phone,
  ) async {
    if (result.requiresTwoFactor) {
      store.dispatch(
        TwoFactorRequired(
          challenge: result.challenge ?? '',
          userName: result.userName,
          restaurantName: result.restaurantName,
        ),
      );

      return;
    }

    store.dispatch(
      SignInSucceeded(
        restaurantCode: restaurantCode.trim().toUpperCase(),
        phone: phone.trim(),
        mustChangePassword: result.mustChangePassword,
        mustEnrolTwoFactor: result.mustEnrolTwoFactor,
      ),
    );

    await bootstrap(store);
  }

  // ----------------------------------------------------------- settings

  /// Saves a settings change and keeps the screen honest about the result.
  ///
  /// The new state is applied immediately so switches and figures respond
  /// under the finger, then replaced by whatever the server stored. If the
  /// save fails the previous state is put back: a toggle that silently sprang
  /// back on the next launch is the bug this replaces, and one that lies about
  /// having saved is no better.
  static Future<void> saveSettings(
    Store<AppState> store,
    SettingsState settings,
  ) async {
    final SettingsState previous = store.state.settings;

    store.dispatch(SettingsLoaded(settings));

    try {
      final SettingsState saved = await _repository.saveSettings(settings);
      store.dispatch(SettingsLoaded(saved));
    } on ApiException {
      // Put the old value back and let the caller show why: the screen owns
      // the message, as it does everywhere else in this file.
      store.dispatch(SettingsLoaded(previous));
      rethrow;
    }
  }

  // ---------------------------------------------------------- lifecycle

  static Future<void> bootstrap(Store<AppState> store) async {
    store.dispatch(const BootstrapStarted());

    try {
      final BootstrapPayload payload = await _repository.bootstrap();

      store.dispatch(payload.bootstrap);
      if (payload.settings != null) {
        store.dispatch(SettingsLoaded(payload.settings!));
      }
      store.dispatch(payload.dashboard);

      // Before the first checkout, not on opening the Accounts screen: a
      // till that offers only the seeded four until somebody browses
      // Settings would take a payment against the wrong method.
      await refreshPaymentMethods(store);
      // Loaded at open-up for the same reason: the checkout has to be able to
      // offer accounts without waiting for somebody to visit the list first.
      // A user without customers.view gets a 403, which the effect swallows.
      await loadCustomers(store);
      // At sign-in, not on opening the Sanduuqa screen. The POS shows a
      // banner when no till is open, and a state that defaults to closed
      // until somebody visits that screen would raise a false alarm on
      // every morning the till was already open.
      await loadShift(store);
      await loadNotifications(store);
      unawaited(startPush(store));
      await loadReports(store, store.state.reports.range);
    } on ApiException catch (e) {
      // In development, a POS that cannot reach its backend at open-up is
      // still more useful showing the seeded catalogue than an error page.
      //
      // In a shipped build it is not: the seeded catalogue has other people's
      // prices and invented takings, and a manager reading them would have no
      // way to tell. Release fails loudly and offers a retry.
      if (_repository is ApiRepository &&
          e.isNetwork &&
          AppConfig.allowOfflineData) {
        debugPrint('[dacaam] API unreachable (${e.message}); using local data');
        _repository = MockRepository();
        await bootstrap(store);
        return;
      }
      store.dispatch(BootstrapFailed(e.message));
    } catch (e) {
      store.dispatch(BootstrapFailed('$e'));
    }
  }

  static Future<void> signOut(Store<AppState> store) async {
    try {
      await _repository.signOut();
    } on ApiException catch (e) {
      // A token the server has already forgotten is still gone locally; the
      // user must not be trapped in the app by a failed round trip.
      debugPrint('[dacaam] sign-out call failed: ${e.message}');
    }

    store.dispatch(const SignedOut());
  }

  /// Exposed for the Security screen: after changing a password or enrolling
  /// in 2FA, the obligation the server reported at sign-in is satisfied.
  static void resolveObligation(
    Store<AppState> store, {
    bool passwordChanged = false,
    bool twoFactorEnrolled = false,
  }) {
    store.dispatch(
      SecurityObligationResolved(
        passwordChanged: passwordChanged,
        twoFactorEnrolled: twoFactorEnrolled,
      ),
    );
  }

  // ---------------------------------------------------------- dashboard

  static Future<void> refreshDashboard(Store<AppState> store) async {
    store.dispatch(const DashboardLoadStarted());

    try {
      store.dispatch(await _repository.dashboard());
    } on ApiException catch (e) {
      debugPrint('[dacaam] dashboard refresh failed: ${e.message}');
    }
  }

  // ------------------------------------------------------------ reports

  static Future<void> changeReportRange(
    Store<AppState> store,
    ReportRange range, {
    DateTime? from,
    DateTime? to,
  }) async {
    store.dispatch(ReportRangeChanged(range, from: from, to: to));
    await loadReports(store, range);
  }

  static Future<void> changeReportFilters(
    Store<AppState> store,
    ReportFilters filters,
  ) async {
    store.dispatch(ReportFiltersChanged(filters));
    await loadReports(store, store.state.reports.range);
  }

  static Future<void> loadReports(
    Store<AppState> store,
    ReportRange range,
  ) async {
    store.dispatch(const ReportLoadStarted());

    try {
      store.dispatch(
        await _repository.reports(range, filters: store.state.reports.filters),
      );
    } on ApiException catch (e) {
      debugPrint('[dacaam] reports failed: ${e.message}');
    }
  }

  /// Re-reads the figures the Home screen shows, after money has moved.
  ///
  /// Today's takings and the two standing figures — what is owed to the
  /// restaurant and what it holds on deposit — are computed by the server, so
  /// nothing the app does locally can keep them current. Without this they sat
  /// stale until somebody pulled to refresh, which meant taking a 100,000
  /// deposit and watching "Deposits held" not move.
  ///
  /// Deliberately quiet, and deliberately not awaited by its callers:
  ///
  ///   - No `ReportLoadStarted`, so the Reports screen does not blink to a
  ///     skeleton because a deposit was taken two screens away.
  ///   - Failures are logged, never surfaced. These are informational; a sale
  ///     that succeeded must not look like it failed because a summary query
  ///     timed out behind it.
  ///   - Fire and forget, so a checkout on a slow connection is not held up by
  ///     two queries nobody is waiting to read.
  static Future<void> refreshFigures(Store<AppState> store) async {
    try {
      store.dispatch(await _repository.dashboard());
    } on ApiException catch (e) {
      debugPrint('[dacaam] dashboard not refreshed: ${e.message}');
    }

    try {
      store.dispatch(
        await _repository.reports(
          store.state.reports.range,
          filters: store.state.reports.filters,
        ),
      );
    } on ApiException catch (e) {
      debugPrint('[dacaam] figures not refreshed: ${e.message}');
    }
  }
  /// Downloads the CSV for the current range and filters and writes it to the
  /// app's documents directory.
  ///
  /// Deliberately no native share sheet: the package that provides one drags
  /// in an FFI toolchain dependency that has to be enabled globally, which is
  /// too much to impose on a whole machine for one button. The caller gets the
  /// file back and offers the path plus copy-to-clipboard instead.
  static Future<File> exportReport(
    Store<AppState> store, {
    required String type,
  }) async {
    final DacaamApi? api = Effects.api;
    if (api == null) {
      throw const ApiException(
        'Export needs the DACAAM API',
        statusCode: 0,
        code: 'offline',
      );
    }

    final String csv = await api.exportReport(
      range: _rangeKey(store.state.reports.range),
      type: type,
      filters: store.state.reports.filters.toQuery(),
    );

    // systemTemp comes from dart:io, so the export needs no platform plugin —
    // the packages that offer nicer directories now drag in an FFI toolchain
    // dependency that has to be enabled machine-wide.
    final Directory dir = Directory.systemTemp;
    final String stamp = DateTime.now().toIso8601String().substring(0, 10);
    final File file = File('${dir.path}/dacaam-$type-$stamp.csv');
    await file.writeAsString(csv, flush: true);

    return file;
  }

  /// The CSV body itself, for putting on the clipboard.
  static Future<String> exportReportCsv(
    Store<AppState> store, {
    required String type,
  }) async {
    final DacaamApi? api = Effects.api;
    if (api == null) {
      throw const ApiException(
        'Export needs the DACAAM API',
        statusCode: 0,
        code: 'offline',
      );
    }

    return api.exportReport(
      range: _rangeKey(store.state.reports.range),
      type: type,
      filters: store.state.reports.filters.toQuery(),
    );
  }

  static String _rangeKey(ReportRange range) => switch (range) {
    ReportRange.today => 'today',
    ReportRange.sevenDays => '7_days',
    ReportRange.thirtyDays => '30_days',
    ReportRange.thisMonth => 'this_month',
    ReportRange.lastMonth => 'last_month',
    ReportRange.custom => 'custom',
  };

  // ------------------------------------------------------------- orders

  /// Commits the current cart.
  ///
  /// The request carries item ids and quantities only — pricing is resolved by
  /// the repository, which for the live backend means the server recomputes
  /// every figure from stored menu prices.
  static Future<RestaurantOrder> placeOrder(Store<AppState> store) async {
    final AppState state = store.state;

    final RestaurantOrder order = await _repository.placeOrder(
      OrderRequest(
        type: state.cart.orderType,
        lines: state.cart.lines,
        tableId: state.cart.tableId,
        waiterId: state.cart.waiterId,
        guests: state.cart.guests,
        discount: state.cart.discount,
        customerName: state.cart.customerName,
        customerPhone: state.cart.customerPhone,
        notes: state.cart.notes,
        paymentMethod: state.cart.paymentMethod,
        paymentReference: state.cart.paymentReference,
        settingsPackagingFee: state.settings.packagingFee,
        settingsTaxFraction: state.settings.taxFraction,
        customerId: state.cart.customerId,
        paymentMode: state.cart.paymentMode,
      ),
    );

    store.dispatch(
      OrderPlaced(order: order, byUser: state.auth.user?.name ?? ''),
    );

    // A sale on an account moved that account's balance, and the customer list
    // behind the POS would otherwise still show what they owed a minute ago.
    if (order.customerId != null) {
      await loadCustomers(store);
      if (store.state.customers.selected?.id == order.customerId) {
        await loadCustomer(store, order.customerId!);
      }
    }

    // Not awaited: the till returns to the success screen now, and the
    // figures catch up behind it.
    unawaited(refreshFigures(store));

    return order;
  }

  /// Pulls one order complete with its history.
  ///
  /// Opening the details sheet is the only moment the audit trail is wanted,
  /// and loading it for every row of a two-hundred order list would be a
  /// query per row for something nobody is looking at.
  static Future<void> loadOrder(Store<AppState> store, int id) async {
    try {
      store.dispatch(OrderUpdated(await _repository.order(id)));
    } on ApiException catch (e) {
      debugPrint('[dacaam] order $id not refreshed: ${e.message}');
    }
  }

  /// Replaces an open order's lines. The server reprices and returns the
  /// authoritative order, which replaces the local one wholesale — patching
  /// it here would be a second, divergent implementation of the pricing rules.
  static Future<void> updateOrderItems(
    Store<AppState> store,
    int orderId,
    List<OrderLine> lines, {
    double? discount,
    String? reason,
  }) async {
    final RestaurantOrder updated = await _repository.updateOrderItems(
      orderId,
      lines,
      discount: discount,
      reason: reason,
    );

    store.dispatch(OrderUpdated(updated));

    // Editing a customer's order restates their debt on the server; the app
    // has to re-read it or the profile keeps showing the old total.
    await _resyncCustomer(store, updated);
  }

  /// Re-reads the account an order sits on, when it sits on one.
  static Future<void> _resyncCustomer(
    Store<AppState> store,
    RestaurantOrder order,
  ) async {
    if (order.customerId == null) return;

    await loadCustomers(store);
    if (store.state.customers.selected?.id == order.customerId) {
      await loadCustomer(store, order.customerId!);
    }

    unawaited(refreshFigures(store));
  }

  static Future<void> addPayment(
    Store<AppState> store,
    int orderId, {
    required PaymentMethod method,
    required double amount,
    String reference = '',
  }) async {
    final RestaurantOrder updated = await _repository.addPayment(
      orderId,
      method: method,
      amount: amount,
      reference: reference,
    );

    store.dispatch(OrderUpdated(updated));
    await refreshAccounts(store);
    await _resyncCustomer(store, updated);
    unawaited(refreshFigures(store));
  }

  // ------------------------------------------------------------- drafts

  static Future<void> refreshDrafts(Store<AppState> store) async {
    store.dispatch(DraftsLoaded(await _repository.drafts()));
  }

  static Future<void> saveDraft(
    Store<AppState> store,
    DraftRequest request,
  ) async {
    await _repository.saveDraft(request);
    await refreshDrafts(store);
  }

  /// Cancels a refused draft. The row stays, so the list still shows it.
  static Future<void> cancelDraft(
    Store<AppState> store,
    int id,
    String reason,
  ) async {
    await _repository.cancelDraft(id, reason);
    await refreshDrafts(store);
  }

  /// Turns a parked draft into a real sale. Only at this point does it reach
  /// reports, KPIs and account balances.
  static Future<RestaurantOrder> convertDraft(
    Store<AppState> store,
    int id, {
    PaymentMethod? method,
    OrderType? orderType,
    int? tableId,
    int? waiterId,
  }) async {
    final RestaurantOrder order = await _repository.convertDraft(
      id,
      method: method,
      orderType: orderType,
      tableId: tableId,
      waiterId: waiterId,
    );

    store.dispatch(
      OrderPlaced(order: order, byUser: store.state.auth.user?.name ?? ''),
    );
    await refreshDrafts(store);
    await refreshAccounts(store);

    return order;
  }

  // --------------------------------------------------------------- menu

  /// Attaches or removes a menu photograph.
  ///
  /// The item comes back from the server with its new address, so the POS grid
  /// and the menu list both update from the same reply.
  static Future<void> setMenuItemImage(
    Store<AppState> store,
    int id,
    String? base64,
  ) async {
    store.dispatch(
      MenuItemSaved(await _repository.setMenuItemImage(id, base64)),
    );
  }

  static Future<void> saveMenuItem(
    Store<AppState> store,
    MenuItem item, {
    String? reason,
  }) async {
    store.dispatch(
      MenuItemSaved(await _repository.saveMenuItem(item, reason: reason)),
    );
  }

  static Future<void> toggleMenuItem(Store<AppState> store, int id) async {
    store.dispatch(MenuItemSaved(await _repository.toggleMenuItem(id)));
  }

  static Future<void> deleteMenuItem(Store<AppState> store, int id) async {
    await _repository.deleteMenuItem(id);
    store.dispatch(MenuItemDeleted(id));
  }

  static Future<void> saveCategory(
    Store<AppState> store,
    MenuCategory category,
  ) async {
    store.dispatch(CategoriesLoaded(await _repository.saveCategory(category)));
  }

  static Future<void> deleteCategory(Store<AppState> store, int id) async {
    store.dispatch(CategoriesLoaded(await _repository.deleteCategory(id)));
  }

  // ------------------------------------------------------------- tables

  static Future<void> refreshTables(Store<AppState> store) async {
    store.dispatch(TablesLoaded(await _repository.tables()));
  }

  static Future<void> saveTable(
    Store<AppState> store,
    DiningTable table,
  ) async {
    store.dispatch(TablesLoaded(await _repository.saveTable(table)));
  }

  static Future<void> deleteTable(Store<AppState> store, int id) async {
    store.dispatch(TablesLoaded(await _repository.deleteTable(id)));
  }

  // ----------------------------------------------------------- expenses

  static Future<void> saveExpense(
    Store<AppState> store,
    ExpenseRequest request,
  ) async {
    store.dispatch(ExpensesLoaded(await _repository.saveExpense(request)));
    await refreshAccounts(store);
  }

  // ------------------------------------------------------------- shifts

  /// Whether a till is open, and what the last one left behind.
  ///
  /// Quiet on failure. The shift banner is context, not the task at hand, and
  /// a red error across the POS because a status call timed out would be worse
  /// than not showing the banner.
  static Future<void> loadShift(Store<AppState> store) async {
    try {
      store.dispatch(ShiftStatusLoaded(await _repository.currentShift()));
    } on ApiException {
      // Left as it was.
    }
  }

  static Future<void> openShift(
    Store<AppState> store,
    double openingFloat, {
    String notes = '',
  }) async {
    store.dispatch(
      ShiftStatusLoaded(
        await _repository.openShift(openingFloat: openingFloat, notes: notes),
      ),
    );
  }

  /// Counts the drawer.
  ///
  /// The figures come back in the response and are put into `lastClosed` for
  /// the screen to show once. They are not merged into the till status, which
  /// the next person to open will read.
  static Future<Shift> closeShift(
    Store<AppState> store,
    int id,
    Map<int, double> counts, {
    String reason = '',
  }) async {
    final Shift closed = await _repository.closeShift(
      id,
      counts: counts,
      reason: reason,
    );

    store.dispatch(ShiftClosed(closed));
    await loadShift(store);

    // The variance was posted to the till as a visible adjustment, so the
    // balances on screen are stale the moment this returns.
    await refreshAccounts(store);

    return closed;
  }

  /// One closed shift, in full.
  ///
  /// Not put into the store: it is read once, looked at, and closed. Keeping
  /// it in state would leave the expected total sitting in memory for the
  /// next screen that happens to render, and that figure is the one thing
  /// this feature keeps away from whoever is about to count.
  static Future<ShiftDetail> shiftDetail(Store<AppState> store, int id) =>
      _repository.shiftDetail(id);

  static Future<void> loadShiftHistory(Store<AppState> store) async {
    store.dispatch(ShiftHistoryLoaded(await _repository.shiftHistory()));
  }
  static Future<void> cancelExpense(
    Store<AppState> store,
    int id,
    String reason,
  ) async {
    store.dispatch(ExpensesLoaded(await _repository.cancelExpense(id, reason)));
    await refreshAccounts(store);
  }

  // ----------------------------------------------------------- accounts

  /// Loads money movements for the given filters, remembering them so a pull
  /// to refresh repeats the same view rather than resetting it.
  static Future<void> loadTransactions(
    Store<AppState> store, {
    AccountFilters? filters,
  }) async {
    final AccountFilters f = filters ?? store.state.accounts.filters;

    try {
      store.dispatch(
        TransactionsLoaded(
          await _repository.accountTransactions(filters: f),
          f,
        ),
      );
    } on ApiException catch (e) {
      debugPrint('[dacaam] transactions not loaded: ${e.message}');
    }
  }

  static Future<void> refreshPaymentMethods(Store<AppState> store) async {
    try {
      store.dispatch(PaymentMethodsLoaded(await _repository.paymentMethods()));
    } on ApiException catch (e) {
      // The pickers fall back to the seeded four, so a failure here degrades
      // rather than blocking a sale.
      debugPrint('[dacaam] payment methods not loaded: ${e.message}');
    }
  }

  static Future<void> savePaymentMethod(
    Store<AppState> store, {
    int? id,
    String? name,
    bool? isActive,
  }) async {
    store.dispatch(
      PaymentMethodsLoaded(
        await _repository.savePaymentMethod(
          id: id,
          name: name,
          isActive: isActive,
        ),
      ),
    );
  }

  static Future<void> removePaymentMethod(Store<AppState> store, int id) async {
    store.dispatch(
      PaymentMethodsLoaded(await _repository.removePaymentMethod(id)),
    );
  }

  static Future<void> saveAccount(
    Store<AppState> store, {
    int? id,
    String? name,
    String? method,
    double balance = 0,
    bool? isActive,
  }) async {
    store.dispatch(
      AccountsLoaded(
        await _repository.saveAccount(
          id: id,
          name: name,
          method: method,
          balance: balance,
          isActive: isActive,
        ),
      ),
    );
  }

  static Future<void> removeAccount(Store<AppState> store, int id) async {
    store.dispatch(AccountsLoaded(await _repository.removeAccount(id)));
  }

  static Future<void> refreshAccounts(Store<AppState> store) async {
    try {
      store.dispatch(AccountsLoaded(await _repository.accounts()));
    } on ApiException catch (e) {
      // Balances are informational here; a caller without accounts.view must
      // not have their order or expense fail because of it.
      debugPrint('[dacaam] account refresh skipped: ${e.message}');
    }
  }

  static Future<void> transfer(
    Store<AppState> store, {
    required int fromAccountId,
    required int toAccountId,
    required double amount,
    String description = '',
  }) async {
    store.dispatch(
      AccountsLoaded(
        await _repository.transfer(
          fromAccountId: fromAccountId,
          toAccountId: toAccountId,
          amount: amount,
          description: description,
        ),
      ),
    );
  }

  // ------------------------------------------------------ notifications

  /// Pulls the messages this user can see.
  ///
  /// Failures are swallowed. A shop whose bell cannot load must still be able
  /// to take an order, and the message will be there on the next attempt.
  static Future<void> loadNotifications(Store<AppState> store) async {
    try {
      store.dispatch(NotificationsLoaded(await _repository.notifications()));
    } on ApiException catch (e) {
      debugPrint('[dacaam] notifications not loaded: ${e.message}');
    }
  }

  static Future<void> markNotificationRead(
    Store<AppState> store,
    int id,
  ) async {
    // Applied locally first so the badge drops under the finger, then
    // confirmed. A failed call leaves the server unchanged and the next load
    // puts it back — which is the honest outcome, not a silent lie.
    store.dispatch(
      NotificationsLoaded(
        store.state.notifications.messages
            .map((AppNotification n) => n.id == id ? n.copyWith(isRead: true) : n)
            .toList(),
      ),
    );

    try {
      await _repository.markNotificationRead(id);
    } on ApiException catch (e) {
      debugPrint('[dacaam] read not recorded: ${e.message}');
      await loadNotifications(store);
    }
  }

  static Future<void> markAllNotificationsRead(Store<AppState> store) async {
    try {
      await _repository.markAllNotificationsRead();
    } on ApiException catch (e) {
      debugPrint('[dacaam] read-all not recorded: ${e.message}');
    }

    await loadNotifications(store);
  }

  /// Starts push and tells the server where to deliver.
  ///
  /// Called after sign-in, because registration is authenticated — which also
  /// means the row carries who was signed in, and keeps carrying it after they
  /// sign out. That is what lets a general message reach a till nobody is
  /// logged into.
  static Future<void> startPush(Store<AppState> store) async {
    final PushService push = PushService.instance;

    // A message arriving while the app is open should move the bell, not wait
    // for somebody to pull down a list.
    push.onMessage = () => loadNotifications(store);
    push.onTokenChanged = (String token) => _registerDevice(store, token);

    await push.start();

    final String? token = push.token;
    if (token != null) await _registerDevice(store, token);
  }

  static Future<void> _registerDevice(Store<AppState> store, String token) async {
    try {
      await _repository.registerDevice(token);
    } on ApiException catch (e) {
      // Push is a convenience. Losing it must not stop the app working.
      debugPrint('[dacaam] device not registered: ${e.message}');
    }
  }
  // ---------------------------------------------------------- customers

  /// Loads the list for the given narrowing, remembering it so a pull to
  /// refresh repeats the same view rather than resetting it.
  static Future<void> loadCustomers(
    Store<AppState> store, {
    CustomerFilter? filter,
    String? search,
  }) async {
    final CustomerFilter f = filter ?? store.state.customers.filter;
    final String q = search ?? store.state.customers.search;

    store.dispatch(CustomerQueryChanged(filter: f, search: q));

    try {
      store.dispatch(
        CustomersLoaded(await _repository.customers(search: q, filter: f)),
      );
    } on ApiException catch (e) {
      debugPrint('[dacaam] customers not loaded: ${e.message}');
      store.dispatch(const CustomersLoaded(<Customer>[]));
    }
  }

  /// The profile, with its ledger.
  static Future<void> loadCustomer(Store<AppState> store, int id) async {
    final Customer? known = store.state.customers.byId(id);

    // Shows what the list already had while the ledger arrives, so opening a
    // profile is not a blank screen over a name and a balance already in hand.
    if (known != null) store.dispatch(CustomerProfileLoaded(known));

    store.dispatch(CustomerProfileLoaded(await _repository.customer(id)));
  }

  /// Puts an unpaid order onto a customer's account.
  ///
  /// Everything the order touched moves with it: the customer now carries the
  /// balance, so their list row and profile are re-read, and the report figure
  /// for money owed by nobody falls by the same amount.
  static Future<void> attachOrderCustomer(
    Store<AppState> store,
    int orderId, {
    required int customerId,
    required String reason,
  }) async {
    final RestaurantOrder updated = await _repository.attachOrderCustomer(
      orderId,
      customerId: customerId,
      reason: reason,
    );

    store.dispatch(OrderUpdated(updated));
    await _resyncCustomer(store, updated);
  }
  static Future<Customer> saveCustomer(
    Store<AppState> store,
    CustomerRequest request,
  ) async {
    final Customer saved = await _repository.saveCustomer(request);
    await loadCustomers(store);

    return saved;
  }

  static Future<void> deactivateCustomer(Store<AppState> store, int id) async {
    store.dispatch(
      CustomerProfileLoaded(await _repository.deactivateCustomer(id)),
    );
    await loadCustomers(store);
  }

  /// A repayment, a deposit, or a hand adjustment.
  ///
  /// All three land here because all three end the same way: the profile is
  /// re-read so the new ledger line is in front of whoever just took the money,
  /// the list is refreshed, and — for the two that move real cash — the account
  /// balances are too.
  static Future<void> postCustomerMoney(
    Store<AppState> store,
    int id, {
    required LedgerKind kind,
    required double amount,
    PaymentMethod method = PaymentMethod.cash,
    String description = '',
    String reason = '',
  }) async {
    final Customer after = switch (kind) {
      LedgerKind.payment => await _repository.payCustomer(
        id,
        amount: amount,
        method: method,
        description: description,
      ),
      LedgerKind.deposit => await _repository.depositForCustomer(
        id,
        amount: amount,
        method: method,
        description: description,
      ),
      _ => await _repository.adjustCustomer(id, amount: amount, reason: reason),
    };

    store.dispatch(CustomerProfileLoaded(after));
    await loadCustomers(store);

    // An adjustment moves no cash, so there is nothing for the tills to say.
    //
    // The transaction list is reloaded as well as the balances. Refreshing
    // only the balances left the Accounts screen showing a list that predated
    // the deposit, so the money looked like it had gone into the account
    // without a movement behind it — the exact thing that list exists to
    // disprove. Filters are kept: a narrowed view is the user's choice, and
    // silently widening it would be a different kind of lie.
    if (kind != LedgerKind.adjustment) {
      await refreshAccounts(store);
      await loadTransactions(store);
    }

    // Every kind moves the balance, so every kind moves "owed to you" or
    // "deposits held" — an adjustment most of all.
    unawaited(refreshFigures(store));
  }

  // ------------------------------------------------------------- orders

  static Future<void> updateOrderStatus(
    Store<AppState> store,
    int orderId,
    OrderStatus status, {
    String? reason,
  }) async {
    final String actor = store.state.auth.user?.name ?? '';

    // Applied locally first so the list reflects the tap immediately; a failed
    // call re-syncs from the server rather than leaving a phantom state.
    store.dispatch(
      OrderStatusUpdated(
        orderId: orderId,
        status: status,
        byUser: actor,
        reason: reason,
      ),
    );

    try {
      final RestaurantOrder updated =
          await _repository.setOrderStatus(orderId, status, reason: reason);
      store.dispatch(OrderUpdated(updated));

      // Cancelling a credit order gives the customer their money back on the
      // books — a compensating ledger entry, made server-side. Re-read it.
      await _resyncCustomer(store, updated);

      // Outside _resyncCustomer, which only runs for customer orders: voiding
      // a paid walk-in takes cash back out of the till, and today's takings
      // have to fall with it.
      unawaited(refreshFigures(store));
    } on ApiException catch (e) {
      debugPrint('[dacaam] status update rejected: ${e.message}');
      await bootstrap(store);
      rethrow;
    }
  }
}
