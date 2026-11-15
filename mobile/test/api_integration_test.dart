import 'dart:io';

import 'package:dacaam_pos/core/utils/enums.dart';
import 'package:dacaam_pos/data/api/api_client.dart';
import 'package:dacaam_pos/data/api/dacaam_api.dart';
import 'package:dacaam_pos/data/api/token_store.dart';
import 'package:dacaam_pos/data/models/finance.dart';
import 'package:dacaam_pos/data/models/menu.dart';
import 'package:dacaam_pos/data/models/order.dart';
import 'package:dacaam_pos/data/repository/api_repository.dart';
import 'package:dacaam_pos/data/repository/dacaam_repository.dart';
import 'package:dacaam_pos/redux/actions.dart';
import 'package:flutter_test/flutter_test.dart';

/// Live integration against the PHP backend.
///
/// Skips itself when the API is not running, so `flutter test` stays green on
/// a machine with no backend:
///
///   cd backend
///   php bin/migrate.php --fresh --seed
///   php -S 127.0.0.1:8090 -t public public/index.php
///   cd ../mobile && flutter test test/api_integration_test.dart
const String kBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://127.0.0.1:8090/api/v1',
);

Future<bool> _apiIsUp() async {
  try {
    final HttpClient client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 2);
    final HttpClientRequest request = await client.getUrl(
      Uri.parse('$kBaseUrl/health'),
    );
    final HttpClientResponse response = await request.close();
    await response.drain<void>();
    client.close();

    return response.statusCode == 200;
  } catch (_) {
    return false;
  }
}

/// A signed-in repository for the given tenant.
///
/// Each test gets its own client and its own token — sessions must never leak
/// between them, which is exactly what a shared static would do.
Future<ApiRepository> _repo({
  String code = 'HAMZE',
  String phone = '0634567890',
  String password = 'admin123',
}) async {
  final ApiRepository repo = ApiRepository(
    api: DacaamApi(ApiClient(baseUrl: kBaseUrl)),
    tokens: MemoryTokenStore(),
  );

  final SignInResult result = await repo.signIn(
    restaurantCode: code,
    phone: phone,
    password: password,
  );
  expect(result.requiresTwoFactor, isFalse, reason: 'seeded users have no 2FA');

  // Nothing can be sold before a till is open — that is the rule the shift
  // feature enforces, not an inconvenience — so the suite opens one exactly as
  // a restaurant does at the start of service. Idempotent: an open till is left
  // as it is, because a second open is refused by the database.
  try {
    final ShiftStatus till = await repo.currentShift();

    if (!till.isOpen) {
      await repo.openShift(openingFloat: 100000);
    }
  } on ApiException {
    // A server that predates shifts, or a user without the right to open one.
    // Neither is this helper's problem to solve.
  }

  return repo;
}

void main() {
  late bool up;

  setUpAll(() async {
    up = await _apiIsUp();
    if (!up) {
      // ignore: avoid_print
      print('SKIPPING: no API at $kBaseUrl');
    }
  });

  test('a wrong password is rejected as an ApiException', () async {
    if (!up) return;

    final ApiRepository repo = ApiRepository(
      api: DacaamApi(ApiClient(baseUrl: kBaseUrl)),
      tokens: MemoryTokenStore(),
    );

    await expectLater(
      repo.signIn(
        restaurantCode: 'HAMZE',
        phone: '0634567890',
        password: 'definitely-wrong',
      ),
      throwsA(
        isA<ApiException>().having(
          (ApiException e) => e.isUnauthorized,
          'isUnauthorized',
          isTrue,
        ),
      ),
    );
  });

  test('a stored session is restored without signing in again', () async {
    if (!up) return;

    final MemoryTokenStore store = MemoryTokenStore();
    final ApiRepository first = ApiRepository(
      api: DacaamApi(ApiClient(baseUrl: kBaseUrl)),
      tokens: store,
    );
    await first.signIn(
      restaurantCode: 'HAMZE',
      phone: '0634567890',
      password: 'admin123',
    );

    // A second client, same stored token — this is what happens when the app
    // is reopened mid-shift.
    final ApiRepository second = ApiRepository(
      api: DacaamApi(ApiClient(baseUrl: kBaseUrl)),
      tokens: store,
    );
    expect(await second.restoreSession(), isTrue);

    final BootstrapPayload payload = await second.bootstrap();
    expect(payload.bootstrap.restaurant.slug, 'HAMZE');

    // Signing out invalidates it for everyone holding that token.
    await second.signOut();
    expect(await second.restoreSession(), isFalse);
  });

  test('a revoked token cannot be restored', () async {
    if (!up) return;

    final MemoryTokenStore store = MemoryTokenStore();
    final ApiRepository repo = ApiRepository(
      api: DacaamApi(ApiClient(baseUrl: kBaseUrl)),
      tokens: store,
    );
    await repo.signIn(
      restaurantCode: 'HAMZE',
      phone: '0631122334', // Faadumo, operator
      password: 'admin123',
    );
    await repo.signOut();

    // Put the dead token back and try to adopt it.
    await store.write(
      const StoredSession(token: 'not-a-real-token', restaurantCode: 'HAMZE'),
    );
    final ApiRepository reopened = ApiRepository(
      api: DacaamApi(ApiClient(baseUrl: kBaseUrl)),
      tokens: store,
    );

    expect(await reopened.restoreSession(), isFalse);
    expect(await store.read(), isNull, reason: 'the dead token is discarded');
  });

  test('bootstrap loads the signed-in tenant', () async {
    if (!up) return;

    final BootstrapPayload payload = await (await _repo()).bootstrap();
    final BootstrapSucceeded data = payload.bootstrap;

    expect(data.restaurant.slug, 'HAMZE');
    expect(data.restaurant.name, 'Hamze Restaurant');
    expect(data.items.length, 18);
    expect(data.categories.length, 6);
    // Tables are deactivated rather than deleted — past orders point at them —
    // so the count only ever grows. Assert the seeded floor is present rather
    // than an exact number another suite's fixtures can perturb.
    expect(data.tables.length, greaterThanOrEqualTo(12));
    expect(
      data.tables.map((dynamic t) => t.name as String),
      contains('VIP Hall'),
    );
    expect(data.staff, isNotEmpty);

    // Permission codes round-trip through the wire format.
    expect(data.user.can(Permission.reportsView), isTrue);
    expect(data.user.role, UserRole.admin);

    expect(payload.settings, isNotNull);
    expect(payload.settings!.currencyPrefix, 'SLSH');
    expect(payload.settings!.taxEnabled, isFalse);
    expect(payload.dashboard.weekly, isNotEmpty);
  });

  test('a waiter receives only the permissions their role grants', () async {
    if (!up) return;

    // Creates its own waiter rather than borrowing a seeded one: the PHP auth
    // suite deliberately changes passwords and locks accounts, and a test that
    // breaks depending on what ran before it is worse than no test.
    final ApiRepository admin = await _repo();
    final String phone = '0639${DateTime.now().millisecondsSinceEpoch % 1000000}';

    await admin.api.createUser(<String, dynamic>{
      'name': 'Fixture Waiter',
      'phone': phone,
      'password': 'fixture123',
      'role_code': 'waiter',
    });

    final BootstrapPayload payload = await (await _repo(
      phone: phone,
      password: 'fixture123',
    )).bootstrap();

    expect(payload.bootstrap.user.role, UserRole.waiter);
    expect(payload.bootstrap.user.can(Permission.ordersCreate), isTrue);
    expect(payload.bootstrap.user.can(Permission.reportsView), isFalse);
    expect(payload.bootstrap.user.can(Permission.usersView), isFalse);
  });

  test('the server prices the order, not the client', () async {
    if (!up) return;

    final ApiRepository repo = await _repo();
    final BootstrapPayload payload = await repo.bootstrap();

    // Chicken Burger 35,000 + French Fries x2 30,000 + Fresh Juice 20,000
    final RestaurantOrder order = await repo.placeOrder(
      OrderRequest(
        type: OrderType.takeaway,
        lines: <OrderLine>[
          OrderLine.fromMenuItem(
            payload.bootstrap.items.firstWhere((dynamic i) => i.name == 'Chicken Burger'),
          ),
          OrderLine.fromMenuItem(
            payload.bootstrap.items.firstWhere((dynamic i) => i.name == 'French Fries'),
            quantity: 2,
          ),
          OrderLine.fromMenuItem(
            payload.bootstrap.items.firstWhere((dynamic i) => i.name == 'Fresh Juice'),
          ),
        ],
        paymentMethod: PaymentMethod.cash,
      ),
    );

    expect(order.subtotal, 85000);
    // Four portions — burger, two fries, juice — each in its own container.
    expect(order.packagingFee, 20000);
    expect(order.total, 105000);
    // Paid in full at the counter, so it is done. `preparing` was the answer
    // when the kitchen had its own states; those were removed and completion is
    // now derived from the payments, which is why a cash sale lands here rather
    // than sitting in a queue nobody works.
    expect(order.status, OrderStatus.completed);
    expect(order.lines.length, 3);
    expect(order.tableId, isNull);
    expect(order.events, isNotEmpty);
    expect(order.payments.single.method, PaymentMethod.cash);
  });

  test('a status change comes back with its audit entry', () async {
    if (!up) return;

    final ApiRepository repo = await _repo();
    final BootstrapPayload payload = await repo.bootstrap();

    final RestaurantOrder order = await repo.placeOrder(
      OrderRequest(
        type: OrderType.takeaway,
        lines: <OrderLine>[
          OrderLine.fromMenuItem(payload.bootstrap.items.first),
        ],
      ),
    );

    final RestaurantOrder cancelled = await repo.setOrderStatus(
      order.id,
      OrderStatus.cancelled,
      reason: 'Macmiilku wuu ka noqday',
    );

    expect(cancelled.status, OrderStatus.cancelled);
    expect(cancelled.cancelReason, 'Macmiilku wuu ka noqday');
    expect(
      cancelled.events.any(
        (OrderEvent e) =>
            e.labelKey == 'orderStatusChanged' && e.newValue == 'cancelled',
      ),
      isTrue,
    );
  });

  test('each tenant sees only its own catalogue', () async {
    if (!up) return;

    final BootstrapPayload hamze = await (await _repo()).bootstrap();
    final BootstrapPayload warfa = await (await _repo(
      code: 'WARFA',
      phone: '0637778899',
    )).bootstrap();

    final List<String> hamzeNames = hamze.bootstrap.items
        .map((dynamic i) => i.name as String)
        .toList();
    final List<String> warfaNames = warfa.bootstrap.items
        .map((dynamic i) => i.name as String)
        .toList();

    expect(hamzeNames, contains('Chicken Burger'));
    expect(hamzeNames, isNot(contains('Camel Suqaar')));
    expect(warfaNames, contains('Camel Suqaar'));
    expect(warfaNames, isNot(contains('Chicken Burger')));

    // WARFA runs with tax enabled, HAMZE without — settings are per tenant.
    expect(hamze.settings!.taxEnabled, isFalse);
    expect(warfa.settings!.taxEnabled, isTrue);
    expect(warfa.settings!.packagingFee, 3000);
  });

  test('editing an order reprices it server-side', () async {
    if (!up) return;

    final ApiRepository repo = await _repo();
    final BootstrapPayload payload = await repo.bootstrap();
    final MenuItem burger = payload.bootstrap.items.firstWhere(
      (MenuItem i) => i.name == 'Chicken Burger',
    );
    final MenuItem fries = payload.bootstrap.items.firstWhere(
      (MenuItem i) => i.name == 'French Fries',
    );

    final RestaurantOrder order = await repo.placeOrder(
      OrderRequest(
        type: OrderType.takeaway,
        lines: <OrderLine>[OrderLine.fromMenuItem(burger)],
      ),
    );
    expect(order.total, 40000); // 35,000 + 5,000 packaging

    final RestaurantOrder edited = await repo.updateOrderItems(
      order.id,
      <OrderLine>[
        OrderLine.fromMenuItem(burger, quantity: 2),
        OrderLine.fromMenuItem(fries),
      ],
      reason: 'Customer added fries',
    );

    expect(edited.total, 100000); // 70,000 + 15,000 + 3 x 5,000
    expect(edited.lines.length, 2);
    expect(
      edited.events.any((OrderEvent e) => e.reason == 'Customer added fries'),
      isTrue,
      reason: 'the reason reaches the audit trail',
    );
  });

  test('a payment can be taken against an open order', () async {
    if (!up) return;

    final ApiRepository repo = await _repo();
    final BootstrapPayload payload = await repo.bootstrap();

    final RestaurantOrder order = await repo.placeOrder(
      OrderRequest(
        type: OrderType.takeaway,
        lines: <OrderLine>[
          OrderLine.fromMenuItem(payload.bootstrap.items.first),
        ],
      ),
    );
    expect(order.payments, isEmpty);

    final RestaurantOrder paid = await repo.addPayment(
      order.id,
      method: PaymentMethod.zaad,
      amount: order.total,
      reference: 'ZD-TEST',
    );

    expect(paid.payments.single.method, PaymentMethod.zaad);
    expect(paid.payments.single.amount, order.total);
    expect(paid.payments.single.reference, 'ZD-TEST');
  });

  test('a draft becomes revenue only when converted', () async {
    if (!up) return;

    final ApiRepository repo = await _repo();
    final BootstrapPayload payload = await repo.bootstrap();
    final MenuItem item = payload.bootstrap.items.firstWhere(
      (MenuItem i) => i.name == 'Chicken Burger',
    );

    final DraftOrder draft = await repo.saveDraft(
      DraftRequest(
        customerName: 'Fixture Customer',
        type: OrderType.takeaway,
        lines: <OrderLine>[OrderLine.fromMenuItem(item, quantity: 2)],
      ),
    );
    expect(draft.status, DraftStatus.draft);
    expect(draft.subtotal, 70000);

    final List<DraftOrder> parked = await repo.drafts();
    expect(parked.any((DraftOrder d) => d.id == draft.id), isTrue);

    final RestaurantOrder order = await repo.convertDraft(
      draft.id,
      method: PaymentMethod.cash,
    );
    expect(order.total, 80000); // 70,000 + 2 x 5,000 packaging
    expect(order.customerName, 'Fixture Customer');

    // A converted draft no longer sits in the parked list.
    final List<DraftOrder> after = await repo.drafts();
    expect(
      after.any(
        (DraftOrder d) => d.id == draft.id && d.status == DraftStatus.draft,
      ),
      isFalse,
    );
  });

  test('menu items round-trip through create, edit and delete', () async {
    if (!up) return;

    final ApiRepository repo = await _repo();
    final BootstrapPayload payload = await repo.bootstrap();
    final MenuCategory category = payload.bootstrap.categories.first;

    final MenuItem created = await repo.saveMenuItem(
      MenuItem(
        id: -1,
        restaurantId: 0,
        categoryId: category.id,
        name: 'Integration Burger',
        price: 33000,
        emoji: '🍔',
      ),
    );
    expect(created.id, greaterThan(0));
    expect(created.price, 33000);

    final MenuItem repriced = await repo.saveMenuItem(
      MenuItem(
        id: created.id,
        restaurantId: created.restaurantId,
        categoryId: created.categoryId,
        name: created.name,
        price: 36000,
        emoji: created.emoji,
      ),
      reason: 'Price update',
    );
    expect(repriced.price, 36000);

    final MenuItem toggled = await repo.toggleMenuItem(created.id);
    expect(toggled.available, isFalse);

    await repo.deleteMenuItem(created.id);
    final BootstrapPayload after = await repo.bootstrap();
    expect(
      after.bootstrap.items.any((MenuItem i) => i.id == created.id),
      isFalse,
    );
  });

  test('an expense moves a real account balance', () async {
    if (!up) return;

    final ApiRepository repo = await _repo();
    await repo.bootstrap();

    double cash(List<Account> accounts) => accounts
        .firstWhere((Account a) => a.method == PaymentMethod.cash)
        .balance;

    final double before = cash(await repo.accounts());

    final List<Expense> withExpense = await repo.saveExpense(
      const ExpenseRequest(
        name: 'Integration fuel',
        amount: 12000,
        kind: ExpenseKind.daily,
        method: PaymentMethod.cash,
      ),
    );
    final Expense created = withExpense.firstWhere(
      (Expense e) => e.name == 'Integration fuel',
    );

    expect(cash(await repo.accounts()), before - 12000);

    // Cancelled, not deleted — the row stays in the books and the money goes
    // back to the till it came out of.
    final List<Expense> after = await repo.cancelExpense(
      created.id,
      'Integration test cleanup',
    );

    expect(cash(await repo.accounts()), before, reason: 'cancelling refunds it');
    expect(
      after.firstWhere((Expense e) => e.id == created.id).isCancelled,
      isTrue,
      reason: 'the entry survives, marked void',
    );
  });

  test('a transfer moves money between the restaurant own accounts', () async {
    if (!up) return;

    final ApiRepository repo = await _repo();
    await repo.bootstrap();

    final List<Account> before = await repo.accounts();
    final Account from = before.firstWhere(
      (Account a) => a.method == PaymentMethod.cash,
    );
    final Account to = before.firstWhere(
      (Account a) => a.method == PaymentMethod.bank,
    );

    final List<Account> after = await repo.transfer(
      fromAccountId: from.id,
      toAccountId: to.id,
      amount: 25000,
      description: 'Integration deposit',
    );

    expect(
      after.firstWhere((Account a) => a.id == from.id).balance,
      from.balance - 25000,
    );
    expect(
      after.firstWhere((Account a) => a.id == to.id).balance,
      to.balance + 25000,
    );
  });

  test('reports parse into the chart models', () async {
    if (!up) return;

    final ApiRepository repo = await _repo();
    await repo.bootstrap();

    final ReportLoaded report = await repo.reports(ReportRange.sevenDays);

    expect(report.daily.length, 7);
    expect(report.hourly.length, 15);
    expect(report.sales.value, greaterThan(0));
    expect(report.byCategory, isNotEmpty);
    expect(report.byPayment, isNotEmpty);
    expect(report.topItems, isNotEmpty);
    // Every slice must carry a colour, whether the server supplied one or the
    // mapper assigned it from the shared palette.
    for (final dynamic slice in report.byPayment) {
      expect(slice.color, isNotNull);
    }
  });
}
