import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:redux/redux.dart';

import '../../core/i18n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/utils/enums.dart';
import '../../data/models/restaurant.dart';
import '../../redux/app_state.dart';
import '../../redux/effects.dart';
import '../../widgets/app_card.dart';
import '../../widgets/entrance.dart';
import '../management/about_screen.dart';
import '../management/support_screen.dart';
import '../management/audit_screen.dart';
import '../customers/customers_screen.dart';
import '../management/accounts_screen.dart';
import '../management/payment_methods_screen.dart';
import '../management/drafts_screen.dart';
import '../management/expenses_screen.dart';
import '../management/security_screen.dart';
import '../management/settings_screen.dart';
import '../management/shift_screen.dart';
import '../management/tables_screen.dart';
import '../management/users_screen.dart';

/// Management hub for everything that doesn't belong in the bottom bar.
class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return StoreConnector<AppState, _MoreVm>(
      converter: _MoreVm.from,
      builder: (BuildContext context, _MoreVm vm) {
        return Scaffold(
          body: SafeArea(
            bottom: false,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.gutter,
                AppSpacing.md,
                AppSpacing.gutter,
                AppSpacing.xxxl,
              ),
              children: <Widget>[
                Text(context.t('navMore'), style: context.texts.headlineSmall),
                const SizedBox(height: AppSpacing.lg),
                Entrance(index: 0, child: _ProfileCard(vm: vm)),
                const SizedBox(height: AppSpacing.xl),

                Entrance(
                  index: 1,
                  child: _Group(
                    title: context.t('management'),
                    tiles: <Widget>[
                      _MoreTile(
                        icon: Icons.edit_note_rounded,
                        color: AppColors.secondary,
                        label: context.t('draftOrders'),
                        badge: vm.draftCount,
                        onTap: () => _push(context, const DraftsScreen()),
                      ),
                      if (vm.can(Permission.customersView))
                        _MoreTile(
                          icon: Icons.people_alt_rounded,
                          color: AppColors.primary,
                          label: context.t('customers'),
                          onTap: () =>
                              _push(context, const CustomersScreen()),
                        ),
                      if (vm.can(Permission.tablesView))
                        _MoreTile(
                          icon: Icons.table_restaurant_rounded,
                          color: AppColors.info,
                          label: context.t('tables'),
                          onTap: () => _push(context, const TablesScreen()),
                        ),
                      if (vm.can(Permission.expensesView))
                        _MoreTile(
                          icon: Icons.account_balance_wallet_rounded,
                          color: AppColors.violet,
                          label: context.t('expenses'),
                          onTap: () => _push(context, const ExpensesScreen()),
                        ),
                      // Counting the drawer. Sits beside Accounts because
                      // that is the balance it is checked against.
                      if (vm.can(Permission.shiftsManage) ||
                          vm.can(Permission.shiftsView))
                        _MoreTile(
                          icon: Icons.point_of_sale_rounded,
                          color: AppColors.primary,
                          label: context.t('shift'),
                          onTap: () => _push(context, const ShiftScreen()),
                        ),
                      if (vm.can(Permission.accountsView))
                        _MoreTile(
                          icon: Icons.savings_rounded,
                          color: AppColors.success,
                          label: context.t('accountsPayments'),
                          onTap: () => _push(context, const AccountsScreen()),
                        ),
                      if (vm.can(Permission.accountsManage))
                        _MoreTile(
                          icon: Icons.account_balance_wallet_rounded,
                          color: AppColors.teal,
                          label: context.t('managePayments'),
                          onTap: () =>
                              _push(context, const PaymentMethodsScreen()),
                        ),
                    ],
                  ),
                ),

                // Always rendered: Security is per-user, so even a waiter has
                // their own 2FA, devices and password to manage here.
                const SizedBox(height: AppSpacing.lg),
                Entrance(
                  index: 2,
                  child: _Group(
                    title: context.t('administration'),
                    tiles: <Widget>[
                      if (vm.can(Permission.usersView))
                        _MoreTile(
                          icon: Icons.groups_rounded,
                          color: AppColors.primary,
                          label: context.t('usersRoles'),
                          onTap: () => _push(context, const UsersScreen()),
                        ),
                      _MoreTile(
                        icon: Icons.shield_rounded,
                        color: AppColors.success,
                        label: context.t('security'),
                        badge: vm.securityAttention ? 1 : 0,
                        onTap: () => _push(context, const SecurityScreen()),
                      ),
                      if (vm.can(Permission.settingsView))
                        _MoreTile(
                          icon: Icons.settings_rounded,
                          color: AppColors.teal,
                          label: context.t('settings'),
                          onTap: () => _push(context, const SettingsScreen()),
                        ),
                    ],
                  ),
                ),

                const SizedBox(height: AppSpacing.lg),
                Entrance(
                  index: 3,
                  child: _Group(
                    title: context.t('system'),
                    tiles: <Widget>[
                      if (vm.can(Permission.auditView))
                        _MoreTile(
                          icon: Icons.history_rounded,
                          color: AppColors.info,
                          label: context.t('auditLogs'),
                          onTap: () => _push(context, const AuditScreen()),
                        ),
                      _MoreTile(
                        icon: Icons.help_outline_rounded,
                        color: AppColors.secondary,
                        label: context.t('helpSupport'),
                        onTap: () => _push(context, const SupportScreen()),
                      ),
                      _MoreTile(
                        icon: Icons.info_outline_rounded,
                        color: AppColors.violet,
                        label: context.t('aboutApp'),
                        onTap: () => _push(context, const AboutScreen()),
                      ),
                      _MoreTile(
                        icon: Icons.logout_rounded,
                        color: AppColors.danger,
                        label: context.t('logout'),
                        danger: true,
                        onTap: () => _confirmLogout(context, vm),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static void _push(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  Future<void> _confirmLogout(BuildContext context, _MoreVm vm) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(context.t('logoutTitle')),
        content: Text(context.t('logoutBody')),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.t('cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.t('logout')),
          ),
        ],
      ),
    );
    if (ok ?? false) vm.onLogout();
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.vm});

  final _MoreVm vm;

  @override
  Widget build(BuildContext context) {
    final AppUser? user = vm.user;
    final String roleKey = switch (user?.role) {
      UserRole.admin => 'admin',
      UserRole.operator => 'operator',
      UserRole.waiter => 'waiter',
      null => 'admin',
    };

    return GradientCard(
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const UsersScreen())),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        children: <Widget>[
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.24),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white38),
            ),
            child: Center(
              child: Text(
                user?.initials ?? '?',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  user?.name ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${context.t(roleKey)} · ${vm.restaurantName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: Colors.white),
        ],
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.title, required this.tiles});

  final String title;
  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    if (tiles.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(
            left: AppSpacing.xs,
            bottom: AppSpacing.sm,
          ),
          child: Text(
            title.toUpperCase(),
            style: context.texts.labelSmall?.copyWith(letterSpacing: 1),
          ),
        ),
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Column(
            children: List<Widget>.generate(tiles.length * 2 - 1, (int i) {
              if (i.isOdd) {
                return Divider(height: 1, color: context.palette.border);
              }
              return tiles[i ~/ 2];
            }),
          ),
        ),
      ],
    );
  }
}

class _MoreTile extends StatelessWidget {
  const _MoreTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
    this.badge = 0,
    this.danger = false,
  });

  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;
  final int badge;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md - 1),
        child: Row(
          children: <Widget>[
            IconBadge(icon: icon, color: color, size: 34, iconSize: 17),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                label,
                style: context.texts.titleMedium?.copyWith(
                  color: danger ? AppColors.danger : context.palette.text,
                ),
              ),
            ),
            if (badge > 0)
              Container(
                margin: const EdgeInsets.only(right: AppSpacing.sm),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(
                  '$badge',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            if (!danger)
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: context.palette.subtext,
              ),
          ],
        ),
      ),
    );
  }
}

class _MoreVm {
  const _MoreVm({
    required this.user,
    required this.restaurantName,
    required this.draftCount,
    required this.permissions,
    required this.securityAttention,
    required this.onLogout,
  });

  factory _MoreVm.from(Store<AppState> store) {
    final AppState s = store.state;
    return _MoreVm(
      user: s.auth.user,
      restaurantName: s.restaurant.restaurant?.name ?? '',
      draftCount: s.drafts.openCount,
      permissions: s.auth.user?.permissions ?? const <Permission>{},
      // A badge on Security when the server told us something is outstanding.
      securityAttention: s.auth.mustChangePassword || s.auth.mustEnrolTwoFactor,
      // Revokes the server-side token, clears state, then re-establishes a
      // session. Until the sign-in screen lands in Phase 3 this keeps logout a
      // real action without stranding the user on a splash with no way back.
      onLogout: () => Effects.signOut(store),
    );
  }

  final AppUser? user;
  final String restaurantName;
  final int draftCount;
  final Set<Permission> permissions;
  final bool securityAttention;
  final VoidCallback onLogout;

  bool can(Permission p) => permissions.contains(p);

  bool canAny(List<Permission> ps) => ps.any(permissions.contains);
}
