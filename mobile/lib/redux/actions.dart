import 'package:flutter/material.dart';

import '../core/utils/enums.dart';
import '../data/models/analytics.dart';
import '../data/models/app_notification.dart';
import '../data/models/customer.dart';
import '../data/models/dining_table.dart';
import '../data/models/finance.dart';
import '../data/models/menu.dart';
import '../data/models/order.dart';
import '../data/models/shift.dart';
import '../data/repository/dacaam_repository.dart';
import '../data/models/restaurant.dart';
import 'states/customer_state.dart';
import 'states/order_state.dart';
import 'states/report_state.dart';
import 'states/settings_state.dart';
import 'states/finance_state.dart';

// ---------------------------------------------------------------- lifecycle

class BootstrapStarted {
  const BootstrapStarted();
}

class BootstrapFailed {
  const BootstrapFailed(this.message);

  final String message;
}

/// Everything the app needs for the first paint, delivered in one shot so the
/// UI flips from skeleton to content atomically.
class BootstrapSucceeded {
  const BootstrapSucceeded({
    required this.restaurant,
    required this.user,
    required this.staff,
    required this.categories,
    required this.items,
    required this.tables,
    required this.orders,
    required this.drafts,
    required this.expenses,
    required this.expenseCategories,
    required this.accounts,
    this.tillOpen = false,
  });

  final Restaurant restaurant;
  final AppUser user;
  final List<AppUser> staff;
  final List<MenuCategory> categories;
  final List<MenuItem> items;
  final List<DiningTable> tables;
  final List<RestaurantOrder> orders;
  final List<DraftOrder> drafts;
  final List<Expense> expenses;

  /// Whether a till is open, as one bit.
  ///
  /// Sent with the session because a waiter has to know the POS will
  /// refuse to sell — and a waiter has no shifts.manage, so cannot read
  /// the shift endpoint that carries the counting figures.
  final bool tillOpen;
  final List<ExpenseCategory> expenseCategories;
  final List<Account> accounts;
}

class SignedOut {
  const SignedOut();
}

// --------------------------------------------------------------- sign-in

/// No stored session — show the login form.
class SessionRestoreFailed {
  const SessionRestoreFailed({this.restaurantCode = '', this.phone = ''});

  /// Remembered from the last sign-in so the form opens prefilled.
  final String restaurantCode;
  final String phone;
}

/// A stored session exists but this handset asks for a face or fingerprint
/// first. Carries the remembered name so the lock screen can greet whoever it
/// is rather than showing a blank prompt.
class SessionLocked {
  const SessionLocked({this.userName = '', this.restaurantCode = ''});

  final String userName;
  final String restaurantCode;
}

class SignInStarted {
  const SignInStarted();
}

class SignInFailed {
  const SignInFailed(this.message, {this.fields = const <String, String>{}});

  final String message;
  final Map<String, String> fields;
}

/// Password accepted; the server wants a one-time code.
class TwoFactorRequired {
  const TwoFactorRequired({
    required this.challenge,
    this.userName = '',
    this.restaurantName = '',
  });

  final String challenge;
  final String userName;
  final String restaurantName;
}

/// A session now exists. Bootstrap follows.
class SignInSucceeded {
  const SignInSucceeded({
    this.restaurantCode = '',
    this.phone = '',
    this.mustChangePassword = false,
    this.mustEnrolTwoFactor = false,
  });

  final String restaurantCode;
  final String phone;
  final bool mustChangePassword;
  final bool mustEnrolTwoFactor;
}

/// Clears an obligation once the user has dealt with it.
class SecurityObligationResolved {
  const SecurityObligationResolved({
    this.passwordChanged = false,
    this.twoFactorEnrolled = false,
  });

  final bool passwordChanged;
  final bool twoFactorEnrolled;
}

/// Returns from the OTP screen to the password form.
class TwoFactorCancelled {
  const TwoFactorCancelled();
}

// ------------------------------------------------------------------- shell

class TabSelected {
  const TabSelected(this.index);

  final int index;
}

// ---------------------------------------------------------------- settings

class LanguageChanged {
  const LanguageChanged(this.language);

  final AppLanguage language;
}

class ThemeModeChanged {
  const ThemeModeChanged(this.mode);

  final ThemeMode mode;
}

class SettingToggled {
  const SettingToggled({
    this.taxEnabled,
    this.packagingFeeEnabled,
    this.requireTableForDineIn,
    this.guestCountEnabled,
  });

  final bool? taxEnabled;
  final bool? packagingFeeEnabled;
  final bool? requireTableForDineIn;
  final bool? guestCountEnabled;
}

class SettingValueChanged {
  const SettingValueChanged({
    this.taxRate,
    this.packagingFee,
    this.currencyPrefix,
  });

  final double? taxRate;
  final double? packagingFee;
  final String? currencyPrefix;
}

/// Server-side settings replacing the local defaults at bootstrap.
///
/// The device's theme preference is preserved: appearance is a property of the
/// handset, not of the restaurant account.
class SettingsLoaded {
  const SettingsLoaded(this.settings);

  final SettingsState settings;
}

// --------------------------------------------------------------- dashboard

class DashboardLoadStarted {
  const DashboardLoadStarted();
}

class DashboardLoaded {
  const DashboardLoaded({
    required this.date,
    required this.sales,
    required this.orders,
    required this.expenses,
    required this.profit,
    required this.weekly,
    required this.previousWeekly,
    required this.topItems,
  });

  final DateTime date;
  final KpiValue sales;
  final KpiValue orders;
  final KpiValue expenses;
  final KpiValue profit;
  final List<SeriesPoint> weekly;
  final List<double> previousWeekly;
  final List<RankedItem> topItems;
}

// --------------------------------------------------------------------- POS

class PosTabChanged {
  const PosTabChanged(this.index);

  final int index;
}

class PosSearchChanged {
  const PosSearchChanged(this.query);

  final String query;
}

class PosCategorySelected {
  const PosCategorySelected(this.categoryId);

  /// `null` selects the "All" chip.
  final int? categoryId;
}

// -------------------------------------------------------------------- cart

class CartItemAdded {
  const CartItemAdded(this.item, {this.quantity = 1});

  final MenuItem item;
  final int quantity;
}

class CartItemIncremented {
  const CartItemIncremented(this.itemId);

  final int itemId;
}

/// Decrementing to zero removes the line — one tap fewer for staff.
class CartItemDecremented {
  const CartItemDecremented(this.itemId);

  final int itemId;
}

class CartItemRemoved {
  const CartItemRemoved(this.itemId);

  final int itemId;
}

/// Loads a parked order back into the cart so it can be changed.
///
/// The POS is where somebody knows how to add and remove things, so editing a
/// draft is done there rather than in a second editor that would have to grow
/// its own menu, its own quantity steppers and its own idea of pricing.
class DraftLoadedIntoCart {
  const DraftLoadedIntoCart(this.draft);

  final DraftOrder draft;
}

class CartCleared {
  const CartCleared();
}

class CartOrderTypeChanged {
  const CartOrderTypeChanged(this.type);

  final OrderType type;
}

class CartTableSelected {
  const CartTableSelected(this.tableId);

  final int? tableId;
}

class CartWaiterSelected {
  const CartWaiterSelected(this.waiterId);

  final int? waiterId;
}

class CartGuestsChanged {
  const CartGuestsChanged(this.guests);

  final int guests;
}

class CartDiscountChanged {
  const CartDiscountChanged(this.discount);

  final double discount;
}

class CartCustomerChanged {
  const CartCustomerChanged({this.name, this.phone, this.notes});

  final String? name;
  final String? phone;
  final String? notes;
}

class CartPaymentChanged {
  const CartPaymentChanged({this.method, this.reference});

  final PaymentMethod? method;
  final String? reference;
}

/// Attaches a customer account to the sale, or takes it off again.
///
/// [customerId] null with [clear] true means walk-in, which also forces the
/// mode back to cash — credit without an account is not a thing the till can
/// represent.
class CartCustomerAttached {
  const CartCustomerAttached({this.customerId, this.mode, this.clear = false});

  final int? customerId;
  final PaymentMode? mode;
  final bool clear;
}

/// Emitted after client-side validation passes. The reducer builds the order,
/// occupies the table, and clears the cart in a single transition.
class OrderPlaced {
  const OrderPlaced({required this.order, required this.byUser});

  final RestaurantOrder order;
  final String byUser;
}

// ------------------------------------------------------------------ orders

class OrderStatusFilterChanged {
  const OrderStatusFilterChanged(this.status);

  final OrderStatus? status;
}

class OrderFiltersChanged {
  const OrderFiltersChanged(this.filters);

  final OrderFilters filters;
}

class OrderSearchChanged {
  const OrderSearchChanged(this.query);

  final String query;
}

class OrderStatusUpdated {
  const OrderStatusUpdated({
    required this.orderId,
    required this.status,
    required this.byUser,
    this.reason,
  });

  final int orderId;
  final OrderStatus status;
  final String byUser;
  final String? reason;
}

// ------------------------------------------------------------------- menu

class MenuTabChanged {
  const MenuTabChanged(this.index);

  final int index;
}

class MenuSearchChanged {
  const MenuSearchChanged(this.query);

  final String query;
}

class MenuCategoryFilterChanged {
  const MenuCategoryFilterChanged(this.categoryId);

  final int? categoryId;
}

class MenuItemAvailabilityToggled {
  const MenuItemAvailabilityToggled(this.itemId);

  final int itemId;
}

class MenuItemSaved {
  const MenuItemSaved(this.item);

  final MenuItem item;
}

class MenuItemDeleted {
  const MenuItemDeleted(this.itemId);

  final int itemId;
}

// ----------------------------------------------------- server-side lists
//
// Mutations return the authoritative collection rather than a patch, so the
// client never has to guess what a write did to the rest of the list. Each of
// these simply replaces a slice.

class CategoriesLoaded {
  const CategoriesLoaded(this.categories);

  final List<MenuCategory> categories;
}

class TablesLoaded {
  const TablesLoaded(this.tables);

  final List<DiningTable> tables;
}

class DraftsLoaded {
  const DraftsLoaded(this.drafts);

  final List<DraftOrder> drafts;
}

/// The till's current state, as the server sees it.
class ShiftStatusLoaded {
  const ShiftStatusLoaded(this.till);

  final ShiftStatus till;
}

class ShiftHistoryLoaded {
  const ShiftHistoryLoaded(this.shifts);

  final List<Shift> shifts;
}

/// A shift that has just been counted and closed.
///
/// Carried separately from the history so the screen can show the figures
/// once, at the only moment they are meant to be seen: after the count.
class ShiftClosed {
  const ShiftClosed(this.shift);

  final Shift shift;
}

/// Puts the reveal away again, so reopening the screen does not show the last
/// count's expected total to whoever is about to make the next one.
class ShiftRevealDismissed {
  const ShiftRevealDismissed();
}
class ExpensesLoaded {
  const ExpensesLoaded(this.expenses);

  final List<Expense> expenses;
}

/// Money movements for the current filters, plus the filters they answer to —
/// carried together so the list and the chips can never disagree about what is
/// being shown.
class TransactionsLoaded {
  const TransactionsLoaded(this.transactions, this.filters);

  final List<AccountTransaction> transactions;
  final AccountFilters filters;
}

class PaymentMethodsLoaded {
  const PaymentMethodsLoaded(this.methods);

  final List<PaymentMethodRecord> methods;
}

class NotificationsLoaded {
  const NotificationsLoaded(this.messages);

  final List<AppNotification> messages;
}

// -------------------------------------------------------------- customers

class CustomersLoaded {
  const CustomersLoaded(this.customers);

  final List<Customer> customers;
}

/// One customer with their ledger attached — the profile screen's payload.
class CustomerProfileLoaded {
  const CustomerProfileLoaded(this.customer);

  final Customer customer;
}

class CustomerProfileCleared {
  const CustomerProfileCleared();
}

/// The list narrowing. Carried with the results rather than applied on arrival,
/// so the chips and the rows always describe the same query.
class CustomerQueryChanged {
  const CustomerQueryChanged({this.filter, this.search});

  final CustomerFilter? filter;
  final String? search;
}

class AccountsLoaded {
  const AccountsLoaded(this.accounts);

  final List<Account> accounts;
}

class OrdersLoaded {
  const OrdersLoaded(this.orders);

  final List<RestaurantOrder> orders;
}

/// Replaces one order in place — the response to editing lines, taking a
/// payment or changing status.
class OrderUpdated {
  const OrderUpdated(this.order);

  final RestaurantOrder order;
}

// --------------------------------------------------------------- expenses

class ExpenseKindChanged {
  const ExpenseKindChanged(this.kind);

  final ExpenseKind kind;
}

// ---------------------------------------------------------------- reports

class ReportRangeChanged {
  const ReportRangeChanged(this.range, {this.from, this.to});

  final ReportRange range;
  final DateTime? from;
  final DateTime? to;
}

class ReportFiltersChanged {
  const ReportFiltersChanged(this.filters);

  final ReportFilters filters;
}

class ReportLoadStarted {
  const ReportLoadStarted();
}

class ReportLoaded {
  const ReportLoaded({
    required this.sales,
    required this.orders,
    required this.expenses,
    required this.profit,
    required this.daily,
    required this.hourly,
    required this.byCategory,
    required this.byPayment,
    required this.byWaiter,
    required this.byTable,
    required this.topItems,
    required this.lowItems,
    required this.discounts,
    required this.tax,
    required this.packaging,
    required this.completedOrders,
    required this.cancelledOrders,
    required this.draftOrders,
    required this.dineInOrders,
    required this.takeawayOrders,
    this.cash = const CashSummary(),
    this.receivables = 0,
    this.depositsHeld = 0,
    this.unpaidOrders = 0,
    this.topCustomers = const <CustomerRank>[],
    this.topDebtors = const <CustomerRank>[],
  });

  final KpiValue sales;
  final KpiValue orders;
  final KpiValue expenses;
  final KpiValue profit;
  final List<SeriesPoint> daily;
  final List<SeriesPoint> hourly;
  final List<BreakdownSlice> byCategory;
  final List<BreakdownSlice> byPayment;
  final List<BreakdownSlice> byWaiter;
  final List<BreakdownSlice> byTable;
  final List<RankedItem> topItems;
  final List<RankedItem> lowItems;
  final double discounts;
  final double tax;
  final double packaging;
  final int completedOrders;
  final int cancelledOrders;
  final int draftOrders;
  final int dineInOrders;
  final int takeawayOrders;

  /// The cash-basis half of the picture. Everything above is accrual.
  final CashSummary cash;
  final double receivables;
  final double depositsHeld;

  /// Owed on orders that no customer ledger carries.
  final double unpaidOrders;
  final List<CustomerRank> topCustomers;
  final List<CustomerRank> topDebtors;
}
