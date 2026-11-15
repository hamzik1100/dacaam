import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:redux/redux.dart';

import '../../core/i18n/app_strings.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/utils/enums.dart';
import '../../data/models/customer.dart';
import '../../redux/app_state.dart';
import '../../redux/effects.dart';
import '../../widgets/app_sheet.dart';
import '../../widgets/skeletons.dart';
import '../../widgets/states.dart';
import 'customer_sheet.dart';
import 'customers_screen.dart';

/// Picks the account a sale goes on.
///
/// Returns the chosen customer, or a [CustomerChoice.walkIn] when the user
/// clears it. Null means they backed out and whatever was attached stays.
Future<CustomerChoice?> showCustomerPicker(BuildContext context) {
  return showAppSheet<CustomerChoice>(
    context,
    builder: (BuildContext context) => const _PickerSheet(),
  );
}

/// Either a customer or the explicit absence of one.
class CustomerChoice {
  const CustomerChoice(this.customer);

  const CustomerChoice.walkIn() : customer = null;

  final Customer? customer;

  bool get isWalkIn => customer == null;
}

class _PickerSheet extends StatefulWidget {
  const _PickerSheet();

  @override
  State<_PickerSheet> createState() => _PickerSheetState();
}

class _PickerSheetState extends State<_PickerSheet> {
  final TextEditingController _search = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StoreConnector<AppState, _Vm>(
      converter: _Vm.from,
      onInit: (Store<AppState> store) => Effects.loadCustomers(store),
      builder: (BuildContext context, _Vm vm) {
        return AppSheet(
          title: context.t('selectCustomer'),
          trailing: vm.canCreate
              ? IconButton(
                  icon: const Icon(Icons.person_add_alt_1_rounded, size: 20),
                  onPressed: () async {
                    final Customer? made = await showCustomerSheet(context);
                    if (made != null && context.mounted) {
                      Navigator.of(context).pop(CustomerChoice(made));
                    }
                  },
                )
              : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              TextField(
                controller: _search,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: context.t('search'),
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                ),
                onChanged: (String q) {
                  _debounce?.cancel();
                  _debounce = Timer(
                    const Duration(milliseconds: 350),
                    () => vm.onSearch(q),
                  );
                },
              ),
              const SizedBox(height: AppSpacing.md),

              // Always first: clearing the account is the common correction,
              // and hunting for it under a list of names is the wrong order.
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.person_off_rounded),
                title: Text(context.t('walkIn')),
                onTap: () =>
                    Navigator.of(context).pop(const CustomerChoice.walkIn()),
              ),
              const Divider(height: 1),
              const SizedBox(height: AppSpacing.md),

              if (vm.loading)
                const ListSkeleton(rows: 4)
              else if (vm.customers.isEmpty)
                EmptyState(
                  icon: Icons.people_alt_rounded,
                  title: context.t('noCustomers'),
                  message: context.t('noCustomersBody'),
                  compact: true,
                )
              else
                ...vm.customers.map(
                  (Customer c) => CustomerRow(
                    customer: c,
                    onTap: () =>
                        Navigator.of(context).pop(CustomerChoice(c)),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Vm {
  const _Vm({
    required this.customers,
    required this.loading,
    required this.canCreate,
    required this.onSearch,
  });

  factory _Vm.from(Store<AppState> store) => _Vm(
    customers: store.state.customers.customers,
    loading: store.state.customers.status.isLoading,
    canCreate: store.state.auth.can(Permission.customersCreate),
    onSearch: (String q) => Effects.loadCustomers(store, search: q),
  );

  final List<Customer> customers;
  final bool loading;
  final bool canCreate;
  final ValueChanged<String> onSearch;
}
