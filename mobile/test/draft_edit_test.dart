import 'package:dacaam_pos/core/utils/enums.dart';
import 'package:dacaam_pos/data/api/mappers.dart';
import 'package:dacaam_pos/data/models/order.dart';
import 'package:dacaam_pos/redux/actions.dart';
import 'package:dacaam_pos/redux/app_state.dart';
import 'package:dacaam_pos/redux/reducers.dart';
import 'package:flutter_test/flutter_test.dart';

/// Editing a parked order.
///
/// A customer rings back and wants two more of something. Without this the only
/// answer is to cancel the ticket and key the whole order again, which is how a
/// line gets dropped — so the draft is loaded back into the cart, changed there,
/// and saved over itself.
///
/// The part that has to hold is that it saves over *itself*. A cart that forgot
/// which draft it came from would park a second ticket, and the kitchen would
/// make both.
void main() {
  DraftOrder makeDraft() => Api.draft(<String, dynamic>{
    'id': 7,
    'code': 'D-007',
    'customer_name': 'Cabdi Telefoon',
    'customer_phone': '0631234567',
    'order_type': 'dine_in',
    'table_id': 3,
    'table_label': 'Table 03',
    'notes': 'Bilaa basal',
    'status': 'draft',
    'items': <dynamic>[
      <String, dynamic>{
        'menu_item_id': 1,
        'item_name': 'Suqaar',
        'unit_price': 35000,
        'quantity': 2,
      },
    ],
    'created_at': '2026-08-20T12:00:00+03:00',
  });

  group('the draft carries its table', () {
    test('by id, not only by label', () {
      // The label reads well but cannot be sent back. Editing used to drop the
      // table and make the cashier pick it again.
      final DraftOrder d = makeDraft();

      expect(d.tableId, 3);
      expect(d.tableLabel, 'Table 03');
    });
  });

  group('loading one into the cart', () {
    test('brings the lines, the customer and the table', () {
      final AppState after = appReducer(
        const AppState(),
        DraftLoadedIntoCart(makeDraft()),
      );

      expect(after.cart.lines.length, 1);
      expect(after.cart.lines.first.quantity, 2);
      expect(after.cart.customerName, 'Cabdi Telefoon');
      expect(after.cart.customerPhone, '0631234567');
      expect(after.cart.orderType, OrderType.dineIn);
      expect(after.cart.tableId, 3);
      expect(after.cart.notes, 'Bilaa basal');
    });

    test('and remembers which draft it is', () {
      final AppState after = appReducer(
        const AppState(),
        DraftLoadedIntoCart(makeDraft()),
      );

      expect(
        after.cart.editingDraftId,
        7,
        reason: 'without this the next save parks a second ticket',
      );
      expect(after.cart.isEditingDraft, isTrue);
    });

    test('and opens the cart tab, because that is what they came for', () {
      final AppState after = appReducer(
        const AppState(),
        DraftLoadedIntoCart(makeDraft()),
      );

      expect(after.pos.tabIndex, 1);
    });
  });

  group('what the save sheet will be filled with', () {
    // The sheet reads these straight off the cart. Leaving them empty made
    // somebody retype a name the app was already holding — and a blank one
    // would then overwrite the customer on the second save.
    test('the customer comes back with the draft', () {
      final AppState after = appReducer(
        const AppState(),
        DraftLoadedIntoCart(makeDraft()),
      );

      expect(after.cart.customerName, isNotEmpty);
      expect(after.cart.customerName, 'Cabdi Telefoon');
      expect(after.cart.customerPhone, '0631234567');
      expect(after.cart.notes, 'Bilaa basal');
    });
  });

  group('after the cart is cleared', () {
    test('the draft link is gone', () {
      // Otherwise the next unrelated sale would save itself over somebody's
      // parked order.
      final AppState loaded = appReducer(
        const AppState(),
        DraftLoadedIntoCart(makeDraft()),
      );

      final AppState cleared = appReducer(loaded, const CartCleared());

      expect(cleared.cart.editingDraftId, isNull);
      expect(cleared.cart.isEditingDraft, isFalse);
      expect(cleared.cart.lines, isEmpty);
    });
  });

  group('an ordinary sale', () {
    test('is not tied to any draft', () {
      expect(const AppState().cart.editingDraftId, isNull);
      expect(const AppState().cart.isEditingDraft, isFalse);
    });
  });
}
