import 'package:flutter/foundation.dart';

import '../../core/utils/enums.dart';
import '../../data/models/finance.dart';
import 'status.dart';

@immutable
class ExpenseState {
  const ExpenseState({
    this.status = Status.idle,
    this.expenses = const <Expense>[],
    this.categories = const <ExpenseCategory>[],
    this.kind = ExpenseKind.daily,
  });

  final Status status;
  final List<Expense> expenses;
  final List<ExpenseCategory> categories;

  /// Daily / Monthly tab on the Expenses screen.
  final ExpenseKind kind;

  List<Expense> get visible =>
      expenses.where((Expense e) => e.kind == kind).toList();

  double get todayTotal {
    final DateTime now = DateTime.now();
    return expenses
        .where(
          (Expense e) =>
              e.date.year == now.year &&
              e.date.month == now.month &&
              e.date.day == now.day,
        )
        .fold<double>(0, (double s, Expense e) => s + e.amount);
  }

  ExpenseState copyWith({
    Status? status,
    List<Expense>? expenses,
    List<ExpenseCategory>? categories,
    ExpenseKind? kind,
  }) {
    return ExpenseState(
      status: status ?? this.status,
      expenses: expenses ?? this.expenses,
      categories: categories ?? this.categories,
      kind: kind ?? this.kind,
    );
  }
}

@immutable
/// What the Accounts screen is currently narrowed to.
///
/// Empty means everything: the default view answers "where is the money",
/// and a date window imposed by default would hide an account that last moved
/// a fortnight ago.
class AccountFilters {
  const AccountFilters({
    this.accountId,
    this.kind,
    this.range,
    this.search = '',
  });

  final int? accountId;
  final TransactionKind? kind;
  final ReportRange? range;
  final String search;

  bool get isEmpty =>
      accountId == null && kind == null && range == null && search.isEmpty;

  int get activeCount =>
      (accountId == null ? 0 : 1) +
      (kind == null ? 0 : 1) +
      (range == null ? 0 : 1) +
      (search.isEmpty ? 0 : 1);

  AccountFilters copyWith({
    int? accountId,
    TransactionKind? kind,
    ReportRange? range,
    String? search,
    bool clearAccount = false,
    bool clearKind = false,
    bool clearRange = false,
  }) {
    return AccountFilters(
      accountId: clearAccount ? null : (accountId ?? this.accountId),
      kind: clearKind ? null : (kind ?? this.kind),
      range: clearRange ? null : (range ?? this.range),
      search: search ?? this.search,
    );
  }
}

class AccountState {
  const AccountState({
    this.status = Status.idle,
    this.accounts = const <Account>[],
    this.transactions = const <AccountTransaction>[],
    this.filters = const AccountFilters(),
    this.methods = const <PaymentMethodRecord>[],
  });

  final Status status;
  final List<Account> accounts;
  final List<AccountTransaction> transactions;
  final AccountFilters filters;
  final List<PaymentMethodRecord> methods;

  /// What the pickers offer: active methods only, in the order the restaurant
  /// arranged them. Falls back to the seeded four before the first load so a
  /// checkout opened on a cold start is never empty.
  List<PaymentMethod> get pickable => methods.isEmpty
      ? PaymentMethod.builtIn
      : methods
            .where((PaymentMethodRecord m) => m.isActive)
            .map((PaymentMethodRecord m) => m.asMethod)
            .toList();

  double get totalBalance =>
      accounts.fold<double>(0, (double s, Account a) => s + a.balance);

  double get todayIn =>
      accounts.fold<double>(0, (double s, Account a) => s + a.moneyIn);

  Account? byMethod(PaymentMethod m) {
    for (final Account a in accounts) {
      if (a.method == m) return a;
    }
    return null;
  }

  AccountState copyWith({
    Status? status,
    List<Account>? accounts,
    List<AccountTransaction>? transactions,
    AccountFilters? filters,
    List<PaymentMethodRecord>? methods,
  }) {
    return AccountState(
      status: status ?? this.status,
      filters: filters ?? this.filters,
      methods: methods ?? this.methods,
      accounts: accounts ?? this.accounts,
      transactions: transactions ?? this.transactions,
    );
  }
}
