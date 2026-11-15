import 'package:dacaam_pos/app.dart';
import 'package:dacaam_pos/data/repository/mock_repository.dart';
import 'package:dacaam_pos/redux/effects.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Shared setup for widget tests that need the whole app running.
///
/// Everything here exists because `DacaamApp` is booted for real — store,
/// effects, routing — rather than stubbed. That is the point: these tests fail
/// when the app is broken, not when a mock drifts.

/// A realistic phone viewport. The default 800×600 test surface hides the
/// layout problems that actually matter on a handset.
void usePhoneSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1170, 2532); // 390 × 844 logical
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Boots the app on a phone surface and signs in through the real login form.
///
/// A fresh repository per test means a session stored by one test can never
/// sign the next one in behind its back.
Future<void> bootSignedIn(
  WidgetTester tester, {
  String code = 'HAMZE',
  String phone = '0634567890',
  String password = 'admin123',
}) async {
  usePhoneSurface(tester);
  Effects.repository = MockRepository(latency: Duration.zero);

  await tester.pumpWidget(const DacaamApp());
  await tester.pump(const Duration(milliseconds: 400)); // restore resolves
  await tester.pump(const Duration(milliseconds: 400)); // login form settles

  final Finder fields = find.byType(TextFormField);
  await tester.enterText(fields.at(0), code);
  await tester.enterText(fields.at(1), phone);
  await tester.enterText(fields.at(2), password);

  await tester.tap(find.text('Gal')); // Sign In
  await tester.pump(const Duration(seconds: 1)); // bootstrap resolves
  await tester.pump(const Duration(seconds: 2)); // entrance animations
}
