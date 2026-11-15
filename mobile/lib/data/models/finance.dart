import 'package:flutter/material.dart';

import '../../core/utils/enums.dart';

class ExpenseCategory {
  const ExpenseCategory({
    required this.id,
    required this.name,
    required this.icon,
    required this.color,
    required this.kind,
  });

  final int id;
  final String name;
  final IconData icon;
  final Color color;
  final ExpenseKind kind;
}

class Expense {
  const Expense({
    required this.id,
    required this.restaurantId,
    required this.name,
    required this.amount,
    required this.categoryId,
    required this.categoryName,
    required this.method,
    required this.date,
    required this.kind,
    this.notes = '',
    this.createdBy = '',
    this.recurring = false,
    this.cancelledAt,
    this.cancelReason = '',
  });

  final int id;
  final int restaurantId;
  final String name;
  final double amount;
  final int categoryId;
  final String categoryName;
  final PaymentMethod method;
  final DateTime date;
  final ExpenseKind kind;
  final String notes;
  final String createdBy;
  final bool recurring;

  /// When it was voided, or null while it still counts.
  ///
  /// A cancelled expense is never removed — the books have to be able to
  /// explain a figure that was there yesterday — so it stays in the list,
  /// struck through, with its reason showing.
  final DateTime? cancelledAt;
  final String cancelReason;

  bool get isCancelled => cancelledAt != null;
}

/// A money bucket (Cash drawer, Zaad wallet, bank account …).
class Account {
  const Account({
    required this.id,
    required this.restaurantId,
    required this.method,
    required this.balance,
    this.moneyIn = 0,
    this.moneyOut = 0,
  });

  final int id;
  final int restaurantId;
  final PaymentMethod method;
  final double balance;
  final double moneyIn;
  final double moneyOut;

  String get name => method.label;
}

/// A payment method as the server holds it — what the management screen
/// edits. The pickers want [asMethod] instead: they care about identity and
/// appearance, not about ids or how many accounts point at it.
class PaymentMethodRecord {
  const PaymentMethodRecord({
    required this.id,
    required this.code,
    required this.name,
    this.isActive = true,
    this.isSystem = false,
    this.sortOrder = 0,
    this.accountCount = 0,
  });

  final int id;
  final String code;
  final String name;
  final bool isActive;

  /// Cash and the rest: renameable, never removable.
  final bool isSystem;
  final int sortOrder;
  final int accountCount;

  PaymentMethod get asMethod {
    for (final PaymentMethod m in PaymentMethod.builtIn) {
      if (m.api == code) return PaymentMethod(m.api, name, m.icon, m.color);
    }

    return PaymentMethod.custom(code, name);
  }
}

enum TransactionKind {
  moneyIn('money_in', 'moneyIn'),
  moneyOut('money_out', 'moneyOut'),
  transfer('transfer', 'transfer'),
  adjustment('adjustment', 'adjustment');

  const TransactionKind(this.api, this.labelKey);

  /// Matches the account_transactions.kind ENUM.
  final String api;
  final String labelKey;
}

class AccountTransaction {
  const AccountTransaction({
    required this.id,
    required this.accountId,
    required this.kind,
    required this.amount,
    required this.at,
    this.description = '',
    this.toAccountId,
  });

  final int id;
  final int accountId;
  final TransactionKind kind;
  final double amount;
  final DateTime at;
  final String description;
  final int? toAccountId;
}
