/// A till, opened and counted.
///
/// Everything else this app records watches actions somebody entered. A shift
/// watches the money itself: what the drawer held at the start, what the system
/// says went through it, and what was actually in it at the end. The gap
/// between the last two is the only thing that can catch a sale that was never
/// rung up at all.
class Shift {
  const Shift({
    required this.id,
    required this.accountId,
    required this.accountName,
    required this.openedBy,
    required this.openedAt,
    required this.openingFloat,
    this.previousClose,
    this.overnightDiff,
    this.closedBy = '',
    this.closedAt,
    this.expectedClose,
    this.countedClose,
    this.variance,
    this.closeReason,
    this.ordersOutside = 0,
    this.notes = '',
    this.isOpen = true,
    this.accounts = const <ShiftCount>[],
  });

  final int id;
  final int accountId;
  final String accountName;

  final String openedBy;
  final DateTime openedAt;
  final double openingFloat;

  /// What the previous shift counted, and how far this morning's float fell
  /// short of it. Money that went missing overnight is a different question
  /// from a till running short during the day, and the two are kept apart so
  /// neither hides the other.
  final double? previousClose;
  final double? overnightDiff;

  final String closedBy;
  final DateTime? closedAt;

  /// Null while the shift is open — deliberately.
  ///
  /// The server does not send this to whoever is about to count the drawer.
  /// Someone shown the figure they are meant to arrive at will simply type it,
  /// and a variance that is always zero is worse than no count at all because
  /// it looks like a control while being none.
  final double? expectedClose;

  final double? countedClose;
  final double? variance;
  final String? closeReason;

  /// Orders taken while no shift was open. Not blocked; counted.
  final int ordersOutside;

  final String notes;
  final bool isOpen;

  /// One line per account, present once the shift is closed.
  ///
  /// Cash short by twenty thousand while Zaad is over by twenty thousand
  /// nets to nothing and is two separate problems, so the figures are kept
  /// apart rather than summed into a single verdict.
  final List<ShiftCount> accounts;

  bool get isShort => (variance ?? 0) < 0;
  bool get balanced => variance != null && variance!.abs() < 0.01;

  /// Whether the figures are readable yet. Open shifts hide them on purpose.
  bool get figuresVisible => expectedClose != null;
}

/// One account's count at close: what was expected, what was found, the gap.
class ShiftCount {
  const ShiftCount({
    required this.accountId,
    required this.name,
    required this.method,
    required this.expected,
    required this.counted,
    required this.variance,
  });

  final int accountId;
  final String name;
  final String method;
  final double expected;
  final double counted;
  final double variance;

  bool get balanced => variance.abs() < 0.01;
  bool get isShort => variance < -0.01;
}

/// An account the closing screen has to ask about.
///
/// Carries no balance, deliberately: the list builds the form, and the balance
/// is the answer. A screen that holds it will eventually show it.
class CountableAccount {
  const CountableAccount({
    required this.id,
    required this.name,
    required this.method,
    this.received,
    this.paidOut = 0,
  });

  final int id;
  final String name;
  final String method;

  /// What came in on this account since the till opened.
  ///
  /// Cash included. The figure is a demand, not a hint: whatever the system
  /// says came in is money the cashier is expected to be holding, and
  /// showing it does not create a shortfall that was not already there.
  ///
  /// What it buys is the investigation. A drawer that comes up short has to
  /// be looked into before the shift closes — a missed expense, a payment
  /// rung up wrong, a recount — and an empty box gives nowhere to start.
  final double? received;

  /// And what left it: expenses paid, refunds, transfers out.
  final double paidOut;

  bool get isCash => method == 'cash';
}

/// What left the tills since the shift opened.
///
/// Shown while counting because it is why the drawer holds less than the day's
/// sales. The cashier paid these, so it is not news — but without it a close
/// becomes a panicked recount of money that was legitimately spent.
class ShiftExpenses {
  const ShiftExpenses({this.total = 0, this.items = const <ShiftExpenseLine>[]});

  final double total;
  final List<ShiftExpenseLine> items;
}

class ShiftExpenseLine {
  const ShiftExpenseLine({
    required this.name,
    required this.amount,
    required this.method,
  });

  final String name;
  final double amount;
  final String method;
}
/// Everything a closed shift can be asked about.
///
/// A history row shows one number — the variance — and that number means very
/// little on its own. This is what it takes to judge it: who was there, what
/// each account held, what moved through the till, and what was spent.
class ShiftDetail {
  const ShiftDetail({
    required this.shift,
    this.expected = 0,
    this.accounts = const <ShiftCount>[],
    this.expenses = const ShiftExpenses(),
    this.movements = const <ShiftMovement>[],
  });

  final Shift shift;

  /// For an open shift this is live; for a closed one it is what was recorded
  /// at the time, which is a statement about a moment rather than a figure to
  /// be re-derived later.
  final double expected;

  final List<ShiftCount> accounts;
  final ShiftExpenses expenses;
  final List<ShiftMovement> movements;
}

/// One line of the till's ledger during a shift.
class ShiftMovement {
  const ShiftMovement({
    required this.kind,
    required this.description,
    required this.amount,
    required this.at,
  });

  final String kind;
  final String description;
  final double amount;
  final DateTime at;

  /// Money out is anything that left: spending, refunds, transfers away.
  bool get isOut => kind == 'money_out' || (kind == 'adjustment' && amount < 0);
}