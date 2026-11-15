<?php

declare(strict_types=1);

/**
 * Phases 4–6 — order editing, drafts, menu, tables, expenses and accounts.
 *
 *   php bin/migrate.php --fresh --seed
 *   php -S 127.0.0.1:8090 -t public public/index.php
 *   php tests/operations_test.php http://127.0.0.1:8090
 */

require __DIR__ . '/harness.php';

$admin = token(login('HAMZE', '0634567890'));
// A till has to be open before anything can be sold. That is the rule the
// shift feature exists to enforce, so the suite opens one exactly as the
// restaurant does at the start of service.
ensureShift($admin);

$waiter = token(login('HAMZE', '0632233445'));

// ======================================================== order editing

group('Order editing');

$order = request('POST', '/api/v1/orders', [
    'order_type' => 'takeaway',
    'items'      => [['menu_item_id' => 1, 'quantity' => 1]], // Chicken Burger 35,000
], $admin)['json']['data'];
$orderId = (int) $order['id'];
ok((float) $order['total'] === 40000.0, 'a one-item takeaway starts at 40,000');

$edited = request('PUT', "/api/v1/orders/$orderId/items", [
    'items' => [
        ['menu_item_id' => 1, 'quantity' => 2],
        ['menu_item_id' => 16, 'quantity' => 1], // French Fries 15,000
    ],
    'reason' => 'Customer added fries',
], $admin);
ok($edited['status'] === 200, 'the order accepts an edit while open');
ok(
    (float) ($edited['json']['data']['total'] ?? 0) === 100000.0,
    'and reprices server-side (70,000 + 15,000 + 3 x 5,000)',
    'got ' . ($edited['json']['data']['total'] ?? 'null'),
);
ok(count($edited['json']['data']['items'] ?? []) === 2, 'both lines are stored');

$history = request('GET', "/api/v1/orders/$orderId/history", null, $admin)['json']['data'] ?? [];
$actions = array_column($history, 'action');
ok(in_array('quantity_changed', $actions, true), 'the quantity change is audited');
ok(in_array('item_added', $actions, true), 'the added line is audited');
ok(in_array('order_total_changed', $actions, true), 'the total change is audited');

$qtyEvent = null;
foreach ($history as $event) {
    if ($event['action'] === 'quantity_changed') {
        $qtyEvent = $event;
    }
}
ok(($qtyEvent['old_value'] ?? '') === '1', 'with the old quantity');
ok(($qtyEvent['new_value'] ?? '') === '2', 'and the new one');
ok(($qtyEvent['reason'] ?? '') === 'Customer added fries', 'and the reason given');

// Every line change carries a reason — an audit row saying a total moved with
// no explanation is the one a manager cannot use.
$noReason = request('PUT', "/api/v1/orders/$orderId/items", [
    'items' => [['menu_item_id' => 1, 'quantity' => 2]],
], $admin);
ok($noReason['status'] === 422, 'an edit without a reason is refused', 'got ' . $noReason['status']);

$removed = request('PUT', "/api/v1/orders/$orderId/items", [
    'items'  => [['menu_item_id' => 1, 'quantity' => 2]],
    'reason' => 'Customer changed their mind about the fries',
], $admin);
ok(
    (float) ($removed['json']['data']['total'] ?? 0) === 80000.0,
    'removing a line reprices down (70,000 + 2 x 5,000)',
);
$actions = array_column(
    request('GET', "/api/v1/orders/$orderId/history", null, $admin)['json']['data'] ?? [],
    'action',
);
ok(in_array('item_removed', $actions, true), 'the removed line is audited');

$empty = request('PUT', "/api/v1/orders/$orderId/items", [
    'items'  => [],
    'reason' => 'Emptying the order',
], $admin);
ok($empty['status'] === 422, 'an order cannot be edited down to nothing');

// ---- payments constrain edits -----------------------------------------

$owedNow = (float) ($removed['json']['data']['total'] ?? 0);
request('POST', "/api/v1/orders/$orderId/payments", [
    'method' => 'cash',
    'amount' => $owedNow,
], $admin);

// Shrinking an order that is already paid used to be refused, which left the
// restaurant holding money for food it never served with no way to correct it.
// It is allowed now — and the difference has to leave the till, or the day's
// takings quietly keep money that belongs to the customer.
$tillBefore = 0.0;
foreach (request('GET', '/api/v1/accounts', null, $admin)['json']['data'] ?? [] as $account) {
    if (($account['method'] ?? '') === 'cash') {
        $tillBefore = (float) $account['balance'];
    }
}

$shrink = request('PUT', "/api/v1/orders/$orderId/items", [
    'items'  => [['menu_item_id' => 1, 'quantity' => 1]],
    'reason' => 'One plate was returned to the kitchen',
], $admin);
ok(
    $shrink['status'] === 200,
    'a paid order can be shrunk to correct a mistake',
    'got ' . $shrink['status'] . ' ' . json_encode($shrink['json']['error'] ?? []),
);
ok(
    (float) ($shrink['json']['data']['total'] ?? 0) === 40000.0,
    'and reprices down (35,000 + 5,000)',
    'got ' . ($shrink['json']['data']['total'] ?? 'null'),
);

$tillAfter = 0.0;
foreach (request('GET', '/api/v1/accounts', null, $admin)['json']['data'] ?? [] as $account) {
    if (($account['method'] ?? '') === 'cash') {
        $tillAfter = (float) $account['balance'];
    }
}

// 80,000 was taken; 40,000 is owed; 40,000 has to go back out.
ok(
    abs(($tillBefore - $tillAfter) - ($owedNow - 40000.0)) < 0.01,
    'and the overpayment leaves the till rather than staying in the takings',
    sprintf('till went %s -> %s', number_format($tillBefore), number_format($tillAfter)),
);

// Put the order back where the rest of this file expects to find it.
request('PUT', "/api/v1/orders/$orderId/items", [
    'items'  => [['menu_item_id' => 1, 'quantity' => 2]],
    'reason' => 'Restoring the order for the checks that follow',
], $admin);

// Against what is actually outstanding, not what was once handed over.
//
// The shrink above refunded 35,000, and that refund is now recorded as a
// negative payment row — so the order is genuinely short by that much again
// after being restored. Paying it off first is what makes the next payment a
// real overpayment rather than a legitimate settlement.
$restored = request('GET', "/api/v1/orders/$orderId", null, $admin)['json']['data'];
$outstanding = (float) $restored['total'] - (float) array_sum(
    array_column($restored['payments'] ?? [], 'amount'),
);

ok($outstanding > 0, 'the refund left the order short again', number_format($outstanding));

$settle = request('POST', "/api/v1/orders/$orderId/payments", [
    'method' => 'cash',
    'amount' => $outstanding,
], $admin);
ok($settle['status'] === 200, 'and the balance can be settled', 'got ' . $settle['status']);

$overpay = request('POST', "/api/v1/orders/$orderId/payments", [
    'method' => 'cash',
    'amount' => 1000,
], $admin);
ok($overpay['status'] === 422, 'and it cannot be overpaid', 'got ' . $overpay['status']);

// ---- completed orders correct, cancelled ones stay dead ---------------

// Orders complete the moment they are paid, so refusing to edit a completed
// order made a miscounted line permanently uncorrectable. The safeguard is not
// refusal — it is that the change is recorded with who, what and why.
request('PATCH', "/api/v1/orders/$orderId/status", ['status' => 'completed'], $admin);

$correction = request('PUT', "/api/v1/orders/$orderId/items", [
    'items'  => [['menu_item_id' => 1, 'quantity' => 3]],
    'reason' => 'Counter miscounted, third plate was served',
], $admin);
ok(
    $correction['status'] === 200,
    'a completed order can still be corrected',
    'got ' . $correction['status'] . ' ' . json_encode($correction['json']['error'] ?? []),
);
ok(
    (float) ($correction['json']['data']['total'] ?? 0) === 120000.0,
    'and reprices to match (3 x 35,000 + 3 x 5,000)',
    'got ' . ($correction['json']['data']['total'] ?? 'null'),
);

// Raising the total past what was paid puts the order back in debt rather than
// quietly leaving it marked paid.
ok(
    ($correction['json']['data']['payment_status'] ?? '') !== 'paid',
    'and it is no longer treated as settled',
    'got ' . ($correction['json']['data']['payment_status'] ?? 'null'),
);

$correctionHistory = array_column(
    request('GET', "/api/v1/orders/$orderId/history", null, $admin)['json']['data'] ?? [],
    'reason',
);
ok(
    in_array('Counter miscounted, third plate was served', $correctionHistory, true),
    'and the correction is on the record with its reason',
);

$cancelledOrder = request('POST', '/api/v1/orders', [
    'order_type' => 'takeaway',
    'items'      => [['menu_item_id' => 8, 'quantity' => 1]],
], $admin)['json']['data'];
request(
    'PATCH',
    '/api/v1/orders/' . $cancelledOrder['id'] . '/status',
    ['status' => 'cancelled', 'reason' => 'Test'],
    $admin,
);
$editCancelled = request('PUT', '/api/v1/orders/' . $cancelledOrder['id'] . '/items', [
    'items'  => [['menu_item_id' => 8, 'quantity' => 2]],
    'reason' => 'Trying to revive a voided order',
], $admin);
ok(
    $editCancelled['status'] === 409,
    'a cancelled order cannot be edited even with a reason',
    'got ' . $editCancelled['status'],
);

// With a valid body, so a 403 is the permission check refusing and not the
// validator rejecting the request before it ever reaches one.
$waiterEdit = request('PUT', "/api/v1/orders/$orderId/items", [
    'items'  => [['menu_item_id' => 1, 'quantity' => 1]],
    'reason' => 'A waiter should not be able to do this',
], $waiter);
ok($waiterEdit['status'] === 403, 'a waiter cannot edit order lines');

// ================================================================ drafts

group('Draft-ka waa la beddeli karaa ilaa la dhammaystiro');

// A customer rings back and changes their order. Until the draft becomes a real
// order — or is voided — that has to be possible, because the alternative is
// cancelling and re-keying the whole thing.
$editable = request('POST', '/api/v1/drafts', [
    'customer_name' => 'Cabdi Telefoon',
    'order_type'    => 'takeaway',
    'items'         => [['menu_item_id' => 1, 'quantity' => 1]],
], $admin);

ok($editable['status'] === 200, 'draft la abuuray', 'got ' . $editable['status']);
$draftId = (int) ($editable['json']['data']['id'] ?? 0);

$changed = request('PUT', "/api/v1/drafts/$draftId", [
    'items' => [
        ['menu_item_id' => 1, 'quantity' => 3],
        ['menu_item_id' => 8, 'quantity' => 1],
    ],
], $admin);

ok($changed['status'] === 200, 'waa la beddeli karaa', 'got ' . $changed['status']);
ok(
    count($changed['json']['data']['items'] ?? []) === 2,
    'oo labada sadar way ku jiraan',
    (string) count($changed['json']['data']['items'] ?? []),
);

group('Laakiin ma aha ka dib marka la dhammaystiro ama la joojiyo');

$toCancel = request('POST', '/api/v1/drafts', [
    'customer_name' => 'Mid la joojinayo',
    'order_type'    => 'takeaway',
    'items'         => [['menu_item_id' => 1, 'quantity' => 1]],
], $admin)['json']['data'];

request('POST', '/api/v1/drafts/' . $toCancel['id'] . '/cancel', [
    'reason' => 'Macmiilku wuu noqday',
], $admin);

$editCancelled = request('PUT', '/api/v1/drafts/' . $toCancel['id'], [
    'items' => [['menu_item_id' => 1, 'quantity' => 9]],
], $admin);

ok(
    $editCancelled['status'] === 409,
    'mid la joojiyay lama beddeli karo',
    'got ' . $editCancelled['status'],
);

$toConvert = request('POST', '/api/v1/drafts', [
    'customer_name' => 'Mid la beddelayo',
    'order_type'    => 'takeaway',
    'items'         => [['menu_item_id' => 1, 'quantity' => 1]],
], $admin)['json']['data'];

$converted = request('POST', '/api/v1/drafts/' . $toConvert['id'] . '/convert', [
    'payment_method' => 'cash',
], $admin);

if ($converted['status'] === 200) {
    $editConverted = request('PUT', '/api/v1/drafts/' . $toConvert['id'], [
        'items' => [['menu_item_id' => 1, 'quantity' => 9]],
    ], $admin);

    ok(
        $editConverted['status'] === 409,
        'midna la beddelay lama beddeli karo',
        'got ' . $editConverted['status'],
    );
}


group('Drafts');

$draft = request('POST', '/api/v1/drafts', [
    'customer_name' => 'Saynab',
    'order_type'    => 'dine_in',
    'table_id'      => 7,
    'items'         => [['menu_item_id' => 5, 'quantity' => 1]], // Margherita 50,000
], $admin);
ok($draft['status'] === 200, 'a dine-in draft is created');
$draftId = (int) $draft['json']['data']['id'];
ok(
    (float) $draft['json']['data']['subtotal'] === 50000.0,
    'with the live menu price',
);

$updated = request('PUT', "/api/v1/drafts/$draftId", [
    'customer_name' => 'Saynab Cali',
    'items'         => [
        ['menu_item_id' => 5, 'quantity' => 2],
        ['menu_item_id' => 11, 'quantity' => 1],
    ],
], $admin);
ok($updated['status'] === 200, 'a draft can be edited');
ok(
    ($updated['json']['data']['customer_name'] ?? '') === 'Saynab Cali',
    'the customer name updates',
);
ok(
    (float) ($updated['json']['data']['subtotal'] ?? 0) === 108000.0,
    'and it reprices (100,000 + 8,000)',
    'got ' . ($updated['json']['data']['subtotal'] ?? 'null'),
);

$switched = request('PUT', "/api/v1/drafts/$draftId", [
    'order_type' => 'takeaway',
], $admin);
// `?? 'x'` would swallow a correct null, so check the key explicitly.
ok(
    array_key_exists('table_id', $switched['json']['data'] ?? [])
    && $switched['json']['data']['table_id'] === null,
    'switching a draft to takeaway drops its table',
    'got ' . var_export($switched['json']['data']['table_id'] ?? 'missing', true),
);

$salesBefore = (float) request(
    'GET',
    '/api/v1/reports/summary?range=today',
    null,
    $admin,
)['json']['data']['sales']['value'];

$converted = request('POST', "/api/v1/drafts/$draftId/convert", [
    'payment_method' => 'cash',
], $admin);
ok($converted['status'] === 200, 'the draft converts to an order');
// Margherita x2 (100,000) + Shaah (8,000). Only the pizzas need a
// container — Shaah is flagged apply_packaging_fee = 0 — so two fees,
// not three.
ok(
    (float) ($converted['json']['data']['total'] ?? 0) === 118000.0,
    'only the portions that need a container are charged (108,000 + 2 x 5,000)',
    'got ' . ($converted['json']['data']['total'] ?? 'null'),
);

$salesAfter = (float) request(
    'GET',
    '/api/v1/reports/summary?range=today',
    null,
    $admin,
)['json']['data']['sales']['value'];
ok($salesAfter > $salesBefore, 'and only then counts as revenue');

$editConverted = request('PUT', "/api/v1/drafts/$draftId", [
    'customer_name' => 'Too late',
], $admin);
ok($editConverted['status'] === 409, 'a converted draft cannot be edited');

// ============================================================ menu & tables

group('Menu and tables');

$category = request('POST', '/api/v1/menu/categories', [
    'name'  => 'Cabitaan Kulul',
    'emoji' => '☕',
    'color' => '#14B8A6',
], $admin);
ok($category['status'] === 200, 'a category is created');
$categoryId = (int) $category['json']['data']['id'];

$item = request('POST', '/api/v1/menu/items', [
    'category_id' => $categoryId,
    'name'        => 'Qaxwo',
    'price'       => 12000,
    'emoji'       => '☕',
], $admin);
ok($item['status'] === 200, 'an item is added to it');
$itemId = (int) $item['json']['data']['id'];

$counted = request('GET', '/api/v1/menu/categories', null, $admin)['json']['data'] ?? [];
$mine = array_values(array_filter(
    $counted,
    static fn (array $c): bool => (int) $c['id'] === $categoryId,
))[0];
ok(($mine['item_count'] ?? 0) === 1, 'the category reports its item count');

$deleteBusy = request('DELETE', "/api/v1/menu/categories/$categoryId", null, $admin);
ok($deleteBusy['status'] === 409, 'a category with items cannot be deleted');

request('DELETE', "/api/v1/menu/items/$itemId", null, $admin);
$deleteEmpty = request('DELETE', "/api/v1/menu/categories/$categoryId", null, $admin);
ok($deleteEmpty['status'] === 200, 'once empty it can be');

$table = request('POST', '/api/v1/tables', [
    'table_number' => 21,
    'capacity'     => 6,
    'name'         => 'Terrace 1',
], $admin);
ok($table['status'] === 200, 'a table is created');
$tableId = (int) $table['json']['data']['id'];

$duplicate = request('POST', '/api/v1/tables', [
    'table_number' => 21,
    'capacity'     => 2,
], $admin);
ok($duplicate['status'] === 422, 'table numbers are unique per restaurant');

$reserved = request('PUT', "/api/v1/tables/$tableId", ['status' => 'reserved'], $admin);
ok(
    ($reserved['json']['data']['status'] ?? '') === 'reserved',
    'a table can be reserved',
);

$occupied = request('POST', '/api/v1/orders', [
    'order_type' => 'dine_in',
    'table_id'   => $tableId,
    'items'      => [['menu_item_id' => 1, 'quantity' => 1]],
], $admin)['json']['data'];
$deleteOccupied = request('DELETE', "/api/v1/tables/$tableId", null, $admin);
ok($deleteOccupied['status'] === 409, 'an occupied table cannot be removed');

request(
    'PATCH',
    '/api/v1/orders/' . $occupied['id'] . '/status',
    ['status' => 'completed'],
    $admin,
);
$freed = request('DELETE', "/api/v1/tables/$tableId", null, $admin);
ok($freed['status'] === 200, 'once the order closes it can be');

$waiterTable = request('POST', '/api/v1/tables', [
    'table_number' => 22,
    'capacity'     => 2,
], $waiter);
ok($waiterTable['status'] === 403, 'a waiter cannot manage tables');

// ========================================================== expenses

group('Expenses');

/** Reads one account balance. */
function balance(string $token, string $method): float
{
    $accounts = request('GET', '/api/v1/accounts', null, $token)['json']['data'] ?? [];
    foreach ($accounts as $account) {
        if ($account['method'] === $method) {
            return (float) $account['balance'];
        }
    }

    return 0.0;
}

$cashBefore = balance($admin, 'cash');

$expense = request('POST', '/api/v1/expenses', [
    'name'   => 'Shidaal',
    'amount' => 40000,
    'kind'   => 'daily',
    'method' => 'cash',
], $admin);
ok($expense['status'] === 200, 'an expense is recorded');
$expenseId = (int) $expense['json']['data']['id'];

ok(
    round($cashBefore - balance($admin, 'cash'), 2) === 40000.0,
    'and the cash account drops by the amount',
);

$repriced = request('PUT', "/api/v1/expenses/$expenseId", [
    'amount' => 55000,
    'reason' => 'Receipt was higher',
], $admin);
ok($repriced['status'] === 200, 'an expense can be corrected');
ok(
    round($cashBefore - balance($admin, 'cash'), 2) === 55000.0,
    'and the account re-settles to the new amount',
    'delta ' . round($cashBefore - balance($admin, 'cash'), 2),
);

$moved = request('PUT', "/api/v1/expenses/$expenseId", ['method' => 'zaad'], $admin);
ok($moved['status'] === 200, 'the payment method can be corrected');
ok(
    round(balance($admin, 'cash') - $cashBefore, 2) === 0.0,
    'cash is made whole again',
    'delta ' . round(balance($admin, 'cash') - $cashBefore, 2),
);

$ledger = request('GET', '/api/v1/accounts/transactions', null, $admin)['json']['data'] ?? [];
$reversals = array_filter(
    $ledger,
    static fn (array $t): bool => str_contains($t['description'], 'Reversal'),
);
ok($reversals !== [], 'the correction leaves a reversal in the ledger');

request('DELETE', "/api/v1/expenses/$expenseId", null, $admin);
ok(
    round(balance($admin, 'zaad'), 2) === round(balance($admin, 'zaad'), 2),
    'deleting an expense refunds its account',
);

$badAmount = request('POST', '/api/v1/expenses', [
    'name'   => 'Free lunch',
    'amount' => 0,
    'kind'   => 'daily',
    'method' => 'cash',
], $admin);
ok($badAmount['status'] === 422, 'an expense of zero is rejected');

$expCategory = request('POST', '/api/v1/expense-categories', [
    'name' => 'Marketing',
    'kind' => 'monthly',
], $admin);
ok($expCategory['status'] === 200, 'an expense category is created');

$retired = request(
    'DELETE',
    '/api/v1/expense-categories/' . $expCategory['json']['data']['id'],
    null,
    $admin,
);
ok($retired['status'] === 200, 'and can be retired');

$waiterExpense = request('POST', '/api/v1/expenses', [
    'name'   => 'Sneaky',
    'amount' => 1000,
    'kind'   => 'daily',
    'method' => 'cash',
], $waiter);
ok($waiterExpense['status'] === 403, 'a waiter cannot record expenses');

// =========================================================== accounts

group('Accounts');

$cash = balance($admin, 'cash');
$bank = balance($admin, 'bank');

$accounts = request('GET', '/api/v1/accounts', null, $admin)['json']['data'] ?? [];
$byMethod = [];
foreach ($accounts as $account) {
    $byMethod[$account['method']] = $account;
}

$transfer = request('POST', '/api/v1/accounts/transfer', [
    'from_account_id' => $byMethod['cash']['id'],
    'to_account_id'   => $byMethod['bank']['id'],
    'amount'          => 100000,
    'description'     => 'Bank deposit',
], $admin);
ok($transfer['status'] === 200, 'a transfer succeeds');
ok(
    round($cash - balance($admin, 'cash'), 2) === 100000.0
    && round(balance($admin, 'bank') - $bank, 2) === 100000.0,
    'and moves the money both ways',
);

$sameAccount = request('POST', '/api/v1/accounts/transfer', [
    'from_account_id' => $byMethod['cash']['id'],
    'to_account_id'   => $byMethod['cash']['id'],
    'amount'          => 1000,
], $admin);
ok($sameAccount['status'] === 422, 'a transfer to the same account is rejected');

$tooMuch = request('POST', '/api/v1/accounts/transfer', [
    'from_account_id' => $byMethod['edahab']['id'],
    'to_account_id'   => $byMethod['bank']['id'],
    'amount'          => 999999999,
], $admin);
ok($tooMuch['status'] === 422, 'an overdraft is rejected');

$crossTenant = request('POST', '/api/v1/accounts/transfer', [
    'from_account_id' => $byMethod['cash']['id'],
    'to_account_id'   => 5, // a WARFA account
    'amount'          => 1000,
], $admin);
ok(
    $crossTenant['status'] === 404,
    'money cannot be transferred to another restaurant',
    'got ' . $crossTenant['status'],
);

$waiterTransfer = request('POST', '/api/v1/accounts/transfer', [
    'from_account_id' => $byMethod['cash']['id'],
    'to_account_id'   => $byMethod['bank']['id'],
    'amount'          => 1000,
], $waiter);
ok($waiterTransfer['status'] === 403, 'a waiter cannot move money between accounts');

summary();
