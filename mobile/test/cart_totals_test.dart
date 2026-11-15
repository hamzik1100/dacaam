import 'package:dacaam_pos/core/utils/enums.dart';
import 'package:dacaam_pos/data/mock/mock_data.dart';
import 'package:dacaam_pos/data/models/order.dart';
import 'package:dacaam_pos/redux/states/pos_state.dart';
import 'package:dacaam_pos/redux/states/settings_state.dart';
import 'package:flutter_test/flutter_test.dart';

/// The pricing rules the API will have to agree with byte for byte.
void main() {
  OrderLine line(int itemId, int qty) =>
      OrderLine.fromMenuItem(MockData.itemById(itemId), quantity: qty);

  // Chicken Burger 35,000 + French Fries ×2 30,000 + Fresh Juice 20,000.
  final List<OrderLine> basket = <OrderLine>[
    line(1, 1),
    line(16, 2),
    line(10, 1),
  ];

  group('CartTotals', () {
    test('sums line totals with tax disabled', () {
      final CartTotals t = CartTotals.fromLines(
        lines: basket,
        orderType: OrderType.dineIn,
        discount: 0,
        settings: const SettingsState(),
      );

      expect(t.subtotal, 85000);
      expect(t.tax, 0);
      expect(t.packaging, 0);
      expect(t.total, 85000);
    });

    test('applies tax to the discounted subtotal, not the gross', () {
      final CartTotals t = CartTotals.fromLines(
        lines: basket,
        orderType: OrderType.dineIn,
        discount: 5000,
        settings: const SettingsState(taxEnabled: true, taxRate: 5),
      );

      expect(t.discount, 5000);
      expect(t.tax, 4000); // 5% of 80,000, not of 85,000
      expect(t.total, 84000);
    });

    test('charges the packaging fee per portion on takeaway', () {
      // Four portions in the basket: 1 burger, 2 fries, 1 juice. Each goes into
      // its own container, so four fees — not one for the whole bag.
      final CartTotals t = CartTotals.fromLines(
        lines: basket,
        orderType: OrderType.takeaway,
        discount: 0,
        settings: const SettingsState(),
      );

      expect(t.packaging, 20000);
      expect(t.total, 105000);
    });

    test('twenty of one dish is twenty fees', () {
      // The bug this replaced: a single flat charge meant the restaurant bought
      // nineteen containers it never billed for, on every large takeaway, and
      // nobody could see it in the total.
      final CartTotals t = CartTotals.fromLines(
        lines: <OrderLine>[line(1, 20)],
        orderType: OrderType.takeaway,
        discount: 0,
        settings: const SettingsState(),
      );

      expect(t.packaging, 100000, reason: '20 × 5,000');
      expect(t.subtotal, 700000, reason: '20 × 35,000');
      expect(t.total, 800000);
    });

    test('only the eligible portions are counted', () {
      // A drink that needs no container must not add one. Item 10 is eligible
      // in the seeded catalogue; if that ever changes this test says so rather
      // than the arithmetic quietly drifting.
      final List<OrderLine> mixed = <OrderLine>[line(1, 3)];
      final int eligible = mixed
          .where((OrderLine l) => l.applyPackagingFee)
          .fold<int>(0, (int sum, OrderLine l) => sum + l.quantity);

      final CartTotals t = CartTotals.fromLines(
        lines: mixed,
        orderType: OrderType.takeaway,
        discount: 0,
        settings: const SettingsState(),
      );

      expect(t.packaging, 5000 * eligible);
    });

    test('never charges packaging on dine in', () {
      final CartTotals t = CartTotals.fromLines(
        lines: basket,
        orderType: OrderType.dineIn,
        discount: 0,
        settings: const SettingsState(),
      );

      expect(t.packaging, 0);
    });

    test('skips packaging when no line is packaging-eligible', () {
      // Water and Shaah are both flagged applyPackagingFee: false.
      final CartTotals t = CartTotals.fromLines(
        lines: <OrderLine>[line(13, 1), line(11, 2)],
        orderType: OrderType.takeaway,
        discount: 0,
        settings: const SettingsState(),
      );

      expect(t.packaging, 0);
      expect(t.total, 21000);
    });

    test('skips packaging when the fee is disabled in settings', () {
      final CartTotals t = CartTotals.fromLines(
        lines: basket,
        orderType: OrderType.takeaway,
        discount: 0,
        settings: const SettingsState(packagingFeeEnabled: false),
      );

      expect(t.packaging, 0);
    });

    test('caps a discount at the subtotal so a total can never go negative', () {
      final CartTotals t = CartTotals.fromLines(
        lines: basket,
        orderType: OrderType.dineIn,
        discount: 999999,
        settings: const SettingsState(),
      );

      expect(t.discount, 85000);
      expect(t.total, 0);
    });
  });

  group('seed data', () {
    test('every order total matches the sum of its lines', () {
      for (final RestaurantOrder o in MockData.orders) {
        expect(
          o.total,
          o.subtotal - o.discount + o.taxAmount + o.packagingFee,
          reason: 'order #${o.number}',
        );
      }
    });

    test('takeaway orders carry no table, dine in orders do', () {
      for (final RestaurantOrder o in MockData.orders) {
        if (o.type == OrderType.takeaway) {
          expect(o.tableId, isNull, reason: 'order #${o.number}');
        }
      }
    });

    test('cancelled orders always carry a reason', () {
      final Iterable<RestaurantOrder> cancelled = MockData.orders.where(
        (RestaurantOrder o) => o.status == OrderStatus.cancelled,
      );
      expect(cancelled, isNotEmpty);
      for (final RestaurantOrder o in cancelled) {
        expect(o.cancelReason, isNotNull, reason: 'order #${o.number}');
        expect(o.cancelReason, isNotEmpty);
      }
    });

    test('every menu item belongs to a real category', () {
      for (final dynamic item in MockData.menuItems) {
        expect(
          MockData.categories.any((dynamic c) => c.id == item.categoryId),
          isTrue,
          reason: item.name as String,
        );
      }
    });
  });
}
