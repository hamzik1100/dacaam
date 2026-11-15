import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/app_harness.dart';

/// Renders every screen, sheet and dialog on a phone-sized surface in both
/// themes.
///
/// Layout overflow is an assertion failure in tests, so this is the guard that
/// catches a card that stops fitting once a Somali label wraps or an eight
/// figure SLSH total lands in a Row.
Future<void> _boot(WidgetTester tester) => bootSignedIn(tester);

Future<void> _settleFrames(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
}

Future<void> _openTab(WidgetTester tester, IconData icon) async {
  await tester.tap(find.byIcon(icon));
  await _settleFrames(tester);
}

Future<void> _openFromMore(WidgetTester tester, String label) async {
  // The inactive icon only exists while another tab is selected; coming back
  // from a pushed screen leaves More already active.
  if (find.byIcon(Icons.grid_view_outlined).evaluate().isNotEmpty) {
    await _openTab(tester, Icons.grid_view_outlined);
  }
  final Finder tile = find.text(label);
  expect(tile, findsOneWidget, reason: label);
  await tester.ensureVisible(tile);
  await tester.pump();
  await tester.tap(tile);
  await _settleFrames(tester);
}

Future<void> _goBack(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Back').first);
  await _settleFrames(tester);
}

/// The figure rendered under a label in the Home credit strip.
String _stripValue(WidgetTester tester, String label) {
  final Finder row = find.ancestor(
    of: find.text(label),
    matching: find.byType(Column),
  );
  final Finder value = find.descendant(of: row.first, matching: find.byType(Text));

  return tester.widgetList<Text>(value).map((Text t) => t.data ?? '').join('|');
}
void main() {
  testWidgets('all six primary sections render', (WidgetTester tester) async {
    await _boot(tester);

    await _openTab(tester, Icons.point_of_sale_outlined);
    expect(find.text('Raadi cuntooyinka...'), findsOneWidget);

    await _openTab(tester, Icons.receipt_long_outlined);
    expect(find.text('#1025'), findsOneWidget);

    await _openTab(tester, Icons.restaurant_menu_outlined);
    expect(find.text('Qaybaha'), findsOneWidget); // Categories tab

    await _openTab(tester, Icons.bar_chart_outlined);
    expect(find.text('Guudmarka Iibka'), findsOneWidget); // Sales Overview

    await _openTab(tester, Icons.grid_view_outlined);
    expect(find.text('Axmed Xasan'), findsOneWidget);

    await _openTab(tester, Icons.home_outlined);
    expect(find.text('Hamze Restaurant'), findsOneWidget);
  });

  testWidgets('menu categories tab and item sheet render', (
    WidgetTester tester,
  ) async {
    await _boot(tester);
    await _openTab(tester, Icons.restaurant_menu_outlined);

    await tester.tap(find.text('Qaybaha'));
    await _settleFrames(tester);
    expect(find.text('Burgers'), findsOneWidget);

    // Opening a category jumps back to a pre-filtered Items tab.
    await tester.tap(find.text('Burgers'));
    await _settleFrames(tester);
    expect(find.text('Chicken Burger'), findsWidgets);

    await tester.tap(find.text('Chicken Burger').first);
    await _settleFrames(tester);
    expect(find.text('Diyaar u ah Iibka'), findsOneWidget); // Available switch

    await tester.tapAt(const Offset(200, 40)); // dismiss the sheet
    await _settleFrames(tester);
  });

  testWidgets('orders filter sheet and details sheet render', (
    WidgetTester tester,
  ) async {
    await _boot(tester);
    await _openTab(tester, Icons.receipt_long_outlined);

    await tester.tap(find.byIcon(Icons.tune_rounded));
    await _settleFrames(tester);
    expect(find.text('Shaandhee'), findsOneWidget); // Filters
    await tester.tap(find.text('Codso')); // Apply
    await _settleFrames(tester);

    await tester.tap(find.text('#1025'));
    await _settleFrames(tester);
    expect(find.text('Taariikhda Dalabka'), findsOneWidget); // Order History
    expect(find.text('Waxaa beddelay: Abdullahi'), findsWidgets);
  });

  testWidgets('checkout runs end to end and lands on the success screen', (
    WidgetTester tester,
  ) async {
    await _boot(tester);
    await _openTab(tester, Icons.point_of_sale_outlined);

    await tester.tap(
      find.descendant(
        of: find.byType(GridView),
        matching: find.text('Chicken Burger'),
      ),
    );
    await _settleFrames(tester);

    await tester.tap(find.text('Dambiisha')); // Cart tab
    await _settleFrames(tester);
    expect(find.text('Wadarta Hoose'), findsOneWidget); // Subtotal

    await tester.tap(find.text('Bixi')); // Checkout
    await _settleFrames(tester);
    expect(find.text('Nooca Dalabka'), findsOneWidget); // Order Type

    // Dine In requires a table while the setting is on.
    await tester.tap(find.text('Lacag Bixin')); // Payment
    await _settleFrames(tester);
    expect(find.text('Miiska waa lagama maarmaan dalabka halkan la cunayo.'),
        findsOneWidget);

    await tester.tap(find.text('02')); // pick a free table
    await _settleFrames(tester);
    await tester.tap(find.text('Lacag Bixin'));
    await _settleFrames(tester);
    expect(find.text('Habka Lacag Bixinta'), findsOneWidget); // Payment Method

    await tester.tap(find.text('Dhammee Dalabka')); // Place Order
    await tester.pump(const Duration(seconds: 1));
    await _settleFrames(tester);

    expect(find.text('Dalabku Waa Dhammaaday'), findsOneWidget);
    expect(find.text('#1026'), findsOneWidget);
  });

  testWidgets('every management screen renders', (WidgetTester tester) async {
    await _boot(tester);

    for (final (String label, String marker) in <(String, String)>[
      ('Macaamiisha', 'Cabdi Xasan'),
      ('Dalabyo Qabyo', 'D-102'),
      ('Miisaska', 'VIP Hall'),
      ('Kharashaadka', 'Hilib & Digaag'),
      ('Xisaabaadka & Lacagaha', 'Total Balance'),
      ('Isticmaalayaasha & Doorarka', 'Faadumo Cali'),
      ('Dejinta', 'LUQADDA'),
      ('Ku saabsan App-ka', 'DACAAM POS'),
    ]) {
      await _openFromMore(tester, label);
      expect(find.textContaining(marker), findsWidgets, reason: label);
      await _goBack(tester);
    }
  });

  testWidgets('customer profile, ledger and the money sheets render', (
    WidgetTester tester,
  ) async {
    await _boot(tester);
    await _openFromMore(tester, 'Macaamiisha');

    // Cabdi owes; Sahra is in credit. Both totals are on the header.
    expect(find.text('Lagu leeyahay'), findsOneWidget);
    expect(find.text('Lacag aad u haysid'), findsOneWidget);

    await tester.tap(find.text('Cabdi Xasan'));
    await _settleFrames(tester);
    expect(find.text('Buugga Xisaabta'), findsOneWidget);

    // A debtor can be paid; the sheet opens with what they owe on it.
    await tester.tap(find.text('Qaad Lacag'));
    await _settleFrames(tester);
    expect(find.text('Wuu ku leeyahay'), findsWidgets);

    // Overpaying is refused before it reaches the server.
    await tester.enterText(find.byType(TextField).first, '99999999');
    await tester.tap(find.text('Kaydi'));
    await _settleFrames(tester);
    expect(find.textContaining('Deynta way ka yar tahay'), findsOneWidget);
  });

  testWidgets('a deposit never renders as a debt', (WidgetTester tester) async {
    await _boot(tester);
    await _openFromMore(tester, 'Macaamiisha');

    // Sahra is in credit. Take a deposit so the ledger has a row whose
    // resulting balance is negative — the case that used to print as a plain
    // positive figure, indistinguishable from money owed.
    await tester.tap(find.text('Sahra Maxamed'));
    await _settleFrames(tester);

    await tester.tap(find.text('Lacag Dhigasho'));
    await _settleFrames(tester);
    await tester.enterText(find.byType(TextField).first, '40000');
    await tester.tap(find.text('Kaydi'));
    await _settleFrames(tester);

    // The running balance is named, not just signed: 'jeeb' for money held,
    // never a bare figure that reads the same as a debt.
    expect(find.textContaining('jeeb'), findsWidgets);
    expect(find.textContaining('dayn '), findsNothing);
  });

  testWidgets('adding items to a paid order asks how the rest was paid', (
    WidgetTester tester,
  ) async {
    await _boot(tester);
    await _openTab(tester, Icons.receipt_long_outlined);

    // #1022 is completed and fully paid in the seeded set.
    await tester.tap(find.text('#1022'));
    await _settleFrames(tester);

    await tester.tap(find.text('Wax ka beddel Alaabta'));
    await _settleFrames(tester);

    // One more of the first line. The total goes up; what was taken does not.
    await tester.tap(find.byIcon(Icons.add_rounded).first);
    await _settleFrames(tester);

    await tester.enterText(
      find.byType(TextField).last,
      'Macmiilku wuu kordhiyay',
    );
    await tester.tap(find.text('Kaydi'));
    await _settleFrames(tester);

    // The chooser, unasked for: an order left owing has two honest endings —
    // the money now, or somebody named as carrying it — and the edit is the
    // moment to settle which.
    expect(find.text('Lacag baa ka hadhay'), findsOneWidget);
    expect(find.text('Macmiil saar'), findsOneWidget);

    await tester.tap(find.text('Hadda bixi'));
    await _settleFrames(tester);

    // And then the payment sheet, where the method is still known.
    expect(find.text('Ku dar Lacag'), findsWidgets);
    expect(find.textContaining('Hadhay'), findsWidgets);
  });

  testWidgets('an account customer paying cash is still asked for the balance', (
    WidgetTester tester,
  ) async {
    await _boot(tester);
    await _openTab(tester, Icons.receipt_long_outlined);

    // #1019 belongs to a customer with a ledger, but it was paid at the till
    // by eDahab — nothing went on her account. The extra from an edit is owed
    // at the counter, and skipping on the customer id alone used to swallow
    // exactly this case.
    // Down the list, past the newer orders.
    await tester.scrollUntilVisible(
      find.text('#1019'),
      250,
      scrollable: find.byType(Scrollable).last,
    );
    await _settleFrames(tester);
    await tester.tap(find.text('#1019'));
    await _settleFrames(tester);

    await tester.tap(find.text('Wax ka beddel Alaabta'));
    await _settleFrames(tester);
    await tester.tap(find.byIcon(Icons.add_rounded).first);
    await _settleFrames(tester);
    await tester.enterText(find.byType(TextField).last, 'Alaab dheeraad ah');
    await tester.tap(find.text('Kaydi'));
    await _settleFrames(tester);

    expect(find.text('Ku dar Lacag'), findsWidgets);
  });
  testWidgets('a deposit moves the Home figures without a pull to refresh', (
    WidgetTester tester,
  ) async {
    await _boot(tester);

    // What the strip says before anything moves.
    final String before = _stripValue(tester, 'Lacag aad u haysid');

    await _openFromMore(tester, 'Macaamiisha');
    await tester.tap(find.text('Sahra Maxamed'));
    await _settleFrames(tester);
    await tester.tap(find.text('Lacag Dhigasho'));
    await _settleFrames(tester);
    await tester.enterText(find.byType(TextField).first, '50000');
    await tester.tap(find.text('Kaydi'));
    await _settleFrames(tester);
    await _settleFrames(tester);

    // Back to Home without touching anything: the figure has to have moved on
    // its own. It used to sit stale until somebody pulled the list down.
    await _goBack(tester); // profile -> list
    await _goBack(tester); // list -> shell
    await _openTab(tester, Icons.home_outlined);
    await _settleFrames(tester);

    expect(
      _stripValue(tester, 'Lacag aad u haysid'),
      isNot(before),
      reason: 'deposits held should have moved by itself',
    );
  });
  testWidgets('the bell counts unread messages and opens the list', (
    WidgetTester tester,
  ) async {
    await _boot(tester);

    // One of the two seeded messages is unread, so the bell carries a 1.
    expect(find.text('1'), findsWidgets);

    await tester.tap(find.byIcon(Icons.notifications_none_rounded));
    await _settleFrames(tester);

    expect(find.text('Ku soo dhawoow DACAAM'), findsOneWidget);
    expect(find.text('Lacag bixinta bisha'), findsOneWidget);

    // Opening one marks it read; the list does not clear itself on sight.
    await tester.tap(find.text('Ku soo dhawoow DACAAM'));
    await _settleFrames(tester);
    expect(find.text('Dhammaan calaamadee'), findsNothing);
  });

  testWidgets('dark mode renders every primary section', (
    WidgetTester tester,
  ) async {
    await _boot(tester);
    await _openFromMore(tester, 'Dejinta');

    final Finder dark = find.text('Mugdi');
    await tester.ensureVisible(dark);
    await tester.pump();
    await tester.tap(dark);
    await _settleFrames(tester);
    await _goBack(tester);

    for (final IconData icon in <IconData>[
      Icons.home_outlined,
      Icons.point_of_sale_outlined,
      Icons.receipt_long_outlined,
      Icons.restaurant_menu_outlined,
      Icons.bar_chart_outlined,
    ]) {
      await _openTab(tester, icon);
    }

    expect(find.text('Guudmarka Iibka'), findsOneWidget);
  });
}
