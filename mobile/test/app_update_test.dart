import 'dart:io';

import 'package:dacaam_pos/core/config/app_config.dart';
import 'package:dacaam_pos/core/update/app_update.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppUpdate.compare', () {
    test('compares numbers, not text', () {
      expect(AppUpdate.compare('1.10.0', '1.9.0'), greaterThan(0));
      expect(AppUpdate.compare('1.0.0', '1.0.1'), lessThan(0));
      expect(AppUpdate.compare('2.0.0', '1.99.99'), greaterThan(0));
    });

    test('treats missing parts as zero', () {
      expect(AppUpdate.compare('1.1', '1.1.0'), 0);
      expect(AppUpdate.compare('2', '2.0.0'), 0);
    });

    test('ignores build numbers', () {
      expect(AppUpdate.compare('1.1.0+2', '1.1.0'), 0);
    });
  });

  group('UpdateInfo', () {
    UpdateInfo info({String min = '', String latest = ''}) => UpdateInfo(
          minVersion: min,
          latestVersion: latest,
          downloadUrl: 'https://example.test/app.apk',
          message: '',
        );

    test('asks for nothing when nothing is configured', () {
      expect(info().required, isFalse);
      expect(info().available, isFalse);
    });

    test('a minimum above this build is required', () {
      expect(info(min: '99.0.0').required, isTrue);
    });

    test('a minimum at or below this build is not', () {
      expect(info(min: AppConfig.appVersion).required, isFalse);
      expect(info(min: '0.1.0').required, isFalse);
    });

    test('a newer latest is offered, never enforced', () {
      final UpdateInfo newer = info(latest: '99.0.0');
      expect(newer.available, isTrue);
      expect(newer.required, isFalse);
    });

    test('required wins over available', () {
      final UpdateInfo both = info(min: '99.0.0', latest: '99.0.0');
      expect(both.required, isTrue);
      expect(both.available, isFalse);
    });

    test('reads the server response', () {
      final UpdateInfo parsed = UpdateInfo.fromJson(<String, dynamic>{
        'min_version': ' 1.0.0 ',
        'latest_version': '1.2.0',
        'download_url': 'https://example.test/app.apk',
        'message': 'Cusboonaysii',
      });
      expect(parsed.minVersion, '1.0.0');
      expect(parsed.latestVersion, '1.2.0');
      expect(parsed.message, 'Cusboonaysii');
    });
  });

  test('the version constant matches pubspec.yaml', () {
    // build_apk.sh checks the same thing; this catches it in `flutter test`.
    final String pubspec = _read('pubspec.yaml');
    final RegExpMatch? m = RegExp(r'^version:\s*([0-9.]+)', multiLine: true)
        .firstMatch(pubspec);
    expect(m?.group(1), AppConfig.appVersion);
  });
}

String _read(String path) {
  // `flutter test` runs from the package root.
  return File(path).readAsStringSync();
}
