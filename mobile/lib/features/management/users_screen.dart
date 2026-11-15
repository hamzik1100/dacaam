import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:redux/redux.dart';

import '../../core/i18n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/utils/enums.dart';
import '../../data/api/api_client.dart';
import '../../data/api/dacaam_api.dart';
import '../../data/models/restaurant.dart';
import '../../redux/app_state.dart';
import '../../redux/effects.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_sheet.dart';
import '../../widgets/buttons.dart';
import '../../widgets/common.dart';
import '../../widgets/entrance.dart';
import '../../widgets/skeletons.dart';
import '../../widgets/states.dart';

/// Staff, their roles, and exactly what each of them may do.
///
/// The permission tree shown here is the same set the shell reads to decide
/// which tabs and actions to render, so "what the screen says" and "what the
/// app allows" cannot drift.
class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  List<Map<String, dynamic>> _users = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _permissions = <Map<String, dynamic>>[];
  bool _loading = true;
  String? _error;

  DacaamApi? get _api => Effects.api;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final DacaamApi? api = _api;
    if (api == null) {
      setState(() => _loading = false);

      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final List<dynamic> users = await api.users();
      final List<dynamic> permissions = await api.permissions();
      if (!mounted) return;

      setState(() {
        _users = users
            .map((dynamic u) => (u as Map).cast<String, dynamic>())
            .toList();
        _permissions = permissions
            .map((dynamic p) => (p as Map).cast<String, dynamic>())
            .toList();
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return StoreConnector<AppState, _UsersVm>(
      converter: _UsersVm.from,
      builder: (BuildContext context, _UsersVm vm) {
        return Scaffold(
          appBar: AppBar(
            title: Text(context.t('usersRoles')),
            actions: <Widget>[
              if (vm.canCreate && _api != null)
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.gutter),
                  child: Material(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(12),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => _editUser(null, vm),
                      child: const SizedBox(
                        width: 38,
                        height: 38,
                        child: Icon(
                          Icons.person_add_alt_1_rounded,
                          color: Colors.white,
                          size: 19,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          body: _body(vm),
        );
      },
    );
  }

  Widget _body(_UsersVm vm) {
    // Offline the staff list still renders from the seeded dataset — it is
    // read-only there, because there is no server to persist a change to.
    if (_api == null) return _OfflineList(staff: vm.staff);

    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.gutter),
        child: ListSkeleton(hasThumb: false),
      );
    }
    if (_error != null) {
      return ErrorStateView(message: _error, onRetry: _load);
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.primary,
      child: ListView.builder(
        padding: const EdgeInsets.all(AppSpacing.gutter),
        itemCount: _users.length,
        itemBuilder: (BuildContext context, int i) {
          final Map<String, dynamic> user = _users[i];

          return Entrance(
            index: i,
            child: Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: _UserTile(user: user, onTap: () => _openUser(user, vm)),
            ),
          );
        },
      ),
    );
  }

  Future<void> _openUser(Map<String, dynamic> user, _UsersVm vm) async {
    final String? action = await showAppSheet<String>(
      context,
      builder: (BuildContext context) => _UserSheet(
        user: user,
        permissions: _permissions,
        canEdit: vm.canEdit,
        canDelete: vm.canDelete,
        isSelf: (user['id'] as int) == vm.currentUserId,
      ),
    );

    if (action == null || !mounted) return;

    switch (action) {
      case 'edit':
        await _editUser(user, vm);
      case 'permissions':
        await _editPermissions(user);
      case 'deactivate':
        await _deactivate(user);
    }
  }

  Future<void> _editUser(Map<String, dynamic>? user, _UsersVm vm) async {
    final Map<String, dynamic>? payload =
        await showAppSheet<Map<String, dynamic>>(
          context,
          builder: (BuildContext context) => _UserFormSheet(user: user),
        );
    if (payload == null) return;

    try {
      if (user == null) {
        await _api!.createUser(payload);
      } else {
        await _api!.updateUser(user['id'] as int, payload);
      }
      await _load();
      if (!mounted) return;
      _snack(context.t('done'));
    } on ApiException catch (e) {
      _snack(e.fields.values.firstOrNull ?? e.message);
    }
  }

  Future<void> _editPermissions(Map<String, dynamic> user) async {
    final Map<String, bool>? overrides = await showAppSheet<Map<String, bool>>(
      context,
      builder: (BuildContext context) =>
          _PermissionEditorSheet(user: user, permissions: _permissions),
    );
    if (overrides == null) return;

    try {
      await _api!.setUserPermissions(user['id'] as int, overrides);
      await _load();
      if (!mounted) return;
      _snack(context.t('done'));
    } on ApiException catch (e) {
      _snack(e.message);
    }
  }

  Future<void> _deactivate(Map<String, dynamic> user) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(context.t('deactivate')),
        content: Text('${user['name']}'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.t('cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.t('deactivate')),
          ),
        ],
      ),
    );
    if (!(ok ?? false)) return;

    try {
      await _api!.deactivateUser(user['id'] as int);
      await _load();
    } on ApiException catch (e) {
      _snack(e.message);
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

// ============================================================== components

Color _roleColor(String role) => switch (role) {
  'admin' => AppColors.primary,
  'operator' => AppColors.info,
  _ => AppColors.success,
};

String _roleLabel(BuildContext context, String role) => switch (role) {
  'admin' => context.t('admin'),
  'operator' => context.t('operator'),
  _ => context.t('waiter'),
};

String _initials(String name) {
  final List<String> parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((String p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();

  return (parts[0].substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
}

class _UserTile extends StatelessWidget {
  const _UserTile({required this.user, required this.onTap});

  final Map<String, dynamic> user;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final String role = '${user['role']}';
    final Color color = _roleColor(role);
    final bool active = user['is_active'] == true;
    final bool twoFactor = user['two_factor_enabled'] == true;

    return Opacity(
      opacity: active ? 1 : 0.5,
      child: AppCard(
        onTap: onTap,
        child: Row(
          children: <Widget>[
            CircleAvatar(
              radius: 22,
              backgroundColor: color.withValues(
                alpha: context.isDark ? 0.24 : 0.13,
              ),
              child: Text(
                _initials('${user['name']}'),
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          '${user['name']}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.texts.titleMedium,
                        ),
                      ),
                      if (twoFactor) ...<Widget>[
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.shield_rounded,
                          size: 13,
                          color: AppColors.success,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text('${user['phone']}', style: context.texts.bodySmall),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                StatusChip(label: _roleLabel(context, role), color: color),
                const SizedBox(height: 5),
                Text(
                  '${(user['permissions'] as List<dynamic>?)?.length ?? 0} perms',
                  style: context.texts.labelSmall?.copyWith(fontSize: 10),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Read-only fallback when there is no backend to talk to.
class _OfflineList extends StatelessWidget {
  const _OfflineList({required this.staff});

  final List<AppUser> staff;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(AppSpacing.gutter),
      itemCount: staff.length,
      itemBuilder: (BuildContext context, int i) {
        final AppUser u = staff[i];
        final Color color = _roleColor(u.role.api);

        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: AppCard(
            child: Row(
              children: <Widget>[
                CircleAvatar(
                  radius: 22,
                  backgroundColor: color.withValues(
                    alpha: context.isDark ? 0.24 : 0.13,
                  ),
                  child: Text(
                    u.initials,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(u.name, style: context.texts.titleMedium),
                      Text(u.phone, style: context.texts.bodySmall),
                    ],
                  ),
                ),
                StatusChip(
                  label: _roleLabel(context, u.role.api),
                  color: color,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _UserSheet extends StatelessWidget {
  const _UserSheet({
    required this.user,
    required this.permissions,
    required this.canEdit,
    required this.canDelete,
    required this.isSelf,
  });

  final Map<String, dynamic> user;
  final List<Map<String, dynamic>> permissions;
  final bool canEdit;
  final bool canDelete;
  final bool isSelf;

  @override
  Widget build(BuildContext context) {
    final List<String> held =
        ((user['permissions'] as List<dynamic>?) ?? <dynamic>[])
            .map((dynamic p) => '$p')
            .toList();

    final Map<String, List<Map<String, dynamic>>> grouped =
        <String, List<Map<String, dynamic>>>{};
    for (final Map<String, dynamic> p in permissions) {
      grouped
          .putIfAbsent('${p['module']}', () => <Map<String, dynamic>>[])
          .add(p);
    }

    return AppSheet(
      title: '${user['name']}',
      subtitle: _roleLabel(context, '${user['role']}'),
      footer: canEdit
          ? Row(
              children: <Widget>[
                if (canDelete && !isSelf) ...<Widget>[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, 'deactivate'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 50),
                        foregroundColor: AppColors.danger,
                        side: const BorderSide(color: AppColors.danger),
                      ),
                      child: Text(context.t('deactivate')),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                ],
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, 'permissions'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 50),
                    ),
                    child: Text(context.t('permissions')),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: GradientButton(
                    label: context.t('edit'),
                    height: 50,
                    onPressed: () => Navigator.pop(context, 'edit'),
                  ),
                ),
              ],
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          AppCard(
            child: Column(
              children: <Widget>[
                DetailRow(
                  label: context.t('phone'),
                  value: '${user['phone']}',
                  icon: Icons.phone_rounded,
                  dense: true,
                ),
                DetailRow(
                  label: context.t('twoFactor'),
                  value: user['two_factor_enabled'] == true
                      ? context.t('twoFactorOn')
                      : context.t('twoFactorOff'),
                  icon: Icons.shield_rounded,
                  dense: true,
                ),
                DetailRow(
                  label: context.t('status'),
                  value: user['is_active'] == true
                      ? context.t('active')
                      : context.t('inactive'),
                  icon: Icons.toggle_on_rounded,
                  dense: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          ...grouped.entries.map(
            (MapEntry<String, List<Map<String, dynamic>>> entry) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(_titleCase(entry.key), style: context.texts.titleMedium),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: entry.value.map((Map<String, dynamic> p) {
                      final bool granted = held.contains('${p['code']}');

                      return StatusChip(
                        label: _titleCase('${p['action']}'),
                        color: granted
                            ? AppColors.success
                            : context.palette.subtext,
                        icon: granted
                            ? Icons.check_rounded
                            : Icons.close_rounded,
                        filled: granted,
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UserFormSheet extends StatefulWidget {
  const _UserFormSheet({this.user});

  final Map<String, dynamic>? user;

  @override
  State<_UserFormSheet> createState() => _UserFormSheetState();
}

class _UserFormSheetState extends State<_UserFormSheet> {
  late final TextEditingController _name = TextEditingController(
    text: '${widget.user?['name'] ?? ''}',
  );
  late final TextEditingController _phone = TextEditingController(
    text: '${widget.user?['phone'] ?? ''}',
  );
  final TextEditingController _password = TextEditingController();

  late String _role = '${widget.user?['role'] ?? 'waiter'}';
  late bool _active = widget.user?['is_active'] as bool? ?? true;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isNew = widget.user == null;

    return AppSheet(
      title: isNew ? context.t('addUser') : context.t('editUser'),
      footer: GradientButton(
        label: context.t('save'),
        icon: Icons.check_rounded,
        onPressed: _submit,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(labelText: context.t('name')),
          ),
          const SizedBox(height: AppSpacing.lg),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(labelText: context.t('phone')),
          ),
          const SizedBox(height: AppSpacing.lg),
          TextField(
            controller: _password,
            obscureText: true,
            decoration: InputDecoration(
              labelText: isNew
                  ? context.t('password')
                  : '${context.t('newPassword')} (${context.t('optional')})',
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(context.t('role'), style: context.texts.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: <String>['admin', 'operator', 'waiter'].map((
              String role,
            ) {
              final bool selected = _role == role;

              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.sm),
                  child: Material(
                    color: selected ? _roleColor(role) : context.palette.card,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => setState(() => _role = role),
                      child: Container(
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          border: Border.all(
                            color: selected
                                ? _roleColor(role)
                                : context.palette.border,
                          ),
                        ),
                        child: Text(
                          _roleLabel(context, role),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.texts.titleSmall?.copyWith(
                            color: selected
                                ? Colors.white
                                : context.palette.subtext,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: AppSpacing.md),
          SwitchListTile.adaptive(
            value: _active,
            onChanged: (bool v) => setState(() => _active = v),
            contentPadding: EdgeInsets.zero,
            title: Text(context.t('active'), style: context.texts.titleSmall),
            activeThumbColor: Colors.white,
            activeTrackColor: AppColors.success,
          ),
        ],
      ),
    );
  }

  void _submit() {
    final Map<String, dynamic> payload = <String, dynamic>{
      'name': _name.text.trim(),
      'phone': _phone.text.trim(),
      'role_code': _role,
      'is_active': _active,
    };
    if (_password.text.isNotEmpty) {
      payload['password'] = _password.text;
    }

    Navigator.of(context).pop(payload);
  }
}

/// Three-state permission editor: inherit from the role, force on, force off.
class _PermissionEditorSheet extends StatefulWidget {
  const _PermissionEditorSheet({required this.user, required this.permissions});

  final Map<String, dynamic> user;
  final List<Map<String, dynamic>> permissions;

  @override
  State<_PermissionEditorSheet> createState() => _PermissionEditorSheetState();
}

class _PermissionEditorSheetState extends State<_PermissionEditorSheet> {
  late final Map<String, bool> _overrides;

  @override
  void initState() {
    super.initState();
    // Seeded from what the user effectively holds today. Submitting writes
    // every entry as an explicit override, which is what makes "this one
    // waiter may cancel" expressible without inventing a role.
    final List<String> held =
        ((widget.user['permissions'] as List<dynamic>?) ?? <dynamic>[])
            .map((dynamic p) => '$p')
            .toList();

    _overrides = <String, bool>{
      for (final Map<String, dynamic> p in widget.permissions)
        '${p['code']}': held.contains('${p['code']}'),
    };
  }

  @override
  Widget build(BuildContext context) {
    final Map<String, List<Map<String, dynamic>>> grouped =
        <String, List<Map<String, dynamic>>>{};
    for (final Map<String, dynamic> p in widget.permissions) {
      grouped
          .putIfAbsent('${p['module']}', () => <Map<String, dynamic>>[])
          .add(p);
    }

    return AppSheet(
      title: context.t('permissions'),
      subtitle: '${widget.user['name']}',
      footer: GradientButton(
        label: context.t('save'),
        icon: Icons.check_rounded,
        onPressed: () => Navigator.of(context).pop(_overrides),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: grouped.entries.map((
          MapEntry<String, List<Map<String, dynamic>>> entry,
        ) {
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.lg),
            child: AppCard(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.only(
                      top: AppSpacing.sm,
                      bottom: AppSpacing.xs,
                    ),
                    child: Text(
                      _titleCase(entry.key),
                      style: context.texts.titleMedium,
                    ),
                  ),
                  ...entry.value.map((Map<String, dynamic> p) {
                    final String code = '${p['code']}';

                    return SwitchListTile.adaptive(
                      value: _overrides[code] ?? false,
                      onChanged: (bool v) =>
                          setState(() => _overrides[code] = v),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        _titleCase('${p['action']}'),
                        style: context.texts.titleSmall,
                      ),
                      activeThumbColor: Colors.white,
                      activeTrackColor: AppColors.success,
                    );
                  }),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

String _titleCase(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

class _UsersVm {
  const _UsersVm({
    required this.staff,
    required this.currentUserId,
    required this.canCreate,
    required this.canEdit,
    required this.canDelete,
  });

  factory _UsersVm.from(Store<AppState> store) {
    return _UsersVm(
      staff: store.state.restaurant.staff,
      currentUserId: store.state.auth.user?.id ?? 0,
      canCreate: store.state.auth.can(Permission.usersCreate),
      canEdit: store.state.auth.can(Permission.usersEdit),
      canDelete: store.state.auth.can(Permission.usersDelete),
    );
  }

  final List<AppUser> staff;
  final int currentUserId;
  final bool canCreate;
  final bool canEdit;
  final bool canDelete;
}
