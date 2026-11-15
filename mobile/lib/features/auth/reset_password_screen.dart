import 'package:flutter/material.dart';

import '../../core/i18n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../data/api/api_client.dart';
import '../../data/api/dacaam_api.dart';
import '../../redux/effects.dart';
import '../../widgets/buttons.dart';

/// Takes the emailed token and sets a new password.
///
/// The password rules are the restaurant's own and live on the server, so this
/// screen checks only that the two entries match and are not empty, then lets
/// the API be the authority. Duplicating the policy here would mean two rules
/// that drift apart.
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key, this.token = ''});

  final String token;

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  late final TextEditingController _token = TextEditingController(
    text: widget.token,
  );
  final TextEditingController _password = TextEditingController();
  final TextEditingController _confirm = TextEditingController();

  bool _busy = false;
  bool _done = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _token.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.t('resetPassword'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.gutter),
          children: _done ? _success(context) : _form(context),
        ),
      ),
    );
  }

  List<Widget> _form(BuildContext context) {
    return <Widget>[
      Text(
        context.t('resetPasswordBody'),
        style: context.texts.bodyMedium?.copyWith(
          color: context.palette.subtext,
        ),
      ),
      const SizedBox(height: AppSpacing.xl),

      Text(context.t('resetToken'), style: context.texts.labelMedium),
      const SizedBox(height: AppSpacing.xs),
      TextField(
        controller: _token,
        maxLines: 2,
        minLines: 1,
        decoration: InputDecoration(hintText: context.t('resetTokenHint')),
      ),
      const SizedBox(height: AppSpacing.lg),

      Text(context.t('newPassword'), style: context.texts.labelMedium),
      const SizedBox(height: AppSpacing.xs),
      TextField(
        controller: _password,
        obscureText: _obscure,
        decoration: InputDecoration(
          hintText: '••••••••',
          suffixIcon: IconButton(
            icon: Icon(
              _obscure
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              size: 19,
            ),
            onPressed: () => setState(() => _obscure = !_obscure),
          ),
        ),
      ),
      const SizedBox(height: AppSpacing.lg),

      Text(context.t('confirmPassword'), style: context.texts.labelMedium),
      const SizedBox(height: AppSpacing.xs),
      TextField(
        controller: _confirm,
        obscureText: _obscure,
        decoration: const InputDecoration(hintText: '••••••••'),
      ),

      if (_error != null) ...<Widget>[
        const SizedBox(height: AppSpacing.md),
        Text(
          _error!,
          style: context.texts.bodySmall?.copyWith(color: AppColors.danger),
        ),
      ],

      const SizedBox(height: AppSpacing.xl),
      GradientButton(
        label: context.t('resetPassword'),
        height: 52,
        loading: _busy,
        onPressed: _busy ? null : _submit,
      ),
    ];
  }

  List<Widget> _success(BuildContext context) {
    return <Widget>[
      const SizedBox(height: AppSpacing.xxl),
      const Center(
        child: Icon(
          Icons.check_circle_rounded,
          size: 56,
          color: AppColors.success,
        ),
      ),
      const SizedBox(height: AppSpacing.lg),
      Text(
        context.t('passwordChanged'),
        textAlign: TextAlign.center,
        style: context.texts.titleMedium,
      ),
      const SizedBox(height: AppSpacing.xxl),
      GradientButton(
        label: context.t('backToLogin'),
        height: 52,
        // Pops both this and the forgot screen, landing back on sign-in rather
        // than on the form the user has already finished with.
        onPressed: () =>
            Navigator.of(context).popUntil((Route<void> r) => r.isFirst),
      ),
    ];
  }

  Future<void> _submit() async {
    final String token = _token.text.trim();
    final String password = _password.text;

    if (token.isEmpty || password.isEmpty) {
      setState(() => _error = context.t('required'));

      return;
    }

    if (password != _confirm.text) {
      setState(() => _error = context.t('passwordsDoNotMatch'));

      return;
    }

    final DacaamApi? api = Effects.api;
    if (api == null) {
      setState(() => _error = context.t('needsConnection'));

      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await api.resetPassword(token: token, newPassword: password);
      if (mounted) setState(() => _done = true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    }
  }
}
