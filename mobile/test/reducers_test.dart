import 'package:dacaam_pos/core/utils/enums.dart';
import 'package:dacaam_pos/data/mock/mock_data.dart';
import 'package:dacaam_pos/data/models/dining_table.dart';
import 'package:dacaam_pos/data/models/menu.dart';
import 'package:dacaam_pos/data/models/order.dart';
import 'package:dacaam_pos/data/repository/mock_repository.dart';
import 'package:dacaam_pos/redux/actions.dart';
import 'package:dacaam_pos/redux/app_state.dart';
import 'package:dacaam_pos/redux/effects.dart';
import 'package:dacaam_pos/redux/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:redux/redux.dart';

void main() {
  late Store<AppState> store;

  setUp(() {
    // A fresh offline repository per test so order numbering starts from the
    // seeded maximum every time rather than carrying over between tests.
    Effects.repository = MockRepository(latency: Duration.zero);

    store = createStore();
    store.dispatch(
      BootstrapSucceeded(
        restaurant: MockData.restaurant,
        user: MockData.currentUser,
        staff: MockData.users,
        categories: MockData.categories,
        items: MockData.menuItems,
        tables: MockData.tables,
        orders: MockData.orders,
        drafts: MockData.drafts,
        expenses: MockData.expenses,
        expenseCategories: MockData.expenseCategories,
        accounts: MockData.accounts,
      ),
    );
  });

  final MenuItem burger = MockData.itemById(1);

  group('cart', () {
    test('adding the same item merges into one line', () {
      store.dispatch(CartItemAdded(burger));
      store.dispatch(CartItemAdded(burger));

      expect(store.state.cart.lines.length, 1);
      expect(store.state.cart.lines.first.quantity, 2);
      expect(store.state.cart.itemCount, 2);
    });

    test('decrementing the last unit removes the line', () {
      store.dispatch(CartItemAdded(burger));
      store.dispatch(CartItemDecremented(burger.id));

      expect(store.state.cart.lines, isEmpty);
    });

    test('switching to takeaway drops any selected table', () {
      store.dispatch(const CartTableSelected(2));
      expect(store.state.cart.tableId, 2);

      store.dispatch(const CartOrderTypeChanged(OrderType.takeaway));
      expect(store.state.cart.tableId, isNull);
      expect(store.state.cart.guests, 0);
    });

    test('deleting a menu item also pulls it out of the open cart', () {
      store.dispatch(CartItemAdded(burger));
      store.dispatch(MenuItemDeleted(burger.id));

      expect(store.state.cart.lines, isEmpty);
      expect(
        store.state.menu.items.any((MenuItem i) => i.id == burger.id),
        isFalse,
      );
    });
  });

  group('checkout', () {
    test('placing an order clears the cart and occupies the table', () async {
      store.dispatch(CartItemAdded(burger));
      store.dispatch(const CartTableSelected(2));
      final int before = store.state.orders.orders.length;

      final RestaurantOrder order = await Effects.placeOrder(store);

      expect(store.state.orders.orders.length, before + 1);
      expect(store.state.orders.orders.first.id, order.id);
      expect(store.state.orders.lastPlacedOrderId, order.id);
      expect(store.state.cart.lines, isEmpty);

      final DiningTable table = store.state.tables.tables.firstWhere(
        (DiningTable t) => t.id == 2,
      );
      expect(table.status, TableStatus.occupied);
      expect(table.currentOrderId, order.id);
    });

    test('the new order number continues from the highest existing one', () async {
      store.dispatch(CartItemAdded(burger));
      final RestaurantOrder order = await Effects.placeOrder(store);

      expect(order.number, 1026);
    });

    test('the waiter selection survives checkout for the next order', () async {
      store.dispatch(const CartWaiterSelected(3));
      store.dispatch(CartItemAdded(burger));
      await Effects.placeOrder(store);

      expect(store.state.cart.waiterId, 3);
    });

    test('the offline path honours the configured packaging fee', () async {
      store.dispatch(const CartOrderTypeChanged(OrderType.takeaway));
      store.dispatch(CartItemAdded(burger)); // 35,000, packaging-eligible
      store.dispatch(
        const SettingValueChanged(packagingFee: 7500),
      );

      final RestaurantOrder order = await Effects.placeOrder(store);

      expect(order.packagingFee, 7500);
      expect(order.total, 42500);
    });
  });

  group('order status', () {
    test('completing a dine-in order frees its table', () {
      // #1025 sits on table 3.
      store.dispatch(
        const OrderStatusUpdated(
          orderId: 1025,
          status: OrderStatus.completed,
          byUser: 'Axmed Xasan',
        ),
      );

      final DiningTable table = store.state.tables.tables.firstWhere(
        (DiningTable t) => t.id == 3,
      );
      expect(table.status, TableStatus.available);
      expect(table.currentOrderId, isNull);
    });

    test('a status change appends an audit event with old and new values', () {
      store.dispatch(
        const OrderStatusUpdated(
          orderId: 1025,
          status: OrderStatus.ready,
          byUser: 'Axmed Xasan',
          reason: 'Kitchen finished early',
        ),
      );

      final RestaurantOrder o = store.state.orders.byId(1025)!;
      final OrderEvent last = o.events.last;

      expect(o.status, OrderStatus.ready);
      expect(last.labelKey, 'orderStatusChanged');
      expect(last.oldValue, 'preparing');
      expect(last.newValue, 'ready');
      expect(last.reason, 'Kitchen finished early');
      expect(last.byUser, 'Axmed Xasan');
    });
  });

  group('order filters', () {
    test('the status tab narrows the visible list', () {
      store.dispatch(const OrderStatusFilterChanged(OrderStatus.completed));

      expect(
        store.state.orders.visible.every(
          (RestaurantOrder o) => o.status == OrderStatus.completed,
        ),
        isTrue,
      );
      expect(store.state.orders.visible, isNotEmpty);
    });

    test('search matches order number, waiter and table', () {
      store.dispatch(const OrderSearchChanged('1023'));
      expect(store.state.orders.visible.length, 1);
      expect(store.state.orders.visible.first.number, 1023);
    });

    test('activeCount ignores the status tab and free-text search', () {
      store.dispatch(const OrderStatusFilterChanged(OrderStatus.pending));
      store.dispatch(const OrderSearchChanged('omar'));
      expect(store.state.orders.filters.activeCount, 0);

      store.dispatch(
        OrderFiltersChanged(
          store.state.orders.filters.copyWith(type: OrderType.takeaway),
        ),
      );
      expect(store.state.orders.filters.activeCount, 1);
    });
  });

  group('permissions', () {
    test('a waiter cannot reach reports, users or settings', () {
      final Set<Permission> waiter = Permission.forRole(UserRole.waiter);

      expect(waiter.contains(Permission.ordersCreate), isTrue);
      expect(waiter.contains(Permission.reportsView), isFalse);
      expect(waiter.contains(Permission.usersView), isFalse);
      expect(waiter.contains(Permission.settingsManage), isFalse);
    });

    test('an admin holds every permission', () {
      expect(
        Permission.forRole(UserRole.admin).length,
        Permission.values.length,
      );
    });
  });
}
