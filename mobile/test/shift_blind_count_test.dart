import 'package:dacaam_pos/data/api/mappers.dart';
import 'package:dacaam_pos/data/models/order.dart';
import 'package:dacaam_pos/data/models/shift.dart';
import 'package:dacaam_pos/data/repository/dacaam_repository.dart';
import 'package:dacaam_pos/data/repository/mock_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// The blind count.
///
/// A till is counted against what the system says should be in it. If whoever
/// counts can see that figure first, they will enter that figure — the count
/// becomes a transcription and the variance is always zero, which is worse than
/// having no count at all because it looks like a control.
///
/// The server withholds the number while a shift is open. These pin the client
/// half: an absent expected total must stay absent, never become a helpful
/// zero, because a screen that has a number will eventually show it.
void main() {
  group('an open shift', () {
    test('carries no expected total', () {
      final Shift shift = Api.shift(<String, dynamic>{
        'id': 1,
        'account_id': 1,
        'account_name': 'Sanduuqa',
        'opened_by': 'Faarax',
        'opened_at': '2026-08-19T08:00:00+03:00',
        'opening_float': 200000,
        'is_open': true,
        // No expected_close, counted_close or variance — the server does not
        // send them while a till is open.
      });

      expect(shift.isOpen, isTrue);
      expect(
        shift.expectedClose,
        isNull,
        reason: 'absent must not become zero — zero is a number to type in',
      );
      expect(shift.variance, isNull);
      expect(shift.figuresVisible, isFalse);
    });

    test('still reports what the last shift left behind', () {
      // Not the same thing as the expected total: this is what the previous
      // person counted, which the next one needs in order to know what they
      // are starting from.
      final Shift shift = Api.shift(<String, dynamic>{
        'id': 2,
        'account_id': 1,
        'opened_by': 'Faarax',
        'opened_at': '2026-08-19T08:00:00+03:00',
        'opening_float': 150000,
        'previous_close': 200000,
        'overnight_diff': -50000,
        'is_open': true,
      });

      expect(shift.previousClose, 200000);
      expect(shift.overnightDiff, -50000);
      expect(shift.expectedClose, isNull, reason: 'and still no expected total');
    });
  });

  group('a closed shift', () {
    test('reveals the figures', () {
      final Shift shift = Api.shift(<String, dynamic>{
        'id': 3,
        'account_id': 1,
        'opened_by': 'Faarax',
        'opened_at': '2026-08-19T08:00:00+03:00',
        'closed_by': 'Faarax',
        'closed_at': '2026-08-19T22:00:00+03:00',
        'opening_float': 200000,
        'expected_close': 760000,
        'counted_close': 742000,
        'variance': -18000,
        'close_reason': 'Lacag laga waayay',
        'is_open': false,
      });

      expect(shift.figuresVisible, isTrue);
      expect(shift.expectedClose, 760000);
      expect(shift.countedClose, 742000);
      expect(shift.variance, -18000);
      expect(shift.isShort, isTrue);
      expect(shift.balanced, isFalse);
      expect(shift.closeReason, 'Lacag laga waayay');
    });

    test('a till that balances is not flagged', () {
      final Shift shift = Api.shift(<String, dynamic>{
        'id': 4,
        'account_id': 1,
        'opened_by': 'Faarax',
        'opened_at': '2026-08-19T08:00:00+03:00',
        'closed_at': '2026-08-19T22:00:00+03:00',
        'opening_float': 200000,
        'expected_close': 500000,
        'counted_close': 500000,
        'variance': 0,
        'is_open': false,
      });

      expect(shift.balanced, isTrue);
      expect(shift.isShort, isFalse);
    });
  });

  group('an order from a counted evening', () {
    // The server refuses every change to it. The flag is what lets the app
    // say so instead of offering a button that can only fail.
    test('is marked locked', () {
      final RestaurantOrder locked = Api.order(<String, dynamic>{
        'id': 1,
        'order_number': 1042,
        'order_type': 'takeaway',
        'status': 'completed',
        'payment_status': 'paid',
        'is_locked': true,
        'total': 40000,
      });

      expect(locked.isLocked, isTrue);
    });

    test('an order on the open shift is not', () {
      final RestaurantOrder open = Api.order(<String, dynamic>{
        'id': 2,
        'order_number': 1043,
        'order_type': 'takeaway',
        'status': 'completed',
        'payment_status': 'paid',
        'total': 40000,
      });

      expect(open.isLocked, isFalse, reason: 'absent means not locked');
    });
  });

  group('what the counter is shown', () {
    // Both sides of every account, cash included. The figure is a demand rather
    // than a hint — whatever the system says came in is money the cashier is
    // expected to be holding — and it is what a short drawer gets checked
    // against before the shift closes.
    test('cash shows what came in and what went out', () {
      final CountableAccount cash = Api.countableAccount(<String, dynamic>{
        'id': 1,
        'name': 'Sanduuqa',
        'method': 'cash',
        'received': 640000,
        'paid_out': 15000,
      });

      expect(cash.isCash, isTrue);
      expect(cash.received, 640000);
      expect(cash.paidOut, 15000);
    });

    test('Zaad the same', () {
      final CountableAccount zaad = Api.countableAccount(<String, dynamic>{
        'id': 2,
        'name': 'Zaad',
        'method': 'zaad',
        'received': 340000,
      });

      expect(zaad.isCash, isFalse);
      expect(zaad.received, 340000);
      expect(zaad.paidOut, 0, reason: 'nothing left it');
    });

    test('a missing field stays null rather than becoming zero', () {
      // An older server sends no `received` at all. Rendering that as zero
      // would tell the cashier the account took nothing, which is a statement
      // the server never made.
      final CountableAccount old = Api.countableAccount(<String, dynamic>{
        'id': 3,
        'name': 'Bank',
        'method': 'bank',
      });

      expect(old.received, isNull);
    });
  });

  group('the detail of a closed shift', () {
    test('carries the breakdown behind the variance', () {
      final ShiftDetail detail = Api.shiftDetail(<String, dynamic>{
        'shift': <String, dynamic>{
          'id': 9,
          'account_id': 1,
          'opened_by': 'Faarax',
          'opened_at': '2026-08-19T08:00:00+03:00',
          'closed_by': 'Faarax',
          'closed_at': '2026-08-19T22:00:00+03:00',
          'opening_float': 200000,
          'expected_close': 1100000,
          'counted_close': 1082000,
          'variance': -18000,
          'is_open': false,
        },
        'expected': 1100000,
        'accounts': <dynamic>[
          <String, dynamic>{
            'account_id': 1,
            'name': 'Sanduuqa',
            'method': 'cash',
            'expected': 760000,
            'counted': 742000,
            'variance': -18000,
          },
          <String, dynamic>{
            'account_id': 2,
            'name': 'Zaad',
            'method': 'zaad',
            'expected': 340000,
            'counted': 340000,
            'variance': 0,
          },
        ],
        'expenses': <String, dynamic>{
          'total': 15000,
          'items': <dynamic>[
            <String, dynamic>{
              'name': 'Biyo',
              'amount': 15000,
              'method': 'cash',
            },
          ],
        },
        'movements': <dynamic>[
          <String, dynamic>{
            'kind': 'money_in',
            'description': 'Order 1042',
            'amount': 70000,
            'created_at': '2026-08-19T12:00:00+03:00',
          },
          <String, dynamic>{
            'kind': 'money_out',
            'description': 'Biyo',
            'amount': 15000,
            'created_at': '2026-08-19T15:00:00+03:00',
          },
        ],
      });

      expect(detail.accounts.length, 2);

      // The point of the breakdown: one account short and one clean must not be
      // netted into a single verdict.
      final ShiftCount cash = detail.accounts.first;
      expect(cash.method, 'cash');
      expect(cash.variance, -18000);
      expect(cash.isShort, isTrue);
      expect(detail.accounts.last.balanced, isTrue);

      expect(detail.expenses.total, 15000);
      expect(detail.movements.length, 2);
      expect(detail.movements.first.isOut, isFalse);
      expect(detail.movements.last.isOut, isTrue);
    });

    test('an adjustment that took money out reads as money out', () {
      // A negative adjustment is the variance being written back to the till.
      // Colouring it as income would show the evening the drawer came up short
      // as though something had been paid in.
      final ShiftMovement m = Api.shiftMovement(<String, dynamic>{
        'kind': 'adjustment',
        'description': 'Xidhitaanka shifka — gaabis',
        'amount': -18000,
        'created_at': '2026-08-19T22:00:00+03:00',
      });

      expect(m.isOut, isTrue);
    });
  });

  group('the demo behaves the same way', () {
    // A mock that hands over the figures early would let the screen be built
    // the wrong way round, and this is the one property the feature cannot
    // survive losing.
    test('an open shift hides them there too', () async {
      final MockRepository repo = MockRepository();
      final ShiftStatus status = await repo.openShift(openingFloat: 200000);

      expect(status.isOpen, isTrue);
      expect(status.shift!.expectedClose, isNull);
      expect(status.shift!.figuresVisible, isFalse);
    });

    test('and closing reveals them', () async {
      final MockRepository repo = MockRepository();
      final ShiftStatus status = await repo.openShift(openingFloat: 200000);

      // One figure per account — the till is not a single number any more.
      final Shift closed = await repo.closeShift(
        status.shift!.id,
        counts: <int, double>{1: 180000},
      );

      expect(closed.figuresVisible, isTrue);
      expect(closed.countedClose, 180000);
      expect(closed.variance, -20000);
      expect(closed.isOpen, isFalse);
    });

    test('the next open knows what the last one left', () async {
      final MockRepository repo = MockRepository();
      final ShiftStatus first = await repo.openShift(openingFloat: 200000);
      await repo.closeShift(first.shift!.id, counts: <int, double>{1: 180000});

      final ShiftStatus after = await repo.currentShift();
      expect(after.isOpen, isFalse);
      expect(
        after.lastClose,
        180000,
        reason: 'what was counted, so the morning gap is visible',
      );
    });
  });
}
