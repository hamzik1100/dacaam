import 'package:dacaam_pos/data/models/customer.dart';
import 'package:flutter_test/flutter_test.dart';

/// The arithmetic behind a customer's balance, and the boundary the till warns
/// against.
///
/// The bug these pin: `creditAvailable` was `creditLimit - balanceOwed`, and a
/// negative balance is a deposit — so a customer with 200,000 on deposit and a
/// credit limit of zero was shown as having 200,000 of credit available. The
/// restaurant had decided to lend them nothing.
///
/// The server refuses an order when the resulting balance would pass the credit
/// limit, i.e. when `balanceOwed + total > creditLimit`. Rearranged, the most
/// that can go through is `wallet + creditAvailable`, which is [spendable].
/// These tests hold the two definitions together, because a warning the server
/// then contradicts is worse than no warning.
void main() {
  Customer make({double owed = 0, double limit = 0}) =>
      Customer(id: 1, name: 'Test', balanceOwed: owed, creditLimit: limit);

  group('a customer in credit', () {
    test('deposit is a wallet, not credit', () {
      final Customer c = make(owed: -200000);

      expect(c.wallet, 200000);
      expect(c.isDebtor, isFalse);
      expect(c.creditAvailable, 0, reason: 'no limit was set, so no credit');
      expect(c.spendable, 200000, reason: 'their own money, and only that');
    });

    test('a deposit and a limit are added, not conflated', () {
      final Customer c = make(owed: -5000, limit: 30000);

      expect(c.wallet, 5000);
      expect(c.creditAvailable, 30000);
      expect(c.spendable, 35000);
    });
  });

  group('a customer who owes', () {
    test('credit available is what is left of the limit', () {
      final Customer c = make(owed: 10000, limit: 30000);

      expect(c.wallet, 0);
      expect(c.isDebtor, isTrue);
      expect(c.creditAvailable, 20000);
      expect(c.spendable, 20000);
    });

    test('at the limit nothing more can go through', () {
      final Customer c = make(owed: 30000, limit: 30000);

      expect(c.creditAvailable, 0);
      expect(c.spendable, 0);
    });

    test('past the limit never reports a negative', () {
      final Customer c = make(owed: 45000, limit: 30000);

      expect(c.creditAvailable, 0);
      expect(c.spendable, 0);
    });
  });

  group('spendable matches the server rule', () {
    // The server's test is `balanceOwed + total > creditLimit` -> refuse.
    bool serverWouldRefuse(Customer c, double total) =>
        c.balanceOwed + total > c.creditLimit;

    for (final (String label, double owed, double limit) in <
        (String, double, double)>[
      ('walk-up debtor', 10000, 30000),
      ('deposit, no limit', -200000, 0),
      ('deposit and limit', -5000, 30000),
      ('square account', 0, 50000),
      ('no credit at all', 0, 0),
      ('already over', 45000, 30000),
    ]) {
      test('$label: the app warns exactly where the server refuses', () {
        final Customer c = make(owed: owed, limit: limit);

        // Just inside the boundary passes; a hair past it is refused. Checked
        // from both sides so an off-by-one in either definition shows up.
        if (c.spendable > 0) {
          expect(
            serverWouldRefuse(c, c.spendable),
            isFalse,
            reason: 'spending exactly the limit is allowed',
          );
        }
        expect(
          serverWouldRefuse(c, c.spendable + 1),
          isTrue,
          reason: 'one shilling more is refused',
        );
      });
    }
  });
}
