import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:redux/redux.dart';

import '../../core/i18n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../redux/actions.dart';
import '../../redux/app_state.dart';
import '../../redux/effects.dart';
import '../../widgets/app_card.dart';
import '../../widgets/buttons.dart';
import '../../widgets/entrance.dart';

/// Step two of sign-in: the one-time code.
///
/// Accepts a 6-digit authenticator code or a recovery code — the same field
/// takes both, because someone who has lost their phone is already having a
/// bad enough day without hunting for a second input.
class TwoFactorScreen extends StatefulWidget {
  const TwoFactorScreen({super.key});

  @override
  State<TwoFactorScreen> createState() => _TwoFactorScreenState();
}

class _TwoFactorScreenState extends State<TwoFactorScreen> {
  final TextEditingController _code = TextEditingController();
  bool _usingRecoveryCode = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StoreConnector<AppState, _OtpVm>(
      converter: _OtpVm.from,
      builder: (BuildContext context, _OtpVm vm) {
        return Scaffold(
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.xxl),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: SoftIconButton(
                          icon: Icons.arrow_back_rounded,
                          onPressed: vm.onCancel,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xl),

                      Entrance(
                        child: Column(
                          children: <Widget>[
                            Container(
                              width: 72,
                              height: 72,
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(
                                  alpha: context.isDark ? 0.22 : 0.11,
                                ),
                                borderRadius: BorderRadius.circular(22),
                              ),
                              child: const Icon(
                                Icons.shield_rounded,
                                size: 34,
                                color: AppColors.primary,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            Text(
                              context.t('twoFactorTitle'),
                              textAlign: TextAlign.center,
                              style: context.texts.headlineSmall,
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              _usingRecoveryCode
                                  ? context.t('recoveryCodeHint')
                                  : context.t('twoFactorSubtitle'),
                              textAlign: TextAlign.center,
                              style: context.texts.bodyMedium,
                            ),
                            if (vm.userName.isNotEmpty) ...<Widget>[
                              const SizedBox(height: AppSpacing.sm),
                              Text(
                                '${vm.userName} · ${vm.restaurantName}',
                                textAlign: TextAlign.center,
                                style: context.texts.titleSmall?.copyWith(
                                  color: AppColors.primary,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxl),

                      Entrance(
                        index: 1,
                        child: AppCard(
                          padding: const EdgeInsets.all(AppSpacing.xl),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              TextField(
                                controller: _code,
                                autofocus: true,
                                enabled: !vm.submitting,
                                textAlign: TextAlign.center,
                                keyboardType: _usingRecoveryCode
                                    ? TextInputType.text
                                    : TextInputType.number,
                                textCapitalization:
                                    TextCapitalization.characters,
                                inputFormatters: <TextInputFormatter>[
                                  LengthLimitingTextInputFormatter(
                                    _usingRecoveryCode ? 12 : 6,
                                  ),
                                ],
                                style: context.texts.headlineMedium?.copyWith(
                                  letterSpacing: _usingRecoveryCode ? 2 : 10,
                                ),
                                decoration: InputDecoration(
                                  hintText: _usingRecoveryCode
                                      ? 'XXXX-XXXX'
                                      : '000000',
                                  hintStyle: context.texts.headlineMedium
                                      ?.copyWith(
                                        letterSpacing: _usingRecoveryCode
                                            ? 2
                                            : 10,
                                        color: context.palette.border,
                                      ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    vertical: AppSpacing.lg,
                                  ),
                                ),
                                onChanged: (String value) {
                                  // Six digits is the whole code; submitting
                                  // automatically saves a tap at the counter.
                                  if (!_usingRecoveryCode &&
                                      value.length == 6) {
                                    vm.onVerify(value);
                                  }
                                },
                                onSubmitted: vm.onVerify,
                              ),

                              if (vm.error != null) ...<Widget>[
                                const SizedBox(height: AppSpacing.lg),
                                Row(
                                  children: <Widget>[
                                    const Icon(
                                      Icons.error_outline_rounded,
                                      size: 17,
                                      color: AppColors.danger,
                                    ),
                                    const SizedBox(width: AppSpacing.sm),
                                    Expanded(
                                      child: Text(
                                        vm.error!,
                                        style: context.texts.bodyMedium
                                            ?.copyWith(color: AppColors.danger),
                                      ),
                                    ),
                                  ],
                                ),
                              ],

                              const SizedBox(height: AppSpacing.xl),
                              GradientButton(
                                label: context.t('verify'),
                                icon: Icons.check_rounded,
                                loading: vm.submitting,
                                onPressed: () => vm.onVerify(_code.text),
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              TextButton(
                                onPressed: vm.submitting
                                    ? null
                                    : () => setState(() {
                                        _usingRecoveryCode =
                                            !_usingRecoveryCode;
                                        _code.clear();
                                      }),
                                child: Text(
                                  _usingRecoveryCode
                                      ? context.t('useAuthenticator')
                                      : context.t('useRecoveryCode'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _OtpVm {
  const _OtpVm({
    required this.submitting,
    required this.error,
    required this.userName,
    required this.restaurantName,
    required this.onVerify,
    required this.onCancel,
  });

  factory _OtpVm.from(Store<AppState> store) {
    return _OtpVm(
      submitting: store.state.auth.submitting,
      error: store.state.auth.error,
      userName: store.state.auth.pendingUserName,
      restaurantName: store.state.auth.pendingRestaurantName,
      onVerify: (String code) {
        if (store.state.auth.submitting || code.trim().isEmpty) return;
        Effects.verifyTwoFactor(store, code: code);
      },
      onCancel: () => store.dispatch(const TwoFactorCancelled()),
    );
  }

  final bool submitting;
  final String? error;
  final String userName;
  final String restaurantName;
  final ValueChanged<String> onVerify;
  final VoidCallback onCancel;
}
