import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:local_auth/local_auth.dart';
import 'package:redux/redux.dart';

import '../../core/i18n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../redux/app_state.dart';
import '../../redux/effects.dart';
import '../../widgets/buttons.dart';

/// The face / fingerprint gate over a session that is already signed in.
///
/// Not a sign-in screen. Nobody gets in here who was not already in — the
/// stored session is what is being unlocked, and a fingerprint says which
/// person is holding the phone, not which restaurant account they own.
///
/// Two ways out, always. The prompt can fail for reasons that have nothing to
/// do with who you are — wet hands, a cracked sensor, a face in the dark — and
/// a till that can only be opened by a sensor is a till that closes the shop
/// when the sensor breaks.
class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  bool _busy = false;
  bool _refused = false;
  List<BiometricType> _kinds = const <BiometricType>[];

  @override
  void initState() {
    super.initState();
    // Straight into the prompt. Making the user tap "unlock" before the system
    // sheet appears is a tap that achieves nothing.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadKinds();
      _unlock();
    });
  }

  Future<void> _loadKinds() async {
    final List<BiometricType> kinds = await Effects.lock.enrolled();
    if (mounted) setState(() => _kinds = kinds);
  }

  Future<void> _unlock() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _refused = false;
    });

    final Store<AppState> store = StoreProvider.of<AppState>(
      context,
      listen: false,
    );
    final bool ok = await Effects.unlock(store);

    if (!mounted) return;
    setState(() {
      _busy = false;
      _refused = !ok;
    });
  }

  IconData get _icon => _kinds.contains(BiometricType.face)
      ? Icons.face_rounded
      : Icons.fingerprint_rounded;

  String get _labelKey =>
      _kinds.contains(BiometricType.face) ? 'unlockFace' : 'unlockFinger';

  @override
  Widget build(BuildContext context) {
    return StoreConnector<AppState, String>(
      converter: (Store<AppState> store) => store.state.auth.pendingUserName,
      builder: (BuildContext context, String name) {
        return Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xxl),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Container(
                    width: 96,
                    height: 96,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: AppColors.brand,
                    ),
                    child: Icon(_icon, size: 44, color: Colors.white),
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  Text(
                    context.t('lockedTitle'),
                    textAlign: TextAlign.center,
                    style: context.texts.headlineSmall,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    name.isEmpty ? context.t(_labelKey) : name,
                    textAlign: TextAlign.center,
                    style: context.texts.bodyMedium?.copyWith(
                      color: context.palette.subtext,
                    ),
                  ),

                  if (_refused) ...<Widget>[
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      context.t('unlockRefused'),
                      textAlign: TextAlign.center,
                      style: context.texts.bodySmall?.copyWith(
                        color: AppColors.danger,
                      ),
                    ),
                  ],

                  const SizedBox(height: AppSpacing.xxl),
                  GradientButton(
                    label: context.t(_labelKey),
                    icon: _icon,
                    loading: _busy,
                    onPressed: _busy ? null : _unlock,
                  ),
                  const SizedBox(height: AppSpacing.md),

                  // The way back for a broken sensor, and for handing the till
                  // to somebody else.
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => Effects.signOutLocked(
                            StoreProvider.of<AppState>(context, listen: false),
                          ),
                    child: Text(context.t('usePassword')),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
