import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:redux/redux.dart';

import '../../core/i18n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/utils/enums.dart';
import '../../core/utils/formatters.dart';
import '../../data/api/api_client.dart';
import '../../data/api/dacaam_api.dart';
import '../../redux/app_state.dart';
import '../../redux/effects.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_sheet.dart';
import '../../widgets/buttons.dart';
import '../../widgets/common.dart';
import '../../widgets/entrance.dart';
import '../../widgets/skeletons.dart';
import '../../widgets/states.dart';

/// Settings → Security: two-factor, devices, login history, password.
class SecurityScreen extends StatefulWidget {
  const SecurityScreen({super.key});

  @override
  State<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends State<SecurityScreen> {
  Map<String, dynamic>? _overview;
  List<dynamic> _sessions = <dynamic>[];
  List<dynamic> _history = <dynamic>[];
  Map<String, dynamic>? _policy;

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
      final List<dynamic> results = await Future.wait<dynamic>(
        <Future<dynamic>>[
          api.securityOverview(),
          api.sessions(),
          api.loginHistory(),
        ],
      );

      Map<String, dynamic>? policy;
      try {
        policy = await api.securityPolicy();
      } on ApiException {
        // Reading the policy needs settings.view; a waiter simply does not see
        // that card.
        policy = null;
      }

      if (!mounted) return;
      setState(() {
        _overview = results[0] as Map<String, dynamic>;
        _sessions = results[1] as List<dynamic>;
        _history = results[2] as List<dynamic>;
        _policy = policy;
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
    return StoreConnector<AppState, _SecurityVm>(
      converter: _SecurityVm.from,
      builder: (BuildContext context, _SecurityVm vm) {
        return Scaffold(
          appBar: AppBar(title: Text(context.t('security'))),
          body: _body(vm),
        );
      },
    );
  }

  Widget _body(_SecurityVm vm) {
    if (_api == null) {
      return EmptyState(
        icon: Icons.cloud_off_rounded,
        title: context.t('comingSoon'),
        message:
            'Security settings need the DACAAM API. Run the backend and start '
            'the app with --dart-define=USE_API=true.',
      );
    }
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.gutter),
        child: ListSkeleton(hasThumb: false),
      );
    }
    if (_error != null) {
      return ErrorStateView(message: _error, onRetry: _load);
    }

    final bool twoFactorOn =
        (_overview?['two_factor']?['enabled'] as bool?) ?? false;
    final int remainingCodes =
        (_overview?['two_factor']?['unused_recovery_codes'] as int?) ?? 0;

    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.primary,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.gutter,
          0,
          AppSpacing.gutter,
          AppSpacing.xxxl,
        ),
        children: <Widget>[
          if (vm.mustChangePassword)
            Entrance(child: _Notice(message: context.t('mustChangePassword'))),
          if (vm.mustEnrolTwoFactor)
            Entrance(child: _Notice(message: context.t('mustEnrolTwoFactor'))),

          Entrance(
            index: 0,
            child: _TwoFactorCard(
              enabled: twoFactorOn,
              remainingCodes: remainingCodes,
              onEnable: _startTwoFactor,
              onDisable: _disableTwoFactor,
              onRegenerate: _regenerateCodes,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          Entrance(index: 1, child: _PasswordCard(onChange: _changePassword)),
          const SizedBox(height: AppSpacing.lg),

          Entrance(
            index: 2,
            child: _SessionsCard(
              sessions: _sessions,
              onRevoke: _revokeSession,
              onRevokeOthers: _revokeOthers,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          Entrance(index: 3, child: _HistoryCard(history: _history)),

          if (_policy != null && vm.canManageSettings) ...<Widget>[
            const SizedBox(height: AppSpacing.lg),
            Entrance(
              index: 4,
              child: _PolicyCard(policy: _policy!, onEdit: _editPolicy),
            ),
          ],
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ 2FA

  Future<void> _startTwoFactor() async {
    final DacaamApi api = _api!;

    try {
      final Map<String, dynamic> setup = await api.startTwoFactor();
      if (!mounted) return;

      final bool? confirmed = await showAppSheet<bool>(
        context,
        builder: (BuildContext context) => _EnrolSheet(
          secret: '${setup['secret']}',
          otpauthUri: '${setup['otpauth_uri']}',
          api: api,
        ),
      );

      if ((confirmed ?? false) && mounted) {
        Effects.resolveObligation(
          StoreProvider.of<AppState>(context, listen: false),
          twoFactorEnrolled: true,
        );
        await _load();
      }
    } on ApiException catch (e) {
      _snack(e.message);
    }
  }

  Future<void> _disableTwoFactor() async {
    final String? password = await _promptPassword(context.t('disable'));
    if (password == null) return;

    try {
      await _api!.disableTwoFactor(password);
      await _load();
    } on ApiException catch (e) {
      _snack(e.fields['password'] ?? e.message);
    }
  }

  Future<void> _regenerateCodes() async {
    final String? password = await _promptPassword(context.t('regenerate'));
    if (password == null) return;

    try {
      final Map<String, dynamic> result = await _api!.regenerateRecoveryCodes(
        password,
      );
      if (!mounted) return;

      await _showRecoveryCodes(
        (result['recovery_codes'] as List<dynamic>).cast<String>(),
      );
      await _load();
    } on ApiException catch (e) {
      _snack(e.fields['password'] ?? e.message);
    }
  }

  Future<void> _showRecoveryCodes(List<String> codes) async {
    await showAppSheet<void>(
      context,
      builder: (BuildContext context) => _RecoveryCodesSheet(codes: codes),
    );
  }

  // ------------------------------------------------------------- password

  Future<void> _changePassword() async {
    final bool? changed = await showAppSheet<bool>(
      context,
      builder: (BuildContext context) => _ChangePasswordSheet(api: _api!),
    );

    if ((changed ?? false) && mounted) {
      Effects.resolveObligation(
        StoreProvider.of<AppState>(context, listen: false),
        passwordChanged: true,
      );
      _snack(context.t('done'));
      await _load();
    }
  }

  // ------------------------------------------------------------- sessions

  Future<void> _revokeSession(int id) async {
    try {
      await _api!.revokeSession(id);
      await _load();
    } on ApiException catch (e) {
      _snack(e.message);
    }
  }

  Future<void> _revokeOthers() async {
    try {
      await _api!.revokeOtherSessions();
      await _load();
    } on ApiException catch (e) {
      _snack(e.message);
    }
  }

  // --------------------------------------------------------------- policy

  Future<void> _editPolicy() async {
    final Map<String, dynamic>? updated =
        await showAppSheet<Map<String, dynamic>>(
          context,
          builder: (BuildContext context) => _PolicySheet(policy: _policy!),
        );
    if (updated == null) return;

    try {
      await _api!.updateSecurityPolicy(updated);
      await _load();
    } on ApiException catch (e) {
      _snack(e.message);
    }
  }

  Future<String?> _promptPassword(String action) async {
    final TextEditingController controller = TextEditingController();

    final String? result = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(context.t('currentPassword')),
        content: TextField(
          controller: controller,
          obscureText: true,
          autofocus: true,
          decoration: InputDecoration(hintText: context.t('password')),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text(action),
          ),
        ],
      ),
    );
    controller.dispose();

    return (result == null || result.isEmpty) ? null : result;
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

// ============================================================== components

class _Notice extends StatelessWidget {
  const _Notice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: AppCard(
        elevated: false,
        color: AppColors.secondary.withValues(alpha: 0.12),
        borderColor: AppColors.secondary.withValues(alpha: 0.35),
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: <Widget>[
            const Icon(
              Icons.priority_high_rounded,
              size: 18,
              color: AppColors.secondary,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: Text(message, style: context.texts.titleSmall)),
          ],
        ),
      ),
    );
  }
}

class _TwoFactorCard extends StatelessWidget {
  const _TwoFactorCard({
    required this.enabled,
    required this.remainingCodes,
    required this.onEnable,
    required this.onDisable,
    required this.onRegenerate,
  });

  final bool enabled;
  final int remainingCodes;
  final VoidCallback onEnable;
  final VoidCallback onDisable;
  final VoidCallback onRegenerate;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              IconBadge(
                icon: Icons.shield_rounded,
                color: enabled ? AppColors.success : AppColors.subtextLight,
                size: 42,
                iconSize: 20,
                radius: 12,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      context.t('twoFactor'),
                      style: context.texts.titleMedium,
                    ),
                    Text(
                      enabled
                          ? context.t('twoFactorOn')
                          : context.t('twoFactorOff'),
                      style: context.texts.bodySmall,
                    ),
                  ],
                ),
              ),
              StatusChip(
                label: enabled
                    ? context.t('twoFactorOn')
                    : context.t('twoFactorOff'),
                color: enabled ? AppColors.success : AppColors.subtextLight,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          if (!enabled)
            GradientButton(
              label: context.t('enable'),
              icon: Icons.lock_rounded,
              height: 48,
              onPressed: onEnable,
            )
          else ...<Widget>[
            Row(
              children: <Widget>[
                Icon(
                  Icons.vpn_key_rounded,
                  size: 15,
                  color: context.palette.subtext,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    context.tp('recoveryCodesRemaining', <String, String>{
                      'n': '$remainingCodes',
                    }),
                    style: context.texts.bodySmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    onPressed: onRegenerate,
                    child: Text(context.t('regenerate')),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: OutlinedButton(
                    onPressed: onDisable,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.danger,
                      side: const BorderSide(color: AppColors.danger),
                    ),
                    child: Text(context.t('disable')),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _EnrolSheet extends StatefulWidget {
  const _EnrolSheet({
    required this.secret,
    required this.otpauthUri,
    required this.api,
  });

  final String secret;
  final String otpauthUri;
  final DacaamApi api;

  @override
  State<_EnrolSheet> createState() => _EnrolSheetState();
}

class _EnrolSheetState extends State<_EnrolSheet> {
  final TextEditingController _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppSheet(
      title: context.t('twoFactor'),
      subtitle: context.t('scanQr'),
      footer: GradientButton(
        label: context.t('verify'),
        icon: Icons.check_rounded,
        loading: _busy,
        onPressed: _confirm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Center(
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                // The QR must stay black-on-white even in dark mode; scanners
                // read contrast, not themes.
                color: Colors.white,
                borderRadius: AppRadius.cardLarge,
                border: Border.all(color: context.palette.border),
              ),
              child: QrImageView(
                data: widget.otpauthUri,
                size: 180,
                backgroundColor: Colors.white,
                eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: Colors.black,
                ),
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: Colors.black,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(context.t('orEnterKey'), style: context.texts.bodyMedium),
          const SizedBox(height: AppSpacing.sm),
          _CopyableCode(text: widget.secret),
          const SizedBox(height: AppSpacing.xl),
          Text(
            context.t('enterCodeToConfirm'),
            style: context.texts.titleSmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _code,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            enabled: !_busy,
            inputFormatters: <TextInputFormatter>[
              LengthLimitingTextInputFormatter(6),
            ],
            style: context.texts.headlineSmall?.copyWith(letterSpacing: 8),
            decoration: InputDecoration(hintText: '000000', errorText: _error),
            onSubmitted: (_) => _confirm(),
          ),
        ],
      ),
    );
  }

  Future<void> _confirm() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final Map<String, dynamic> result = await widget.api.confirmTwoFactor(
        _code.text.trim(),
      );
      if (!mounted) return;

      final List<String> codes = (result['recovery_codes'] as List<dynamic>)
          .cast<String>();

      await showAppSheet<void>(
        context,
        builder: (BuildContext context) => _RecoveryCodesSheet(codes: codes),
      );

      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.fields['code'] ?? e.message;
      });
    }
  }
}

class _RecoveryCodesSheet extends StatelessWidget {
  const _RecoveryCodesSheet({required this.codes});

  final List<String> codes;

  @override
  Widget build(BuildContext context) {
    return AppSheet(
      title: context.t('recoveryCodes'),
      subtitle: context.t('recoveryCodesHint'),
      footer: GradientButton(
        label: context.t('done'),
        icon: Icons.check_rounded,
        onPressed: () => Navigator.of(context).pop(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AppCard(
            color: context.palette.muted,
            elevated: false,
            child: Wrap(
              spacing: AppSpacing.lg,
              runSpacing: AppSpacing.md,
              alignment: WrapAlignment.center,
              children: codes
                  .map(
                    (String code) => Text(
                      code,
                      style: context.texts.titleMedium?.copyWith(
                        fontFeatures: const <FontFeature>[
                          FontFeature.tabularFigures(),
                        ],
                        letterSpacing: 1.5,
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          OutlinedButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: codes.join('\n')));
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text(context.t('copied'))));
            },
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: Text(context.t('copy')),
          ),
        ],
      ),
    );
  }
}

class _CopyableCode extends StatelessWidget {
  const _CopyableCode({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      color: context.palette.muted,
      elevated: false,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      onTap: () {
        Clipboard.setData(ClipboardData(text: text));
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.t('copied'))));
      },
      child: Row(
        children: <Widget>[
          Expanded(
            child: SelectableText(
              text,
              style: context.texts.titleSmall?.copyWith(letterSpacing: 1.2),
            ),
          ),
          Icon(Icons.copy_rounded, size: 17, color: context.palette.subtext),
        ],
      ),
    );
  }
}

class _PasswordCard extends StatelessWidget {
  const _PasswordCard({required this.onChange});

  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onChange,
      child: Row(
        children: <Widget>[
          const IconBadge(
            icon: Icons.password_rounded,
            color: AppColors.violet,
            size: 42,
            iconSize: 20,
            radius: 12,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              context.t('changePassword'),
              style: context.texts.titleMedium,
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: context.palette.subtext),
        ],
      ),
    );
  }
}

class _ChangePasswordSheet extends StatefulWidget {
  const _ChangePasswordSheet({required this.api});

  final DacaamApi api;

  @override
  State<_ChangePasswordSheet> createState() => _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends State<_ChangePasswordSheet> {
  final TextEditingController _current = TextEditingController();
  final TextEditingController _next = TextEditingController();
  final TextEditingController _confirm = TextEditingController();

  bool _busy = false;
  Map<String, String> _errors = <String, String>{};
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppSheet(
      title: context.t('changePassword'),
      footer: GradientButton(
        label: context.t('save'),
        icon: Icons.check_rounded,
        loading: _busy,
        onPressed: _submit,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          TextField(
            controller: _current,
            obscureText: true,
            enabled: !_busy,
            decoration: InputDecoration(
              labelText: context.t('currentPassword'),
              errorText: _errors['password'] ?? _errors['current_password'],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          TextField(
            controller: _next,
            obscureText: true,
            enabled: !_busy,
            decoration: InputDecoration(
              labelText: context.t('newPassword'),
              errorText: _errors['new_password'],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          TextField(
            controller: _confirm,
            obscureText: true,
            enabled: !_busy,
            decoration: InputDecoration(
              labelText: context.t('confirmPassword'),
            ),
          ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: AppSpacing.lg),
            Text(
              _error!,
              style: context.texts.bodyMedium?.copyWith(
                color: AppColors.danger,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _submit() async {
    if (_busy) return;

    if (_next.text != _confirm.text) {
      setState(() => _error = context.t('passwordsDoNotMatch'));

      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _errors = <String, String>{};
    });

    try {
      await widget.api.changePassword(
        currentPassword: _current.text,
        newPassword: _next.text,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errors = e.fields;
        _error = e.fields.isEmpty ? e.message : null;
      });
    }
  }
}

class _SessionsCard extends StatelessWidget {
  const _SessionsCard({
    required this.sessions,
    required this.onRevoke,
    required this.onRevokeOthers,
  });

  final List<dynamic> sessions;
  final ValueChanged<int> onRevoke;
  final VoidCallback onRevokeOthers;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SectionHeader(
            title: context.t('sessions'),
            actionLabel: sessions.length > 1 ? context.t('revokeOthers') : null,
            onAction: onRevokeOthers,
          ),
          ...sessions.map((dynamic raw) {
            final Map<String, dynamic> s = (raw as Map).cast<String, dynamic>();
            final bool isCurrent = s['is_current'] == true;

            return Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Row(
                children: <Widget>[
                  IconBadge(
                    icon: isCurrent
                        ? Icons.phone_iphone_rounded
                        : Icons.devices_rounded,
                    color: isCurrent ? AppColors.success : AppColors.info,
                    size: 34,
                    iconSize: 17,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          '${s['device']}'.isEmpty
                              ? context.t('noData')
                              : '${s['device']}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.texts.titleSmall,
                        ),
                        Text(
                          '${s['ip']} · ${_relative(context, s['last_used_at'] ?? s['created_at'])}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.texts.bodySmall?.copyWith(
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isCurrent)
                    StatusChip(
                      label: context.t('thisDevice'),
                      color: AppColors.success,
                      dense: true,
                    )
                  else
                    TextButton(
                      onPressed: () => onRevoke(s['id'] as int),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.danger,
                      ),
                      child: Text(context.t('revoke')),
                    ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  static String _relative(BuildContext context, dynamic iso) {
    final DateTime? at = DateTime.tryParse('$iso');

    return at == null
        ? context.t('never')
        : Fmt.relative(at.toLocal(), context.lang);
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.history});

  final List<dynamic> history;

  @override
  Widget build(BuildContext context) {
    final List<dynamic> recent = history.take(12).toList();

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SectionHeader(title: context.t('loginHistory')),
          if (recent.isEmpty)
            Text(context.t('noData'), style: context.texts.bodyMedium)
          else
            ...recent.map((dynamic raw) {
              final Map<String, dynamic> h = (raw as Map)
                  .cast<String, dynamic>();
              final bool ok = h['succeeded'] == true;
              final DateTime? at = DateTime.tryParse('${h['created_at']}');

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: <Widget>[
                    Icon(
                      ok ? Icons.check_circle_rounded : Icons.cancel_rounded,
                      size: 15,
                      color: ok ? AppColors.success : AppColors.danger,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        '${h['user_name']}'.isEmpty
                            ? '${h['phone']}'
                            : '${h['user_name']}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.texts.titleSmall,
                      ),
                    ),
                    Text(
                      at == null
                          ? ''
                          : Fmt.dateTime(at.toLocal(), context.lang),
                      style: context.texts.bodySmall?.copyWith(fontSize: 11),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _PolicyCard extends StatelessWidget {
  const _PolicyCard({required this.policy, required this.onEdit});

  final Map<String, dynamic> policy;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic> password = (policy['password'] as Map)
        .cast<String, dynamic>();

    return AppCard(
      onTap: onEdit,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SectionHeader(
            title: context.t('passwordPolicy'),
            trailing: Icon(
              Icons.edit_rounded,
              size: 17,
              color: context.palette.subtext,
            ),
          ),
          DetailRow(
            label: context.t('minLength'),
            value: '${password['min_length']}',
            dense: true,
          ),
          DetailRow(
            label: context.t('requireNumber'),
            value: password['require_number'] == true
                ? context.t('yes')
                : context.t('no'),
            dense: true,
          ),
          DetailRow(
            label: context.t('requireUpper'),
            value: password['require_upper'] == true
                ? context.t('yes')
                : context.t('no'),
            dense: true,
          ),
          DetailRow(
            label: context.t('sessionTimeout'),
            value: '${policy['session_timeout_days']}',
            dense: true,
          ),
          DetailRow(
            label: context.t('maxFailedLogins'),
            value: '${policy['max_failed_logins']}',
            dense: true,
          ),
          DetailRow(
            label: context.t('requireTwoFactorAdmin'),
            value: policy['require_two_factor_admin'] == true
                ? context.t('yes')
                : context.t('no'),
            dense: true,
          ),
        ],
      ),
    );
  }
}

class _PolicySheet extends StatefulWidget {
  const _PolicySheet({required this.policy});

  final Map<String, dynamic> policy;

  @override
  State<_PolicySheet> createState() => _PolicySheetState();
}

class _PolicySheetState extends State<_PolicySheet> {
  late int _minLength;
  late bool _upper;
  late bool _number;
  late bool _symbol;
  late int _sessionDays;
  late int _maxFailed;
  late bool _require2fa;

  @override
  void initState() {
    super.initState();
    final Map<String, dynamic> p = (widget.policy['password'] as Map)
        .cast<String, dynamic>();
    _minLength = p['min_length'] as int? ?? 6;
    _upper = p['require_upper'] == true;
    _number = p['require_number'] == true;
    _symbol = p['require_symbol'] == true;
    _sessionDays = widget.policy['session_timeout_days'] as int? ?? 30;
    _maxFailed = widget.policy['max_failed_logins'] as int? ?? 5;
    _require2fa = widget.policy['require_two_factor_admin'] == true;
  }

  @override
  Widget build(BuildContext context) {
    return AppSheet(
      title: context.t('passwordPolicy'),
      footer: GradientButton(
        label: context.t('save'),
        icon: Icons.check_rounded,
        onPressed: () => Navigator.of(context).pop(<String, dynamic>{
          'password_min_length': _minLength,
          'password_require_upper': _upper,
          'password_require_number': _number,
          'password_require_symbol': _symbol,
          'session_timeout_days': _sessionDays,
          'max_failed_logins': _maxFailed,
          'require_two_factor_admin': _require2fa,
        }),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _Stepper(
            label: context.t('minLength'),
            value: _minLength,
            min: 4,
            max: 32,
            onChanged: (int v) => setState(() => _minLength = v),
          ),
          _Toggle(
            label: context.t('requireUpper'),
            value: _upper,
            onChanged: (bool v) => setState(() => _upper = v),
          ),
          _Toggle(
            label: context.t('requireNumber'),
            value: _number,
            onChanged: (bool v) => setState(() => _number = v),
          ),
          _Toggle(
            label: context.t('requireSymbol'),
            value: _symbol,
            onChanged: (bool v) => setState(() => _symbol = v),
          ),
          const Divider(height: AppSpacing.xxl),
          _Stepper(
            label: context.t('sessionTimeout'),
            value: _sessionDays,
            min: 1,
            max: 365,
            step: 7,
            onChanged: (int v) => setState(() => _sessionDays = v),
          ),
          _Stepper(
            label: context.t('maxFailedLogins'),
            value: _maxFailed,
            min: 3,
            max: 20,
            onChanged: (int v) => setState(() => _maxFailed = v),
          ),
          _Toggle(
            label: context.t('requireTwoFactorAdmin'),
            value: _require2fa,
            onChanged: (bool v) => setState(() => _require2fa = v),
          ),
        ],
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.step = 1,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final int step;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label, style: context.texts.titleSmall)),
          QuantityStepper(
            quantity: value,
            compact: true,
            onIncrement: () => onChanged((value + step).clamp(min, max)),
            onDecrement: () => onChanged((value - step).clamp(min, max)),
          ),
        ],
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile.adaptive(
      value: value,
      onChanged: onChanged,
      contentPadding: EdgeInsets.zero,
      title: Text(label, style: context.texts.titleSmall),
      activeThumbColor: Colors.white,
      activeTrackColor: AppColors.primary,
    );
  }
}

class _SecurityVm {
  const _SecurityVm({
    required this.mustChangePassword,
    required this.mustEnrolTwoFactor,
    required this.canManageSettings,
  });

  factory _SecurityVm.from(Store<AppState> store) {
    return _SecurityVm(
      mustChangePassword: store.state.auth.mustChangePassword,
      mustEnrolTwoFactor: store.state.auth.mustEnrolTwoFactor,
      canManageSettings: store.state.auth.can(Permission.settingsManage),
    );
  }

  final bool mustChangePassword;
  final bool mustEnrolTwoFactor;
  final bool canManageSettings;
}
