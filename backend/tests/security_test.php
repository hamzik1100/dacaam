<?php

declare(strict_types=1);

/**
 * Phase 10 hardening checks.
 *
 * Rate limiting, subscription enforcement at the API boundary, and the headers
 * every response is supposed to carry.
 *
 *   php bin/migrate.php --fresh --seed
 *   php tests/security_test.php http://127.0.0.1:8090
 *
 * Needs a fresh seed: it expires a tenant's subscription and fills throttle
 * buckets, neither of which it can put back.
 */

require __DIR__ . '/harness.php';

/**
 * Like request(), but returns the response headers too.
 *
 * @param  array<string,mixed>|null $body
 * @return array{status:int,json:array<string,mixed>,headers:array<string,string>}
 */
function headed(string $method, string $path, ?array $body = null, ?string $token = null): array
{
    $ch = curl_init($GLOBALS['t_base'] . $path);
    $headers = ['Accept: application/json', 'X-Device: security-test'];

    if ($body !== null) {
        $headers[] = 'Content-Type: application/json';
        curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($body, JSON_UNESCAPED_UNICODE));
    }
    if ($token !== null) {
        $headers[] = 'Authorization: Bearer ' . $token;
    }

    curl_setopt_array($ch, [
        CURLOPT_CUSTOMREQUEST  => $method,
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_HEADER         => true,
        CURLOPT_HTTPHEADER     => $headers,
        CURLOPT_TIMEOUT        => 20,
    ]);

    $raw = (string) curl_exec($ch);
    $status = (int) curl_getinfo($ch, CURLINFO_HTTP_CODE);
    $size = (int) curl_getinfo($ch, CURLINFO_HEADER_SIZE);
    curl_close($ch);

    $parsed = [];
    foreach (explode("\r\n", substr($raw, 0, $size)) as $line) {
        if (str_contains($line, ':')) {
            [$name, $value] = explode(':', $line, 2);
            $parsed[strtolower(trim($name))] = trim($value);
        }
    }

    $json = json_decode(substr($raw, $size), true);

    return [
        'status'  => $status,
        'json'    => is_array($json) ? $json : [],
        'headers' => $parsed,
    ];
}

/** Runs a query against the database the API is using. */
function sql(string $statement, array $bindings = []): void
{
    require_once dirname(__DIR__) . '/bootstrap.php';
    Dacaam\Core\Database::run($statement, $bindings);
}

function code(array $response): string
{
    return (string) ($response['json']['error']['code'] ?? '');
}

// ------------------------------------------------------------- headers

group('Response headers');

$health = headed('GET', '/api/v1/health');
ok($health['status'] === 200, 'Health responds');
ok(
    ($health['headers']['x-content-type-options'] ?? '') === 'nosniff',
    'nosniff is set',
    $health['headers']['x-content-type-options'] ?? '(absent)',
);
ok(
    ($health['headers']['x-frame-options'] ?? '') === 'DENY',
    'Framing is denied',
);
ok(
    str_contains($health['headers']['cache-control'] ?? '', 'no-store'),
    'Responses are not cacheable',
    $health['headers']['cache-control'] ?? '(absent)',
);
ok(
    ($health['headers']['referrer-policy'] ?? '') === 'no-referrer',
    'No referrer is leaked',
);
ok(
    !isset($health['headers']['strict-transport-security']),
    'HSTS is absent over plain HTTP, where it would be meaningless',
);

$signIn = login('HAMZE', '0634567890');
$token = token($signIn);
// A till has to be open before anything can be sold. That is the rule the
// shift feature exists to enforce, so the suite opens one exactly as the
// restaurant does at the start of service.
ensureShift($token);

ok($token !== '', 'Signed in as HAMZE admin');

$authed = headed('GET', '/api/v1/orders', token: $token);
ok(
    str_contains($authed['headers']['cache-control'] ?? '', 'no-store'),
    'Tenant data is never cached',
);

// ---------------------------------------------------------------- CORS

group('CORS');

$cors = headed('OPTIONS', '/api/v1/orders');
ok($cors['status'] === 204, 'Preflight answers 204', (string) $cors['status']);
ok(
    isset($cors['headers']['access-control-allow-methods']),
    'Preflight names the allowed methods',
);

// ------------------------------------------------------- rate limiting

group('Rate limiting');

// The login route allows 20 per five minutes per address, and a success
// clears the count — so only failures accumulate.
$limited = null;
$attempts = 0;
for ($i = 0; $i < 26; $i++) {
    $attempts++;
    $response = login('HAMZE', '0634567890', 'definitely-not-the-password');
    if ($response['status'] === 429) {
        $limited = $response;
        break;
    }
}

ok($limited !== null, 'Repeated bad passwords are eventually throttled', "gave up after $attempts");
ok(
    $limited !== null && ($limited['json']['error']['code'] ?? '') === 'rate_limited',
    'The refusal says why',
);
ok($attempts > 20, 'The limit is not tripped by a handful of typos', "tripped at $attempts");

// A correct password must still be refused while the window is open —
// otherwise the throttle is trivially bypassed by guessing a real one.
$blocked = login('HAMZE', '0634567890');
ok($blocked['status'] === 429, 'The block applies to correct credentials too');

// Other endpoints keep their own budget.
$forgot = request('POST', '/api/v1/auth/password/forgot', [
    'restaurant_code' => 'HAMZE',
    'phone'           => '0634567890',
]);
ok($forgot['status'] !== 429, 'Password reset has its own budget, not the login one');

// Twenty-six wrong passwords trip two independent guards: the per-address
// throttle above, and the per-account lockout that has existed since Phase 3.
// Both have to be released to carry on.
sql('DELETE FROM rate_limits');
sql('UPDATE users SET failed_logins = 0, locked_until = NULL WHERE restaurant_id = 1');

$recovered = login('HAMZE', '0634567890');
ok($recovered['status'] === 200, 'Signing in works again once the window clears', (string) $recovered['status']);
$token = token($recovered);

// A successful sign-in should leave nothing behind to count against the
// restaurant tomorrow morning.
for ($i = 0; $i < 25; $i++) {
    $ok = login('HAMZE', '0634567890');
}
ok($ok['status'] === 200, 'Twenty-five successful sign-ins in a row are all allowed');

// ------------------------------------------------- subscription expiry

group('Expired subscription');

$before = request('GET', '/api/v1/orders', token: $token);
ok($before['status'] === 200, 'Reads work while the subscription is live');

$create = request('POST', '/api/v1/orders', [
    'order_type' => 'takeaway',
    'items'      => [['menu_item_id' => 1, 'quantity' => 1]],
], $token);
ok($create['status'] === 201 || $create['status'] === 200, 'Writes work while it is live', (string) $create['status']);

sql("UPDATE subscriptions SET ends_on = DATE_SUB(CURDATE(), INTERVAL 3 DAY) WHERE restaurant_id = 1");

$readAfter = request('GET', '/api/v1/orders', token: $token);
ok($readAfter['status'] === 200, 'An expired tenant can still read its own orders');

$reportAfter = request('GET', '/api/v1/reports/summary?range=today', token: $token);
ok($reportAfter['status'] === 200, 'And still run its reports');

$writeAfter = request('POST', '/api/v1/orders', [
    'order_type' => 'takeaway',
    'items'      => [['menu_item_id' => 1, 'quantity' => 1]],
], $token);
ok($writeAfter['status'] === 403, 'But cannot create an order', (string) $writeAfter['status']);
ok(
    code($writeAfter) === 'subscription_expired',
    'And the reason is distinguishable from a permission failure',
    code($writeAfter),
);

$deleteAfter = request('DELETE', '/api/v1/menu/items/1', token: $token);
ok($deleteAfter['status'] === 403, 'Deletes are blocked too');
ok(code($deleteAfter) === 'subscription_expired', 'For the same stated reason');

$logout = request('POST', '/api/v1/auth/logout', [], $token);
ok($logout['status'] === 200, 'Signing out still works when the bill is overdue');

// The neighbouring tenant is untouched by any of this.
$warfa = login('WARFA', '0637778899');
ok($warfa['status'] === 200, 'The other tenant still signs in');
// WARFA sells too, so WARFA needs its own till open. Shifts belong to a
// restaurant, not to the platform.
ensureShift(token($warfa));

$warfaWrite = request('POST', '/api/v1/orders', [
    'order_type' => 'takeaway',
    'items'      => [['menu_item_id' => 30, 'quantity' => 1]],
], token($warfa));
ok(
    $warfaWrite['status'] === 201 || $warfaWrite['status'] === 200,
    'And still writes — one tenant lapsing does not touch another',
    (string) $warfaWrite['status'],
);

sql("UPDATE subscriptions SET ends_on = DATE_ADD(CURDATE(), INTERVAL 1 YEAR) WHERE restaurant_id = 1");

$restored = login('HAMZE', '0634567890');
$restoredWrite = request('POST', '/api/v1/orders', [
    'order_type' => 'takeaway',
    'items'      => [['menu_item_id' => 1, 'quantity' => 1]],
], token($restored));
ok(
    $restoredWrite['status'] === 201 || $restoredWrite['status'] === 200,
    'Renewing restores writing, with nothing lost in between',
);

// ---------------------------------------------------------- suspension

group('Suspension');

sql("UPDATE restaurants SET status = 'suspended' WHERE id = 1");

$suspendedRead = request('GET', '/api/v1/orders', token: token($restored));
ok($suspendedRead['status'] === 403, 'A suspended tenant is refused outright, reads included');

sql("UPDATE restaurants SET status = 'active' WHERE id = 1");

$unsuspended = request('GET', '/api/v1/orders', token: token($restored));
ok($unsuspended['status'] === 200, 'Un-suspending restores access with the same token');

// ---------------------------------------------------------- debug leak

group('Error detail');

$notFound = request('GET', '/api/v1/orders/999999', token: token($restored));
ok($notFound['status'] === 404, 'A missing order is a 404');

// Derive the root rather than naming a drive: hard-coding one means the check
// passes for free the moment the project is moved, hiding a real leak. A path
// can surface with either separator, so both spellings count as a leak.
$projectRoot = dirname(__DIR__, 2);
$haystack    = json_encode($notFound['json']);
$leaked      = false;
foreach ([$projectRoot, str_replace('\\', '/', $projectRoot)] as $spelling) {
    if (str_contains($haystack, trim(json_encode($spelling), '"'))) {
        $leaked = true;
    }
}
ok(
    !$leaked && !str_contains($haystack, '/backend/src/'),
    'No filesystem path is echoed back on a handled error',
);

summary();
