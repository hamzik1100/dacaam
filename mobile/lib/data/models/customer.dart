import 'package:flutter/foundation.dart';

import '../../core/utils/enums.dart';

/// A customer account.
///
/// [balanceOwed] is positive when the customer owes the restaurant and negative
/// when they are in credit — the same sign convention the server uses, kept
/// deliberately rather than flipped here, so the two never disagree about what
/// a number means. [isDebtor] and [wallet] are the readable forms.
@immutable
class Customer {
  const Customer({
    required this.id,
    required this.name,
    this.phone = '',
    this.address = '',
    this.notes = '',
    this.creditLimit = 0,
    this.balanceOwed = 0,
    this.isActive = true,
    this.createdAt,
    this.ledger = const <LedgerEntry>[],
  });

  final int id;
  final String name;
  final String phone;
  final String address;
  final String notes;

  /// Zero means no credit at all — a customer is trusted only once somebody
  /// decides how far.
  final double creditLimit;
  final double balanceOwed;
  final bool isActive;
  final DateTime? createdAt;

  /// Only populated by the profile endpoint; the list leaves it empty.
  final List<LedgerEntry> ledger;

  bool get isDebtor => balanceOwed > 0;

  /// What the customer has on deposit, as a positive number.
  double get wallet => balanceOwed < 0 ? -balanceOwed : 0;

  /// How much more they may put on the tab before the limit refuses them.
  ///
  /// Measured against what they owe, and a customer in credit owes nothing —
  /// so money on deposit is not counted here. It used to be: `creditLimit -
  /// balanceOwed` turned a 200,000 deposit into "200,000 of credit available"
  /// for somebody the restaurant had decided to lend nothing to. Their own
  /// money is [wallet]; this is the restaurant's exposure.
  double get creditAvailable {
    final double owing = balanceOwed > 0 ? balanceOwed : 0;
    final double left = creditLimit - owing;

    return left > 0 ? left : 0;
  }

  /// The most this customer can put through the till right now: their deposit
  /// plus whatever credit is left.
  ///
  /// Mirrors the server's rule exactly — it refuses when the resulting balance
  /// would pass the credit limit, which is the same boundary — so a warning
  /// shown against this figure is one the server will agree with rather than a
  /// guess the order then contradicts.
  double get spendable => wallet + creditAvailable;

  Customer copyWith({List<LedgerEntry>? ledger}) => Customer(
    id: id,
    name: name,
    phone: phone,
    address: address,
    notes: notes,
    creditLimit: creditLimit,
    balanceOwed: balanceOwed,
    isActive: isActive,
    createdAt: createdAt,
    ledger: ledger ?? this.ledger,
  );
}

/// What kind of movement a ledger row records.
enum LedgerKind {
  charge('charge', 'ledgerCharge'),
  payment('payment', 'ledgerPayment'),
  deposit('deposit', 'ledgerDeposit'),
  refund('refund', 'ledgerRefund'),
  adjustment('adjustment', 'ledgerAdjustment');

  const LedgerKind(this.api, this.labelKey);

  final String api;
  final String labelKey;

  static LedgerKind fromApi(String? value) => LedgerKind.values.firstWhere(
    (LedgerKind k) => k.api == value,
    orElse: () => LedgerKind.adjustment,
  );
}

/// One line of a customer's account, exactly as the server recorded it.
///
/// Append-only: a correction is another entry, never a rewrite of this one, so
/// the list read top to bottom explains how the balance got where it is.
@immutable
class LedgerEntry {
  const LedgerEntry({
    required this.id,
    required this.kind,
    required this.amount,
    required this.balanceAfter,
    required this.at,
    this.method = '',
    this.description = '',
    this.sourceType = '',
    this.sourceId,
    this.reason,
    this.createdBy = '',
    this.orderNumber,
    this.orderPaymentStatus,
    this.orderCancelled = false,
  });

  final int id;
  final LedgerKind kind;

  /// Signed like the balance: a charge is positive, a payment negative.
  final double amount;
  final double balanceAfter;
  final DateTime at;
  final String method;
  final String description;
  final String sourceType;
  final int? sourceId;

  /// Required on an adjustment, and the first thing an auditor reads.
  final String? reason;
  final String createdBy;

  /// The order behind this line, when there is one. Null on a deposit, a
  /// repayment or a hand adjustment — none of those came from a sale.
  final int? orderNumber;

  /// Whether that order has been paid for. A line can sit on the account as
  /// debt while the order it came from is separately marked paid at the till,
  /// and a customer asking "did I pay for that one" is asking exactly this.
  final PaymentStatus? orderPaymentStatus;
  final bool orderCancelled;

  bool get increasesDebt => amount > 0;
}
