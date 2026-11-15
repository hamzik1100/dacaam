import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../core/config/app_config.dart';
import '../../core/i18n/app_strings.dart';

/// A failure the UI can present.
///
/// Transport problems and API error envelopes both land here, so screens have
/// one type to catch and one message to show.
class ApiException implements Exception {
  const ApiException(
    this.message, {
    this.statusCode = 0,
    this.code = 'error',
    this.fields = const <String, String>{},
  });

  final String message;
  final int statusCode;
  final String code;

  /// Field-level validation errors, keyed by the API's field name.
  final Map<String, String> fields;

  bool get isUnauthorized => statusCode == 401;

  bool get isForbidden => statusCode == 403;

  bool get isValidation => statusCode == 422 || fields.isNotEmpty;

  bool get isNetwork => statusCode == 0;

  @override
  String toString() => 'ApiException($statusCode $code): $message';
}

/// Thin HTTP client over the DACAAM REST API.
///
/// Owns exactly three things: the bearer token, the `{data}` / `{error}`
/// envelope, and turning every failure into an [ApiException]. Endpoint
/// knowledge lives in `DacaamApi`.
class ApiClient {
  ApiClient({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _baseUrl = (baseUrl ?? AppConfig.apiBaseUrl).replaceAll(
        RegExp(r'/+$'),
        '',
      );

  final http.Client _client;
  final String _baseUrl;

  /// Bearer token for the current session. Held in memory only — persisting it
  /// is a Phase 3 concern that belongs with the sign-in screen.
  String? token;

  bool get hasSession => token != null && token!.isNotEmpty;

  void clearSession() => token = null;

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) =>
      _send('GET', path, query: query);

  /// Fetches a non-JSON body (the CSV export).
  ///
  /// Bypasses the `{data}` envelope because the endpoint deliberately answers
  /// `text/csv` — the point of Export is a file, not JSON to re-encode.
  Future<String> getRaw(String path, {Map<String, dynamic>? query}) async {
    final Uri uri = Uri.parse('$_baseUrl$path').replace(
      queryParameters: query == null
          ? null
          : <String, String>{
              for (final MapEntry<String, dynamic> e in query.entries)
                if (e.value != null) e.key: '${e.value}',
            },
    );

    final http.Response response = await _client
        .get(
          uri,
          headers: <String, String>{
            'Accept': 'text/csv',
            if (hasSession) 'Authorization': 'Bearer $token',
          },
        )
        .timeout(AppConfig.requestTimeout);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return utf8.decode(response.bodyBytes);
    }

    // Errors still come back as the JSON envelope, so reuse the parser.
    return _decode(response) as String;
  }

  Future<dynamic> post(String path, {Object? body}) =>
      _send('POST', path, body: body);

  Future<dynamic> put(String path, {Object? body}) =>
      _send('PUT', path, body: body);

  Future<dynamic> patch(String path, {Object? body}) =>
      _send('PATCH', path, body: body);

  Future<dynamic> delete(String path) => _send('DELETE', path);

  Future<dynamic> _send(
    String method,
    String path, {
    Object? body,
    Map<String, dynamic>? query,
  }) async {
    final Uri uri = Uri.parse('$_baseUrl$path').replace(
      queryParameters: query == null
          ? null
          : <String, String>{
              for (final MapEntry<String, dynamic> e in query.entries)
                if (e.value != null) e.key: '${e.value}',
            },
    );

    final http.Request request = http.Request(method, uri)
      ..headers.addAll(<String, String>{
        'Accept': 'application/json',
        if (body != null) 'Content-Type': 'application/json',
        if (hasSession) 'Authorization': 'Bearer $token',
        'X-Device': defaultTargetPlatform.name,
      });

    if (body != null) {
      request.body = jsonEncode(body);
    }

    http.Response response;
    try {
      final http.StreamedResponse streamed = await _client
          .send(request)
          .timeout(AppConfig.requestTimeout);
      response = await http.Response.fromStream(streamed);
    } on TimeoutException {
      // The real reason is logged, not shown. "Failed host lookup" and
      // "Connection refused" tell a waiter nothing they can act on; the one
      // thing they can do about any of them is check the connection.
      throw _offline('timeout');
    } on SocketException catch (e) {
      throw _offline(e.message);
    } catch (e) {
      throw _offline('$e');
    }

    return _decode(response);
  }

  /// The one message every transport failure gets.
  ///
  /// Already in the user's language: an [ApiException] is shown by fifty-odd
  /// screens that print `e.message` straight into a snackbar, and none of them
  /// can tell a network drop from a rejected form. Translating here means all
  /// of them say the useful thing without any of them knowing about it.
  static ApiException _offline(String detail) {
    debugPrint('[dacaam] network failure: $detail');

    return ApiException(
      AppStrings.tr('noInternet'),
      code: 'offline',
    );
  }

  dynamic _decode(http.Response response) {
    final String raw = response.body;
    dynamic decoded;

    if (raw.isNotEmpty) {
      try {
        decoded = jsonDecode(raw);
      } on FormatException {
        // A non-JSON body means something upstream (a PHP fatal, a proxy, an
        // HTML error page) answered instead of the API.
        throw ApiException(
          'The server returned an unreadable response',
          statusCode: response.statusCode,
          code: 'bad_response',
        );
      }
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (decoded is Map<String, dynamic>) {
        return decoded['data'];
      }
      return decoded;
    }

    if (decoded is Map<String, dynamic> && decoded['error'] is Map) {
      final Map<String, dynamic> error = (decoded['error'] as Map)
          .cast<String, dynamic>();
      final Map<String, String> fields = <String, String>{};
      if (error['fields'] is Map) {
        (error['fields'] as Map).forEach((dynamic k, dynamic v) {
          fields['$k'] = '$v';
        });
      }

      throw ApiException(
        '${error['message'] ?? 'Request failed'}',
        statusCode: response.statusCode,
        code: '${error['code'] ?? 'error'}',
        fields: fields,
      );
    }

    throw ApiException(
      'Request failed (${response.statusCode})',
      statusCode: response.statusCode,
    );
  }

  void close() => _client.close();
}
