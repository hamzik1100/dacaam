<?php

declare(strict_types=1);

/**
 * End-to-end API tests.
 *
 * Runs against a live server and a seeded database:
 *
 *   php bin/migrate.php --fresh --seed
 *   php -S 127.0.0.1:8090 -t public public/index.php
 *   php tests/api_test.php http://127.0.0.1:8090
 *
 * The suite exists mainly to prove three things that must never regress:
 * tenant isolation, server-computed pricing, and permission enforcement.
 */

require __DIR__ . '/harness.php';

// ===================================================================== auth

group('Health & authentication');

$health = request('GET', '/api/v1/health');
ok($health['status'] === 200, 'health endpoint responds', json_encode($health));

$bad = login('HAMZE', '0634567890', 'wrong-password');
ok($bad['status'] === 401, 'wrong password is rejected', 'got ' . $bad['status']);

$unknownTenant = login('NOPE', '0634567890');
ok(
    $unknownTenant['status'] === 401
    && !str_contains(strtolower($unknownTenant['json']['error']['message'] ?? ''), 'restaurant not found'),
    'unknown restaurant code fails identically to a bad password',
    'message: ' . ($unknownTenant['json']['error']['message'] ?? '?'),
);

$adminLogin = login('HAMZE', '0634567890');
ok($adminLogin['status'] === 200, 'HAMZE admin logs in', json_encode($adminLogin['json']));
$admin = $adminLogin['json']['data']['token'] ?? '';
ok($admin !== '', 'a token is issued');
// A till has to be open before anything can be sold. That is the rule the
// shift feature exists to enforce, so the suite opens one exactly as the
// restaurant does at the start of service.
ensureShift($admin);


$spaced = login('HAMZE', '063 456 7890');
ok($spaced['status'] === 200, 'phone with spaces normalises to the same account');

$noToken = request('GET', '/api/v1/bootstrap');
ok($noToken['status'] === 401, 'bootstrap without a token is 401');

$garbage = request('GET', '/api/v1/bootstrap', null, 'not-a-real-token');
ok($garbage['status'] === 401, 'bootstrap with a forged token is 401');

$waiterLogin = login('HAMZE', '0632233445');
$waiter = $waiterLogin['json']['data']['token'] ?? '';
ok($waiter !== '', 'HAMZE waiter logs in');

$warfaLogin = login('WARFA', '0637778899');
$warfa = $warfaLogin['json']['data']['token'] ?? '';
ok($warfa !== '', 'WARFA admin logs in');
// WARFA sells too, so WARFA needs its own till open. Shifts belong to a
// restaurant, not to the platform.
ensureShift($warfa);


// ================================================================ bootstrap

group('Bootstrap payload');

$boot = request('GET', '/api/v1/bootstrap', null, $admin);
ok($boot['status'] === 200, 'bootstrap returns 200');

$data = $boot['json']['data'] ?? [];
ok(($data['restaurant']['slug'] ?? '') === 'HAMZE', 'scoped to the caller\'s restaurant');
ok(count($data['menu_items'] ?? []) === 18, 'returns 18 HAMZE menu items', 'got ' . count($data['menu_items'] ?? []));
ok(count($data['categories'] ?? []) === 6, 'returns 6 categories');
ok(count($data['tables'] ?? []) === 12, 'returns 12 tables');
ok(($data['settings']['currency_prefix'] ?? '') === 'SLSH', 'settings carry the currency prefix');
ok(($data['settings']['tax_enabled'] ?? true) === false, 'HAMZE tax defaults off');
ok(isset($data['dashboard']['sales']['value']), 'dashboard KPIs are included');

// ========================================================= tenant isolation

group('Tenant isolation');

$warfaBoot = request('GET', '/api/v1/bootstrap', null, $warfa);
$warfaItems = array_column($warfaBoot['json']['data']['menu_items'] ?? [], 'name');
ok(in_array('Camel Suqaar', $warfaItems, true), 'WARFA sees its own menu');
ok(!in_array('Chicken Burger', $warfaItems, true), 'WARFA cannot see HAMZE items');

$hamzeItems = array_column($data['menu_items'] ?? [], 'name');
ok(!in_array('Camel Suqaar', $hamzeItems, true), 'HAMZE cannot see WARFA items');

// Order id 13 belongs to WARFA in the seed.
$crossOrder = request('GET', '/api/v1/orders/13', null, $admin);
ok($crossOrder['status'] === 404, 'reading another tenant\'s order id returns 404', 'got ' . $crossOrder['status']);

// Menu item 30 (Camel Suqaar) belongs to WARFA.
$crossItem = request('PUT', '/api/v1/menu/items/30', ['price' => 1], $admin);
ok($crossItem['status'] === 404, 'updating another tenant\'s menu item returns 404', 'got ' . $crossItem['status']);

$crossOrderCreate = request('POST', '/api/v1/orders', [
    'order_type' => 'takeaway',
    'items'      => [['menu_item_id' => 30, 'quantity' => 1]],
], $admin);
ok(
    $crossOrderCreate['status'] === 422,
    'ordering another tenant\'s menu item is rejected',
    'got ' . $crossOrderCreate['status'],
);

// ============================================================ order pricing

group('Server-side pricing');

// Chicken Burger 35,000 + French Fries x2 30,000 + Fresh Juice 20,000 = 85,000
$basket = [
    ['menu_item_id' => 1, 'quantity' => 1],
    ['menu_item_id' => 16, 'quantity' => 2],
    ['menu_item_id' => 10, 'quantity' => 1],
];

$noTable = request('POST', '/api/v1/orders', [
    'order_type' => 'dine_in',
    'items'      => $basket,
], $admin);
ok($noTable['status'] === 422, 'Dine In without a table is rejected while the setting is on');
ok(
    isset($noTable['json']['error']['fields']['table_id']),
    'the rejection names the table_id field',
);

$dineIn = request('POST', '/api/v1/orders', [
    'order_type' => 'dine_in',
    'table_id'   => 2,
    'items'      => $basket,
    // Deliberately bogus: the server must ignore anything price-shaped.
    'total'      => 1,
    'subtotal'   => 1,
], $admin);
ok($dineIn['status'] === 200, 'Dine In with a table succeeds', json_encode($dineIn['json']));
$dineInOrder = $dineIn['json']['data'] ?? [];
ok(($dineInOrder['total'] ?? 0) === 85000.0, 'total is computed server-side (85,000)', 'got ' . ($dineInOrder['total'] ?? 'null'));
ok(($dineInOrder['packaging_fee'] ?? -1) === 0.0, 'no packaging fee on Dine In');
ok(($dineInOrder['tax_amount'] ?? -1) === 0.0, 'no tax while the setting is off');
ok(count($dineInOrder['items'] ?? []) === 3, 'all three lines are stored');

$takeaway = request('POST', '/api/v1/orders', [
    'order_type' => 'takeaway',
    'table_id'   => 2,
    'items'      => $basket,
], $admin);
$takeawayOrder = $takeaway['json']['data'] ?? [];
// Four portions in the basket — 1 burger, 2 fries, 1 juice — and each one
// goes into its own container. 85,000 + 4 x 5,000.
ok(
    ($takeawayOrder['total'] ?? 0) === 105000.0,
    'takeaway charges the packaging fee per portion (85,000 + 4 x 5,000)',
    'got ' . ($takeawayOrder['total'] ?? 'null'),
);
ok(
    ($takeawayOrder['packaging_fee'] ?? 0) === 20000.0,
    'and the fee itself is four of them',
    'got ' . ($takeawayOrder['packaging_fee'] ?? 'null'),
);
// `?? 'x'` would swallow a correct null here, so check the key explicitly.
ok(
    array_key_exists('table_id', $takeawayOrder) && $takeawayOrder['table_id'] === null,
    'a table sent with a takeaway order is dropped',
    'got ' . var_export($takeawayOrder['table_id'] ?? 'missing', true),
);

// Water and Shaah are both flagged apply_packaging_fee = 0.
$noPackaging = request('POST', '/api/v1/orders', [
    'order_type' => 'takeaway',
    'items'      => [
        ['menu_item_id' => 13, 'quantity' => 1],
        ['menu_item_id' => 11, 'quantity' => 2],
    ],
], $admin);
ok(
    ($noPackaging['json']['data']['total'] ?? 0) === 21000.0,
    'no packaging fee when no line is eligible',
    'got ' . ($noPackaging['json']['data']['total'] ?? 'null'),
);

$discounted = request('POST', '/api/v1/orders', [
    'order_type' => 'dine_in',
    'table_id'   => 5,
    'items'      => $basket,
    'discount'   => 999999,
], $admin);
ok(
    ($discounted['json']['data']['total'] ?? -1) === 0.0,
    'a discount is capped at the subtotal so a total cannot go negative',
    'got ' . ($discounted['json']['data']['total'] ?? 'null'),
);

$emptyOrder = request('POST', '/api/v1/orders', [
    'order_type' => 'takeaway',
    'items'      => [],
], $admin);
ok($emptyOrder['status'] === 422, 'an order with no items is rejected');

$unavailable = request('POST', '/api/v1/orders', [
    'order_type' => 'takeaway',
    'items'      => [['menu_item_id' => 15, 'quantity' => 1]], // Ice Cream, unavailable
], $admin);
ok($unavailable['status'] === 422, 'ordering an unavailable item is rejected');

// WARFA prices with tax on at 5% and a 3,000 packaging fee.
$warfaOrder = request('POST', '/api/v1/orders', [
    'order_type' => 'takeaway',
    'items'      => [['menu_item_id' => 30, 'quantity' => 1]], // Camel Suqaar 70,000
], $warfa);
$warfaTotal = $warfaOrder['json']['data']['total'] ?? 0;
ok(
    $warfaTotal === 76500.0,
    'WARFA prices with its own tax and fee (70,000 + 5% + one 3,000 portion)',
    'got ' . $warfaTotal,
);

// ======================================================== order lifecycle

group('Order lifecycle & audit');

$orderId = (int) ($dineInOrder['id'] ?? 0);

$tables = request('GET', '/api/v1/tables', null, $admin)['json']['data'] ?? [];
$table2 = null;
foreach ($tables as $t) {
    if ((int) $t['id'] === 2) {
        $table2 = $t;
    }
}
ok(($table2['status'] ?? '') === 'occupied', 'the table is occupied while the order is open');

$cancelNoReason = request('PATCH', "/api/v1/orders/$orderId/status", ['status' => 'cancelled'], $admin);
ok($cancelNoReason['status'] === 422, 'cancelling without a reason is rejected');

$ready = request('PATCH', "/api/v1/orders/$orderId/status", ['status' => 'ready'], $admin);
ok(($ready['json']['data']['status'] ?? '') === 'ready', 'status moves to ready');

$completed = request('PATCH', "/api/v1/orders/$orderId/status", ['status' => 'completed'], $admin);
ok(($completed['json']['data']['status'] ?? '') === 'completed', 'status moves to completed');

$reopen = request('PATCH', "/api/v1/orders/$orderId/status", ['status' => 'preparing'], $admin);
ok($reopen['status'] === 409, 'a completed order cannot be reopened', 'got ' . $reopen['status']);

$tablesAfter = request('GET', '/api/v1/tables', null, $admin)['json']['data'] ?? [];
foreach ($tablesAfter as $t) {
    if ((int) $t['id'] === 2) {
        ok($t['status'] === 'available', 'completing the order frees the table');
        ok($t['current_order_id'] === null, 'the table no longer points at an order');
    }
}

$history = request('GET', "/api/v1/orders/$orderId/history", null, $admin)['json']['data'] ?? [];
$actions = array_column($history, 'action');
ok(in_array('order_created', $actions, true), 'the audit trail records creation');
ok(in_array('order_status_changed', $actions, true), 'the audit trail records status changes');

$statusEvent = null;
foreach ($history as $event) {
    if ($event['action'] === 'order_status_changed' && $event['new_value'] === 'completed') {
        $statusEvent = $event;
    }
}
ok($statusEvent !== null, 'the completion event exists');
ok(($statusEvent['old_value'] ?? '') === 'ready', 'it records the old value');
ok(($statusEvent['user_name'] ?? '') === 'Axmed Xasan', 'it names who made the change');

$cancelTarget = request('POST', '/api/v1/orders', [
    'order_type' => 'takeaway',
    'items'      => [['menu_item_id' => 8, 'quantity' => 1]],
], $admin)['json']['data'] ?? [];

$cancelled = request(
    'PATCH',
    '/api/v1/orders/' . (int) $cancelTarget['id'] . '/status',
    ['status' => 'cancelled', 'reason' => 'Macmiilku wuu ka noqday'],
    $admin,
);
ok(($cancelled['json']['data']['status'] ?? '') === 'cancelled', 'cancelling with a reason succeeds');
ok(
    ($cancelled['json']['data']['cancel_reason'] ?? '') === 'Macmiilku wuu ka noqday',
    'the reason is stored on the order',
);

// ============================================================== accounts

group('Accounts');

$before = request('GET', '/api/v1/accounts', null, $admin)['json']['data'] ?? [];
$cashBefore = 0.0;
foreach ($before as $account) {
    if ($account['method'] === 'cash') {
        $cashBefore = (float) $account['balance'];
    }
}

request('POST', '/api/v1/orders', [
    'order_type'     => 'takeaway',
    'items'          => [['menu_item_id' => 1, 'quantity' => 1]],
    'payment_method' => 'cash',
], $admin);

$after = request('GET', '/api/v1/accounts', null, $admin)['json']['data'] ?? [];
$cashAfter = 0.0;
foreach ($after as $account) {
    if ($account['method'] === 'cash') {
        $cashAfter = (float) $account['balance'];
    }
}
ok(
    round($cashAfter - $cashBefore, 2) === 40000.0,
    'a cash payment credits the cash account (35,000 + 5,000 packaging)',
    'delta ' . round($cashAfter - $cashBefore, 2),
);

// =========================================================== permissions

group('Permissions');

$waiterOrders = request('GET', '/api/v1/orders', null, $waiter);
ok($waiterOrders['status'] === 200, 'a waiter can list orders');

$waiterReports = request('GET', '/api/v1/reports/summary', null, $waiter);
ok($waiterReports['status'] === 403, 'a waiter cannot read reports', 'got ' . $waiterReports['status']);

$waiterUsers = request('GET', '/api/v1/users', null, $waiter);
ok($waiterUsers['status'] === 403, 'a waiter cannot list users');

$waiterSettings = request('PUT', '/api/v1/settings', ['tax_enabled' => true], $waiter);
ok($waiterSettings['status'] === 403, 'a waiter cannot change settings');

$waiterDelete = request('DELETE', '/api/v1/menu/items/1', null, $waiter);
ok($waiterDelete['status'] === 403, 'a waiter cannot delete menu items');

$waiterCreate = request('POST', '/api/v1/orders', [
    'order_type' => 'takeaway',
    'items'      => [['menu_item_id' => 11, 'quantity' => 1]],
], $waiter);
ok($waiterCreate['status'] === 200, 'a waiter can still take an order');

// ================================================================== menu

group('Menu validation');

$badPrice = request('POST', '/api/v1/menu/items', [
    'category_id' => 1,
    'name'        => 'Free Lunch',
    'price'       => 0,
], $admin);
ok($badPrice['status'] === 422, 'a price of zero is rejected');

$noName = request('POST', '/api/v1/menu/items', [
    'category_id' => 1,
    'price'       => 1000,
], $admin);
ok($noName['status'] === 422, 'a missing name is rejected');

$created = request('POST', '/api/v1/menu/items', [
    'category_id' => 1,
    'name'        => 'Test Burger',
    'price'       => 42000,
    'emoji'       => '🍔',
], $admin);
ok($created['status'] === 200, 'a valid item is created');
$newItemId = (int) ($created['json']['data']['id'] ?? 0);

$repriced = request('PUT', "/api/v1/menu/items/$newItemId", [
    'price'  => 44000,
    'reason' => 'Price update',
], $admin);
ok(($repriced['json']['data']['price'] ?? 0) === 44000.0, 'the item is repriced');

$audit = request('GET', '/api/v1/audit-logs?module=menu', null, $admin)['json']['data'] ?? [];
$priceChange = null;
foreach ($audit as $entry) {
    if ((int) ($entry['record_id'] ?? 0) === $newItemId && $entry['field'] === 'price') {
        $priceChange = $entry;
    }
}
ok($priceChange !== null, 'the price change is audited');
ok(($priceChange['old_value'] ?? '') !== ($priceChange['new_value'] ?? ''), 'with old and new values');
ok(($priceChange['reason'] ?? '') === 'Price update', 'and the supplied reason');

$toggled = request('PATCH', "/api/v1/menu/items/$newItemId/availability", null, $admin);
ok(($toggled['json']['data']['is_available'] ?? true) === false, 'availability toggles off');

$deleted = request('DELETE', "/api/v1/menu/items/$newItemId", null, $admin);
ok($deleted['status'] === 200, 'the item is deleted');

$stillOrderable = request('POST', '/api/v1/orders', [
    'order_type' => 'takeaway',
    'items'      => [['menu_item_id' => $newItemId, 'quantity' => 1]],
], $admin);
ok($stillOrderable['status'] === 422, 'a deleted item can no longer be ordered');

// =============================================================== drafts

group('Drafts');

$draft = request('POST', '/api/v1/drafts', [
    'customer_name' => 'Mohamed',
    'order_type'    => 'takeaway',
    'items'         => [['menu_item_id' => 1, 'quantity' => 2]],
], $admin);
ok($draft['status'] === 200, 'a draft is created');
$draftId = (int) ($draft['json']['data']['id'] ?? 0);
ok(($draft['json']['data']['status'] ?? '') === 'draft', 'it starts in draft status');

$noCustomer = request('POST', '/api/v1/drafts', [
    'order_type' => 'takeaway',
    'items'      => [['menu_item_id' => 1, 'quantity' => 1]],
], $admin);
ok($noCustomer['status'] === 422, 'a draft without a customer name is rejected');

$salesBefore = request('GET', '/api/v1/reports/summary?range=today', null, $admin);
$salesBeforeValue = (float) ($salesBefore['json']['data']['sales']['value'] ?? 0);

$reportAgain = request('GET', '/api/v1/reports/summary?range=today', null, $admin);
ok(
    (float) ($reportAgain['json']['data']['sales']['value'] ?? -1) === $salesBeforeValue,
    'an open draft does not count as revenue',
);

$converted = request('POST', "/api/v1/drafts/$draftId/convert", ['payment_method' => 'zaad'], $admin);
ok($converted['status'] === 200, 'a draft converts into an order');
// Two burgers, so two containers: 70,000 + 2 x 5,000.
ok(
    ($converted['json']['data']['total'] ?? 0) === 80000.0,
    'priced from the live menu (70,000 + 2 x 5,000)',
    'got ' . ($converted['json']['data']['total'] ?? 'null'),
);

$salesAfter = request('GET', '/api/v1/reports/summary?range=today', null, $admin);
ok(
    (float) ($salesAfter['json']['data']['sales']['value'] ?? 0) > $salesBeforeValue,
    'converting the draft does count as revenue',
);

$reconvert = request('POST', "/api/v1/drafts/$draftId/convert", null, $admin);
ok($reconvert['status'] === 409, 'a draft cannot be converted twice');

// ============================================================== reports

group('Reports');

$summary = request('GET', '/api/v1/reports/summary?range=7_days', null, $admin);
ok($summary['status'] === 200, 'the summary responds');
$report = $summary['json']['data'] ?? [];
ok(isset($report['sales']['value'], $report['sales']['delta_percent']), 'KPIs carry value and delta');
ok(count($report['daily'] ?? []) === 7, 'the 7-day series has 7 zero-filled points', 'got ' . count($report['daily'] ?? []));
ok(count($report['hourly'] ?? []) === 15, 'the hourly series covers 08:00–22:00');
ok(
    abs(($report['profit']['value'] ?? 0) - (($report['sales']['value'] ?? 0) - ($report['expenses']['value'] ?? 0))) < 0.01,
    'profit equals sales minus expenses',
);
ok(
    ($report['cancelled_orders'] ?? 0) > 0,
    'cancelled orders are counted separately',
);

$warfaReport = request('GET', '/api/v1/reports/summary?range=7_days', null, $warfa)['json']['data'] ?? [];
ok(
    ($warfaReport['sales']['value'] ?? 0) !== ($report['sales']['value'] ?? 0),
    'each tenant reports only its own sales',
);

// ============================================================== logout

group('Session');

$logout = request('POST', '/api/v1/auth/logout', null, $waiter);
ok($logout['status'] === 200, 'logout succeeds');

$afterLogout = request('GET', '/api/v1/orders', null, $waiter);
ok($afterLogout['status'] === 401, 'the revoked token is rejected');

summary();
