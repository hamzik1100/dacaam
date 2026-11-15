<?php

declare(strict_types=1);

/**
 * Plans, the app version check, archiving and renewal reminders — the parts of
 * the platform features that the restaurant's own API has to enforce.
 *
 *   php backend/tests/plans_test.php http://127.0.0.1:8090
 *
 * Needs upgrade_platform_billing.php applied (test_server.sh does it) and a
 * freshly seeded database: it moves limits, end dates and statuses around and
 * puts them back, but a run that dies halfway leaves them moved.
 */

require __DIR__ . '/harness.php';
require dirname(__DIR__) . '/bootstrap.php';

use Dacaam\Core\Database;
use Dacaam\Support\AppVersion;
use Dacaam\Support\RenewalReminders;

$hamze = (int) Database::scalar('SELECT id FROM restaurants WHERE slug = "HAMZE"');
$warfa = (int) Database::scalar('SELECT id FROM restaurants WHERE slug = "WARFA"');
$admin = token(login('HAMZE', '0634567890', 'admin123'));
$stamp = substr((string) time(), -5);

$planOf = static fn (int $rid): string => (string) Database::scalar(
    'SELECT plan FROM subscriptions WHERE restaurant_id = ?',
    [$rid],
);
$setLimits = static function (string $code, int $users, int $tables): void {
    Database::run(
        'UPDATE plans SET max_users = ?, max_tables = ? WHERE code = ?',
        [$users, $tables, $code],
    );
};
$active = static fn (string $table, int $rid): int => (int) Database::scalar(
    "SELECT COUNT(*) FROM `$table` WHERE restaurant_id = ? AND is_active = 1",
    [$rid],
);

// ---------------------------------------------------------------- upgrade

group('The upgrade');

ok(
    (int) Database::scalar('SELECT COUNT(*) FROM plans WHERE code IN ("trial", "standard")') === 2,
    'Every plan already in use became a real plan',
);
ok(
    (int) Database::scalar('SELECT COUNT(*) FROM plans WHERE max_users <> 0 OR max_tables <> 0') === 0,
    'And none of them limits anybody until someone says so',
);
ok(
    (int) Database::scalar('SELECT COUNT(*) FROM super_admins WHERE role <> "owner"') === 0,
    'Existing administrators kept everything — they are owners',
);

// ------------------------------------------------------------ app version

group('App version');

$version = request('GET', '/api/v1/app/version');
ok($version['status'] === 200, 'The version endpoint answers without signing in', (string) $version['status']);
ok(
    array_keys($version['json']['data'] ?? []) === ['min_version', 'latest_version', 'download_url', 'message'],
    'With exactly the four fields the app reads',
);
ok(($version['json']['data']['min_version'] ?? 'x') === '', 'And asks for nothing until it is configured');

Database::run(
    'INSERT INTO system_settings (key_name, value) VALUES
       ("app_min_version", "1.1.0"), ("app_latest_version", "1.2.0"),
       ("app_download_url", "https://example.test/DACAAM.apk")
     ON DUPLICATE KEY UPDATE value = VALUES(value)',
);

$configured = request('GET', '/api/v1/app/version')['json']['data'] ?? [];
ok(($configured['min_version'] ?? '') === '1.1.0', 'A minimum set in the dashboard reaches the app');
ok(($configured['download_url'] ?? '') === 'https://example.test/DACAAM.apk', 'And so does where to get it');

Database::run('DELETE FROM system_settings WHERE key_name LIKE "app\_%"');

ok(AppVersion::compare('1.10.0', '1.9.0') > 0, '1.10.0 is newer than 1.9.0 — numbers, not text');
ok(AppVersion::compare('1.1', '1.1.0') === 0, '1.1 and 1.1.0 are the same version');
ok(AppVersion::compare('1.0.0', '1.0.1') < 0, '1.0.0 is older than 1.0.1');
ok(AppVersion::isValid('1.2.0') && !AppVersion::isValid('1.2.0-beta') && !AppVersion::isValid(''), 'Only dotted numbers are versions');

// --------------------------------------------------------------- tables

group('Plan limits: tables');

$plan = $planOf($hamze);
$tablesInUse = $active('tables', $hamze);

$setLimits($plan, 0, $tablesInUse);

$refused = request('POST', '/api/v1/tables', [
    'table_number' => (int) ('9' . substr($stamp, -3)),
    'capacity'     => 4,
], $admin);
ok($refused['status'] === 422, 'A table past the plan is refused', (string) $refused['status']);
ok(($refused['json']['error']['code'] ?? '') === 'plan_limit', 'With a code the app can recognise');
ok(
    str_contains((string) ($refused['json']['error']['message'] ?? ''), 'allows ' . $tablesInUse),
    'And a message that says what the limit is',
    (string) ($refused['json']['error']['message'] ?? ''),
);
ok($active('tables', $hamze) === $tablesInUse, 'Nothing was created');

// Switching one off makes room, and the room can be used.
$someTable = (int) Database::scalar(
    'SELECT id FROM `tables` WHERE restaurant_id = ? AND is_active = 1 AND status = "available" ORDER BY id DESC LIMIT 1',
    [$hamze],
);
$off = request('PUT', '/api/v1/tables/' . $someTable, ['is_active' => false], $admin);
ok($off['status'] === 200, 'Switching a table off is always allowed', (string) $off['status']);

$back = request('PUT', '/api/v1/tables/' . $someTable, ['is_active' => true], $admin);
ok($back['status'] === 200, 'And it can come back while there is room', (string) $back['status']);

$again = request('PUT', '/api/v1/tables/' . $someTable, ['is_active' => true], $admin);
ok($again['status'] === 200, 'Saving an already-active table does not count it twice', (string) $again['status']);

$setLimits($plan, 0, 0);

$made = request('POST', '/api/v1/tables', [
    'table_number' => (int) ('9' . substr($stamp, -3)),
    'capacity'     => 4,
], $admin);
ok($made['status'] === 200 || $made['status'] === 201, 'With no limit the same table is created', (string) $made['status']);

// ---------------------------------------------------------------- staff

group('Plan limits: staff');

$usersInUse = $active('users', $hamze);
$setLimits($plan, $usersInUse, 0);

$hire = request('POST', '/api/v1/users', [
    'name'      => 'Plan Test ' . $stamp,
    'phone'     => '0638' . $stamp . '1',
    'password'  => 'Admin-12345',
    'role_code' => 'waiter',
], $admin);
ok($hire['status'] === 422, 'Staff past the plan are refused', (string) $hire['status']);
ok(($hire['json']['error']['code'] ?? '') === 'plan_limit', 'For the plan, not for anything they typed');

$inactiveHire = request('POST', '/api/v1/users', [
    'name'      => 'Plan Test Off ' . $stamp,
    'phone'     => '0638' . $stamp . '2',
    'password'  => 'Admin-12345',
    'role_code' => 'waiter',
    'is_active' => false,
], $admin);
ok(
    $inactiveHire['status'] === 200 || $inactiveHire['status'] === 201,
    'An inactive account takes no place, so it can still be created',
    (string) $inactiveHire['status'] . ' ' . json_encode($inactiveHire['json']['error'] ?? null),
);

$offId = (int) ($inactiveHire['json']['data']['id'] ?? 0);
$wake = request('PUT', '/api/v1/users/' . $offId, ['is_active' => true], $admin);
ok($wake['status'] === 422, 'But switching it on at the limit is refused', (string) $wake['status']);

// Lowering a plan never switches anyone off after the fact.
$setLimits($plan, 1, 0);
ok($active('users', $hamze) === $usersInUse, 'A smaller plan leaves existing staff exactly as they were');

$me = request('GET', '/api/v1/auth/me', null, $admin);
ok($me['status'] === 200, 'And they keep working', (string) $me['status']);

$setLimits($plan, 0, 0);

$wakeNow = request('PUT', '/api/v1/users/' . $offId, ['is_active' => true], $admin);
ok($wakeNow['status'] === 200, 'With the limit lifted, the account switches on', (string) $wakeNow['status']);

// -------------------------------------------------------------- archive

group('Archived restaurants');

$warfaToken = token(login('WARFA', '0637778899', 'admin123'));
ok($warfaToken !== '', 'WARFA can sign in before');

Database::run('UPDATE restaurants SET status = "archived" WHERE id = ?', [$warfa]);

$locked = request('GET', '/api/v1/auth/me', null, $warfaToken);
ok($locked['status'] === 403, 'An archived restaurant is locked out', (string) $locked['status']);

$hamzeStill = request('GET', '/api/v1/auth/me', null, $admin);
ok($hamzeStill['status'] === 200, 'And no other restaurant is touched');

Database::run('UPDATE restaurants SET status = "active" WHERE id = ?', [$warfa]);

$unlocked = request('GET', '/api/v1/auth/me', null, $warfaToken);
ok($unlocked['status'] === 200, 'Restoring it lets the same session back in', (string) $unlocked['status']);

// ------------------------------------------------------------ reminders

group('Renewal reminder stages');

ok(RenewalReminders::stageFor(30) === null, 'A month out, nothing is sent');
ok(RenewalReminders::stageFor(7) === 7, 'Seven days out, the first reminder');
ok(RenewalReminders::stageFor(3) === 7, 'Three days out it is still the first one — never sent twice');
ok(RenewalReminders::stageFor(1) === 1, 'The day before, the second');
ok(RenewalReminders::stageFor(0) === 1, 'On the day itself, still the second');
ok(RenewalReminders::stageFor(-1) === RenewalReminders::ENDED, 'The day after, the "it has ended" notice');
ok(RenewalReminders::stageFor(-30) === null, 'Long-lapsed restaurants are not suddenly messaged');

group('Renewal reminders');

$originalEnd = (string) Database::scalar('SELECT ends_on FROM subscriptions WHERE restaurant_id = ?', [$hamze]);
$subId = (int) Database::scalar('SELECT id FROM subscriptions WHERE restaurant_id = ?', [$hamze]);

Database::run(
    'UPDATE subscriptions SET ends_on = DATE_ADD(CURDATE(), INTERVAL 5 DAY) WHERE id = ?',
    [$subId],
);
Database::run('UPDATE users SET email = ? WHERE id = (SELECT id FROM (SELECT u.id FROM users u
                 JOIN user_roles ur ON ur.user_id = u.id JOIN roles r ON r.id = ur.role_id
                WHERE u.restaurant_id = ? AND r.code = "admin" ORDER BY u.id LIMIT 1) x)',
    ['owner' . $stamp . '@dacaam.test', $hamze]);

$due = array_filter(RenewalReminders::due(), static fn (array $d): bool => (int) $d['subscription_id'] === $subId);
ok(count($due) === 1, 'A subscription ending in five days is due a reminder');
ok((int) (array_values($due)[0]['stage'] ?? 0) === 7, 'The seven-day one');

$outboxBefore = (int) Database::scalar('SELECT COUNT(*) FROM email_outbox WHERE event_key = "subscription.reminder"');
$sent = RenewalReminders::send();

ok(in_array('HAMZE (7 days)', $sent['sent'], true), 'It is sent', json_encode($sent['sent']));
ok($sent['notified'] >= 1, 'To the admins');
ok(
    (int) Database::scalar('SELECT COUNT(*) FROM email_outbox WHERE event_key = "subscription.reminder"') > $outboxBefore,
    'And an email is queued for the admin who has an address',
);

$feed = request('GET', '/api/v1/notifications', null, $admin);
$titles = array_column((array) ($feed['json']['data']['items'] ?? $feed['json']['data'] ?? []), 'title');
ok(
    count(array_filter($titles, static fn ($t): bool => str_contains((string) $t, 'Ishtiraak'))) >= 1,
    'The admin sees it in the app',
    json_encode(array_slice($titles, 0, 3), JSON_UNESCAPED_UNICODE),
);

$waiter = token(login('HAMZE', '0632233445', 'admin123'));
$waiterFeed = request('GET', '/api/v1/notifications', null, $waiter);
$waiterTitles = array_column((array) ($waiterFeed['json']['data']['items'] ?? $waiterFeed['json']['data'] ?? []), 'title');
ok(
    count(array_filter($waiterTitles, static fn ($t): bool => str_contains((string) $t, 'Ishtiraak'))) === 0,
    'The waiters do not — they cannot pay the bill',
);

$second = RenewalReminders::send();
ok(!in_array('HAMZE (7 days)', $second['sent'], true), 'Running it again sends nothing twice');

// Renewing moves the end date, so the next term earns its own reminders.
Database::run(
    'UPDATE subscriptions SET ends_on = DATE_ADD(CURDATE(), INTERVAL 1 DAY) WHERE id = ?',
    [$subId],
);
$dayBefore = RenewalReminders::send();
ok(in_array('HAMZE (1 day)', $dayBefore['sent'], true), 'The day before, the second reminder goes');

// Suspended and archived restaurants are left alone.
$warfaEnd = (string) Database::scalar('SELECT ends_on FROM subscriptions WHERE restaurant_id = ?', [$warfa]);
Database::run('UPDATE subscriptions SET ends_on = DATE_ADD(CURDATE(), INTERVAL 3 DAY) WHERE restaurant_id = ?', [$warfa]);
Database::run('UPDATE restaurants SET status = "archived" WHERE id = ?', [$warfa]);
$archivedDue = array_filter(RenewalReminders::due(), static fn (array $d): bool => (int) $d['restaurant_id'] === $warfa);
ok($archivedDue === [], 'An archived restaurant is not reminded');
Database::run('UPDATE restaurants SET status = "active" WHERE id = ?', [$warfa]);
Database::run('UPDATE subscriptions SET ends_on = ? WHERE restaurant_id = ?', [$warfaEnd, $warfa]);

Database::run('UPDATE subscriptions SET ends_on = ? WHERE id = ?', [$originalEnd, $subId]);

summary();
