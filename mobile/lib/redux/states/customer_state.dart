import 'package:flutter/foundation.dart';

import '../../data/models/customer.dart';
import 'status.dart';

/// Which customers the list is showing.
enum CustomerFilter {
  all,

  /// Owes the restaurant money.
  debtors,

  /// Has money sitting with the restaurant.
  wallet;

  String get labelKey => switch (this) {
    CustomerFilter.all => 'allCustomers',
    CustomerFilter.debtors => 'debtors',
    CustomerFilter.wallet => 'walletHolders',
  };

  /// The query value the server understands. `all` sends nothing.
  String? get api => switch (this) {
    CustomerFilter.all => null,
    CustomerFilter.debtors => 'debtors',
    CustomerFilter.wallet => 'wallet',
  };
}

@immutable
class CustomerState {
  const CustomerState({
    this.status = Status.idle,
    this.customers = const <Customer>[],
    this.filter = CustomerFilter.all,
    this.search = '',
    this.selected,
    this.selectedStatus = Status.idle,
  });

  final Status status;
  final List<Customer> customers;
  final CustomerFilter filter;
  final String search;

  /// The profile currently open, with its ledger. Held apart from [customers]
  /// because the list rows carry no ledger and would otherwise blank it out on
  /// the next refresh.
  final Customer? selected;
  final Status selectedStatus;

  /// Totals across everyone, so the list header can state the position without
  /// a second request. Computed from what is loaded — with the 300-row cap and
  /// a filter applied these are the loaded page, not the books; Reports is
  /// where the authoritative figures live.
  double get totalOwed => customers
      .where((Customer c) => c.isDebtor)
      .fold<double>(0, (double s, Customer c) => s + c.balanceOwed);

  double get totalWallet =>
      customers.fold<double>(0, (double s, Customer c) => s + c.wallet);

  int get debtorCount => customers.where((Customer c) => c.isDebtor).length;

  Customer? byId(int? id) {
    if (id == null) return null;
    for (final Customer c in customers) {
      if (c.id == id) return c;
    }

    return selected?.id == id ? selected : null;
  }

  CustomerState copyWith({
    Status? status,
    List<Customer>? customers,
    CustomerFilter? filter,
    String? search,
    Customer? selected,
    Status? selectedStatus,
    bool clearSelected = false,
  }) {
    return CustomerState(
      status: status ?? this.status,
      customers: customers ?? this.customers,
      filter: filter ?? this.filter,
      search: search ?? this.search,
      selected: clearSelected ? null : (selected ?? this.selected),
      selectedStatus: selectedStatus ?? this.selectedStatus,
    );
  }
}
