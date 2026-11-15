<?php

declare(strict_types=1);

/**
 * What the books must never lose.
 *
 * Two rules, both about the same thing: a figure that was in the accounts
 * yesterday has to still be explainable today. An expense that can be deleted,
 * or a customer whose ledger can be removed, turns "where did the 400,000 go"
 * into a question with no answer — and a missing row cannot tell an honest
 * mistake apart from somebody covering their tracks.
 *
 *   php tests/books_test.php http://127.0.0.1:8090
 */

require __DIR__ . '/harness.php';
require dirname(__DIR__) . '/bootstrap.php';

use Dacaam\Core\Database;

$admin = token(login('HAMZE', '0634567890', 'admin123'));
// A till has to be open before anything can be sold. That is the rule the
// shift feature exists to enforce, so the suite opens one exactly as the
// restaurant does at the start of service.
ensureShift($admin);

$waiter = token(login('HAMZE', '0632233445', 'admin123'));

/** The cash till's balance right now. */
function till(string $admin): float
{
    foreach (request('GET', '/api/v1/accounts', null, $admin)['json']['data'] ?? [] as $account) {
        if (($account['method'] ?? '') === 'cash') {
            return (float) $account['balance'];
        }
    }

    return 0.0;
}

// ==================================================== expenses: no deleting

group('Kharashka lama tirtiro');

// The route has to be gone, not merely unused. A DELETE that still answers is
// a way to remove an expense no matter what the app offers.
$expense = request('POST', '/api/v1/expenses', [
    'name'   => 'Shidaal',
    'amount' => 40000,
    'kind'   => 'daily',
    'method' => 'cash',
], $admin);

ok($expense['status'] === 200, 'kharash la diiwaangeliyay', 'got ' . $expense['status']);
$id = (int) ($expense['json']['data']['id'] ?? 0);

$deleted = request('DELETE', "/api/v1/expenses/$id", null, $admin);
ok(
    $deleted['status'] === 404 || $deleted['status'] === 405,
    'DELETE ma jiro oo dhan',
    'got ' . $deleted['status'],
);

$stillThere = (int) Database::scalar('SELECT COUNT(*) FROM expenses WHERE id = ?', [$id]);
ok($stillThere === 1, 'kharashku wali wuu jiraa');

group('Joojinta waa inay sabab leedahay');

$noReason = request('POST', "/api/v1/expenses/$id/cancel", [], $admin);
ok($noReason['status'] === 422, 'sabab la aan waa la diidayaa', 'got ' . $noReason['status']);

$tooShort = request('POST', "/api/v1/expenses/$id/cancel", ['reason' => 'x'], $admin);
ok($tooShort['status'] === 422, 'sabab gaaban sidoo kale');

$stillLive = (int) Database::scalar(
    'SELECT COUNT(*) FROM expenses WHERE id = ? AND cancelled_at IS NULL',
    [$id],
);
ok($stillLive === 1, 'oo diidmadu waxba ma beddelin');

group('Joojinta');

$tillBefore = till($admin);

$cancelled = request('POST', "/api/v1/expenses/$id/cancel", [
    'reason' => 'Laba jeer ayaa la qoray',
], $admin);

ok($cancelled['status'] === 200, 'joojintu way shaqaysay', 'got ' . $cancelled['status']);
ok(($cancelled['json']['data']['is_cancelled'] ?? false) === true, 'waa la calaamadeeyay');
ok(
    ($cancelled['json']['data']['cancel_reason'] ?? '') === 'Laba jeer ayaa la qoray',
    'sababtu way la socotaa',
);

// The money goes back where it came from.
$tillAfter = till($admin);
ok(
    abs(($tillAfter - $tillBefore) - 40000) < 0.01,
    'lacagtii way ku soo noqotay sanduuqa',
    sprintf('%s -> %s', number_format($tillBefore), number_format($tillAfter)),
);

// And it is still on the list, not hidden.
$listed = request('GET', '/api/v1/expenses', null, $admin)['json']['data'] ?? [];
$found = null;
foreach ($listed as $row) {
    if ((int) $row['id'] === $id) {
        $found = $row;
    }
}
ok($found !== null, 'wali liiska wuu ku jiraa — lama qarin');
ok(($found['is_cancelled'] ?? false) === true, 'oo waa la garanayaa inuu joogsaday');

$hidden = request('GET', '/api/v1/expenses?cancelled=hide', null, $admin)['json']['data'] ?? [];
ok(
    !in_array($id, array_column($hidden, 'id'), true),
    'shaashad rabta kuwa firfircoon oo kaliya way ka saari kartaa',
);

group('Laba jeer lama joojin karo');

// This is the one that matters. Two taps on a slow connection arrive as two
// requests, and a second refund would put money in the till that never left it.
$tillNow = till($admin);

$again = request('POST', "/api/v1/expenses/$id/cancel", [
    'reason' => 'Isku day labaad',
], $admin);

ok($again['status'] === 409, 'labaadku waa la diidayaa', 'got ' . $again['status']);
ok(
    abs(till($admin) - $tillNow) < 0.01,
    'sanduuqu isma beddelin',
    number_format(till($admin)),
);

group('Kharash la joojiyay lama beddeli karo');

$edit = request('PUT', "/api/v1/expenses/$id", ['amount' => 999999], $admin);
ok($edit['status'] === 409, 'wax beddel waa la diidayaa', 'got ' . $edit['status']);

group('Xisaabaadka');

// The whole point: cancelled spend must leave the totals, or two screens
// disagree about profit and nobody can tell which is right.
$report = request('GET', '/api/v1/reports/summary?range=today', null, $admin);
$expenseTotal = (float) ($report['json']['data']['expenses']['value'] ?? -1);

$liveTotal = (float) Database::scalar(
    'SELECT COALESCE(SUM(amount), 0) FROM expenses
      WHERE restaurant_id = (SELECT id FROM restaurants WHERE slug = "HAMZE")
        AND expense_date = CURDATE() AND cancelled_at IS NULL',
);

ok(
    abs($expenseTotal - $liveTotal) < 0.01,
    'warbixintu waxay tirinaysaa kuwa firfircoon oo kaliya',
    sprintf('warbixin %s, xaqiiqda %s', number_format($expenseTotal), number_format($liveTotal)),
);

group('Rukhsadaha');

$waiterCancel = request('POST', "/api/v1/expenses/$id/cancel", ['reason' => 'Isku day'], $waiter);
ok($waiterCancel['status'] === 403, 'waiter ma joojin karo', 'got ' . $waiterCancel['status']);

// ============================================ a refund is recorded as one

group('Lacag la celiyay waa in dalabku sheego');

// The refund used to move the till and the ledger while leaving order_payments
// untouched, so an order went on recording 110,000 collected against a 40,000
// bill. The Payment-method report sums those rows, so it overstated cash by the
// refund — while the shift, which derives from the ledger, had it right. Two
// screens disagreeing about the same money is the worst possible answer.
$refunded = request('POST', '/api/v1/orders', [
    'order_type'     => 'takeaway',
    'items'          => [['menu_item_id' => 1, 'quantity' => 3]],
    'payment_method' => 'cash',
], $admin)['json']['data'];

$paidBefore = (float) Database::scalar(
    'SELECT COALESCE(SUM(amount), 0) FROM order_payments WHERE order_id = ?',
    [$refunded['id']],
);
ok($paidBefore > 0, 'la bixiyay', number_format($paidBefore));

request('PUT', '/api/v1/orders/' . $refunded['id'] . '/items', [
    'items'  => [['menu_item_id' => 1, 'quantity' => 1]],
    'reason' => 'Laba saxan ayaa la celiyay',
], $admin);

$after = request('GET', '/api/v1/orders/' . $refunded['id'], null, $admin)['json']['data'];
$paidAfter = (float) Database::scalar(
    'SELECT COALESCE(SUM(amount), 0) FROM order_payments WHERE order_id = ?',
    [$refunded['id']],
);

ok(
    abs($paidAfter - (float) $after['total']) < 0.01,
    'wixii la bixiyay wuxuu la mid yahay wadarta',
    sprintf('la bixiyay %s, wadar %s', number_format($paidAfter), number_format((float) $after['total'])),
);

$refundRow = Database::selectOne(
    'SELECT amount, method FROM order_payments WHERE order_id = ? AND amount < 0',
    [$refunded['id']],
);
ok($refundRow !== null, 'saf taban ayaa la qoray — lama tirtirin kii hore');
ok(
    ($refundRow['method'] ?? '') === 'cash',
    'oo habkiisu waa kii lacagta lagu qaaday',
    (string) ($refundRow['method'] ?? '-'),
);

// The report and the till now agree.
$byPayment = request('GET', '/api/v1/reports/summary?range=today', null, $admin);
ok($byPayment['status'] === 200, 'warbixintu way shaqaynaysaa');

// ================================================== customers: no deleting

group('Macmiilka lama tirtiro');

$customer = request('POST', '/api/v1/customers', [
    'name'         => 'Xaawo Cali',
    'phone'        => '0617' . substr((string) time(), -6),
    'credit_limit' => 500000,
], $admin)['json']['data'];

$cid = (int) $customer['id'];

// Put them in debt.
$order = request('POST', '/api/v1/orders', [
    'order_type'   => 'takeaway',
    'items'        => [['menu_item_id' => 1, 'quantity' => 2]],
    'customer_id'  => $cid,
    'payment_mode' => 'credit',
], $admin)['json']['data'];

$owing = (float) Database::scalar('SELECT balance_owed FROM customers WHERE id = ?', [$cid]);
ok($owing > 0, 'macmiilku dayn buu qaatay', number_format($owing));

group('Dayn haddii uu leeyahay lama xidhi karo');

$closeWithDebt = request('DELETE', "/api/v1/customers/$cid", null, $admin);
ok($closeWithDebt['status'] === 422, 'xidhidda waa la diidayaa', 'got ' . $closeWithDebt['status']);
ok(
    str_contains(strtolower($closeWithDebt['json']['error']['message'] ?? ''), 'collect'),
    'oo sababtu waa daynta',
    $closeWithDebt['json']['error']['message'] ?? '',
);

$stillActive = (int) Database::scalar('SELECT is_active FROM customers WHERE id = ?', [$cid]);
ok($stillActive === 1, 'wali wuu firfircoon yahay');

group('Marka daynta la bixiyo');

request('POST', "/api/v1/customers/$cid/payment", [
    'amount' => $owing,
    'method' => 'cash',
], $admin);

$ledgerBefore = (int) Database::scalar(
    'SELECT COUNT(*) FROM account_transactions WHERE source_id = ? OR source_id = ?',
    [$cid, $order['id']],
);

$closed = request('DELETE', "/api/v1/customers/$cid", null, $admin);
ok($closed['status'] === 200, 'hadda waa la xidhi karaa', 'got ' . $closed['status']);
ok(($closed['json']['data']['is_active'] ?? true) === false, 'wuu damay');

$row = Database::selectOne('SELECT * FROM customers WHERE id = ?', [$cid]);
ok($row !== null, 'MACMIILKU WALI WUU JIRAA — lama tirtirin');

group('Taariikhdiisu way sii jirtaa');

$ledgerAfter = (int) Database::scalar(
    'SELECT COUNT(*) FROM account_transactions WHERE source_id = ? OR source_id = ?',
    [$cid, $order['id']],
);
ok($ledgerAfter === $ledgerBefore, 'diiwaanka lacagtu wuu dhan yahay', "$ledgerBefore -> $ledgerAfter");

$orderStill = Database::selectOne('SELECT customer_id FROM orders WHERE id = ?', [$order['id']]);
ok(
    (int) ($orderStill['customer_id'] ?? 0) === $cid,
    'dalabkiisii wali isaga ayuu ku xidhan yahay',
);

$entries = request('GET', "/api/v1/customers/$cid/ledger", null, $admin);
ok($entries['status'] === 200, 'ledger-kiisa wali waa la akhrin karaa');
ok(($entries['json']['data'] ?? []) !== [], 'oo wax buu ku jiraan');

group('Dib loo furi karaa');

$reopened = request('PUT', "/api/v1/customers/$cid", [
    'name'      => 'Xaawo Cali',
    'is_active' => true,
], $admin);

ok($reopened['status'] === 200, 'dib ayaa loo furi karaa', 'got ' . $reopened['status']);
ok(($reopened['json']['data']['is_active'] ?? false) === true, 'oo wuu firfircoon yahay');

$balance = (float) Database::scalar('SELECT balance_owed FROM customers WHERE id = ?', [$cid]);
ok(abs($balance) < 0.01, 'xisaabtiisu waa eber sidii hore');

summary();
