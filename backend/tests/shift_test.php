<?php

declare(strict_types=1);

/**
 * Counting the drawer.
 *
 * Every other control here watches actions that were recorded. This one catches
 * the sale that was never entered — the only kind no audit trail can see —
 * because the money in the drawer is not something the software can be talked
 * out of.
 *
 * The checks that matter most are not "does it add up". They are:
 *   - the person counting cannot read the answer first
 *   - closing twice cannot adjust the till twice
 *   - the balance ends up matching what was actually counted
 *
 *   php tests/shift_test.php http://127.0.0.1:8090
 */

require __DIR__ . '/harness.php';
require dirname(__DIR__) . '/bootstrap.php';

use Dacaam\Core\Database;

$admin = token(login('HAMZE', '0634567890', 'admin123'));
$rid = (int) Database::scalar('SELECT id FROM restaurants WHERE slug = "HAMZE"');

// Seeded orders predate shifts and carry no shift_id. Anchoring on the
// highest id before the run keeps them out of assertions about the gate.
$baselineOrderId = (int) Database::scalar('SELECT COALESCE(MAX(id), 0) FROM orders');

$tillId = (int) Database::scalar(
    'SELECT id FROM accounts WHERE restaurant_id = ? AND method = "cash" ORDER BY id LIMIT 1',
    [$rid],
);

/// Counts every account the server insists on, at the figures given.
///
/// The close refuses a partial set on purpose, so the tests have to send them
/// all — which is the behaviour being pinned.
function countsFor(string $token, array $overrides = [], float $default = 0): array
{
    $accounts = request('GET', '/api/v1/shifts/current', null, $token)['json']['data']['accounts'] ?? [];
    $out = [];

    foreach ($accounts as $a) {
        $id = (int) $a['id'];
        // A non-cash account defaults to what the server says came in —
        // which is what a cashier reading the Zaad app would find when
        // nothing is wrong. Defaulting them to zero made every unrelated
        // Zaad payment look like a shortfall.
        $fallback = ($a['method'] ?? '') === 'cash'
            ? $default
            : (float) ($a['received'] ?? $default);

        $out[] = [
            'account_id' => $id,
            'counted'    => $overrides[$id] ?? ($overrides[$a['method']] ?? $fallback),
        ];
    }

    return $out;
}
function till(int $id): float
{
    return (float) Database::scalar('SELECT balance FROM accounts WHERE id = ?', [$id]);
}

// An operator runs the till; they may open and close it but may not read the
// expected total. That split is the blind count.
$operatorPhone = '0614' . substr((string) time(), -6);
request('POST', '/api/v1/users', [
    'name' => 'Operator Shift', 'phone' => $operatorPhone,
    'password' => 'operator1', 'role_code' => 'operator',
], $admin);

$operator = token(login('HAMZE', $operatorPhone, 'operator1'));

// ======================================================= the hard gate

group('POS-ku ma shaqeeyo shift la\'aan');

Database::run('DELETE FROM shifts WHERE restaurant_id = ?', [$rid]);

// The rule the whole feature rests on. An order taken with no till open
// belongs to nobody and appears in no count — which is the exact shape of the
// sale this was built to catch — so it is refused rather than merely noted.
$blocked = request('POST', '/api/v1/orders', [
    'order_type'     => 'takeaway',
    'items'          => [['menu_item_id' => 1, 'quantity' => 1]],
    'payment_method' => 'cash',
], $admin);

ok($blocked['status'] === 409, 'dalab lama qaadi karo', 'got ' . $blocked['status']);
ok(
    ($blocked['json']['error']['code'] ?? '') === 'shift_required',
    'oo koodhku wuu caddahay si app-ku u weydiiyo furitaanka',
    $blocked['json']['error']['code'] ?? '',
);

$noOrders = (int) Database::scalar(
    'SELECT COUNT(*) FROM orders WHERE restaurant_id = ? AND id > ?',
    [$rid, $baselineOrderId],
);
ok($noOrders === 0, 'oo waxba lama abuurin');

// A waiter cannot open a till themselves — that is deliberate — so the message
// has to point at what needs to happen rather than at them.
$waiterPhone = '0632233445';
$waiterToken = token(login('HAMZE', $waiterPhone, 'admin123'));

if ($waiterToken !== '') {
    $waiterBlocked = request('POST', '/api/v1/orders', [
        'order_type' => 'takeaway',
        'items'      => [['menu_item_id' => 1, 'quantity' => 1]],
    ], $waiterToken);

    ok($waiterBlocked['status'] === 409, 'waiter-kuna sidoo kale waa la joojinayaa');

    $waiterOpen = request('POST', '/api/v1/shifts', ['opening_float' => 1000], $waiterToken);
    ok($waiterOpen['status'] === 403, 'oo iskiis ma furi karo', 'got ' . $waiterOpen['status']);
}

// ============================================================ opening

group('Bootstrap-ku wuxuu sheegayaa haddii sanduuqu furan yahay');

// A waiter has no shifts.manage and cannot read the shift endpoint, but the
// POS refuses to sell without an open till — so they have to be told why.
// One bit rides along with the session: whether, and nothing about how much.
$closedBoot = request('GET', '/api/v1/bootstrap', null, $admin)['json']['data'] ?? [];
ok(array_key_exists('till_open', $closedBoot), 'bootstrap-ku waa uu sheegayaa');
ok(($closedBoot['till_open'] ?? true) === false, 'oo hadda waa xidhan yahay');

group('Furitaanka');

$before = request('GET', '/api/v1/shifts/current', null, $admin);
ok($before['status'] === 200, 'xaaladda tillka waa la akhrin karaa');
// array_key_exists, not ??: the coalesce operator cannot tell an explicit null
// apart from a missing key, and "no shift is open" is expressed as a null.
ok(
    array_key_exists('shift', $before['json']['data'] ?? [])
    && $before['json']['data']['shift'] === null,
    'shift furan ma jiro',
    json_encode($before['json']['data'] ?? []),
);

$opened = request('POST', '/api/v1/shifts', [
    'opening_float' => 200000,
], $admin);

ok($opened['status'] === 200, 'shift waa la furay', 'got ' . $opened['status']);
$shiftId = (int) ($opened['json']['data']['id'] ?? 0);
ok($shiftId > 0, 'aqoonsi buu leeyahay');
ok(($opened['json']['data']['opening_float'] ?? 0) === 200000.0, 'lacagta bilowga waa la qoray');

// And once a till is open it says so — including to somebody who cannot read
// the shift endpoint at all.
$openBoot = request('GET', '/api/v1/bootstrap', null, $admin)['json']['data'] ?? [];
ok(($openBoot['till_open'] ?? false) === true, 'furitaanka ka dib waa furan yahay');

if ($waiterToken !== '') {
    $waiterBoot = request('GET', '/api/v1/bootstrap', null, $waiterToken)['json']['data'] ?? [];
    ok(($waiterBoot['till_open'] ?? false) === true, 'waiter-kuna wuu arkaa');
}

group('Hal shift oo tillkiiba');

$twice = request('POST', '/api/v1/shifts', ['opening_float' => 50000], $admin);
ok($twice['status'] === 409, 'labaad lama furi karo', 'got ' . $twice['status']);

// ==================================================== the blind count

group('Tirasho indho-la\'aan — TAN AYAA XAYNDAABKA');

// The whole control rests on this. Somebody who can read the expected total
// before counting will type the expected total, and a variance that is always
// zero looks like a control while being none.
$peekAsOperator = request('GET', "/api/v1/shifts/$shiftId", null, $operator);
ok(
    $peekAsOperator['status'] === 403,
    'operator-ku ma arki karo waxa la filayo',
    'got ' . $peekAsOperator['status'],
);

$currentAsOperator = request('GET', '/api/v1/shifts/current', null, $operator);
ok($currentAsOperator['status'] === 200, 'laakiin wuu arki karaa in shift furan yahay');
ok(
    !array_key_exists('expected_close', $currentAsOperator['json']['data']['shift'] ?? []),
    'iyadoo aan lambarka la filayo la sheegin',
);

$listAsOperator = request('GET', '/api/v1/shifts', null, $operator);
ok($listAsOperator['status'] === 403, 'taariikhduna waa u xidhan tahay');

// The manager may look — that is what the split is for.
$peekAsAdmin = request('GET', "/api/v1/shifts/$shiftId", null, $admin);
ok($peekAsAdmin['status'] === 200, 'maamuluhu wuu eegi karaa');
ok(isset($peekAsAdmin['json']['data']['expected']), 'oo wuxuu arkaa waxa la filayo');

// ================================================== money moves

group('Lacagtu way dhaqaaqdaa');

$startExpected = (float) $peekAsAdmin['json']['data']['expected'];
ok(abs($startExpected - 200000) < 0.01, 'bilowgu waa lacagtii la furay', number_format($startExpected));

$order = request('POST', '/api/v1/orders', [
    'order_type'     => 'takeaway',
    'items'          => [['menu_item_id' => 1, 'quantity' => 2]],
    'payment_method' => 'cash',
], $admin)['json']['data'];

$orderTotal = (float) $order['total'];

request('POST', '/api/v1/expenses', [
    'name' => 'Biyo', 'amount' => 15000, 'kind' => 'daily', 'method' => 'cash',
], $admin);

$afterMoves = request('GET', "/api/v1/shifts/$shiftId", null, $admin)['json']['data'];
$expected = (float) $afterMoves['expected'];

ok(
    abs($expected - (200000 + $orderTotal - 15000)) < 0.01,
    'la filayo = bilow + iib − kharash',
    sprintf('%s (iib %s)', number_format($expected), number_format($orderTotal)),
);

// The order belongs to this shift, so it is not counted as happening outside one.
$stamped = (int) Database::scalar('SELECT shift_id FROM orders WHERE id = ?', [$order['id']]);
ok($stamped === $shiftId, 'dalabku shiftkan ayuu ku xidhan yahay', (string) $stamped);

// ==================================================== closing

group('Xisaabaad kasta waa la tirinayaa');

// Cash is not the only account that can be checked. A Zaad balance can be read
// off the phone, so a payment recorded as Zaad that never arrived is findable —
// and leaving it unchecked is what keeps that hole open.
$sheet = request('GET', '/api/v1/shifts/current', null, $admin)['json']['data'];

ok(($sheet['accounts'] ?? []) !== [], 'shaashadda xidhitaanku waxay leedahay liis xisaabaad');
ok(count($sheet['accounts']) > 1, 'oo ka badan sanduuqa cash-ka', (string) count($sheet['accounts'] ?? []));

// The list must not carry balances or expected totals. It builds the form; those
// are the answer, and a screen holding them will eventually show them.
$leaked = false;
foreach ($sheet['accounts'] as $a) {
    if (array_key_exists('balance', $a) || array_key_exists('expected', $a)) {
        $leaked = true;
    }
}
ok(!$leaked, 'iyadoo aan lambarrada la filayo la sheegin', json_encode($sheet['accounts'][0] ?? []));

group('Xisaab kastaa wuxuu tusayaa waxa soo gashay iyo waxa baxay');

// The figure is a demand, not a hint: whatever the system says came in is money
// the cashier is expected to be holding, and showing it does not create a
// shortfall that was not already there.
//
// What it buys is the investigation. A drawer that is short has to be looked
// into before the shift closes — a missed expense, a payment rung up wrong, a
// recount — and an empty box gives nowhere to start.
$cashRow = null;
$otherRow = null;

foreach ($sheet['accounts'] as $a) {
    if (($a['method'] ?? '') === 'cash') {
        $cashRow = $a;
    } elseif ($otherRow === null) {
        $otherRow = $a;
    }
}

ok($cashRow !== null, 'sanduuqa cash-ka wuu ku jiraa');
ok(
    ($cashRow['received'] ?? null) !== null,
    'CASH: lacagta soo gashay waa la tusayaa',
    json_encode($cashRow),
);
ok(
    array_key_exists('paid_out', $cashRow ?? []),
    'iyo waxa ka baxay — kharashka',
    json_encode($cashRow),
);
ok(
    abs((float) ($cashRow['paid_out'] ?? 0) - 15000) < 0.01,
    'oo waa 15,000 — kii la diiwaangeliyay',
    (string) ($cashRow['paid_out'] ?? 'null'),
);

ok($otherRow !== null, 'xisaab aan cash ahayn wuu jiraa');
ok(
    ($otherRow['received'] ?? null) !== null,
    'ZAAD/BANK: isaguna waa la tusayaa',
    json_encode($otherRow),
);

// The closing total is still not among them. That figure is theirs to write.
$leakedExpected = false;
foreach ($sheet['accounts'] as $a) {
    if (array_key_exists('expected', $a) || array_key_exists('balance', $a)) {
        $leakedExpected = true;
    }
}
ok(!$leakedExpected, 'laakiin wadarta la filayo weli lama sheegayo');

// And the figure has to be real, not a placeholder.
$zaadAccount = (int) ($otherRow['id'] ?? 0);
$zaadOrder = request('POST', '/api/v1/orders', [
    'order_type'     => 'takeaway',
    'items'          => [['menu_item_id' => 1, 'quantity' => 1]],
    'payment_method' => $otherRow['method'],
], $admin);

if ($zaadOrder['status'] === 200) {
    $afterPayment = request('GET', '/api/v1/shifts/current', null, $admin)['json']['data'];

    $updated = null;
    foreach ($afterPayment['accounts'] as $a) {
        if ((int) $a['id'] === $zaadAccount) {
            $updated = $a;
        }
    }

    ok(
        (float) ($updated['received'] ?? 0) > (float) ($otherRow['received'] ?? 0),
        'oo wuu kordhayaa marka lacag timaaddo',
        sprintf('%s -> %s', $otherRow['received'] ?? '-', $updated['received'] ?? '-'),
    );
}

group('Kharashka maalinta waa la arkayaa');

// The cashier paid these, so it tells them nothing new — but it is why the
// drawer holds less than the day's sales, and a close without it turns into a
// panicked recount of money that was legitimately spent.
ok(isset($sheet['expenses']['total']), 'wadarta kharashka way la socotaa');
ok(
    abs((float) $sheet['expenses']['total'] - 15000) < 0.01,
    'oo waa 15,000 — kii la diiwaangeliyay',
    (string) ($sheet['expenses']['total'] ?? 'null'),
);
ok(
    ($sheet['expenses']['items'][0]['name'] ?? '') === 'Biyo',
    'iyo liiskooda magacyada',
    json_encode($sheet['expenses']['items'][0] ?? []),
);

group('Xisaabaad la dhaafay waa la diidayaa');

// Closing on the cash drawer alone would report a balanced till while a hole
// sat in the one account nobody was asked about.
$partial = request('POST', "/api/v1/shifts/$shiftId/close", [
    'counts' => [['account_id' => $tillId, 'counted' => 100000]],
    'reason' => 'Sanduuqa oo kaliya',
], $admin);

ok($partial['status'] === 422, 'xisaabaad maqan waa la diidayaa', 'got ' . $partial['status']);
ok(
    str_contains(strtolower(json_encode($partial['json']['error']['fields'] ?? [])), 'count every account'),
    'oo waxay magacawdaa kuwa maqan',
    json_encode($partial['json']['error']['fields'] ?? []),
);

group('Sabab waa waajib marka farqigu weyn yahay');

$noReason = request('POST', "/api/v1/shifts/$shiftId/close", [
    'counts' => countsFor($admin, ['cash' => $expected - 18000]),
], $admin);

ok($noReason['status'] === 422, 'farqi weyn oo sabab la\'aan waa la diidayaa', 'got ' . $noReason['status']);
ok(
    str_contains(strtolower(json_encode($noReason['json']['error']['fields'] ?? [])), 'short'),
    'oo waxay sheegaysaa inuu gaabis yahay',
    json_encode($noReason['json']['error']['fields'] ?? []),
);

$stillOpen = (int) Database::scalar('SELECT COUNT(*) FROM shifts WHERE id = ? AND closed_at IS NULL', [$shiftId]);
ok($stillOpen === 1, 'shiftku wali wuu furan yahay');

group('Xidhitaanka');

$tillBefore = till($tillId);

$closed = request('POST', "/api/v1/shifts/$shiftId/close", [
    'counts' => countsFor($admin, ['cash' => $expected - 18000]),
    'reason' => 'Lacag laga waayay sanduuqa',
], $admin);

ok($closed['status'] === 200, 'waa la xidhay', 'got ' . $closed['status']);

$data = $closed['json']['data'];
ok(abs(($data['variance'] ?? 0) + 18000) < 0.01, 'farqigu waa −18,000', (string) ($data['variance'] ?? 'null'));
ok(($data['close_reason'] ?? '') === 'Lacag laga waayay sanduuqa', 'sababtu way la socotaa');
ok(($data['is_open'] ?? true) === false, 'wuu xidhan yahay');
ok(isset($data['expected_close']), 'hadda ayaa la muujiyay waxa la filayay');

group('Farqi xisaabkiiba');

// Two errors that cancel out are still two errors. A single total for the whole
// till would net them to zero and report a clean night.
$lines = $closed['json']['data']['accounts'] ?? [];
ok($lines !== [], 'jawaabtu waxay leedahay xisaab kasta', (string) count($lines));

$cashLine = null;
foreach ($lines as $line) {
    if (($line['method'] ?? '') === 'cash') {
        $cashLine = $line;
    }
}

ok($cashLine !== null, 'sanduuqa cash-ka wuu ku jiraa');
ok(
    abs((float) ($cashLine['variance'] ?? 0) + 18000) < 0.01,
    'oo farqigiisu waa −18,000',
    (string) ($cashLine['variance'] ?? 'null'),
);

$stored = (int) Database::scalar('SELECT COUNT(*) FROM shift_counts WHERE shift_id = ?', [$shiftId]);
ok($stored === count($lines), 'oo mid kasta waa la kaydiyay', (string) $stored);

group('Balance-ku wuxuu la mid noqonayaa waxa la tiriyay');

// If the balance is left alone, tomorrow starts from a figure nobody has ever
// held and the error compounds until the number means nothing.
$tillAfter = till($tillId);
ok(
    abs($tillAfter - ($tillBefore - 18000)) < 0.01,
    'sanduuqu wuxuu la mid noqday tiradii la tiriyay',
    sprintf('%s -> %s', number_format($tillBefore), number_format($tillAfter)),
);

$adjustment = Database::selectOne(
    'SELECT kind, amount, description, created_by FROM account_transactions
      WHERE source_type = "shift" AND source_id = ? ORDER BY id DESC LIMIT 1',
    [$shiftId],
);

ok($adjustment !== null, 'saf ledger ah ayaa la qoray — si aamusan uma dhicin');
ok(($adjustment['kind'] ?? '') === 'adjustment', 'nooca waa adjustment');
ok(
    str_contains((string) ($adjustment['description'] ?? ''), 'Lacag laga waayay'),
    'oo sababtu way ku qoran tahay',
);
ok(((int) ($adjustment['created_by'] ?? 0)) > 0, 'oo qof buu leeyahay');

group('Faahfaahinta shift la xidhay');

// Tapping a closed shift has to answer the whole question: who, when, what was
// in each account, what moved through it, and what was spent. A row that only
// shows a variance leaves the reader with the one number and no way to judge
// it.
$detail = request('GET', "/api/v1/shifts/$shiftId", null, $admin);
ok($detail['status'] === 200, 'faahfaahinta waa la akhrin karaa', 'got ' . $detail['status']);

$d = $detail['json']['data'];

ok(($d['shift']['opened_by'] ?? '') !== '', 'kii furay waa la magacaabay', (string) ($d['shift']['opened_by'] ?? '-'));
ok(($d['shift']['closed_by'] ?? '') !== '', 'iyo kii xidhay', (string) ($d['shift']['closed_by'] ?? '-'));
ok(($d['shift']['closed_at'] ?? null) !== null, 'iyo waqtiga la xidhay');

ok(($d['accounts'] ?? []) !== [], 'xisaab kasta wuu ku jiraa', (string) count($d['accounts'] ?? []));

$cash = null;
foreach ($d['accounts'] as $line) {
    if (($line['method'] ?? '') === 'cash') {
        $cash = $line;
    }
}

ok($cash !== null, 'sanduuqa cash-ka wuu ku jiraa');
ok(isset($cash['expected'], $cash['counted'], $cash['variance']), 'oo saddexda tiro wuu wataa');
ok(
    abs((float) ($cash['variance'] ?? 0) + 18000) < 0.01,
    'farqigiisuna waa −18,000',
    (string) ($cash['variance'] ?? 'null'),
);

ok(($d['movements'] ?? []) !== [], 'dhaqdhaqaaqa lacagta wuu ku jiraa', (string) count($d['movements'] ?? []));
ok(isset($d['expenses']['total']), 'kharashkuna wuu la socdaa');

group('Kharashku wuxuu ku xidhan yahay waqtiga shiftka');

// A closed shift is a window with two ends. Without the upper bound, opening
// last Tuesday from the history would list this morning's spending as though it
// had happened that night.
// The window closes on a second boundary, and this whole test runs inside
// one. A real shift lasts hours, so waiting for the clock to tick is the
// honest way to put the expense outside it rather than fabricating a
// timestamp the app could never produce.
sleep(1);

$laterExpense = request('POST', '/api/v1/expenses', [
    'name' => 'Kharash danbe', 'amount' => 7000, 'kind' => 'daily', 'method' => 'cash',
], $admin);

ok($laterExpense['status'] === 200, 'kharash cusub oo shiftka ka dambeeya');

$again = request('GET', "/api/v1/shifts/$shiftId", null, $admin)['json']['data'];
$names = array_column($again['expenses']['items'] ?? [], 'name');

ok(
    !in_array('Kharash danbe', $names, true),
    'shiftkii hore kuma soo bixin',
    implode(', ', $names),
);

group('Laba jeer lama xidhi karo');

$tillNow = till($tillId);
$again = request('POST', "/api/v1/shifts/$shiftId/close", [
    'counts' => [['account_id' => $tillId, 'counted' => 1]],
    'reason' => 'Isku day labaad',
], $admin);

ok($again['status'] === 409, 'labaadku waa la diidayaa', 'got ' . $again['status']);
ok(abs(till($tillId) - $tillNow) < 0.01, 'sanduuqu isma beddelin');

// ==================================================== overnight

group('Dalab shift la xidhay lama beddeli karo');

// A counted evening is settled: the drawer was counted, the difference was
// explained by somebody who put their name to it, and the balance was corrected
// to match. Editing an order inside that window moves the total the count was
// measured against — and nothing recomputes, so the reconciliation simply stops
// being true without anybody being told.
$lockedEdit = request('PUT', '/api/v1/orders/' . $order['id'] . '/items', [
    'items'  => [['menu_item_id' => 1, 'quantity' => 9]],
    'reason' => 'Isku day beddel shift la xidhay',
], $admin);

ok($lockedEdit['status'] === 409, 'beddelku waa la diidayaa', 'got ' . $lockedEdit['status']);
ok(
    ($lockedEdit['json']['error']['code'] ?? '') === 'shift_closed',
    'oo koodhku wuu caddahay',
    $lockedEdit['json']['error']['code'] ?? '',
);

$lockedPayment = request('POST', '/api/v1/orders/' . $order['id'] . '/payments', [
    'method' => 'cash', 'amount' => 1000,
], $admin);
ok($lockedPayment['status'] === 409, 'lacag lagama qaadi karo');

$lockedCancel = request('PATCH', '/api/v1/orders/' . $order['id'] . '/status', [
    'status' => 'cancelled', 'reason' => 'Isku day',
], $admin);
ok($lockedCancel['status'] === 409, 'lamana joojin karo');

// Nothing moved.
$stillTotal = (float) Database::scalar('SELECT total FROM orders WHERE id = ?', [$order['id']]);
ok(
    abs($stillTotal - $orderTotal) < 0.01,
    'dalabku sidiisii ayuu yahay',
    number_format($stillTotal),
);

group('Lacagta habeenkii lumta');

// A different question from a shift being short: this went missing while
// nobody was there, and folding the two together hides both.
$counted = (float) $data['counted_close'];

$reopened = request('POST', '/api/v1/shifts', [
    'opening_float' => $counted - 50000,
], $admin);

ok($reopened['status'] === 200, 'shift cusub waa la furay');
ok(
    abs(($reopened['json']['data']['overnight_diff'] ?? 0) + 50000) < 0.01,
    'farqiga habeenkii si gaar ah ayaa loo qoray',
    (string) ($reopened['json']['data']['overnight_diff'] ?? 'null'),
);
ok(
    abs(($reopened['json']['data']['previous_close'] ?? 0) - $counted) < 0.01,
    'oo xidhitaankii hore waa la xusay',
);

group('Farqi yar si aamus ah ayaa loo qaadanayaa');

$second = (int) $reopened['json']['data']['id'];
$secondExpected = (float) request('GET', "/api/v1/shifts/$second", null, $admin)['json']['data']['expected'];

$small = request('POST', "/api/v1/shifts/$second/close", [
    'counts' => countsFor($admin, ['cash' => $secondExpected - 200]),
], $admin);

ok($small['status'] === 200, 'farqi 200 ah sabab uma baahna', 'got ' . $small['status']);

group('Wax shift ka baxsan ma jiri karo');

// The column that counted them is still there, holding the rows written
// before the rule changed — but nothing new can land outside a shift, so
// what is pinned now is that the count stays at zero.
$anyOutside = (int) Database::scalar(
    'SELECT COUNT(*) FROM orders WHERE restaurant_id = ? AND shift_id IS NULL AND id > ?',
    [$rid, $baselineOrderId],
);
ok($anyOutside === 0, 'dalab kasta shift buu leeyahay', (string) $anyOutside);

group('Shift wuxuu ku furmaa sanduuqa cash-ka');

$zaad = (int) Database::scalar(
    'SELECT id FROM accounts WHERE restaurant_id = ? AND method <> "cash" LIMIT 1',
    [$rid],
);

if ($zaad > 0) {
    $zaadShift = request('POST', '/api/v1/shifts', [
        'account_id' => $zaad, 'opening_float' => 1000,
    ], $admin);

    ok($zaadShift['status'] === 422, 'Zaad lagama furi karo — waa la tirinayaa marka la xidhayo', 'got ' . $zaadShift['status']);
}

group('Ogaysiiska — kaliya marka aan la dhamaystirin');

// The owner has to hear about a short till. They must NOT hear about the four
// hundred evenings it balanced, or they will stop reading the sender and the
// short one will arrive somewhere they no longer look.
Database::run(
    'UPDATE users u JOIN user_roles ur ON ur.user_id = u.id JOIN roles r ON r.id = ur.role_id
        SET u.email = "owner@hamze.test"
      WHERE u.restaurant_id = ? AND r.code = "admin"',
    [$rid],
);

Database::run('DELETE FROM email_outbox WHERE restaurant_id = ?', [$rid]);

// A shift that balances exactly.
$clean = request('POST', '/api/v1/shifts', ['opening_float' => 100000], $admin)['json']['data'];
$cleanExpected = (float) request('GET', '/api/v1/shifts/' . $clean['id'], null, $admin)['json']['data']['expected'];
request('POST', '/api/v1/shifts/' . $clean['id'] . '/close', [
    'counts' => countsFor($admin, ['cash' => $cleanExpected]),
], $admin);

$afterClean = (int) Database::scalar(
    'SELECT COUNT(*) FROM email_outbox WHERE event_key = "shifts.shift_variance"',
);
ok($afterClean === 0, 'sanduuq dhamaystiran email ma noqdo', (string) $afterClean);

// And one that does not.
$short = request('POST', '/api/v1/shifts', ['opening_float' => 100000], $admin)['json']['data'];
$shortExpected = (float) request('GET', '/api/v1/shifts/' . $short['id'], null, $admin)['json']['data']['expected'];
request('POST', '/api/v1/shifts/' . $short['id'] . '/close', [
    'counts' => countsFor($admin, ['cash' => $shortExpected - 40000]),
    'reason' => 'Lama garanayo',
], $admin);

$afterShort = Database::select(
    'SELECT subject, body FROM email_outbox WHERE event_key = "shifts.shift_variance"',
);

ok($afterShort !== [], 'sanduuq gaabis ah email ayuu noqdaa', (string) count($afterShort));
ok(
    str_contains((string) ($afterShort[0]['subject'] ?? ''), 'DEG-DEG'),
    'oo waa deg-deg',
);
ok(
    str_contains((string) ($afterShort[0]['body'] ?? ''), 'Lama garanayo'),
    'sababtii la qoray way ku jirtaa',
);

summary();
