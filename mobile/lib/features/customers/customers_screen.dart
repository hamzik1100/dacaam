import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:redux/redux.dart';

import '../../core/i18n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/utils/enums.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/customer.dart';
import '../../redux/app_state.dart';
import '../../redux/effects.dart';
import '../../redux/states/customer_state.dart';
import '../../redux/states/status.dart';
import '../../widgets/app_card.dart';
import '../../widgets/skeletons.dart';
import '../../widgets/states.dart';
import 'customer_profile_screen.dart';
import 'customer_sheet.dart';

/// Who owes the restaurant, and who has money sitting with it.
///
/// The two totals at the top are the whole point of the screen: a manager
/// wants one number for what is out on tabs and one for what is held on
/// deposit, before they read a single name.
class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  final TextEditingController _search = TextEditingController();

  /// Typing is not a request per keystroke — a search field wired straight to
  /// the API sends six calls for "Cabdi" and shows whichever lands last.
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
        return Scaffold(
          appBar: AppBar(title: Text(context.t('customers'))),
          floatingActionButton: vm.canCreate
              ? FloatingActionButton.extended(
                  onPressed: () => showCustomerSheet(context),
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                  label: Text(context.t('addCustomer')),
                )
              : null,
          body: RefreshIndicator(
            onRefresh: vm.onRefresh,
            child: CustomScrollView(
              slivers: <Widget>[
                SliverToBoxAdapter(child: _Totals(vm: vm)),
                SliverToBoxAdapter(
                  child: _SearchAndFilters(
                    controller: _search,
                    filter: vm.filter,
                    onFilter: vm.onFilter,
                    onSearch: (String q) {
                      _debounce?.cancel();
                      _debounce = Timer(
                        const Duration(milliseconds: 350),
                        () => vm.onSearch(q),
                      );
                    },
                  ),
                ),
                if (vm.status.isLoading)
                  const SliverToBoxAdapter(child: ListSkeleton(rows: 6))
                else if (vm.customers.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: EmptyState(
                      icon: Icons.people_alt_rounded,
                      title: vm.filter == CustomerFilter.debtors
                          ? context.t('noDebtors')
                          : context.t('noCustomers'),
                      message: vm.filter == CustomerFilter.all
                          ? context.t('noCustomersBody')
                          : null,
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.gutter,
                      0,
                      AppSpacing.gutter,
                      AppSpacing.xxxl * 2,
                    ),
                    sliver: SliverList.builder(
                      itemCount: vm.customers.length,
                      itemBuilder: (BuildContext context, int i) =>
                          CustomerRow(customer: vm.customers[i]),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// One row of the list, also used by the checkout picker.
class CustomerRow extends StatelessWidget {
  const CustomerRow({super.key, required this.customer, this.onTap});

  final Customer customer;

  /// Defaults to opening the profile. The picker passes its own.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Color tint = customer.isDebtor
        ? AppColors.danger
        : (customer.wallet > 0 ? AppColors.success : AppColors.info);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        padding: const EdgeInsets.all(AppSpacing.md),
        onTap:
            onTap ??
            () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => CustomerProfileScreen(customerId: customer.id),
              ),
            ),
        child: Row(
          children: <Widget>[
            _Avatar(name: customer.name, tint: tint),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    customer.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.texts.titleSmall,
                  ),
                  if (customer.phone.isNotEmpty)
                    Text(
                      customer.phone,
                      style: context.texts.bodySmall?.copyWith(
                        color: context.palette.subtext,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Text(
                  // A settled account shows nothing rather than a zero: zero in
                  // red would read as a problem where there is none.
                  customer.balanceOwed == 0
                      ? context.t('settled')
                      : Fmt.money(
                          customer.isDebtor
                              ? customer.balanceOwed
                              : customer.wallet,
                        ),
                  style: context.texts.titleSmall?.copyWith(color: tint),
                ),
                Text(
                  customer.balanceOwed == 0
                      ? ''
                      : (customer.isDebtor
                            ? context.t('owesYou')
                            : context.t('youHold')),
                  style: context.texts.labelSmall?.copyWith(
                    color: context.palette.subtext,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, required this.tint});

  final String name;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final String initial = name.trim().isEmpty
        ? '?'
        : name.trim().characters.first.toUpperCase();

    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        initial,
        style: context.texts.titleMedium?.copyWith(color: tint),
      ),
    );
  }
}

class _Totals extends StatelessWidget {
  const _Totals({required this.vm});

  final _Vm vm;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        AppSpacing.md,
        AppSpacing.gutter,
        AppSpacing.sm,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: _TotalCard(
              label: context.t('receivables'),
              value: vm.totalOwed,
              tint: AppColors.danger,
              icon: Icons.trending_up_rounded,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: _TotalCard(
              label: context.t('depositsHeld'),
              value: vm.totalWallet,
              tint: AppColors.success,
              icon: Icons.savings_rounded,
            ),
          ),
        ],
      ),
    );
  }
}

class _TotalCard extends StatelessWidget {
  const _TotalCard({
    required this.label,
    required this.value,
    required this.tint,
    required this.icon,
  });

  final String label;
  final double value;
  final Color tint;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, size: 16, color: tint),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.texts.labelSmall?.copyWith(
                    color: context.palette.subtext,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            Fmt.money(value),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.texts.titleMedium?.copyWith(color: tint),
          ),
        ],
      ),
    );
  }
}

class _SearchAndFilters extends StatelessWidget {
  const _SearchAndFilters({
    required this.controller,
    required this.filter,
    required this.onFilter,
    required this.onSearch,
  });

  final TextEditingController controller;
  final CustomerFilter filter;
  final ValueChanged<CustomerFilter> onFilter;
  final ValueChanged<String> onSearch;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        AppSpacing.xs,
        AppSpacing.gutter,
        AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          TextField(
            controller: controller,
            onChanged: onSearch,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: context.t('search'),
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              suffixIcon: controller.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () {
                        controller.clear();
                        onSearch('');
                      },
                    ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          // Wrap rather than Row: three Somali labels plus chip padding are
          // wider than a small phone, and a chip past the edge is a filter
          // nobody can reach.
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: CustomerFilter.values.map((CustomerFilter f) {
              return ChoiceChip(
                label: Text(context.t(f.labelKey)),
                selected: filter == f,
                onSelected: (_) => onFilter(f),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _Vm {
  const _Vm({
    required this.status,
    required this.customers,
    required this.filter,
    required this.totalOwed,
    required this.totalWallet,
    required this.canCreate,
    required this.onRefresh,
    required this.onFilter,
    required this.onSearch,
  });

  factory _Vm.from(Store<AppState> store) {
    final CustomerState s = store.state.customers;

    return _Vm(
      status: s.status,
      customers: s.customers,
      filter: s.filter,
      totalOwed: s.totalOwed,
      totalWallet: s.totalWallet,
      canCreate: store.state.auth.can(Permission.customersCreate),
      onRefresh: () => Effects.loadCustomers(store),
      onFilter: (CustomerFilter f) => Effects.loadCustomers(store, filter: f),
      onSearch: (String q) => Effects.loadCustomers(store, search: q),
    );
  }

  final Status status;
  final List<Customer> customers;
  final CustomerFilter filter;
  final double totalOwed;
  final double totalWallet;
  final bool canCreate;
  final Future<void> Function() onRefresh;
  final ValueChanged<CustomerFilter> onFilter;
  final ValueChanged<String> onSearch;
}
