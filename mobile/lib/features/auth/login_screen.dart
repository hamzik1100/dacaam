import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:redux/redux.dart';

import '../../core/i18n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../redux/app_state.dart';
import '../../redux/effects.dart';
import '../../widgets/app_card.dart';
import '../../widgets/buttons.dart';
import '../../widgets/entrance.dart';
import 'forgot_password_screen.dart';

/// Step one of sign-in: restaurant code, phone, password.
///
/// The restaurant code is what selects the tenant, so it comes first and is
/// remembered between sessions — staff at one restaurant type it once.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final GlobalKey<FormState> _form = GlobalKey<FormState>();
  late final TextEditingController _code;
  late final TextEditingController _phone;
  final TextEditingController _password = TextEditingController();
  final FocusNode _passwordFocus = FocusNode();

  bool _obscure = true;
  bool _seeded = false;

  @override
  void initState() {
    super.initState();
    _code = TextEditingController();
    _phone = TextEditingController();
  }

  @override
  void dispose() {
    _code.dispose();
    _phone.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StoreConnector<AppState, _LoginVm>(
      converter: _LoginVm.from,
      builder: (BuildContext context, _LoginVm vm) {
        // Prefill once from whatever the last session remembered.
        if (!_seeded) {
          _seeded = true;
          _code.text = vm.restaurantCode;
          _phone.text = vm.phone;
        }

        return Scaffold(
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.xxl),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Form(
                    key: _form,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        const Entrance(child: _Brand()),
                        const SizedBox(height: AppSpacing.xxxl),

                        Entrance(
                          index: 1,
                          child: AppCard(
                            padding: const EdgeInsets.all(AppSpacing.xl),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: <Widget>[
                                _Label(text: context.t('restaurantCode')),
                                TextFormField(
                                  controller: _code,
                                  enabled: !vm.submitting,
                                  textCapitalization:
                                      TextCapitalization.characters,
                                  textInputAction: TextInputAction.next,
                                  autocorrect: false,
                                  inputFormatters: <TextInputFormatter>[
                                    UpperCaseFormatter(),
                                    LengthLimitingTextInputFormatter(32),
                                  ],
                                  decoration: InputDecoration(
                                    hintText: 'Restaurant Code',
                                    prefixIcon: const Icon(
                                      Icons.storefront_rounded,
                                      size: 20,
                                    ),
                                    errorText:
                                        vm.fieldErrors['restaurant_code'],
                                  ),
                                  validator: (String? v) =>
                                      (v == null || v.trim().isEmpty)
                                      ? context.t('required')
                                      : null,
                                ),
                                const SizedBox(height: AppSpacing.lg),

                                _Label(text: context.t('phone')),
                                TextFormField(
                                  controller: _phone,
                                  enabled: !vm.submitting,
                                  keyboardType: TextInputType.phone,
                                  textInputAction: TextInputAction.next,
                                  decoration: InputDecoration(
                                    hintText: '063XXXXXXX',
                                    prefixIcon: const Icon(
                                      Icons.phone_rounded,
                                      size: 20,
                                    ),
                                    errorText: vm.fieldErrors['phone'],
                                  ),
                                  validator: (String? v) =>
                                      (v == null || v.trim().length < 7)
                                      ? context.t('required')
                                      : null,
                                  onFieldSubmitted: (_) =>
                                      _passwordFocus.requestFocus(),
                                ),
                                const SizedBox(height: AppSpacing.lg),

                                _Label(text: context.t('password')),
                                TextFormField(
                                  controller: _password,
                                  focusNode: _passwordFocus,
                                  enabled: !vm.submitting,
                                  obscureText: _obscure,
                                  textInputAction: TextInputAction.done,
                                  decoration: InputDecoration(
                                    hintText: '••••••••',
                                    prefixIcon: const Icon(
                                      Icons.lock_rounded,
                                      size: 20,
                                    ),
                                    suffixIcon: IconButton(
                                      onPressed: () =>
                                          setState(() => _obscure = !_obscure),
                                      icon: Icon(
                                        _obscure
                                            ? Icons.visibility_rounded
                                            : Icons.visibility_off_rounded,
                                        size: 19,
                                      ),
                                      tooltip: _obscure
                                          ? context.t('show')
                                          : context.t('hide'),
                                    ),
                                    errorText: vm.fieldErrors['password'],
                                  ),
                                  validator: (String? v) =>
                                      (v == null || v.isEmpty)
                                      ? context.t('required')
                                      : null,
                                  onFieldSubmitted: (_) => _submit(vm),
                                ),

                                if (vm.error != null) ...<Widget>[
                                  const SizedBox(height: AppSpacing.lg),
                                  _ErrorBanner(message: vm.error!),
                                ],

                                const SizedBox(height: AppSpacing.xl),
                                GradientButton(
                                  label: context.t('signIn'),
                                  icon: Icons.login_rounded,
                                  loading: vm.submitting,
                                  onPressed: () => _submit(vm),
                                ),
                                const SizedBox(height: AppSpacing.sm),
                                // Carries whatever code is already typed, so
                                // the next screen does not ask for it twice.
                                TextButton(
                                  onPressed: () => Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => ForgotPasswordScreen(
                                        restaurantCode: _code.text.trim(),
                                      ),
                                    ),
                                  ),
                                  child: Text(context.t('forgotPassword')),
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: AppSpacing.xl),
                        Entrance(
                          index: 2,
                          child: Text(
                            context.t('loginHelp'),
                            textAlign: TextAlign.center,
                            style: context.texts.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _submit(_LoginVm vm) {
    if (vm.submitting) return;
    if (!(_form.currentState?.validate() ?? false)) return;

    FocusScope.of(context).unfocus();
    vm.onSignIn(_code.text, _phone.text, _password.text);
  }
}

/// Keeps the restaurant code uppercase as it is typed — it is a code, and
/// `hamze` matching `HAMZE` should not depend on remembering the shift key.
class UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Container(
          width: 78,
          height: 78,
          decoration: BoxDecoration(
            gradient: AppColors.brand,
            borderRadius: BorderRadius.circular(24),
            boxShadow: AppShadows.brand(),
          ),
          child: const Center(
            child: Text('🍔', style: TextStyle(fontSize: 36)),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'DACAAM',
          style: context.texts.headlineMedium?.copyWith(letterSpacing: 4),
        ),
        const SizedBox(height: 2),
        Text(context.t('signInSubtitle'), style: context.texts.bodySmall),
      ],
    );
  }
}

class _Label extends StatelessWidget {
  const _Label({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm, left: 2),
      child: Text(text, style: context.texts.titleSmall),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: context.isDark ? 0.18 : 0.09),
        borderRadius: AppRadius.card,
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(
            Icons.error_outline_rounded,
            size: 18,
            color: AppColors.danger,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: context.texts.bodyMedium?.copyWith(
                color: AppColors.danger,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoginVm {
  const _LoginVm({
    required this.submitting,
    required this.error,
    required this.fieldErrors,
    required this.restaurantCode,
    required this.phone,
    required this.onSignIn,
  });

  factory _LoginVm.from(Store<AppState> store) {
    return _LoginVm(
      submitting: store.state.auth.submitting,
      error: store.state.auth.error,
      fieldErrors: store.state.auth.fieldErrors,
      restaurantCode: store.state.auth.restaurantSlug,
      phone: store.state.auth.phone,
      onSignIn: (String code, String phone, String password) => Effects.signIn(
        store,
        restaurantCode: code,
        phone: phone,
        password: password,
      ),
    );
  }

  final bool submitting;
  final String? error;
  final Map<String, String> fieldErrors;
  final String restaurantCode;
  final String phone;
  final void Function(String, String, String) onSignIn;
}
