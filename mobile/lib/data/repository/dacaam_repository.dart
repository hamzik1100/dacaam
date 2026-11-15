import '../../core/utils/enums.dart';
import '../../redux/actions.dart';
import '../../redux/states/report_state.dart';
import '../../redux/states/settings_state.dart';
import '../../redux/states/customer_state.dart';
import '../models/app_notification.dart';
import '../models/customer.dart';
import '../models/dining_table.dart';
import '../models/finance.dart';
import '../models/menu.dart';
import '../models/order.dart';
import '../models/shift.dart';
import '../../redux/states/finance_state.dart';

/// What the app needs for its first paint.
///
/// [settings] and [dashboard] are nullable because the offline dataset has no
/// server-side settings row and computes its dashboard locally.
class BootstrapPayload {
  const BootstrapPayload({
    required this.bootstrap,
    required this.dashboard,
    this.settings,
  });

  final BootstrapSucceeded bootstrap;
  final DashboardLoaded dashboard;
  final SettingsState? settings;
}

/// The seam between the UI and its data source.
///
/// [MockRepository] serves the seeded in-memory dataset; [ApiRepository] talks
/// to the PHP backend. Nothing above this interface — reducers, effects,
/// screens — can tell which one is in use.
///
/// Dashboard and report results are returned as their Redux action objects
/// rather than a parallel set of DTOs: those actions are already immutable
/// data carriers with exactly the right shape, and a second identical class
/// per payload would only be something to keep in sync.
abstract class DacaamRepository {
  /// Re-establishes a stored session. Returns false when there is none, or
  /// when the stored token has expired or been revoked.
  Future<bool> restoreSession();

  /// Step one: restaurant code, phone, password.
  Future<SignInResult> signIn({
    required String restaurantCode,
    required String phone,
    required String password,
  });

  /// Step two, when [SignInResult.requiresTwoFactor] is true. Accepts a TOTP
  /// code or a recovery code.
  Future<SignInResult> verifyTwoFactor({
    required String challenge,
    required String code,
  });

  Future<BootstrapPayload> bootstrap();

  Future<DashboardLoaded> dashboard();

  Future<ReportLoaded> reports(ReportRange range, {ReportFilters filters});

  /// Commits an order. Implementations must treat the server as authoritative
  /// on pricing — the request carries item ids and quantities, never totals.
  Future<RestaurantOrder> placeOrder(OrderRequest request);

  /// One order, with its audit trail. The list endpoint omits history — it
  /// would mean a query per row — so the details screen fetches the full
  /// record when it opens.
  Future<RestaurantOrder> order(int id);

  Future<RestaurantOrder> setOrderStatus(
    int orderId,
    OrderStatus status, {
    String? reason,
  });

  /// Replaces an open order's lines. Repricing is the server's job, so this
  /// sends item ids and quantities exactly like [placeOrder] does.
  Future<RestaurantOrder> updateOrderItems(
    int orderId,
    List<OrderLine> lines, {
    double? discount,
    String? reason,
  });

  Future<RestaurantOrder> addPayment(
    int orderId, {
    required PaymentMethod method,
    required double amount,
    String reference,
  });

  // ------------------------------------------------------------- drafts

  Future<List<DraftOrder>> drafts();

  /// Creates when [id] is null, updates otherwise.
  Future<DraftOrder> saveDraft(DraftRequest request);

  /// Marks a refused draft cancelled, keeping the row and the reason.
  Future<DraftOrder> cancelDraft(int id, String reason);

  /// Converts a parked draft into a real order.
  ///
  /// The type, table and waiter are passed at this moment rather than taken
  /// from the draft: a dine-in draft parked without a table cannot become an
  /// order while "require table" is on, so the screen asks for what is missing.
  Future<RestaurantOrder> convertDraft(
    int id, {
    PaymentMethod? method,
    OrderType? orderType,
    int? tableId,
    int? waiterId,
  });

  // --------------------------------------------------------------- menu

  Future<MenuItem> saveMenuItem(MenuItem item, {String? reason});

  Future<MenuItem> toggleMenuItem(int id);

  /// Attaches a photograph, or removes it when [base64] is null.
  ///
  /// The bytes are resized on the phone before they get here — see the picker
  /// — so what travels is about 100 KB rather than a 4 MB camera frame.
  Future<MenuItem> setMenuItemImage(int id, String? base64);

  Future<void> deleteMenuItem(int id);

  Future<List<MenuCategory>> saveCategory(MenuCategory category);

  Future<List<MenuCategory>> deleteCategory(int id);

  // ------------------------------------------------------------- tables

  Future<List<DiningTable>> tables();

  Future<List<DiningTable>> saveTable(DiningTable table);

  Future<List<DiningTable>> deleteTable(int id);

  // ----------------------------------------------------------- expenses

  Future<List<Expense>> expenses();

  Future<List<Expense>> saveExpense(ExpenseRequest request);

  // ------------------------------------------------------------- shifts

  /// The open shift on the till, or null. Never carries the expected total.
  Future<ShiftStatus> currentShift();

  Future<ShiftStatus> openShift({required double openingFloat, String notes});

  /// Counts every account and closes the till. The returned shift carries
  /// the figures — the one moment they are meant to be readable.
  Future<Shift> closeShift(
    int id, {
    required Map<int, double> counts,
    String reason,
  });

  Future<List<Shift>> shiftHistory();

  /// One closed shift, in full — the breakdown behind its variance.
  Future<ShiftDetail> shiftDetail(int id);
  /// Voids an expense. Deleting one is not offered anywhere, on purpose.
  Future<List<Expense>> cancelExpense(int id, String reason);

  // ----------------------------------------------------------- accounts

  Future<List<Account>> accounts();

  /// Money movements, newest first. Filters are applied by the server so the
  /// 200-row cap lands on the rows the user asked for rather than on the most
  /// recent ones regardless.
  Future<List<AccountTransaction>> accountTransactions({
    AccountFilters filters = const AccountFilters(),
  });

  Future<List<PaymentMethodRecord>> paymentMethods();

  Future<List<PaymentMethodRecord>> savePaymentMethod({
    int? id,
    String? name,
    bool? isActive,
  });

  /// Deactivates rather than deletes — a method named on real payments has to
  /// keep resolving or those records lose how they were paid.
  Future<List<PaymentMethodRecord>> removePaymentMethod(int id);

  Future<List<Account>> saveAccount({
    int? id,
    String? name,
    String? method,
    double balance,
    bool? isActive,
  });

  Future<List<Account>> removeAccount(int id);

  Future<List<Account>> transfer({
    required int fromAccountId,
    required int toAccountId,
    required double amount,
    String description,
  });

  // ------------------------------------------------------ notifications

  Future<List<AppNotification>> notifications();

  Future<void> markNotificationRead(int id);

  Future<void> markAllNotificationsRead();

  /// Registers this handset for push. Silent when push is unavailable.
  Future<void> registerDevice(String token);

  // ---------------------------------------------------------- customers

  Future<List<Customer>> customers({String search, CustomerFilter filter});

  /// One customer with their ledger. The list carries no ledger — it would be
  /// a query per row — so the profile fetches the full record when it opens.
  Future<Customer> customer(int id);

  /// Creates when [id] is null, updates otherwise.
  Future<Customer> saveCustomer(CustomerRequest request);

  /// Closes an account. Refused by the server while a balance is outstanding:
  /// a customer with money owing is not somebody to lose track of.
  Future<Customer> deactivateCustomer(int id);

  /// Puts an existing order onto a customer's account, moving whatever is
  /// still owed on it to their ledger.
  ///
  /// The resolution for an order left owing money with nobody named against
  /// it. Only the outstanding part moves: an order half-settled at the till
  /// puts the remainder on the tab, never the whole total.
  Future<RestaurantOrder> attachOrderCustomer(
    int orderId, {
    required int customerId,
    required String reason,
  });

  /// A repayment against what they owe. Not revenue — the sale was counted
  /// when the food went out; this is a receivable turning into cash.
  Future<Customer> payCustomer(
    int id, {
    required double amount,
    required PaymentMethod method,
    String description,
  });

  /// Money handed over in advance, to be eaten against later.
  Future<Customer> depositForCustomer(
    int id, {
    required double amount,
    required PaymentMethod method,
    String description,
  });

  /// A balance moved by hand. Signed: positive adds to what they owe, negative
  /// forgives it. The reason is mandatory, because this is the only way a debt
  /// disappears without a payment behind it.
  Future<Customer> adjustCustomer(
    int id, {
    required double amount,
    required String reason,
  });

  // ----------------------------------------------------------- settings

  /// Persists restaurant settings and returns what the server stored.
  ///
  /// The returned state replaces the local one rather than being assumed: the
  /// server clamps values the client would happily send — a tax rate above 100,
  /// a negative fee — and the app should show what was actually saved.
  Future<SettingsState> saveSettings(SettingsState settings);

  Future<void> signOut();
}

/// A draft to create or update. `id == null` means create.
class DraftRequest {
  const DraftRequest({
    required this.customerName,
    required this.type,
    required this.lines,
    this.id,
    this.customerPhone = '',
    this.tableId,
    this.notes = '',
  });

  final int? id;
  final String customerName;
  final String customerPhone;
  final OrderType type;
  final List<OrderLine> lines;
  final int? tableId;
  final String notes;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'customer_name': customerName,
    'order_type': type.api,
    'items': lines
        .map(
          (OrderLine l) => <String, dynamic>{
            'menu_item_id': l.itemId,
            'quantity': l.quantity,
          },
        )
        .toList(),
    if (customerPhone.isNotEmpty) 'customer_phone': customerPhone,
    if (tableId != null) 'table_id': tableId,
    if (notes.isNotEmpty) 'notes': notes,
  };
}

/// A customer to create or update. `id == null` means create.
///
/// No balance field, deliberately. The balance is the sum of the ledger, and a
/// field that let it be typed over would make the ledger decorative.
class CustomerRequest {
  const CustomerRequest({
    required this.name,
    this.id,
    this.phone = '',
    this.address = '',
    this.notes = '',
    this.creditLimit = 0,
    this.isActive,
    this.reason,
  });

  final int? id;
  final String name;
  final String phone;
  final String address;
  final String notes;

  /// Zero means no credit at all — a customer is trusted only once somebody
  /// decides how far.
  final double creditLimit;
  final bool? isActive;

  /// Why the record changed. Raising a credit limit without one is exactly
  /// what an auditor asks about later.
  final String? reason;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'name': name,
    'phone': phone,
    'address': address,
    'notes': notes,
    'credit_limit': creditLimit,
    if (isActive != null) 'is_active': isActive,
    if (reason != null && reason!.isNotEmpty) 'reason': reason,
  };
}

/// An expense to create or update. `id == null` means create.
class ExpenseRequest {
  const ExpenseRequest({
    required this.name,
    required this.amount,
    required this.kind,
    required this.method,
    this.id,
    this.categoryId,
    this.date,
    this.notes = '',
    this.recurring = false,
    this.reason,
  });

  final int? id;
  final String name;
  final double amount;
  final ExpenseKind kind;
  final PaymentMethod method;
  final int? categoryId;
  final DateTime? date;
  final String notes;
  final bool recurring;

  /// Why an existing expense was corrected — goes straight into the audit
  /// trail, because a changed amount without a reason is what an auditor
  /// notices.
  final String? reason;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'name': name,
    'amount': amount,
    'kind': kind.api,
    'method': method.api,
    'is_recurring': recurring,
    if (categoryId != null) 'expense_category_id': categoryId,
    if (date != null) 'expense_date': date!.toIso8601String().substring(0, 10),
    if (notes.isNotEmpty) 'notes': notes,
    if (reason != null && reason!.isNotEmpty) 'reason': reason,
  };
}

/// The outcome of a sign-in step: either a session, or a demand for a code.
class SignInResult {
  const SignInResult._({
    required this.requiresTwoFactor,
    this.challenge,
    this.userName = '',
    this.restaurantName = '',
    this.mustChangePassword = false,
    this.mustEnrolTwoFactor = false,
  });

  const SignInResult.session({
    bool mustChangePassword = false,
    bool mustEnrolTwoFactor = false,
  }) : this._(
         requiresTwoFactor: false,
         mustChangePassword: mustChangePassword,
         mustEnrolTwoFactor: mustEnrolTwoFactor,
       );

  const SignInResult.twoFactorRequired({
    required String challenge,
    String userName = '',
    String restaurantName = '',
  }) : this._(
         requiresTwoFactor: true,
         challenge: challenge,
         userName: userName,
         restaurantName: restaurantName,
       );

  final bool requiresTwoFactor;
  final String? challenge;
  final String userName;
  final String restaurantName;

  /// Obligations to resolve before the user can settle into normal work.
  final bool mustChangePassword;
  final bool mustEnrolTwoFactor;
}

/// What the client asks for when checking out.
///
/// Note the absence of any money field: prices, tax and the packaging fee are
/// resolved by whoever fulfils the request.
class OrderRequest {
  const OrderRequest({
    required this.type,
    required this.lines,
    this.tableId,
    this.waiterId,
    this.guests = 0,
    this.discount = 0,
    this.customerName = '',
    this.customerPhone = '',
    this.notes = '',
    this.paymentMethod,
    this.paymentReference = '',
    this.settingsPackagingFee = 0,
    this.settingsTaxFraction = 0,
    this.customerId,
    this.paymentMode = PaymentMode.cash,
  });

  final OrderType type;
  final List<OrderLine> lines;
  final int? tableId;
  final int? waiterId;
  final int guests;
  final double discount;
  final String customerName;
  final String customerPhone;
  final String notes;
  final PaymentMethod? paymentMethod;
  final String paymentReference;

  /// Current fee/tax *settings*, not computed prices.
  ///
  /// Only the offline repository reads these, so an order placed with no
  /// backend still honours the configured fee. They are deliberately absent
  /// from [toJson]: the server reads its own settings row and would ignore
  /// them anyway.
  final double settingsPackagingFee;
  final double settingsTaxFraction;

  /// The account the sale goes on. Null is a walk-in paying at the till.
  final int? customerId;

  /// How they are settling: now, on the tab, or out of their deposit. The
  /// server refuses credit and wallet without a [customerId] rather than
  /// trusting the client to have checked.
  final PaymentMode paymentMode;

  /// JSON body for `POST /orders`.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'order_type': type.api,
    'items': lines
        .map(
          (OrderLine l) => <String, dynamic>{
            'menu_item_id': l.itemId,
            'quantity': l.quantity,
          },
        )
        .toList(),
    if (tableId != null) 'table_id': tableId,
    if (waiterId != null) 'waiter_id': waiterId,
    if (guests > 0) 'guests': guests,
    if (discount > 0) 'discount': discount,
    if (customerName.isNotEmpty) 'customer_name': customerName,
    if (customerPhone.isNotEmpty) 'customer_phone': customerPhone,
    if (notes.isNotEmpty) 'notes': notes,
    if (paymentMethod != null) 'payment_method': paymentMethod!.api,
    if (paymentReference.isNotEmpty) 'payment_reference': paymentReference,
    if (customerId != null) 'customer_id': customerId,
    if (paymentMode != PaymentMode.cash) 'payment_mode': paymentMode.api,
  };
}

/// What the till looks like right now.
///
/// `shift` is null when nothing is open. `lastClose` is what the previous
/// person counted — the number whoever opens next needs in order to know what
/// they are starting from, and the one that reveals money gone overnight.
class ShiftStatus {
  const ShiftStatus({
    this.shift,
    this.lastClose,
    this.accountId,
    this.accounts = const <CountableAccount>[],
    this.expenses = const ShiftExpenses(),
  });

  final Shift? shift;
  final double? lastClose;
  final int? accountId;

  /// Every account the close has to ask about — names only, no balances.
  final List<CountableAccount> accounts;

  /// What has gone out of the tills since the shift opened.
  final ShiftExpenses expenses;

  bool get isOpen => shift != null;
}