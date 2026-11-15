import 'package:dacaam_pos/app.dart';
import 'package:dacaam_pos/data/repository/mock_repository.dart';
import 'package:dacaam_pos/redux/effects.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/app_harness.dart';

/// Boots the real app (store, effects, theme) on a phone-sized surface and
/// signs in, so each test starts on the dashboard.
///
/// Skeletons shimmer on a repeating controller, so these walk the clock with
/// explicit pumps instead of `pumpAndSettle`, which would never settle.
Future<void> _bootApp(WidgetTester tester) => bootSignedIn(tester);

void main() {
  testWidgets('shows the brand splash before the session resolves', (
    WidgetTester tester,
  ) async {
    usePhoneSurface(tester);
    Effects.repository = MockRepository(latency: const Duration(seconds: 5));

    await tester.pumpWidget(const DacaamApp());
    expect(find.text('DACAAM'), findsOneWidget);
  });

  testWidgets('lands on the dashboard in Somali by default', (
    WidgetTester tester,
  ) async {
    await _bootApp(tester);

    expect(find.text('Hamze Restaurant'), findsOneWidget);
    expect(find.text('Ficillo Degdeg ah'), findsOneWidget); // Quick Actions
    expect(find.text('Quick Actions'), findsNothing);
    expect(find.text('Iibka Maanta'), findsOneWidget); // Today's Sales
  });

  testWidgets('the bottom bar exposes all six sections for an admin', (
    WidgetTester tester,
  ) async {
    await _bootApp(tester);

    for (final String label in <String>[
      'Guriga',
      'POS',
      'Dalabyada',
      'Menu',
      'Warbixin',
      'Kale',
    ]) {
      expect(find.text(label), findsWidgets, reason: label);
    }
  });

  testWidgets('tapping a POS product adds it to the cart', (
    WidgetTester tester,
  ) async {
    await _bootApp(tester);

    await tester.tap(find.byIcon(Icons.point_of_sale_outlined));
    await tester.pump(const Duration(seconds: 1));

    final Finder burger = find.descendant(
      of: find.byType(GridView),
      matching: find.text('Chicken Burger'),
    );
    expect(burger, findsOneWidget);

    await tester.tap(burger);
    await tester.pump(const Duration(milliseconds: 500));

    // The card shows a quantity badge and the sticky bar shows the total.
    expect(find.text('×1'), findsOneWidget);
    expect(find.textContaining('SLSH 35,000'), findsWidgets);
  });

  testWidgets('switching the language re-renders the shell in English', (
    WidgetTester tester,
  ) async {
    await _bootApp(tester);

    await tester.tap(find.byIcon(Icons.grid_view_outlined));
    await tester.pump(const Duration(seconds: 1));

    final Finder settings = find.text('Dejinta'); // Settings
    expect(settings, findsOneWidget);
    await tester.ensureVisible(settings);
    await tester.pump();
    await tester.tap(settings);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1)); // route transition

    // Language names are endonyms, so "English" reads the same either way.
    final Finder english = find.text('English');
    expect(english, findsOneWidget);
    await tester.ensureVisible(english);
    await tester.pump();
    await tester.tap(english);
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Settings'), findsOneWidget); // app bar retitled
    expect(find.text('LANGUAGE'), findsOneWidget);
    expect(find.text('Dejinta'), findsNothing);
  });
}
