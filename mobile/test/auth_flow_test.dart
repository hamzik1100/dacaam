import 'package:dacaam_pos/app.dart';
import 'package:dacaam_pos/data/repository/mock_repository.dart';
import 'package:dacaam_pos/redux/effects.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The sign-in gate, driven through the real app.
///
/// Uses the offline repository, which accepts any non-empty credentials — the
/// point here is the routing and the form, not the credential check, which the
/// PHP suite covers against a real database.
Future<void> _open(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1170, 2532); // 390 × 844 logical
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  // A fresh repository per test, so a session stored by one test cannot sign
  // the next one in behind its back.
  Effects.repository = MockRepository(latency: Duration.zero);

  await tester.pumpWidget(const DacaamApp());
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> _fillAndSubmit(
  WidgetTester tester, {
  String code = 'HAMZE',
  String phone = '0634567890',
  String password = 'admin123',
}) async {
  final Finder fields = find.byType(TextFormField);
  await tester.enterText(fields.at(0), code);
  await tester.enterText(fields.at(1), phone);
  await tester.enterText(fields.at(2), password);

  await tester.tap(find.text('Gal')); // Sign In
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 2));
}

void main() {
  testWidgets('an unauthenticated launch lands on the login screen', (
    WidgetTester tester,
  ) async {
    await _open(tester);

    expect(find.text('Koodhka Makhaayadda'), findsOneWidget); // Restaurant Code
    expect(find.text('Gal'), findsOneWidget); // Sign In
    expect(find.text('Hamze Restaurant'), findsNothing); // no shell yet
  });

  testWidgets('the form refuses to submit while fields are empty', (
    WidgetTester tester,
  ) async {
    await _open(tester);

    await tester.tap(find.text('Gal'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Waa loo baahan yahay'), findsWidgets); // Required
    expect(find.text('Hamze Restaurant'), findsNothing);
  });

  testWidgets('signing in reaches the dashboard', (WidgetTester tester) async {
    await _open(tester);
    await _fillAndSubmit(tester);

    expect(find.text('Hamze Restaurant'), findsOneWidget);
    expect(find.text('Guriga'), findsWidgets); // bottom nav is up
  });

  testWidgets('the restaurant code is upper-cased as it is typed', (
    WidgetTester tester,
  ) async {
    await _open(tester);

    await tester.enterText(find.byType(TextFormField).at(0), 'hamze');
    await tester.pump();

    // Read the controller rather than the rendered text: the field's hint is
    // also "HAMZE" and stays in the tree, so find.text would match twice.
    final EditableText field = tester.widget<EditableText>(
      find.byType(EditableText).first,
    );
    expect(field.controller.text, 'HAMZE');
  });

  testWidgets('signing out returns to the login screen and keeps the code', (
    WidgetTester tester,
  ) async {
    await _open(tester);
    await _fillAndSubmit(tester);
    expect(find.text('Hamze Restaurant'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.grid_view_outlined)); // More
    await tester.pump(const Duration(seconds: 1));

    // Scrolled to, not assumed visible. The More screen grows a tile every
    // time the app gains a feature, and a list that builds lazily means the
    // sign-out below the fold is not merely off-screen — it is not in the tree
    // at all, so ensureVisible has nothing to find.
    final Finder logout = find.text('Ka bax');
    await tester.scrollUntilVisible(
      logout,
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    await tester.tap(logout);
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.widgetWithText(FilledButton, 'Ka bax'));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Gal'), findsOneWidget); // back at sign-in

    // The restaurant code is not a secret, and retyping it every shift is the
    // kind of friction that gets a POS abandoned.
    final EditableText codeField = tester.widget<EditableText>(
      find.byType(EditableText).first,
    );
    expect(codeField.controller.text, 'HAMZE');
  });
}
