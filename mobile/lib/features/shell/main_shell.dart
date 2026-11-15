import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:redux/redux.dart';

import '../../core/i18n/app_strings.dart';
import '../../core/utils/enums.dart';
import '../../redux/actions.dart';
import '../../redux/app_state.dart';
import '../home/home_screen.dart';
import '../menu/menu_screen.dart';
import '../more/more_screen.dart';
import '../orders/orders_screen.dart';
import '../pos/pos_screen.dart';
import '../reports/reports_screen.dart';
import 'bottom_nav.dart';

/// A bottom-nav destination plus the permission that reveals it.
class _Destination {
  const _Destination({
    required this.nav,
    required this.builder,
    this.permission,
  });

  final NavDestination nav;
  final WidgetBuilder builder;

  /// `null` == always visible (Home and More).
  final Permission? permission;
}

const List<_Destination> _allDestinations = <_Destination>[
  _Destination(
    nav: NavDestination(
      labelKey: 'navHome',
      icon: Icons.home_outlined,
      activeIcon: Icons.home_rounded,
    ),
    builder: _buildHome,
  ),
  _Destination(
    nav: NavDestination(
      labelKey: 'navPos',
      icon: Icons.point_of_sale_outlined,
      activeIcon: Icons.point_of_sale_rounded,
    ),
    permission: Permission.ordersCreate,
    builder: _buildPos,
  ),
  _Destination(
    nav: NavDestination(
      labelKey: 'navOrders',
      icon: Icons.receipt_long_outlined,
      activeIcon: Icons.receipt_long_rounded,
    ),
    permission: Permission.ordersView,
    builder: _buildOrders,
  ),
  _Destination(
    nav: NavDestination(
      labelKey: 'navMenu',
      icon: Icons.restaurant_menu_outlined,
      activeIcon: Icons.restaurant_menu_rounded,
    ),
    permission: Permission.menuView,
    builder: _buildMenu,
  ),
  _Destination(
    nav: NavDestination(
      labelKey: 'navReports',
      icon: Icons.bar_chart_outlined,
      activeIcon: Icons.bar_chart_rounded,
    ),
    permission: Permission.reportsView,
    builder: _buildReports,
  ),
  _Destination(
    nav: NavDestination(
      labelKey: 'navMore',
      icon: Icons.grid_view_outlined,
      activeIcon: Icons.grid_view_rounded,
    ),
    builder: _buildMore,
  ),
];

/// Resolves a destination's index within the *visible* nav for the given
/// permission set. Quick Actions use this to jump tabs without assuming the
/// full six-tab layout is present.
int shellIndexOf(String labelKey, Set<Permission> permissions) {
  final List<_Destination> visible = _allDestinations
      .where(
        (_Destination d) =>
            d.permission == null || permissions.contains(d.permission),
      )
      .toList();
  final int i = visible.indexWhere(
    (_Destination d) => d.nav.labelKey == labelKey,
  );
  return i < 0 ? 0 : i;
}

Widget _buildHome(BuildContext context) => const HomeScreen();
Widget _buildPos(BuildContext context) => const PosScreen();
Widget _buildOrders(BuildContext context) => const OrdersScreen();
Widget _buildMenu(BuildContext context) => const MenuScreen();
Widget _buildReports(BuildContext context) => const ReportsScreen();
Widget _buildMore(BuildContext context) => const MoreScreen();

/// Root container for the six primary sections.
///
/// The visible destination list is derived from the signed-in user's
/// permissions — a Waiter simply never gets a Reports tab, rather than getting
/// one that refuses them.
class MainShell extends StatelessWidget {
  const MainShell({super.key});

  @override
  Widget build(BuildContext context) {
    return StoreConnector<AppState, _ShellVm>(
      distinct: true,
      converter: _ShellVm.from,
      builder: (BuildContext context, _ShellVm vm) {
        final List<_Destination> visible = _allDestinations
            .where(
              (_Destination d) =>
                  d.permission == null || vm.permissions.contains(d.permission),
            )
            .toList();

        final int index = vm.activeTab.clamp(0, visible.length - 1);
        final int posIndex = visible.indexWhere(
          (_Destination d) => d.nav.labelKey == 'navPos',
        );

        return PopScope(
          // Back on a secondary tab returns to Home before leaving the app.
          canPop: index == 0,
          onPopInvokedWithResult: (bool didPop, Object? result) {
            if (!didPop) vm.onSelect(0);
          },
          child: Scaffold(
            body: IndexedStack(
              index: index,
              children: visible
                  .map((_Destination d) => d.builder(context))
                  .toList(),
            ),
            bottomNavigationBar: AppBottomNav(
              destinations: visible.map((_Destination d) => d.nav).toList(),
              labelOf: (NavDestination d) => context.t(d.labelKey),
              currentIndex: index,
              onSelected: vm.onSelect,
              badges: <int, int>{
                if (posIndex >= 0 && vm.cartCount > 0) posIndex: vm.cartCount,
              },
            ),
          ),
        );
      },
    );
  }
}

class _ShellVm {
  const _ShellVm({
    required this.activeTab,
    required this.permissions,
    required this.cartCount,
    required this.onSelect,
  });

  factory _ShellVm.from(Store<AppState> store) {
    return _ShellVm(
      activeTab: store.state.activeTab,
      permissions: store.state.auth.user?.permissions ?? const <Permission>{},
      cartCount: store.state.cart.itemCount,
      onSelect: (int i) => store.dispatch(TabSelected(i)),
    );
  }

  final int activeTab;
  final Set<Permission> permissions;
  final int cartCount;
  final ValueChanged<int> onSelect;

  @override
  bool operator ==(Object other) =>
      other is _ShellVm &&
      other.activeTab == activeTab &&
      other.cartCount == cartCount &&
      other.permissions.length == permissions.length;

  @override
  int get hashCode => Object.hash(activeTab, cartCount, permissions.length);
}
