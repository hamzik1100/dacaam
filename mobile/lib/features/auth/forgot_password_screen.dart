import 'package:flutter/material.dart';

import '../../core/i18n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../data/api/api_client.dart';
import '../../data/api/dacaam_api.dart';
import '../../redux/effects.dart';
import '../../widgets/buttons.dart';
import 'reset_password_screen.dart';

/// Asks for the restaurant code and phone, and has the server email a link.
///
/// The confirmation is deliberately the same whether or not the account exists.
/// Telling an unknown caller "no such phone" turns this screen into a way to
/// find out which numbers are registered, and staff phone numbers are not ours
/// to leak.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.restaurantCode = ''});

  final String restaurantCode;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  late final TextEditingController _code = TextEditingController(
    text: widget.restaurantCode,
  );
  final TextEditingController _phone = TextEditingController();

  bool _busy = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.t('forgotPassword'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.gutter),
          children: <Widget>[
            if (_sent) ..._confirmation(context) else ..._form(context),
          ],
        ),
      ),
    );
  }

  List<Widget> _form(BuildContext context) {
    return <Widget>[
      Text(
        context.t('forgotPasswordBody'),
        style: context.texts.bodyMedium?.copyWith(
          color: context.palette.subtext,
        ),
      ),
      const SizedBox(height: AppSpacing.xl),

      Text(context.t('restaurantCode'), style: context.texts.labelMedium),
      const SizedBox(height: AppSpacing.xs),
      TextField(
        controller: _code,
        textCapitalization: TextCapitalization.characters,
        decoration: const InputDecoration(hintText: 'Restaurant Code'),
      ),
      const SizedBox(height: AppSpacing.lg),

      Text(context.t('phone'), style: context.texts.labelMedium),
      const SizedBox(height: AppSpacing.xs),
      TextField(
        controller: _phone,
        keyboardType: TextInputType.phone,
        decoration: const InputDecoration(hintText: '063XXXXXXX'),
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
        label: context.t('sendResetLink'),
        height: 52,
        loading: _busy,
        onPressed: _busy ? null : _submit,
      ),
      const SizedBox(height: AppSpacing.md),
      TextButton(
        onPressed: () => _openReset(context),
        child: Text(context.t('haveToken')),
      ),
    ];
  }

  List<Widget> _confirmation(BuildContext context) {
    return <Widget>[
      const SizedBox(height: AppSpacing.xxl),
      const Center(
        child: Icon(
          Icons.mark_email_read_rounded,
          size: 56,
          color: AppColors.success,
        ),
      ),
      const SizedBox(height: AppSpacing.lg),
      Text(
        context.t('resetLinkSent'),
        textAlign: TextAlign.center,
        style: context.texts.titleMedium,
      ),
      const SizedBox(height: AppSpacing.sm),
      Text(
        context.t('resetLinkSentBody'),
        textAlign: TextAlign.center,
        style: context.texts.bodySmall?.copyWith(
          color: context.palette.subtext,
        ),
      ),
      const SizedBox(height: AppSpacing.xxl),
      GradientButton(
        label: context.t('haveToken'),
        height: 52,
        onPressed: () => _openReset(context),
      ),
      const SizedBox(height: AppSpacing.md),
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(context.t('backToLogin')),
      ),
    ];
  }

  void _openReset(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const ResetPasswordScreen()),
    );
  }

  Future<void> _submit() async {
    final String code = _code.text.trim().toUpperCase();
    final String phone = _phone.text.trim();

    if (code.isEmpty || phone.isEmpty) {
      setState(() => _error = context.t('required'));

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
      await api.forgotPassword(restaurantCode: code, phone: phone);
      if (mounted) setState(() => _sent = true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    }
  }
}
