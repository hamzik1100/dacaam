import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../i18n/app_strings.dart';

/// Face or fingerprint over a session that is already signed in.
///
/// This is a lock, not a second way to sign in. The app keeps a session token
/// so staff are not asked for a password every time they reopen it mid-shift —
/// which is convenient and also means anyone holding the handset is inside.
/// Turning this on puts the phone's own biometric between the two.
///
/// It can never replace a password on a fresh device: there is no session to
/// unlock, and a fingerprint proves whose finger it is, not which restaurant
/// account they own. That case still asks for the real credentials, which is
/// what [isAvailable] returning false on a first install means in practice.
///
/// The preference is stored per device rather than on the server on purpose.
/// The same account is used on the counter tablet and on a manager's phone,
/// and only one of those is worth locking.
class AppLock {
  AppLock({LocalAuthentication? auth}) : _auth = auth ?? LocalAuthentication();

  static const String _enabledKey = 'dacaam.lock.biometric';

  final LocalAuthentication _auth;

  /// Whether this handset can do it at all: hardware present, and the user has
  /// actually enrolled a face or finger. Both matter — a phone with a sensor
  /// nobody registered will refuse every prompt.
  Future<bool> isAvailable() async {
    try {
      if (!await _auth.isDeviceSupported()) return false;

      return await _auth.canCheckBiometrics;
    } on PlatformException catch (e) {
      debugPrint('[dacaam] biometrics unavailable: ${e.code}');

      return false;
    }
  }

  /// What the handset offers, so the prompt can say "face" or "fingerprint"
  /// rather than something vague.
  Future<List<BiometricType>> enrolled() async {
    try {
      return await _auth.getAvailableBiometrics();
    } on PlatformException {
      return const <BiometricType>[];
    }
  }

  Future<bool> isEnabled() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    return prefs.getBool(_enabledKey) ?? false;
  }

  Future<void> setEnabled(bool value) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, value);
  }

  /// Asks the handset. True only on a positive match.
  ///
  /// `biometricOnly: false` lets the user fall back to the device PIN, which
  /// is deliberate: a cook with wet hands still has to be able to open the
  /// till, and the PIN is the same standard the phone already trusts.
  Future<bool> authenticate() async {
    try {
      return await _auth.authenticate(
        localizedReason: AppStrings.tr('unlockReason'),
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );
    } on PlatformException catch (e) {
      // A failed or cancelled prompt is not an error to shout about — the user
      // is left on the lock screen with the password still available.
      debugPrint('[dacaam] unlock refused: ${e.code}');

      return false;
    }
  }
}
