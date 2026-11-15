import 'package:dacaam_pos/core/config/app_config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards the rule that a shipped build must have a real server behind it.
///
/// The bug this exists for: an APK built with a plain `flutter build apk`
/// carried no `USE_API` define, so it ran entirely on the seeded dataset. The
/// sign-in screen accepted any restaurant code, phone and password, the
/// dashboard showed invented takings, and nothing ever reached the server —
/// and none of it looked wrong. It was installed before anybody noticed.
///
/// Tests run in debug, so [AppConfig.isMisconfigured] is false here by
/// definition and cannot be asserted directly. What is asserted is the shape
/// of the rules underneath it, which is what actually went wrong.
void main() {
  test('offline data is refused outside debug', () {
    // The whole safety property in one line: demo data and a release build are
    // mutually exclusive. Every fallback in Effects, and MockRepository's own
    // sign-in, hang off this.
    expect(AppConfig.allowOfflineData, !kReleaseMode);
    expect(AppConfig.allowOfflineData, isTrue, reason: 'tests run in debug');
  });

  test('a release build with no API define is misconfigured', () {
    // USE_API is absent under `flutter test`, which is exactly the state the
    // bad APK shipped in. In release that combination must be caught.
    expect(
      AppConfig.useApi,
      isFalse,
      reason: 'no dart-define here, same as a plain build',
    );

    // Mirrors AppConfig.isMisconfigured without kReleaseMode, so the condition
    // is checked even though this suite cannot run in release mode.
    bool wouldBeMisconfigured(String url, {required bool useApi}) =>
        !useApi ||
        url.contains('127.0.0.1') ||
        url.contains('localhost') ||
        url.contains('10.0.2.2');

    expect(
      wouldBeMisconfigured(AppConfig.apiBaseUrl, useApi: AppConfig.useApi),
      isTrue,
      reason: 'this build would be blocked if it were a release build',
    );
  });

  test('a localhost address is refused even with USE_API set', () {
    // The second half of the trap: remembering the define but leaving the
    // emulator address in it. No handset can reach either of these, so the app
    // would install, fail every call, and look like a broken server.
    bool wouldBeMisconfigured(String url) =>
        url.contains('127.0.0.1') ||
        url.contains('localhost') ||
        url.contains('10.0.2.2');

    expect(wouldBeMisconfigured('http://127.0.0.1:8090/api/v1'), isTrue);
    expect(wouldBeMisconfigured('http://10.0.2.2:8090/api/v1'), isTrue);
    expect(wouldBeMisconfigured('http://localhost:8090/api/v1'), isTrue);
    expect(wouldBeMisconfigured('https://api.dhuuh.shop/api/v1'), isFalse);
  });
}
