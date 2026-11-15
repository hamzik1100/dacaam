import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';

/// What the platform says about app versions.
///
/// The APK is handed out directly rather than through a store, so nothing
/// else tells a restaurant that a newer one exists — or that the one on the
/// till has stopped being supported. The Super Admin dashboard sets a minimum
/// and a latest version; the app asks once when it starts.
class UpdateInfo {
  const UpdateInfo({
    required this.minVersion,
    required this.latestVersion,
    required this.downloadUrl,
    required this.message,
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> json) => UpdateInfo(
        minVersion: '${json['min_version'] ?? ''}'.trim(),
        latestVersion: '${json['latest_version'] ?? ''}'.trim(),
        downloadUrl: '${json['download_url'] ?? ''}'.trim(),
        message: '${json['message'] ?? ''}'.trim(),
      );

  final String minVersion;
  final String latestVersion;
  final String downloadUrl;
  final String message;

  /// Below the minimum: the app stops and points at the download.
  bool get required =>
      minVersion.isNotEmpty &&
      AppUpdate.compare(AppConfig.appVersion, minVersion) < 0;

  /// Below the latest but still supported: mentioned, never enforced.
  bool get available =>
      !required &&
      latestVersion.isNotEmpty &&
      AppUpdate.compare(AppConfig.appVersion, latestVersion) < 0;
}

class AppUpdate {
  const AppUpdate._();

  /// Asks the server, or answers null.
  ///
  /// Null on every failure — offline, slow, or a server older than this
  /// endpoint (404). A version check that could stop a till opening because
  /// the network blinked would be worse than having none.
  static Future<UpdateInfo?> check({http.Client? client}) async {
    if (!AppConfig.useApi) return null;

    final http.Client c = client ?? http.Client();
    try {
      final http.Response response = await c
          .get(
            Uri.parse('${AppConfig.apiBaseUrl}/app/version'),
            headers: const <String, String>{'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) return null;

      final dynamic body = jsonDecode(response.body);
      final dynamic data = body is Map<String, dynamic> ? body['data'] : null;
      if (data is! Map<String, dynamic>) return null;

      return UpdateInfo.fromJson(data);
    } on Object {
      return null;
    } finally {
      if (client == null) c.close();
    }
  }

  /// Like `compareTo`: `1.10.0` is newer than `1.9.0` — numbers, not text.
  /// Anything after a `+` or `-` (build number, pre-release) is ignored.
  static int compare(String a, String b) {
    List<int> parts(String v) => v
        .split(RegExp(r'[+-]'))
        .first
        .split('.')
        .map((String p) => int.tryParse(p.trim()) ?? 0)
        .toList();

    final List<int> pa = parts(a);
    final List<int> pb = parts(b);

    for (int i = 0; i < 3; i++) {
      final int x = i < pa.length ? pa[i] : 0;
      final int y = i < pb.length ? pb[i] : 0;
      if (x != y) return x.compareTo(y);
    }
    return 0;
  }
}
