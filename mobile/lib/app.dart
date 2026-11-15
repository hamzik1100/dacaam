import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:redux/redux.dart';
import 'package:url_launcher/url_launcher.dart';

import 'core/i18n/app_strings.dart';
import 'core/theme/app_theme.dart';
import 'core/update/app_update.dart';
import 'core/utils/enums.dart';
import 'core/utils/formatters.dart';
import 'features/auth/lock_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/two_factor_screen.dart';
import 'features/shell/main_shell.dart';
import 'features/shell/splash_screen.dart';
import 'features/shell/update_required_screen.dart';
import 'redux/app_state.dart';
import 'redux/effects.dart';
import 'redux/states/auth_state.dart';
import 'redux/store.dart';

class DacaamApp extends StatefulWidget {
  const DacaamApp({super.key});

  @override
  State<DacaamApp> createState() => _DacaamAppState();
}

class _DacaamAppState extends State<DacaamApp> {
  late final Store<AppState> _store = createStore();
  final GlobalKey<ScaffoldMessengerState> _messenger =
      GlobalKey<ScaffoldMessengerState>();

  /// What the platform says about versions. Null until it answers, and for
  /// good if it never does — the check must never be what stops a till.
  UpdateInfo? _update;

  @override
  void initState() {
    super.initState();
    Effects.restoreSession(_store);
    _checkForUpdate();
  }

  Future<void> _checkForUpdate() async {
    final UpdateInfo? info = await AppUpdate.check();
    if (!mounted) return;

    setState(() => _update = info);

    // Supported but not the newest: said once, never in the way.
    if (info != null && info.available && info.downloadUrl.isNotEmpty) {
      _messenger.currentState?.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 10),
          content: Text(
            info.message.isNotEmpty
                ? info.message
                : AppStrings.tr('updateAvailable'),
          ),
          action: SnackBarAction(
            label: AppStrings.tr('updateDownload'),
            onPressed: () => launchUrl(
              Uri.parse(info.downloadUrl),
              mode: LaunchMode.externalApplication,
            ),
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    _store.teardown();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StoreProvider<AppState>(
      store: _store,
      child: StoreConnector<AppState, _AppVm>(
        distinct: true,
        converter: _AppVm.from,
        builder: (BuildContext context, _AppVm vm) {
          // Keep the formatter's currency prefix in step with Settings so any
          // widget can call Fmt.money() without threading settings through.
          Fmt.prefix = vm.currencyPrefix;

          return MaterialApp(
            title: 'DACAAM POS',
            debugShowCheckedModeBanner: false,
            scaffoldMessengerKey: _messenger,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: vm.themeMode,
            builder: (BuildContext context, Widget? child) {
              return AppStrings(
                language: vm.language,
                child: MediaQuery.withClampedTextScaling(
                  // Guard the dense POS grid against extreme system font
                  // scaling while still honouring accessibility settings.
                  minScaleFactor: 0.9,
                  maxScaleFactor: 1.25,
                  child: child ?? const SizedBox.shrink(),
                ),
              );
            },
            // One switch decides what is on screen: there is never a moment
            // where the shell and the login form disagree about who is here.
            // An unsupported build comes before all of it — whoever is signed
            // in, the next step is the same.
            home: _update != null && _update!.required
                ? UpdateRequiredScreen(
                    info: _update!,
                    onRecheck: _checkForUpdate,
                  )
                : switch (vm.stage) {
              AuthStage.restoring => const SplashScreen(),
              AuthStage.signedOut => const LoginScreen(),
              AuthStage.awaitingTwoFactor => const TwoFactorScreen(),
              AuthStage.locked => const LockScreen(),
              AuthStage.signedIn =>
                vm.booted ? const MainShell() : const SplashScreen(),
            },
          );
        },
      ),
    );
  }
}

class _AppVm {
  const _AppVm({
    required this.language,
    required this.themeMode,
    required this.currencyPrefix,
    required this.booted,
    required this.stage,
  });

  factory _AppVm.from(Store<AppState> store) {
    return _AppVm(
      language: store.state.settings.language,
      themeMode: store.state.settings.themeMode,
      currencyPrefix: store.state.settings.currencyPrefix,
      booted: store.state.booted,
      stage: store.state.auth.stage,
    );
  }

  final AppLanguage language;
  final ThemeMode themeMode;
  final String currencyPrefix;
  final bool booted;
  final AuthStage stage;

  @override
  bool operator ==(Object other) =>
      other is _AppVm &&
      other.language == language &&
      other.themeMode == themeMode &&
      other.currencyPrefix == currencyPrefix &&
      other.booted == booted &&
      other.stage == stage;

  @override
  int get hashCode =>
      Object.hash(language, themeMode, currencyPrefix, booted, stage);
}
