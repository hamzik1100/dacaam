import 'package:shared_preferences/shared_preferences.dart';

/// Persists the session so staff are not asked to sign in every time the app
/// is reopened mid-shift.
///
/// The token is an opaque random string that the server stores only as a hash,
/// and it is scoped to one restaurant. It is *not* a password: it expires, it
/// can be revoked from Security → Sessions, and changing the account password
/// kills it. Plain `SharedPreferences` is the right storage tier for that;
/// moving to the platform keychain is a hardening step for Phase 10, noted in
/// the README rather than silently assumed.
abstract class TokenStore {
  Future<StoredSession?> read();

  Future<void> write(StoredSession session);

  Future<void> clear();
}

class StoredSession {
  const StoredSession({
    required this.token,
    required this.restaurantCode,
    this.phone = '',
  });

  final String token;
  final String restaurantCode;
  final String phone;
}

class PrefsTokenStore implements TokenStore {
  static const String _tokenKey = 'dacaam.session.token';
  static const String _codeKey = 'dacaam.session.restaurant_code';
  static const String _phoneKey = 'dacaam.session.phone';

  @override
  Future<StoredSession?> read() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? token = prefs.getString(_tokenKey);
    if (token == null || token.isEmpty) return null;

    return StoredSession(
      token: token,
      restaurantCode: prefs.getString(_codeKey) ?? '',
      phone: prefs.getString(_phoneKey) ?? '',
    );
  }

  @override
  Future<void> write(StoredSession session) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, session.token);
    await prefs.setString(_codeKey, session.restaurantCode);
    // The phone is remembered to prefill the next sign-in. The password never
    // is, under any circumstances.
    await prefs.setString(_phoneKey, session.phone);
  }

  @override
  Future<void> clear() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    // The restaurant code and phone survive a sign-out so the login screen
    // opens prefilled — they are not secrets, and retyping a restaurant code
    // every shift is exactly the kind of friction that gets a POS abandoned.
  }
}

/// In-memory store for tests and for the offline dataset.
class MemoryTokenStore implements TokenStore {
  StoredSession? _session;

  @override
  Future<StoredSession?> read() async => _session;

  @override
  Future<void> write(StoredSession session) async => _session = session;

  @override
  Future<void> clear() async => _session = null;
}
