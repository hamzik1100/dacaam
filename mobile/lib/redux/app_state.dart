import 'package:flutter/foundation.dart';

import 'states/auth_state.dart';
import 'states/customer_state.dart';
import 'states/dashboard_state.dart';
import 'states/finance_state.dart';
import 'states/menu_state.dart';
import 'states/notification_state.dart';
import 'states/order_state.dart';
import 'states/pos_state.dart';
import 'states/report_state.dart';
import 'states/settings_state.dart';
import 'states/shift_state.dart';

/// The single source of truth.
///
/// One slice per module, mirroring the state list in the product spec. Slices
/// never reach into each other; anything that needs two (cart totals need
/// settings, order placement needs tables) is composed at the reducer or the
/// selector, not stored twice.
@immutable
class AppState {
  const AppState({
    this.auth = const AuthState(),
    this.restaurant = const RestaurantState(),
    this.settings = const SettingsState(),
    this.dashboard = const DashboardState(),
    this.pos = const PosState(),
    this.cart = const CartState(),
    this.orders = const OrderState(),
    this.drafts = const DraftState(),
    this.menu = const MenuState(),
    this.categories = const CategoryState(),
    this.tables = const TableState(),
    this.expenses = const ExpenseState(),
    this.shifts = const ShiftState(),
    this.accounts = const AccountState(),
    this.customers = const CustomerState(),
    this.notifications = const NotificationState(),
    this.reports = const ReportState(),
    this.activeTab = 0,
    this.booted = false,
  });

  final AuthState auth;
  final RestaurantState restaurant;
  final SettingsState settings;
  final DashboardState dashboard;
  final PosState pos;
  final CartState cart;
  final OrderState orders;
  final DraftState drafts;
  final MenuState menu;
  final CategoryState categories;
  final TableState tables;
  final ExpenseState expenses;
  final ShiftState shifts;
  final AccountState accounts;
  final CustomerState customers;
  final NotificationState notifications;
  final ReportState reports;

  /// Index into the six primary bottom-nav destinations.
  final int activeTab;

  /// False until the first data load resolves; drives the splash.
  final bool booted;

  /// Derived once here so the cart, checkout sheet and POS badge can never
  /// disagree about a total.
  CartTotals get cartTotals => CartTotals.of(cart, settings);

  AppState copyWith({
    AuthState? auth,
    RestaurantState? restaurant,
    SettingsState? settings,
    DashboardState? dashboard,
    PosState? pos,
    CartState? cart,
    OrderState? orders,
    DraftState? drafts,
    MenuState? menu,
    CategoryState? categories,
    TableState? tables,
    ExpenseState? expenses,
    ShiftState? shifts,
    AccountState? accounts,
    CustomerState? customers,
    NotificationState? notifications,
    ReportState? reports,
    int? activeTab,
    bool? booted,
  }) {
    return AppState(
      auth: auth ?? this.auth,
      restaurant: restaurant ?? this.restaurant,
      settings: settings ?? this.settings,
      dashboard: dashboard ?? this.dashboard,
      pos: pos ?? this.pos,
      cart: cart ?? this.cart,
      orders: orders ?? this.orders,
      drafts: drafts ?? this.drafts,
      menu: menu ?? this.menu,
      categories: categories ?? this.categories,
      tables: tables ?? this.tables,
      expenses: expenses ?? this.expenses,
      shifts: shifts ?? this.shifts,
      accounts: accounts ?? this.accounts,
      customers: customers ?? this.customers,
      notifications: notifications ?? this.notifications,
      reports: reports ?? this.reports,
      activeTab: activeTab ?? this.activeTab,
      booted: booted ?? this.booted,
    );
  }
}
