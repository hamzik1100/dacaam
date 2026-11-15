<?php

declare(strict_types=1);

/**
 * Email alerts, end to end.
 *
 * The thing that has to be proved is not that a mail function exists — it is
 * that cancelling a paid order puts a message in the outbox addressed to the
 * owner, that two hundred routine edits do NOT, and that a failure to send
 * leaves evidence rather than vanishing.
 */

require __DIR__ . '/harness.php';
require dirname(__DIR__) . '/bootstrap.php';

use Dacaam\Core\Database;

function outbox(string $key = ''): array
{
    $sql = 'SELECT * FROM email_outbox';
    $args = [];
    if ($key !== '') {
        $sql .= ' WHERE event_key = :k';
        $args = ['k' => $key];
    }

    return Database::select($sql . ' ORDER BY id DESC', $args);
}

$rid = (int) Database::scalar('SELECT id FROM restaurants WHERE slug = "HAMZE"');
$admin = token(login('HAMZE', '0634567890', 'admin123'));
// A till has to be open before anything can be sold. That is the rule the
// shift feature exists to enforce, so the suite opens one exactly as the
// restaurant does at the start of service.
ensureShift($admin);


// The owner needs an address, or there is nobody to alert.
Database::run(
    'UPDATE users u JOIN user_roles ur ON ur.user_id = u.id JOIN roles r ON r.id = ur.role_id
        SET u.email = "owner@hamze.test"
      WHERE u.restaurant_id = ? AND r.code = "admin"',
    [$rid],
);

Database::run('DELETE FROM email_outbox WHERE restaurant_id = ?', [$rid]);

echo "\nLIISKA DHACDOOYINKA\n";

// Two of these were wrong when the feature was written — `customer_adjusted`
// for what the code calls `customer_adjustment`, and `account_transfer` for
// `transfer` — and both were money events. A key that matches nothing fails
// silently and for ever: no error, no email, no way to notice except by an
// owner not being told about the one thing they most needed to know.
$reflection = new ReflectionClass(Dacaam\Support\Alerts::class);
$groups = $reflection->getConstant('GROUPS');
$labels = $reflection->getConstant('LABELS');

ok($groups !== false && $groups !== [], 'liiska dhacdooyinka waa la akhrin karaa');

$source = '';
foreach (new RecursiveIteratorIterator(
    new RecursiveDirectoryIterator(dirname(__DIR__) . '/src'),
) as $file) {
    if ($file->isFile() && $file->getExtension() === 'php') {
        $source .= file_get_contents($file->getPathname());
    }
}

// Three of them are assembled at runtime as 'customer_' . $kind, so they are
// checked against the ledger kinds instead of against a literal action name.
// This exemption covers exactly those three: letting it cover every
// `customers.*` key is what made an earlier version of this check pass on the
// very typo it was written to catch.
$runtime = [
    'customers.customer_payment'    => 'payment',
    'customers.customer_deposit'    => 'deposit',
    'customers.customer_adjustment' => 'adjustment',
];

$missing = [];

foreach (array_keys($groups) as $key) {
    if (isset($runtime[$key])) {
        if (!str_contains($source, "kind: '" . $runtime[$key] . "'")) {
            $missing[] = $key . ' (kind)';
        }

        continue;
    }

    [, $action] = explode('.', $key, 2);

    // The action name has to appear somewhere in the code that writes audit
    // rows, or nothing will ever match it.
    if (!str_contains($source, "'" . $action . "'")) {
        $missing[] = $key;
    }
}

ok($missing === [], 'dhacdo kasta waa mid code-ku dhab ahaan qoro', implode(', ', $missing));

// Every alerted event needs a Somali label, or the owner gets a raw key.
$unlabelled = [];
foreach ($groups as $key => $group) {
    if (in_array($group, ['money', 'security'], true) && !isset($labels[$key])) {
        $unlabelled[] = $key;
    }
}

ok($unlabelled === [], 'mid kasta oo deg-deg ah magac buu leeyahay', implode(', ', $unlabelled));

echo "\nHABAYNTA\n";

$settings = Database::selectOne(
    'SELECT alerts_money, alerts_security, alerts_orders, alerts_menu
       FROM restaurant_settings WHERE restaurant_id = ?',
    [$rid],
);

ok($settings['alerts_money'] === 'instant', 'lacagta: deg-deg', (string) $settings['alerts_money']);
ok($settings['alerts_security'] === 'instant', 'amniga: deg-deg', (string) $settings['alerts_security']);
ok($settings['alerts_orders'] === 'digest', 'dalabyada: warbixin', (string) $settings['alerts_orders']);

echo "\nDALAB LA JOOJIYAY — WAA INUU EMAIL NOQDAA\n";

$table = request('GET', '/api/v1/tables', null, $admin)['json']['data'][0] ?? null;

$order = request('POST', '/api/v1/orders', [
    'order_type' => 'takeaway',
    'items'      => [['menu_item_id' => 1, 'quantity' => 2]],
], $admin)['json']['data'];

request('POST', '/api/v1/orders/' . $order['id'] . '/payments', [
    'method' => 'cash', 'amount' => $order['total'],
], $admin);

$before = count(outbox());

request('PATCH', '/api/v1/orders/' . $order['id'] . '/status', [
    'status' => 'cancelled',
    'reason'  => 'Macmiilku wuu noqday',
], $admin);

$queued = outbox('orders.order_status_changed');
ok(count($queued) > $before || $queued !== [], 'joojinta email ayay noqotay', count($queued) . ' fariin');

$message = $queued[0] ?? [];
ok(($message['to_email'] ?? '') === 'owner@hamze.test', 'waxay u socotaa milkiilaha', (string) ($message['to_email'] ?? '-'));
ok(str_contains((string) ($message['subject'] ?? ''), 'DEG-DEG'), 'cinwaanku wuu calaamadaysan yahay');
ok(str_contains((string) ($message['body'] ?? ''), 'Macmiilku wuu noqday'), 'sababtu way ku jirtaa');
ok(str_contains((string) ($message['body'] ?? ''), 'HAMZE'), 'makhaayadda waa la magacaabay');

echo "\nWAX LA BEDDELAY — WAA IN AANAY EMAIL NOQON\n";

$noisy = request('POST', '/api/v1/orders', [
    'order_type' => 'takeaway',
    'items'      => [['menu_item_id' => 1, 'quantity' => 1]],
], $admin)['json']['data'];

$countBefore = count(outbox());

// Ten edits, the sort a busy counter does all day.
for ($i = 2; $i <= 11; $i++) {
    request('PUT', '/api/v1/orders/' . $noisy['id'] . '/items', [
        'items'  => [['menu_item_id' => 1, 'quantity' => $i]],
        'reason' => 'Macmiilku wuu kordhiyay',
    ], $admin);
}

$countAfter = count(outbox());
ok(
    $countAfter === $countBefore,
    'toban beddel = eber email',
    "$countBefore -> $countAfter",
);

// But they are still on the record, ready for the daily summary.
$audited = (int) Database::scalar(
    'SELECT COUNT(*) FROM audit_logs
      WHERE restaurant_id = ? AND action = "quantity_changed" AND DATE(created_at) = CURDATE()',
    [$rid],
);
ok($audited >= 10, 'laakiin audit-ka way ku jiraan', "$audited saf");

echo "\nAMNIGA\n";

$before = count(outbox());
request('POST', '/api/v1/users', [
    'name' => 'Cusub Shaqaale', 'phone' => '0611' . substr((string) time(), -6),
    'password' => 'newpass1', 'role_code' => 'waiter',
], $admin);

ok(count(outbox('users.user_created')) > 0, 'shaqaale cusub waa email');

echo "\nXISAAB GACAN LAGU BEDDELAY — TAN AYAA UGU KHATARSAN\n";

// Money invented or erased with no order behind it. If one alert has to work,
// it is this one.
$customer = request('POST', '/api/v1/customers', [
    'name' => 'Cabdi Deyn', 'phone' => '0615' . substr((string) time(), -6),
    'credit_limit' => 100000,
], $admin)['json']['data'] ?? [];

ok(($customer['id'] ?? 0) > 0, 'macmiil la abuuray', json_encode($customer));

$before = count(outbox('customers.customer_adjustment'));

$adjusted = request('POST', '/api/v1/customers/' . $customer['id'] . '/adjust', [
    'amount' => -50000,
    'reason' => 'Wax la iska dhaafay',
], $admin);

$queued = outbox('customers.customer_adjustment');
ok(
    count($queued) > $before,
    'beddelka gacanta email ayuu noqday',
    'status ' . $adjusted['status'] . ', ' . count($queued) . ' fariin',
);

if ($queued !== []) {
    ok(str_contains((string) $queued[0]['subject'], 'DEG-DEG'), 'oo waa deg-deg');
    ok(str_contains((string) $queued[0]['body'], 'Wax la iska dhaafay'), 'sababtu way ku jirtaa');
}

echo "\nXADKA DAYNTA LA KORDHIYAY\n";

$before = count(outbox('customers.customer_updated'));

request('PUT', '/api/v1/customers/' . $customer['id'], [
    'name' => 'Cabdi Deyn',
    'credit_limit' => 900000,
], $admin);

ok(
    count(outbox('customers.customer_updated')) > $before,
    'kordhinta xadka daynta email ayay noqotay',
);

echo "\nWARBIXIN MAALMEED\n";

Database::run('UPDATE restaurant_settings SET alerts_last_digest = NULL WHERE restaurant_id = ?', [$rid]);
Database::run('DELETE FROM email_outbox WHERE event_key = "digest.daily"');

exec(sprintf(
    '%s %s %s 2>&1',
    escapeshellarg(PHP_BINARY),
    escapeshellarg(dirname(__DIR__) . '/bin/send_digest.php'),
    escapeshellarg(date('Y-m-d')),
), $out);

$digest = outbox('digest.daily');
ok($digest !== [], 'warbixin la diyaariyay', implode(' | ', $out));

if ($digest !== []) {
    $body = (string) $digest[0]['body'];
    ok(str_contains($body, 'Tirada la beddelay'), 'tobankii beddel way ku jiraan');
    ok(preg_match('/Tirada la beddelay\s+(\d+)/', $body, $m) === 1 && (int) $m[1] >= 10,
        'oo la tiriyay', $m[1] ?? '-');
    ok(!str_contains($body, 'Dalab la joojiyay'), 'joojintu kuma jirto — horeba way u dhacday');
}

// Second run must not send a second copy.
$firstCount = count(outbox('digest.daily'));
exec(sprintf(
    '%s %s %s 2>&1',
    escapeshellarg(PHP_BINARY),
    escapeshellarg(dirname(__DIR__) . '/bin/send_digest.php'),
    escapeshellarg(date('Y-m-d')),
));
ok(count(outbox('digest.daily')) === $firstCount, 'mar labaad lama celin');

echo "\nDIIDMADA SMTP\n";

// Point the mailer at a port nothing is listening on and confirm the failure
// is recorded rather than swallowed. isConfigured() wants a from-address as
// well as a host, so both go in — otherwise the drain declines to run at all
// and the test proves nothing.
foreach ([
    'smtp_host'       => '127.0.0.1',
    'smtp_port'       => '1',
    'smtp_from_email' => 'no-reply@hamze.test',
    'smtp_from_name'  => 'DACAAM',
] as $key => $value) {
    Database::run(
        'INSERT INTO system_settings (`key_name`, `value`) VALUES (:k, :v)
         ON DUPLICATE KEY UPDATE `value` = :v2',
        ['k' => $key, 'v' => $value, 'v2' => $value],
    );
}

exec(escapeshellarg(PHP_BINARY) . ' ' . escapeshellarg(dirname(__DIR__) . '/bin/send_outbox.php') . ' 1 2>&1', $drainOut);

$stuck = Database::selectOne(
    'SELECT attempts, last_error, sent_at FROM email_outbox
      WHERE sent_at IS NULL ORDER BY id ASC LIMIT 1',
);

ok($stuck !== null, 'fariintu wali way taagan tahay');
ok((int) ($stuck['attempts'] ?? 0) > 0, 'isku day waa la tiriyay', (string) ($stuck['attempts'] ?? 0));
ok(($stuck['last_error'] ?? '') !== '', 'khaladku waa la kaydiyay', substr((string) ($stuck['last_error'] ?? '-'), 0, 60));

summary();
