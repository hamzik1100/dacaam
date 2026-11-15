import 'package:flutter/foundation.dart';

/// Build-time configuration.
///
/// In debug the app runs on the seeded in-memory dataset, so design work and
/// demos need no backend. Point it at the REST API with dart-defines:
///
/// ```
/// flutter run \
///   --dart-define=USE_API=true \
///   --dart-define=API_BASE_URL=http://10.0.2.2:8090/api/v1
/// ```
///
/// `10.0.2.2` is how the Android emulator reaches the host machine's
/// localhost; a physical handset needs the machine's LAN address.
///
/// A **release** build must be given those defines. It is not a preference:
/// the offline dataset accepts any password and serves invented figures, which
/// on a shipped APK means anybody who installs it is inside, looking at numbers
/// that are not the restaurant's. [isMisconfigured] is what the app checks
/// before it paints anything, so that build reaches a locked screen instead of
/// a working-looking till.
class AppConfig {
  const AppConfig._();

  static const bool useApi = bool.fromEnvironment('USE_API');

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8090/api/v1',
  );

  /// Prefills the restaurant code on the sign-in screen.
  ///
  /// Empty by default, and left empty in the shipped build. A code sitting
  /// in the box is one more thing on a sign-in screen that is not the
  /// user's own — and on a handset that has never signed in it names a
  /// restaurant the person holding it may have nothing to do with.
  ///
  /// Set it with --dart-define for a development build if typing the code
  /// every time gets tiring. `DEMO_PHONE` and `DEMO_PASSWORD` used to live
  /// beside this and were removed for release: a real password compiled
  /// into a shipping binary is a credential anyone with the APK can read.
  static const String restaurantCode = String.fromEnvironment(
    'RESTAURANT_CODE',
  );

  static const Duration requestTimeout = Duration(seconds: 20);

  /// This build's version, compared against the minimum the platform sets in
  /// the Super Admin dashboard.
  ///
  /// Must match `version:` in pubspec.yaml (the part before `+`). A constant
  /// rather than a plugin that reads the package at runtime: one fewer
  /// dependency on a till, and build_apk.sh refuses to build when the two
  /// disagree, so the number cannot drift silently.
  static const String appVersion = '1.1.0';

  /// True when this is a release build that was never told where its server
  /// is, or was pointed at a local address no handset can reach.
  ///
  /// Checked rather than assumed because the failure is silent otherwise: the
  /// app starts, the login screen appears, any password works, and everything
  /// looks right until somebody notices the sales are somebody else's.
  static bool get isMisconfigured {
    if (!kReleaseMode) return false;

    return !useApi ||
        apiBaseUrl.contains('127.0.0.1') ||
        apiBaseUrl.contains('localhost') ||
        apiBaseUrl.contains('10.0.2.2');
  }

  /// Whether the offline dataset may be used at all.
  ///
  /// Never in release. A shipped app that quietly swaps to invented data when
  /// the network drops is worse than one that says it cannot reach the server.
  static bool get allowOfflineData => !kReleaseMode;
}
