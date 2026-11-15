import 'dart:math';

import '../../core/utils/enums.dart';
import 'api_client.dart';

/// Endpoint surface of the DACAAM REST API.
///
/// One method per route, returning raw decoded JSON. Model construction is the
/// mappers' job and state shaping is the repository's — this layer only knows
/// URLs, verbs and query parameters.
class DacaamApi {
  DacaamApi(this._client);

  final ApiClient _client;

  ApiClient get client => _client;

  // --------------------------------------------------------------- auth

  Future<Map<String, dynamic>> login({
    required String restaurantCode,
    required String phone,
    required String password,
  }) async {
    final dynamic data = await _client.post(
      '/auth/login',
      body: <String, dynamic>{
        'restaurant_code': restaurantCode,
        'phone': phone,
        'password': password,
      },
    );

    final Map<String, dynamic> json = (data as Map).cast<String, dynamic>();
    // A 2FA account returns a challenge, not a token; only adopt a session
    // when one was actually issued.
    if (json['token'] != null) {
      _client.token = '${json['token']}';
    }

    return json;
  }

  Future<Map<String, dynamic>> verifyTwoFactor({
    required String challenge,
    required String code,
  }) async {
    final dynamic data = await _client.post(
      '/auth/2fa/verify',
      body: <String, dynamic>{'challenge': challenge, 'code': code},
    );

    final Map<String, dynamic> json = (data as Map).cast<String, dynamic>();
    if (json['token'] != null) {
      _client.token = '${json['token']}';
    }

    return json;
  }

  // ----------------------------------------------------------- security

  Future<Map<String, dynamic>> securityOverview() async =>
      ((await _client.get('/security/overview')) as Map)
          .cast<String, dynamic>();

  Future<Map<String, dynamic>> startTwoFactor() async =>
      ((await _client.post('/security/2fa/setup')) as Map)
          .cast<String, dynamic>();

  Future<Map<String, dynamic>> confirmTwoFactor(String code) async =>
      ((await _client.post(
                '/security/2fa/confirm',
                body: <String, dynamic>{'code': code},
              ))
              as Map)
          .cast<String, dynamic>();

  Future<Map<String, dynamic>> disableTwoFactor(String password) async =>
      ((await _client.post(
                '/security/2fa/disable',
                body: <String, dynamic>{'password': password},
              ))
              as Map)
          .cast<String, dynamic>();

  Future<Map<String, dynamic>> regenerateRecoveryCodes(String password) async =>
      ((await _client.post(
                '/security/2fa/recovery-codes',
                body: <String, dynamic>{'password': password},
              ))
              as Map)
          .cast<String, dynamic>();

  Future<List<dynamic>> sessions() async =>
      (await _client.get('/security/sessions')) as List<dynamic>;

  Future<void> revokeSession(int id) =>
      _client.delete('/security/sessions/$id');

  Future<Map<String, dynamic>> revokeOtherSessions() async =>
      ((await _client.post('/security/sessions/revoke-others')) as Map)
          .cast<String, dynamic>();

  Future<List<dynamic>> loginHistory() async =>
      (await _client.get('/security/login-history')) as List<dynamic>;

  Future<Map<String, dynamic>> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async =>
      ((await _client.post(
                '/security/password',
                body: <String, dynamic>{
                  'current_password': currentPassword,
                  'new_password': newPassword,
                },
              ))
              as Map)
          .cast<String, dynamic>();

  Future<Map<String, dynamic>> securityPolicy() async =>
      ((await _client.get('/security/policy')) as Map).cast<String, dynamic>();

  Future<Map<String, dynamic>> updateSecurityPolicy(
    Map<String, dynamic> payload,
  ) async => ((await _client.put('/security/policy', body: payload)) as Map)
      .cast<String, dynamic>();

  // -------------------------------------------------- users & permissions

  Future<Map<String, dynamic>> createUser(Map<String, dynamic> payload) async =>
      ((await _client.post('/users', body: payload)) as Map)
          .cast<String, dynamic>();

  Future<Map<String, dynamic>> updateUser(
    int id,
    Map<String, dynamic> payload,
  ) async => ((await _client.put('/users/$id', body: payload)) as Map)
      .cast<String, dynamic>();

  Future<Map<String, dynamic>> setUserPermissions(
    int id,
    Map<String, bool> permissions,
  ) async =>
      ((await _client.put(
                '/users/$id/permissions',
                body: <String, dynamic>{'permissions': permissions},
              ))
              as Map)
          .cast<String, dynamic>();

  Future<void> deactivateUser(int id) => _client.delete('/users/$id');

  Future<List<dynamic>> roles() async =>
      (await _client.get('/roles')) as List<dynamic>;

  Future<List<dynamic>> permissions() async =>
      (await _client.get('/permissions')) as List<dynamic>;

  Future<void> logout() async {
    try {
      await _client.post('/auth/logout');
    } on ApiException {
      // A token that is already gone server-side is still gone locally; the
      // user must not be blocked from signing out by a failed round trip.
    } finally {
      _client.clearSession();
    }
  }

  Future<Map<String, dynamic>> me() async =>
      ((await _client.get('/auth/me')) as Map).cast<String, dynamic>();

  // ---------------------------------------------------------- bootstrap

  Future<Map<String, dynamic>> bootstrap() async =>
      ((await _client.get('/bootstrap')) as Map).cast<String, dynamic>();

  // ------------------------------------------------------------- orders

  Future<List<dynamic>> orders({
    OrderStatus? status,
    OrderType? type,
    String? range,
    String? search,
    int? limit,
  }) async =>
      (await _client.get(
            '/orders',
            query: <String, dynamic>{
              'status': status?.api,
              'order_type': type?.api,
              'range': range,
              'search': search,
              'limit': limit,
            },
          ))
          as List<dynamic>;

  Future<Map<String, dynamic>> order(int id) async =>
      ((await _client.get('/orders/$id')) as Map).cast<String, dynamic>();

  Future<Map<String, dynamic>> createOrder(
    Map<String, dynamic> payload,
  ) async => ((await _client.post('/orders', body: payload)) as Map)
      .cast<String, dynamic>();

  Future<Map<String, dynamic>> setOrderStatus(
    int id,
    OrderStatus status, {
    String? reason,
  }) async =>
      ((await _client.patch(
                '/orders/$id/status',
                body: <String, dynamic>{
                  'status': status.api,
                  if (reason != null && reason.isNotEmpty) 'reason': reason,
                },
              ))
              as Map)
          .cast<String, dynamic>();

  Future<Map<String, dynamic>> addPayment(
    int orderId, {
    required PaymentMethod method,
    required double amount,
    String reference = '',
  }) async =>
      ((await _client.post(
                '/orders/$orderId/payments',
                body: <String, dynamic>{
                  'method': method.api,
                  'amount': amount,
                  'reference': reference,
                },
              ))
              as Map)
          .cast<String, dynamic>();

  // ------------------------------------------------------------- drafts

  Future<List<dynamic>> drafts() async =>
      (await _client.get('/drafts')) as List<dynamic>;

  Future<Map<String, dynamic>> createDraft(
    Map<String, dynamic> payload,
  ) async => ((await _client.post('/drafts', body: payload)) as Map)
      .cast<String, dynamic>();

  Future<Map<String, dynamic>> updateDraft(
    int id,
    Map<String, dynamic> payload,
  ) async => ((await _client.put('/drafts/$id', body: payload)) as Map)
      .cast<String, dynamic>();

  Future<Map<String, dynamic>> updateOrderItems(
    int id,
    Map<String, dynamic> payload,
  ) async => ((await _client.put('/orders/$id/items', body: payload)) as Map)
      .cast<String, dynamic>();

  Future<Map<String, dynamic>> convertDraft(
    int id, {
    PaymentMethod? method,
    OrderType? orderType,
    int? tableId,
    int? waiterId,
  }) async =>
      ((await _client.post(
                '/drafts/$id/convert',
                body: <String, dynamic>{
                  if (method != null) 'payment_method': method.api,
                  'order_type': ?orderType?.api,
                  'table_id': ?tableId,
                  'waiter_id': ?waiterId,
                },
              ))
              as Map)
          .cast<String, dynamic>();

  /// Cancels rather than deletes: a refused draft is kept, with the reason.
  Future<Map<String, dynamic>> cancelDraft(int id, String reason) async =>
      ((await _client.post(
                '/drafts/$id/cancel',
                body: <String, dynamic>{'reason': reason},
              ))
              as Map)
          .cast<String, dynamic>();

  // --------------------------------------------------------------- menu

  Future<List<dynamic>> menuItems() async =>
      (await _client.get('/menu/items')) as List<dynamic>;

  Future<List<dynamic>> categories() async =>
      (await _client.get('/menu/categories')) as List<dynamic>;

  Future<Map<String, dynamic>> createMenuItem(
    Map<String, dynamic> payload,
  ) async => ((await _client.post('/menu/items', body: payload)) as Map)
      .cast<String, dynamic>();

  Future<Map<String, dynamic>> updateMenuItem(
    int id,
    Map<String, dynamic> payload,
  ) async => ((await _client.put('/menu/items/$id', body: payload)) as Map)
      .cast<String, dynamic>();

  Future<Map<String, dynamic>> toggleMenuItem(int id) async =>
      ((await _client.patch('/menu/items/$id/availability')) as Map)
          .cast<String, dynamic>();

  /// Uploads a menu photograph, already resized by the phone.
  ///
  /// Base64 in the JSON body rather than a multipart form: it is one request
  /// per photograph, the whole API already speaks JSON, and the third extra
  /// in bytes costs less than a second transport nobody else uses.
  Future<Map<String, dynamic>> uploadMenuImage(int id, String base64) async =>
      ((await _client.post(
                '/menu/items/$id/image',
                body: <String, dynamic>{'image': base64},
              ))
              as Map)
          .cast<String, dynamic>();

  Future<Map<String, dynamic>> deleteMenuImage(int id) async =>
      ((await _client.delete('/menu/items/$id/image')) as Map)
          .cast<String, dynamic>();

  Future<void> deleteMenuItem(int id) => _client.delete('/menu/items/$id');

  Future<Map<String, dynamic>> createCategory(
    Map<String, dynamic> payload,
  ) async => ((await _client.post('/menu/categories', body: payload)) as Map)
      .cast<String, dynamic>();

  Future<Map<String, dynamic>> updateCategory(
    int id,
    Map<String, dynamic> payload,
  ) async => ((await _client.put('/menu/categories/$id', body: payload)) as Map)
      .cast<String, dynamic>();

  Future<void> deleteCategory(int id) => _client.delete('/menu/categories/$id');

  // ------------------------------------------------------------- tables

  Future<List<dynamic>> tables() async =>
      (await _client.get('/tables')) as List<dynamic>;

  Future<Map<String, dynamic>> createTable(
    Map<String, dynamic> payload,
  ) async => ((await _client.post('/tables', body: payload)) as Map)
      .cast<String, dynamic>();

  Future<Map<String, dynamic>> updateTable(
    int id,
    Map<String, dynamic> payload,
  ) async => ((await _client.put('/tables/$id', body: payload)) as Map)
      .cast<String, dynamic>();

  Future<void> deleteTable(int id) => _client.delete('/tables/$id');

  // ----------------------------------------------------------- expenses

  Future<List<dynamic>> expenses() async =>
      (await _client.get('/expenses')) as List<dynamic>;

  Future<List<dynamic>> expenseCategories() async =>
      (await _client.get('/expense-categories')) as List<dynamic>;

  Future<Map<String, dynamic>> createExpense(
    Map<String, dynamic> payload,
  ) async => ((await _client.post('/expenses', body: payload)) as Map)
      .cast<String, dynamic>();

  Future<Map<String, dynamic>> updateExpense(
    int id,
    Map<String, dynamic> payload,
  ) async => ((await _client.put('/expenses/$id', body: payload)) as Map)
      .cast<String, dynamic>();

  // ------------------------------------------------------------- shifts

  /// What is open on the till, without the expected total.
  ///
  /// The server withholds that figure from whoever is about to count the
  /// drawer, so it is not here to be shown by accident either.
  Future<Map<String, dynamic>> currentShift() async =>
      ((await _client.get('/shifts/current')) as Map).cast<String, dynamic>();

  Future<Map<String, dynamic>> openShift({
    required double openingFloat,
    int? accountId,
    String notes = '',
  }) async =>
      ((await _client.post(
        '/shifts',
        body: <String, dynamic>{
          'opening_float': openingFloat,
          // Dropped when null so the server falls back to the restaurant's own
          // cash drawer, which is the only till there is in almost every case.
          'account_id': ?accountId,
          if (notes.isNotEmpty) 'notes': notes,
        },
      )) as Map)
          .cast<String, dynamic>();

  /// Counts the drawer. The expected total comes back in the response — after
  /// the count is committed, never before.
  /// Counts every account and closes the till.
  ///
  /// One figure per account, not one for the whole till: cash short by twenty
  /// thousand while Zaad is over by twenty thousand nets to nothing and is two
  /// separate problems. The server refuses a partial set.
  Future<Map<String, dynamic>> closeShift(
    int id, {
    required Map<int, double> counts,
    String reason = '',
    String notes = '',
  }) async =>
      ((await _client.post(
        '/shifts/$id/close',
        body: <String, dynamic>{
          'counts': counts.entries
              .map(
                (MapEntry<int, double> e) => <String, dynamic>{
                  'account_id': e.key,
                  'counted': e.value,
                },
              )
              .toList(),
          if (reason.isNotEmpty) 'reason': reason,
          if (notes.isNotEmpty) 'notes': notes,
        },
      )) as Map)
          .cast<String, dynamic>();

  /// One shift, in full. Requires shifts.view — it carries the expected total,
  /// which is exactly what the person counting must not be shown.
  Future<Map<String, dynamic>> shift(int id) async =>
      ((await _client.get('/shifts/$id')) as Map).cast<String, dynamic>();
  Future<List<dynamic>> shiftHistory() async =>
      (await _client.get('/shifts')) as List<dynamic>;
  /// Voids an expense. There is no delete — the server removed the route,
  /// because an expense that can vanish leaves the books unable to explain
  /// a figure that was there yesterday.
  Future<Map<String, dynamic>> cancelExpense(int id, String reason) async =>
      ((await _client.post(
        '/expenses/$id/cancel',
        body: <String, dynamic>{'reason': reason},
      )) as Map)
          .cast<String, dynamic>();

  Future<Map<String, dynamic>> createExpenseCategory(
    Map<String, dynamic> payload,
  ) async => ((await _client.post('/expense-categories', body: payload)) as Map)
      .cast<String, dynamic>();

  // ----------------------------------------------------------- accounts

  Future<List<dynamic>> accounts() async =>
      (await _client.get('/accounts')) as List<dynamic>;

  Future<List<dynamic>> accountTransactions({
    int? accountId,
    String? kind,
    String? range,
    String? search,
  }) async =>
      (await _client.get(
            '/accounts/transactions',
            query: <String, dynamic>{
              'account_id': accountId,
              'kind': kind,
              'range': range,
              'search': search,
            },
          ))
          as List<dynamic>;

  // --------------------------------------------------- notifications

  Future<List<dynamic>> notifications() async =>
      (await _client.get('/notifications')) as List<dynamic>;

  Future<void> markNotificationRead(int id) =>
      _client.post('/notifications/$id/read');

  Future<void> markAllNotificationsRead() =>
      _client.post('/notifications/read-all');

  /// Tells the server where to deliver. Sent on every launch that has a
  /// session, because Android reissues tokens without warning.
  Future<void> registerDevice(String token) => _client.post(
    '/devices',
    body: <String, dynamic>{'token': token, 'platform': 'android'},
  );

  // ------------------------------------------------------- customers

  Future<List<dynamic>> customers({String? search, String? filter}) async =>
      (await _client.get(
            '/customers',
            query: <String, dynamic>{'search': search, 'filter': filter},
          ))
          as List<dynamic>;

  Future<Map<String, dynamic>> customer(int id) async =>
      ((await _client.get('/customers/$id')) as Map).cast<String, dynamic>();

  Future<Map<String, dynamic>> saveCustomer(
    Map<String, dynamic> payload, {
    int? id,
  }) async =>
      ((id == null
                  ? await _client.post('/customers', body: payload)
                  : await _client.put('/customers/$id', body: payload))
              as Map)
          .cast<String, dynamic>();

  Future<void> deleteCustomer(int id) => _client.delete('/customers/$id');

  /// Puts an existing unpaid order onto a customer's account.
  Future<Map<String, dynamic>> attachOrderCustomer(
    int orderId,
    int customerId,
    String reason,
  ) async =>
      ((await _client.patch(
                '/orders/$orderId/customer',
                body: <String, dynamic>{
                  'customer_id': customerId,
                  'reason': reason,
                },
              ))
              as Map)
          .cast<String, dynamic>();

  /// kind is payment, deposit or adjust — the three ways a balance moves by
  /// hand, each its own endpoint so the server can guard them separately.
  Future<Map<String, dynamic>> customerLedgerPost(
    int id,
    String kind,
    Map<String, dynamic> body,
  ) async =>
      ((await _client.post(
                '/customers/$id/$kind',
                // One key per call. A retry of *this* request carries the same
                // key and is ignored by the server; a genuine second deposit is
                // a second call and gets a new one.
                body: <String, dynamic>{...body, 'request_key': _requestKey()},
              ))
              as Map)
          .cast<String, dynamic>();

  /// A key unique enough to name one tap.
  ///
  /// Not a UUID package for one string: microseconds plus a counter plus a
  /// random tail is unique within a device, and the server scopes keys per
  /// restaurant, which is as far as the guarantee needs to reach.
  static int _keySeq = 0;

  static String _requestKey() {
    _keySeq++;

    return '${DateTime.now().microsecondsSinceEpoch}-$_keySeq-'
        '${Random().nextInt(0x7fffffff)}';
  }

  // ------------------------------------------------- payment methods

  Future<List<dynamic>> paymentMethods() async =>
      (await _client.get('/payment-methods')) as List<dynamic>;

  Future<Map<String, dynamic>> createPaymentMethod(String name) async =>
      ((await _client.post(
                '/payment-methods',
                body: <String, dynamic>{'name': name},
              ))
              as Map)
          .cast<String, dynamic>();

  Future<Map<String, dynamic>> updatePaymentMethod(
    int id, {
    String? name,
    bool? isActive,
  }) async =>
      ((await _client.put(
                '/payment-methods/$id',
                body: <String, dynamic>{'name': ?name, 'is_active': ?isActive},
              ))
              as Map)
          .cast<String, dynamic>();

  Future<void> deletePaymentMethod(int id) =>
      _client.delete('/payment-methods/$id');

  // ------------------------------------------------------- accounts

  Future<Map<String, dynamic>> createAccount({
    required String name,
    required String method,
    double balance = 0,
  }) async =>
      ((await _client.post(
                '/accounts',
                body: <String, dynamic>{
                  'name': name,
                  'method': method,
                  'balance': balance,
                },
              ))
              as Map)
          .cast<String, dynamic>();

  Future<Map<String, dynamic>> updateAccount(
    int id, {
    String? name,
    bool? isActive,
  }) async =>
      ((await _client.put(
                '/accounts/$id',
                body: <String, dynamic>{'name': ?name, 'is_active': ?isActive},
              ))
              as Map)
          .cast<String, dynamic>();

  Future<void> deleteAccount(int id) => _client.delete('/accounts/$id');

  Future<Map<String, dynamic>> transfer({
    required int fromAccountId,
    required int toAccountId,
    required double amount,
    String description = '',
  }) async =>
      ((await _client.post(
                '/accounts/transfer',
                body: <String, dynamic>{
                  'from_account_id': fromAccountId,
                  'to_account_id': toAccountId,
                  'amount': amount,
                  if (description.isNotEmpty) 'description': description,
                },
              ))
              as Map)
          .cast<String, dynamic>();

  // ------------------------------------------------------------ reports

  Future<Map<String, dynamic>> reportSummary(
    String range, {
    Map<String, dynamic> filters = const <String, dynamic>{},
  }) async =>
      ((await _client.get(
                '/reports/summary',
                query: <String, dynamic>{'range': range, ...filters},
              ))
              as Map)
          .cast<String, dynamic>();

  /// Returns the CSV body. The endpoint answers text/csv, so this bypasses
  /// the JSON envelope the rest of the client expects.
  Future<String> exportReport({
    required String range,
    required String type,
    Map<String, dynamic> filters = const <String, dynamic>{},
  }) => _client.getRaw(
    '/reports/export',
    query: <String, dynamic>{'range': range, 'type': type, ...filters},
  );

  Future<Map<String, dynamic>> dashboard() async =>
      ((await _client.get('/reports/dashboard')) as Map)
          .cast<String, dynamic>();

  // ----------------------------------------------------- password reset

  /// Always succeeds as far as the caller can tell. The server answers the
  /// same way whether or not the account exists, so that this endpoint cannot
  /// be used to find out which phone numbers are registered.
  Future<void> forgotPassword({
    required String restaurantCode,
    required String phone,
  }) async {
    await _client.post(
      '/auth/password/forgot',
      body: <String, dynamic>{
        'restaurant_code': restaurantCode,
        'phone': phone,
      },
    );
  }

  Future<void> resetPassword({
    required String token,
    required String newPassword,
  }) async {
    await _client.post(
      '/auth/password/reset',
      body: <String, dynamic>{'token': token, 'new_password': newPassword},
    );
  }

  // ----------------------------------------------------------- settings

  Future<Map<String, dynamic>> settings() async =>
      ((await _client.get('/settings')) as Map).cast<String, dynamic>();

  Future<Map<String, dynamic>> updateSettings(
    Map<String, dynamic> payload,
  ) async => ((await _client.put('/settings', body: payload)) as Map)
      .cast<String, dynamic>();

  // -------------------------------------------------------------- users

  Future<List<dynamic>> users() async =>
      (await _client.get('/users')) as List<dynamic>;

  Future<List<dynamic>> auditLogs({String? module}) async =>
      (await _client.get(
            '/audit-logs',
            query: <String, dynamic>{'module': module},
          ))
          as List<dynamic>;
}
