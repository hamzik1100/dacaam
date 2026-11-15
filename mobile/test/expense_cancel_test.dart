import 'package:dacaam_pos/core/utils/enums.dart';
import 'package:dacaam_pos/data/models/finance.dart';
import 'package:dacaam_pos/data/repository/mock_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// Expenses are cancelled, never deleted.
///
/// The rule exists for the books: a figure that was in the accounts yesterday
/// has to still be explainable today, and a deleted row cannot tell an honest
/// mistake apart from somebody covering their tracks. The server enforces it —
/// the DELETE route is gone — and these pin the client side of the same rule,
/// including the demo data, because a mock where cancelling makes rows vanish
/// is a mock the screens get built wrong against.
void main() {
  Expense make({DateTime? cancelledAt, String reason = ''}) => Expense(
    id: 1,
    restaurantId: 1,
    name: 'Shidaal',
    amount: 40000,
    categoryId: 1,
    categoryName: 'Gaadiid',
    method: PaymentMethod.cash,
    date: DateTime(2026, 8, 19),
    kind: ExpenseKind.daily,
    cancelledAt: cancelledAt,
    cancelReason: reason,
  );

  group('the model', () {
    test('a live expense is not cancelled', () {
      expect(make().isCancelled, isFalse);
    });

    test('one with a date is', () {
      expect(make(cancelledAt: DateTime(2026, 8, 19)).isCancelled, isTrue);
    });

    test('and carries why', () {
      final Expense e = make(
        cancelledAt: DateTime(2026, 8, 19),
        reason: 'Laba jeer ayaa la qoray',
      );

      expect(e.cancelReason, 'Laba jeer ayaa la qoray');
    });
  });

  group('cancelling', () {
    test('marks the entry instead of removing it', () async {
      final MockRepository repo = MockRepository();
      final List<Expense> before = await repo.expenses();

      expect(before, isNotEmpty, reason: 'the demo has expenses to work with');

      final int id = before.first.id;
      final List<Expense> after = await repo.cancelExpense(id, 'Qalad ayaa jiray');

      expect(
        after.length,
        before.length,
        reason: 'nothing was removed — the count cannot drop',
      );

      final Expense target = after.firstWhere((Expense e) => e.id == id);

      expect(target.isCancelled, isTrue);
      expect(target.cancelReason, 'Qalad ayaa jiray');
      expect(
        target.amount,
        before.first.amount,
        reason: 'the figure is preserved, not zeroed — the books need it',
      );
    });

    test('leaves every other entry alone', () async {
      final MockRepository repo = MockRepository();
      final List<Expense> before = await repo.expenses();

      if (before.length < 2) return;

      final int id = before.first.id;
      final List<Expense> after = await repo.cancelExpense(id, 'Mid kaliya');

      final Iterable<Expense> others = after.where((Expense e) => e.id != id);

      expect(
        others.every((Expense e) => !e.isCancelled),
        isTrue,
        reason: 'cancelling one must not touch the rest',
      );
    });
  });
}
