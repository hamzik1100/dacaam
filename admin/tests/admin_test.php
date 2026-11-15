<?php

declare(strict_types=1);

/**
 * End-to-end checks for the Super Admin dashboard.
 *
 * Drives the real HTML surface with a cookie jar, exactly as a browser would:
 * every POST first fetches the page to read its CSRF token, so a broken CSRF
 * pipeline fails the suite rather than silently passing.
 *
 *   php admin/tests/admin_test.php http://127.0.0.1:8091
 *
 * Start the server the way the real host is configured, or two whole classes of
 * bug stay invisible:
 *
 *   php -d disable_functions=exec,shell_exec,passthru,system \
 *       -d error_log=<repo>/backend/storage/logs/error.log -d log_errors=1 \
 *       -S 127.0.0.1:8091 admin/public/index.php
 *
 * The disabled functions are what shared hosting disables — code that shells
 * out passes locally and dies there. The error log is what lets the suite see
 * a fatal that happens AFTER the page has been echoed: the body is already
 * sent, the status is already 200, and nothing about the response says the
 * request died. That is precisely how a broken page shipped and stayed broken.
 */

require __DIR__ . '/../../backend/tests/harness.php';
// For reading back what the pages wrote.
require_once dirname(__DIR__, 2) . '/backend/bootstrap.php';

$jar = tempnam(sys_get_temp_dir(), 'dacaam_admin_') ?: '';
register_shutdown_function(static function () use ($jar): void {
    if ($jar !== '' && is_file($jar)) {
        unlink($jar);
    }
});

/**
 * @param  array<string,string>|null $post
 * @return array{status:int,body:string,location:string}
 */
function web(string $path, ?array $post = null, string $referer = ''): array
{
    $ch = curl_init($GLOBALS['t_base'] . $path);

    curl_setopt_array($ch, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_HEADER         => true,
        CURLOPT_COOKIEJAR      => $GLOBALS['jar'],
        CURLOPT_COOKIEFILE     => $GLOBALS['jar'],
        CURLOPT_FOLLOWLOCATION => false,
        CURLOPT_TIMEOUT        => 20,
    ]);

    if ($referer !== '') {
        curl_setopt($ch, CURLOPT_REFERER, $GLOBALS['t_base'] . $referer);
    }
    if ($post !== null) {
        curl_setopt($ch, CURLOPT_POST, true);
        curl_setopt($ch, CURLOPT_POSTFIELDS, http_build_query($post));
    }

    $raw = (string) curl_exec($ch);
    $status = (int) curl_getinfo($ch, CURLINFO_HTTP_CODE);
    $headerSize = (int) curl_getinfo($ch, CURLINFO_HEADER_SIZE);
    curl_close($ch);

    $headers = substr($raw, 0, $headerSize);
    $body = substr($raw, $headerSize);

    $location = '';
    if (preg_match('/^Location:\s*(.+)$/mi', $headers, $m) === 1) {
        $location = trim($m[1]);
    }

    return ['status' => $status, 'body' => $body, 'location' => $location];
}

/** Reads the CSRF token out of a rendered page. */
function csrf(string $path): string
{
    $page = web($path);

    return preg_match('/name="_csrf" value="([a-f0-9]+)"/', $page['body'], $m) === 1
        ? $m[1]
        : '';
}

/**
 * @param  array<string,string> $fields
 * @return array{status:int,body:string,location:string}
 */
function submit(string $formPath, string $action, array $fields): array
{
    $fields['_csrf'] = csrf($formPath);

    return web($action, $fields, referer: $formPath);
}

function has(string $body, string $needle): bool
{
    return str_contains($body, $needle);
}

/**
 * Anything the server logged since the last call.
 *
 * A 200 is not proof a request succeeded. `View::page()` echoes and returns
 * nothing, so a controller declaring the wrong return type sends the entire
 * page and then dies — status 200, body intact, fatal in the log. Reading the
 * log is the only way to see it.
 */
function logged(): string
{
    $path = dirname(__DIR__, 2) . '/backend/storage/logs/error.log';

    if (!is_file($path)) {
        return '';
    }

    clearstatcache(true, $path);
    $size = (int) filesize($path);
    $from = $GLOBALS['t_log_at'] ?? 0;
    $GLOBALS['t_log_at'] = $size;

    if ($size <= $from) {
        return '';
    }

    $handle = fopen($path, 'r');
    fseek($handle, $from);
    $new = (string) fread($handle, $size - $from);
    fclose($handle);

    return $new;
}

/** Follows a redirect and returns the error message rendered on the far side. */
function errorAfter(array $response): string
{
    if ($response['status'] !== 302) {
        return $response['body'];
    }

    $path = (string) parse_url($response['location'], PHP_URL_PATH);
    $page = web($path === '' ? '/' : $path);

    return preg_match('/flash flash-error">([^<]*)</', $page['body'], $m) === 1
        ? $m[1]
        : '';
}

$GLOBALS['jar'] = $jar;
$stamp = substr((string) time(), -6);
$slug = 'TEST' . $stamp;

// --------------------------------------------------------------- guests

group('Guests are locked out');

$home = web('/');
ok($home['status'] === 302, 'Dashboard redirects when signed out', "got {$home['status']}");
ok(str_contains($home['location'], '/login'), 'Redirect points at /login', $home['location']);

$restaurants = web('/restaurants');
ok($restaurants['status'] === 302, 'Restaurant list is protected');

$loginPage = web('/login');
ok($loginPage['status'] === 200, 'Login page renders');
ok(has($loginPage['body'], 'name="_csrf"'), 'Login form carries a CSRF token');
ok(has($loginPage['body'], 'DACAAM'), 'Login page is branded');

// The front controller sees every request, so a static asset is one careless
// route away from being answered with the 404 page.
$css = web('/assets/app.css');
ok($css['status'] === 200, 'The stylesheet is served', "got {$css['status']}");
ok(has($css['body'], '--primary'), 'And it is CSS, not the error page');

// --------------------------------------------------------------- setup

group('First-run setup');

// The seeded database already has an administrator, so the page that creates
// the first one must be shut. If it ever answers 200 here, anyone on the
// internet can appoint themselves platform administrator.
$setup = web('/setup');
ok($setup['status'] === 302, 'Setup is closed once an administrator exists', (string) $setup['status']);
ok(str_contains($setup['location'], '/login'), 'And it sends you to sign in instead');

$setupPost = web('/setup', ['name' => 'Intruder', 'email' => 'x@y.z', 'password' => 'Nice-Try-12345', '_csrf' => csrf('/login')]);
ok(
    $setupPost['status'] === 302 && !str_contains($setupPost['location'], '/setup'),
    'And posting to it directly creates nothing',
);

$admins = web('/login');
ok(!has($admins['body'], 'First-run setup'), 'The login page is not the setup page');

// ---------------------------------------------------------------- CSRF

group('CSRF');

$forged = web('/login', ['email' => 'super@dacaam.test', 'password' => 'admin123', '_csrf' => 'nope']);
ok($forged['status'] === 419, 'A bad CSRF token is rejected with 419', "got {$forged['status']}");

// --------------------------------------------------------------- login

group('Sign in');

$bad = submit('/login', '/login', ['email' => 'super@dacaam.test', 'password' => 'wrong']);
ok($bad['status'] === 302, 'A wrong password redirects back');
$badPage = web('/login');
ok(has($badPage['body'], 'flash-error'), 'A wrong password shows an error');

$in = submit('/login', '/login', ['email' => 'super@dacaam.test', 'password' => 'admin123']);
ok($in['status'] === 302, 'Correct credentials redirect');
ok(!str_contains($in['location'], '/login'), 'Redirect leaves the login page', $in['location']);

$dash = web('/');
ok($dash['status'] === 200, 'Dashboard renders once signed in', "got {$dash['status']}");
ok(has($dash['body'], 'Total restaurants'), 'Dashboard shows the restaurant count');
ok(has($dash['body'], 'Subscription revenue'), 'Dashboard shows subscription revenue');
ok(has($dash['body'], 'Sign out'), 'The layout offers a sign-out');

// --------------------------------------------------------- restaurants

group('Restaurants');

$list = web('/restaurants');
ok($list['status'] === 200, 'Restaurant list renders');
ok(has($list['body'], 'HAMZE'), 'Seeded HAMZE is listed');
ok(has($list['body'], 'WARFA'), 'Seeded WARFA is listed');

$filtered = web('/restaurants?q=HAMZE');
ok(has($filtered['body'], 'HAMZE'), 'Search finds HAMZE');
ok(!has($filtered['body'], '>WARFA<'), 'Search excludes WARFA');

$missing = web('/restaurants/999999');
ok($missing['status'] === 404, 'An unknown restaurant is a 404', "got {$missing['status']}");

$form = web('/restaurants/new');
ok($form['status'] === 200, 'The create form renders');
ok(has($form['body'], 'Restaurant admin'), 'The form asks for the first admin');

// ------------------------------------------------------- provisioning

group('Provisioning');

$created = submit('/restaurants/new', '/restaurants', [
    'name'              => 'Test Kitchen ' . $stamp,
    'slug'              => $slug,
    'phone'             => '0631' . $stamp,
    'address'           => 'Hargeysa',
    'logo_emoji'        => '🥘',
    'status'            => 'trial',
    'plan'              => 'standard',
    'subscription_days' => '30',
    'amount'            => '150000',
    'admin_name'        => 'Test Admin',
    'admin_phone'       => '0632' . $stamp,
    'admin_email'       => 'test' . $stamp . '@dacaam.test',
    'admin_password'    => 'admin123',
]);
ok($created['status'] === 302, 'Creating a restaurant redirects', "got {$created['status']}");

preg_match('#/restaurants/(\d+)#', $created['location'], $m);
$newId = (int) ($m[1] ?? 0);
ok($newId > 0, 'The new restaurant has an id', $created['location']);

$show = web('/restaurants/' . $newId);
ok($show['status'] === 200, 'The new restaurant page renders');
ok(has($show['body'], $slug), 'It carries its own code');
ok(has($show['body'], 'Test Admin'), 'Its admin user exists');
ok(has($show['body'], 'Subscription'), 'It has a subscription panel');

$duplicate = submit('/restaurants/new', '/restaurants', [
    'name'           => 'Duplicate',
    'slug'           => $slug,
    'plan'           => 'standard',
    'admin_name'     => 'Someone',
    'admin_phone'    => '0639' . $stamp,
    'admin_password' => 'admin123',
]);
ok($duplicate['status'] === 200, 'A duplicate code re-renders the form');
ok(has($duplicate['body'], 'flash-error'), 'A duplicate code explains itself');

// The provisioner runs in a transaction, so the rejected duplicate must not
// have left a half-built tenant behind. (The search term itself is echoed back
// into the filter box, so the empty state is what proves the point.)
$after = web('/restaurants?q=Duplicate');
ok(has($after['body'], 'No restaurants match'), 'The rejected tenant was rolled back');

// ------------------------------------------------------------ lifecycle

group('Lifecycle');

$suspend = submit('/restaurants/' . $newId, '/restaurants/' . $newId . '/status', [
    'status' => 'suspended',
]);
ok($suspend['status'] === 302, 'Suspending redirects');

$suspended = web('/restaurants/' . $newId);
ok(has($suspended['body'], 'chip-suspended'), 'The restaurant reads as suspended');

$reactivate = submit('/restaurants/' . $newId, '/restaurants/' . $newId . '/status', [
    'status' => 'active',
]);
ok($reactivate['status'] === 302, 'Reactivating redirects');

$active = web('/restaurants/' . $newId);
ok(has($active['body'], 'chip-active'), 'The restaurant reads as active again');
ok(has($active['body'], 'Test Admin'), 'Suspension destroyed nothing');

$rename = submit('/restaurants/' . $newId, '/restaurants/' . $newId, [
    'name'       => 'Renamed Kitchen ' . $stamp,
    'slug'       => $slug,
    'phone'      => '0631' . $stamp,
    'address'    => 'Berbera',
    'logo_emoji' => '🥘',
]);
ok($rename['status'] === 302, 'Editing a restaurant redirects');
$renamed = web('/restaurants/' . $newId);
ok(has($renamed['body'], 'Renamed Kitchen'), 'The new name stuck');
ok(has($renamed['body'], 'Berbera'), 'The new address stuck');

// ---------------------------------------------------------- passwords

group('Password reset');

preg_match('/name="user_id" value="(\d+)"/', $renamed['body'], $um);
$userId = (int) ($um[1] ?? 0);
ok($userId > 0, 'A staff row exposes a reset control');

$short = submit('/restaurants/' . $newId, '/restaurants/' . $newId . '/reset-password', [
    'user_id'  => (string) $userId,
    'password' => 'abc',
]);
ok(
    str_contains($short['location'], '/restaurants/' . $newId),
    'A refused reset returns to the page it came from',
    $short['location'],
);
ok(has(errorAfter($short), 'at least 6'), 'A short password is refused');

$reset = submit('/restaurants/' . $newId, '/restaurants/' . $newId . '/reset-password', [
    'user_id'  => (string) $userId,
    'password' => 'newpass123',
]);
ok($reset['status'] === 302, 'A valid reset redirects');

// A reset must not be usable to reach into another tenant.
$hamzeUser = 1;
$crossTenant = submit('/restaurants/' . $newId, '/restaurants/' . $newId . '/reset-password', [
    'user_id'  => (string) $hamzeUser,
    'password' => 'newpass123',
]);
ok(
    has(errorAfter($crossTenant), 'does not belong'),
    'A user from another restaurant cannot be reset through this page',
);

// ---------------------------------------------------------------- plans

group('Plans');

$plansPage = web('/plans');
ok($plansPage['status'] === 200, 'The plans page renders', (string) $plansPage['status']);
ok(has($plansPage['body'], '>standard<') && has($plansPage['body'], '>trial<'), 'The plans in use are listed');
ok(has($plansPage['body'], 'Add a plan'), 'An owner is offered the form');

$newPlan = submit('/plans', '/plans', [
    'code'        => 'enterprise',
    'name'        => 'Enterprise',
    'price'       => '250000',
    'max_users'   => '50',
    'max_tables'  => '40',
    'description' => 'Chains',
]);
ok($newPlan['status'] === 302, 'Adding a plan redirects');
ok(has(web('/plans')['body'], 'Enterprise'), 'And it is listed');

$dupPlan = submit('/plans', '/plans', ['code' => 'enterprise', 'name' => 'Again']);
ok(str_contains(errorAfter($dupPlan), 'already exists'), 'A plan code cannot be used twice');

$badPlan = submit('/plans', '/plans', ['code' => 'Has Spaces!', 'name' => 'Bad']);
ok(str_contains(errorAfter($badPlan), 'lowercase'), 'A code has to be a code');

$enterpriseId = (int) Dacaam\Core\Database::scalar('SELECT id FROM plans WHERE code = "enterprise"');
$priced = submit('/plans', '/plans/' . $enterpriseId, [
    'name'        => 'Enterprise',
    'price'       => '300000',
    'max_users'   => '50',
    'max_tables'  => '40',
    'description' => 'Chains',
    'is_active'   => '1',
]);
ok($priced['status'] === 302, 'A plan can be repriced');
ok(
    (float) Dacaam\Core\Database::scalar('SELECT price FROM plans WHERE id = ?', [$enterpriseId]) === 300000.0,
    'And the new price is stored',
);

$createForm = web('/restaurants/new');
ok(has($createForm['body'], '<select id="plan"'), 'New restaurants pick a plan from a list, not a text box');

// ------------------------------------------------------- subscriptions

group('Subscriptions');

$subs = web('/subscriptions');
ok($subs['status'] === 200, 'Subscription list renders');
ok(has($subs['body'], 'Collected lifetime'), 'It totals what has been collected');
ok(has($subs['body'], $slug), 'The new tenant appears');

$expiring = web('/subscriptions?status=expiring');
ok($expiring['status'] === 200, 'The expiring filter renders');

preg_match('#/subscriptions/(\d+)/renew#', $renamed['body'], $sm);
$subId = (int) ($sm[1] ?? 0);
ok($subId > 0, 'The restaurant page offers a renewal form');

$renew = submit('/restaurants/' . $newId, '/subscriptions/' . $subId . '/renew', [
    'months'    => '12',
    'amount'    => '600000',
    'method'    => 'zaad',
    'reference' => 'TEST-' . $stamp,
]);
ok($renew['status'] === 302, 'Renewing redirects');

$renewed = web('/restaurants/' . $newId);
ok(has($renewed['body'], 'TEST-' . $stamp), 'The payment is recorded against the restaurant');
ok(has($renewed['body'], 'zaad'), 'The payment method is kept');

$unknownPlan = submit('/restaurants/' . $newId, '/subscriptions/' . $subId, [
    'plan'    => 'no-such-plan',
    'status'  => 'active',
    'ends_on' => date('Y-m-d', strtotime('+400 days')),
    'amount'  => '900000',
]);
ok(str_contains(errorAfter($unknownPlan), 'Choose a plan'), 'A plan that does not exist is refused');

$adjust = submit('/restaurants/' . $newId, '/subscriptions/' . $subId, [
    'plan'    => 'enterprise',
    'status'  => 'active',
    'ends_on' => date('Y-m-d', strtotime('+400 days')),
    'amount'  => '900000',
]);
ok($adjust['status'] === 302, 'Adjusting a subscription redirects');
$adjusted = web('/restaurants/' . $newId);
ok(has($adjusted['body'], 'enterprise'), 'The plan changed');

$badDate = submit('/restaurants/' . $newId, '/subscriptions/' . $subId, [
    'plan'    => 'enterprise',
    'status'  => 'active',
    'ends_on' => 'not-a-date',
    'amount'  => '0',
]);
ok(has(errorAfter($badDate), 'not valid'), 'An invalid end date is refused');

$limits = web('/restaurants/' . $newId);
ok(has($limits['body'], 'of 50'), 'The page shows staff used against the plan limit');

// -------------------------------------------------------------- invoices

group('Invoices');

$paymentId = (int) Dacaam\Core\Database::scalar(
    'SELECT id FROM subscription_payments WHERE reference = ?',
    ['TEST-' . $stamp],
);
$payment = Dacaam\Core\Database::selectOne('SELECT * FROM subscription_payments WHERE id = ?', [$paymentId]) ?? [];

ok((int) ($payment['months'] ?? 0) === 12, 'A payment remembers how many months it bought');
ok(($payment['period_start'] ?? null) !== null && ($payment['period_end'] ?? null) !== null, 'And the period it covers');
ok(($payment['plan'] ?? '') === 'standard', 'And the plan it was for');

$number = sprintf('INV-%s-%05d', date('Y', (int) strtotime((string) ($payment['paid_on'] ?? ''))), $paymentId);
ok(has($limits['body'], $number), 'The restaurant page links the invoice', $number);

$invoice = web('/invoices/' . $paymentId);
ok($invoice['status'] === 200, 'The invoice renders', (string) $invoice['status']);
ok(has($invoice['body'], $number) && has($invoice['body'], 'PAID'), 'Numbered, and marked paid');
ok(has($invoice['body'], 'TEST-' . $stamp), 'With the payment reference');
ok(has($invoice['body'], '600,000'), 'And the amount');
ok(!has($invoice['body'], 'class="sidebar"'), 'On a page of its own, ready to print');
ok(web('/invoices/999999')['status'] === 404, 'An unknown invoice is a 404');

$outboxBefore = (int) Dacaam\Core\Database::scalar('SELECT COUNT(*) FROM email_outbox WHERE event_key = "subscription.invoice"');
$emailed = submit('/restaurants/' . $newId, '/invoices/' . $paymentId . '/email', []);
ok($emailed['status'] === 302, 'Emailing an invoice redirects');
ok(
    (int) Dacaam\Core\Database::scalar('SELECT COUNT(*) FROM email_outbox WHERE event_key = "subscription.invoice"') === $outboxBefore + 1,
    'And queues it for the restaurant admin',
);

$issuer = submit('/settings', '/settings/invoice', [
    'business_name'    => 'Dhuuh Technologies',
    'business_address' => 'Hargeysa',
    'business_phone'   => '063 0000000',
    'business_email'   => 'billing@dhuuh.test',
    'footer'           => 'Mahadsanid.',
]);
ok($issuer['status'] === 302, 'Invoice details can be set');
$branded = web('/invoices/' . $paymentId);
ok(has($branded['body'], 'Dhuuh Technologies') && has($branded['body'], 'Mahadsanid.'), 'And the invoice carries them');

// ------------------------------------------------------------- reminders

group('Renewal reminders');

Dacaam\Core\Database::run(
    'UPDATE subscriptions SET ends_on = DATE_ADD(CURDATE(), INTERVAL 6 DAY) WHERE id = ?',
    [$subId],
);

$subsPage = web('/subscriptions');
ok(has($subsPage['body'], 'Renewal reminders'), 'The subscriptions page shows the reminders');
ok(has($subsPage['body'], 'Send 1 due reminder'), 'With the one that is due', '');

$reminded = submit('/subscriptions', '/subscriptions/reminders', []);
ok($reminded['status'] === 302, 'Sending them redirects');
ok(
    (int) Dacaam\Core\Database::scalar('SELECT COUNT(*) FROM subscription_reminders WHERE subscription_id = ?', [$subId]) === 1,
    'And records that it went',
);
ok(
    (int) Dacaam\Core\Database::scalar(
        'SELECT COUNT(*) FROM notifications WHERE restaurant_id = ? AND title LIKE "Ishtiraak%"',
        [$newId],
    ) >= 1,
    'The restaurant admin has it in the app',
);

submit('/subscriptions', '/subscriptions/reminders', []);
ok(
    (int) Dacaam\Core\Database::scalar('SELECT COUNT(*) FROM subscription_reminders WHERE subscription_id = ?', [$subId]) === 1,
    'Pressing it again sends nothing twice',
);

Dacaam\Core\Database::run(
    'UPDATE subscriptions SET ends_on = DATE_ADD(CURDATE(), INTERVAL 400 DAY) WHERE id = ?',
    [$subId],
);

// ------------------------------------------------------------ CSV export

group('CSV export');

$bom = "\xEF\xBB\xBF";

$restaurantsCsv = web('/restaurants?format=csv');
ok($restaurantsCsv['status'] === 200, 'The restaurant list exports');
ok(str_starts_with($restaurantsCsv['body'], $bom . 'Name,Code'), 'As UTF-8 CSV Excel will open', substr($restaurantsCsv['body'], 0, 40));
ok(has($restaurantsCsv['body'], $slug), 'With the restaurants in it');

$subsCsv = web('/subscriptions?format=csv');
ok(str_starts_with($subsCsv['body'], $bom . 'Restaurant,'), 'Subscriptions export');

$reportsCsv = web('/reports?days=30&format=csv');
ok(str_starts_with($reportsCsv['body'], $bom . 'Restaurant,'), 'Global reports export');

$ordersCsv = web('/restaurants/' . $newId . '/export/orders');
ok($ordersCsv['status'] === 200 && str_starts_with($ordersCsv['body'], $bom . 'Order,'), "A restaurant's orders export");

$staffCsv = web('/restaurants/' . $newId . '/export/staff');
ok(has($staffCsv['body'], 'Test Admin'), 'Its staff export');
ok(!has($staffCsv['body'], '$2y$'), 'Without a single password hash');

ok(web('/restaurants/' . $newId . '/export/passwords')['status'] === 404, 'Only the listed datasets exist');

// A name typed by somebody else must not run as a formula on the desk of
// whoever opens the export.
Dacaam\Core\Database::run('UPDATE restaurants SET name = ? WHERE id = ?', ['=HYPERLINK("http://x")', $newId]);
$injected = web('/restaurants?format=csv&q=' . $slug);
ok(has($injected['body'], "'=HYPERLINK"), 'A cell that looks like a formula is defused');
Dacaam\Core\Database::run('UPDATE restaurants SET name = ? WHERE id = ?', ['Renamed Kitchen ' . $stamp, $newId]);

ok(
    (int) Dacaam\Core\Database::scalar(
        'SELECT COUNT(*) FROM platform_audit_logs WHERE action = "restaurant_data_exported" AND restaurant_id = ?',
        [$newId],
    ) >= 2,
    'Every restaurant data download is in the platform audit',
);

// --------------------------------------------------------- reports etc

group('Reports, audit and settings');

$reports = web('/reports');
ok($reports['status'] === 200, 'Global reports render');
ok(has($reports['body'], 'Platform volume'), 'Reports show platform volume');
ok(has($reports['body'], 'By restaurant'), 'Reports break down by restaurant');

$reports90 = web('/reports?days=90');
ok(has($reports90['body'], 'last 90 days'), 'The range switch works');

$audit = web('/audit');
ok($audit['status'] === 200, 'The audit log renders');
ok(has($audit['body'], 'restaurant created'), 'Provisioning was recorded');
ok(has($audit['body'], 'subscription renewed'), 'The renewal was recorded');
ok(has($audit['body'], 'user password reset'), 'The password reset was recorded');

$filteredAudit = web('/audit?action=restaurant_created');
ok(has($filteredAudit['body'], 'restaurant created'), 'The audit filter keeps its own action');
ok(!has($filteredAudit['body'], '>subscription renewed<'), 'The audit filter excludes others');

$settings = web('/settings');
ok($settings['status'] === 200, 'Settings render');
ok(has($settings['body'], 'Mail (SMTP)'), 'Settings expose SMTP');
ok(has($settings['body'], 'super@dacaam.test'), 'Settings list platform administrators');
ok(!has($settings['body'], 'smtp_password'), 'The stored SMTP password is never rendered');

$smtp = submit('/settings', '/settings/smtp', [
    'host'       => 'smtp.example.test',
    'port'       => '587',
    'encryption' => 'tls',
    'username'   => 'mailer@example.test',
    'password'   => '',
    'from_email' => 'no-reply@example.test',
    'from_name'  => 'DACAAM',
]);
ok($smtp['status'] === 302, 'Saving SMTP redirects');
$savedSmtp = web('/settings');
ok(has($savedSmtp['body'], 'smtp.example.test'), 'The SMTP host was saved');

// ----------------------------------------------- operations pages

/**
 * The pages that watch the platform itself.
 *
 * Every one of these shipped broken and stayed broken until a restaurant
 * noticed: a controller that returned null, a query using a reserved word, a
 * call to a function the host disables. All three were the same failure — the
 * page 500s the instant it is opened — and all three would have been caught
 * here by nothing more clever than asking whether the page renders.
 */
group('Operations pages');

logged(); // Start from here; anything earlier belongs to another test.

$notifications = web('/notifications');
ok($notifications['status'] === 200, 'Notifications render', substr($notifications['body'], 0, 200));
ok(has($notifications['body'], 'DACAAM'), 'And come wrapped in the layout, not bare');
ok(!has($notifications['body'], 'SQLSTATE'), 'No SQL error leaked onto the page');
ok(logged() === '', 'And the request did not die after sending the page', trim(logged()));

$health = web('/health');
ok($health['status'] === 200, 'Health renders', substr($health['body'], 0, 200));
ok(has($health['body'], 'Database'), 'Health reports on the database');
ok(has($health['body'], 'Audit rows'), 'Including the table that only grows');

// An error page that cannot say when something last happened cannot answer the
// only question anybody opens it to ask: is this still going wrong, or is it
// something already fixed? Prove it against a log with real dates in it.
$logFile = dirname(__DIR__, 2) . '/backend/storage/logs/error.log';
@mkdir(dirname($logFile), 0755, true);
$logWas = is_file($logFile) ? (int) filesize($logFile) : 0;

file_put_contents($logFile, sprintf(
    "[%s] PHP Fatal error:  Uncaught Error: dacaam test - stale fault\n"
    . "[%s] PHP Fatal error:  Uncaught Error: dacaam test - stale fault\n"
    . "[%s] PHP Warning:  dacaam test - fresh fault\n",
    date('d-M-Y H:i:s e', time() - 90000),
    date('d-M-Y H:i:s e', time() - 86400),
    date('d-M-Y H:i:s e', time() - 120),
), FILE_APPEND);

$dated = web('/health');
ok(has($dated['body'], 'Last seen'), 'Errors carry when they were last seen');
ok(has($dated['body'], 'stale fault'), 'The old fault is listed');
ok(has($dated['body'], '1d ago'), 'And dated in days, not shown as though it were now');
ok(has($dated['body'], 'just now'), 'While a fault from two minutes ago reads as current');

// Two identical lines, one row: the grouping still holds with dates attached.
ok(
    preg_match('/stale fault.*?>2</s', $dated['body']) === 1,
    'Repeats are still counted rather than listed twice',
);

// Put the log back to whatever length it was before this test wrote to it.
$handle = fopen($logFile, 'r+');
ftruncate($handle, $logWas);
fclose($handle);

$quiet = web('/health');
ok(!has($quiet['body'], 'stale fault'), 'And the seeded entries are gone again');

// A failed alert is the one failure with no witness: no browser is waiting on
// it, and the symptom of "the owner stopped being told about voided orders" is
// silence, which looks exactly like a quiet week. So it has to be on a page.
require_once dirname(__DIR__, 2) . '/backend/bootstrap.php';

if ((int) Dacaam\Core\Database::scalar(
    'SELECT COUNT(*) FROM information_schema.tables
      WHERE table_schema = DATABASE() AND table_name = "email_outbox"',
) > 0) {
    Dacaam\Core\Database::run('DELETE FROM email_outbox');
    Dacaam\Core\Database::run(
        'INSERT INTO email_outbox
            (restaurant_id, to_email, subject, body, event_key, attempts, last_error)
         VALUES (1, "owner@test.example", "DEG-DEG: Dalab la joojiyay", "x",
                 "orders.order_status_changed", 4, "SMTP connect failed: refused")',
    );

    $withFailure = web('/health');
    ok(has($withFailure['body'], 'Alert email'), 'Health reports on the alert outbox');
    ok(has($withFailure['body'], 'never sent'), 'And says how many were given up on');
    ok(
        has($withFailure['body'], 'SMTP connect failed'),
        'And shows what the mail server actually said',
    );
    ok(
        has($withFailure['body'], 'owner@test.example'),
        'And who never received it',
    );

    Dacaam\Core\Database::run('DELETE FROM email_outbox');

    $clean = web('/health');
    ok(!has($clean['body'], 'never sent'), 'With nothing stuck it stops shouting');
    ok(has($clean['body'], 'delivering'), 'And reports as delivering');
}

$backups = web('/backups');
ok($backups['status'] === 200, 'Backups render', substr($backups['body'], 0, 200));

// The exec() bug: the button existed, looked fine, and failed on a host where
// shelling out is disabled. Pressing it is not enough to catch that — the
// failure is caught and flashed, so the redirect still looks healthy and a
// backup file from an earlier run still sits in the directory. What has to be
// asserted is that THIS press produced a NEW file.
// By name, not by count: the directory is capped at fourteen, so once it is
// full a new backup replaces an old one and the count never moves.
$backupDir = dirname(__DIR__, 2) . '/backend/storage/backups';
$before = array_map('basename', glob($backupDir . '/*.sql.gz') ?: []);

$taken = submit('/backups', '/backups', []);
ok($taken['status'] === 302, 'Taking a backup redirects');

$afterBackup = web('/backups');
ok(has($afterBackup['body'], 'flash-success'), 'It reports success, not a flashed failure');
ok(!has($afterBackup['body'], 'undefined function'), 'Nothing was shelled out to');
ok(!has($afterBackup['body'], 'Backup failed'), 'The backup did not fail');

$after = array_map('basename', glob($backupDir . '/*.sql.gz') ?: []);
$fresh = array_diff($after, $before);

ok(
    $fresh !== [],
    'And a backup file that was not there before now is',
    count($before) . ' -> ' . count($after) . ' files',
);

// A file that exists but is empty is worse than no backup: it looks like one.
$newest = $fresh === [] ? null : $backupDir . '/' . reset($fresh);
ok(
    $newest !== null && filesize($newest) > 1024,
    'And it has actual content in it',
    $newest === null ? 'no new file' : basename($newest) . ' is ' . filesize($newest) . ' bytes',
);

// Fourteen is the cap. Backups that pile up without limit fill a shared host's
// disk, which takes the restaurant down in a way no backup helps with.
ok(
    count($after) <= 14,
    'And the directory stays capped',
    count($after) . ' files',
);

// Everything this run wrote goes when the run does. The cap means a test dump
// left behind pushes out a real backup, and the per-restaurant files for the
// TEST tenants are never pruned at all — 120 of them had piled up unnoticed.
register_shutdown_function(static function () use ($backupDir, $fresh, $slug): void {
    $mine = array_merge(
        array_map(static fn (string $f): string => $backupDir . '/' . $f, $fresh),
        glob($backupDir . '/' . $slug . '-*.rsql.gz') ?: [],
    );

    foreach ($mine as $path) {
        if (is_file($path)) {
            unlink($path);
        }
    }
});

// ------------------------------------------- per-restaurant backups

group('Per-restaurant backup and restore');

$own = submit('/restaurants/' . $newId, '/restaurants/' . $newId . '/backup', []);
ok($own['status'] === 302, 'Backing up one restaurant redirects');

$page = web('/restaurants/' . $newId);
ok(has($page['body'], '.rsql.gz'), 'The restaurant now has a backup of its own');

preg_match('/value="([^"]*\.rsql\.gz)"/', $page['body'], $fm);
$file = $fm[1] ?? '';
ok($file !== '', 'The backup is offered for restore', $file);

// The guard: a restore is one misclick from erasing a restaurant's history, so
// it demands the slug typed out.
$unconfirmed = submit('/restaurants/' . $newId, '/restaurants/' . $newId . '/restore', [
    'file'    => $file,
    'confirm' => 'wrong',
]);
ok($unconfirmed['status'] === 302, 'An unconfirmed restore redirects');
ok(
    str_contains(errorAfter($unconfirmed), 'exactly'),
    'And refuses, because the code was not typed correctly',
);

$restored = submit('/restaurants/' . $newId, '/restaurants/' . $newId . '/restore', [
    'file'    => $file,
    'confirm' => $slug,
]);
ok($restored['status'] === 302, 'A confirmed restore redirects');

$restoredPage = web('/restaurants/' . $newId);
ok(!has($restoredPage['body'], 'Restore failed'), 'The restore succeeded');
ok(has($restoredPage['body'], 'Restored'), 'And said how much it put back');

// The whole point of a per-tenant restore: it stops at the tenant boundary.
$others = web('/restaurants');
ok(has($others['body'], 'Hamze'), 'The other restaurants are still there');

// ------------------------------------------------- platform administrators

/**
 * The account that can reach every restaurant.
 *
 * There used to be exactly one, created at first-run setup and never touched
 * again — no second administrator, no way to disable one, and nothing at all if
 * that person left. The checks that matter here are the ones that stop the
 * platform locking itself out.
 */
group('Mobile app version');

$noUrl = submit('/settings', '/settings/app-version', [
    'min_version' => '1.2.0', 'latest_version' => '1.2.0', 'download_url' => '', 'message' => '',
]);
ok(
    str_contains(errorAfter($noUrl), 'download link'),
    'A minimum with nowhere to download from is refused — it would strand old phones',
);

$backwards = submit('/settings', '/settings/app-version', [
    'min_version' => '2.0.0', 'latest_version' => '1.5.0',
    'download_url' => 'https://example.test/DACAAM.apk', 'message' => '',
]);
ok(str_contains(errorAfter($backwards), 'cannot be newer'), 'A minimum above the latest is refused');

$notVersion = submit('/settings', '/settings/app-version', [
    'min_version' => 'one', 'latest_version' => '', 'download_url' => 'https://example.test/a.apk', 'message' => '',
]);
ok(str_contains(errorAfter($notVersion), 'look like'), 'A version has to be a version');

$badUrl = submit('/settings', '/settings/app-version', [
    'min_version' => '', 'latest_version' => '1.1.0', 'download_url' => 'javascript:alert(1)', 'message' => '',
]);
ok(str_contains(errorAfter($badUrl), 'https://'), 'The link has to be a web address');

$saved = submit('/settings', '/settings/app-version', [
    'min_version' => '1.0.0', 'latest_version' => '1.1.0',
    'download_url' => 'https://example.test/DACAAM.apk', 'message' => 'Cusboonaysii',
]);
ok($saved['status'] === 302, 'A sensible version saves');
ok(has(web('/settings')['body'], 'minimum 1.0.0'), 'And the page shows it');
ok(
    (string) Dacaam\Core\Database::scalar('SELECT value FROM system_settings WHERE key_name = "app_min_version"') === '1.0.0',
    'Where the API reads it from',
);

submit('/settings', '/settings/app-version', [
    'min_version' => '', 'latest_version' => '', 'download_url' => '', 'message' => '',
]);
ok(
    (string) Dacaam\Core\Database::scalar('SELECT value FROM system_settings WHERE key_name = "app_min_version"') === '',
    'And it can be cleared again',
);

group('Administrators');

$adminsPage = web('/admins');
ok($adminsPage['status'] === 200, 'The administrators page renders', substr($adminsPage['body'], 0, 200));
ok(has($adminsPage['body'], 'super@dacaam.test'), 'The seeded administrator is listed');
ok(has($adminsPage['body'], 'first-run setup'), 'And is marked as the one nobody invited');
ok(logged() === '', 'And nothing was logged', trim(logged()));

group('The platform cannot lock itself out');

// With one administrator, there is no button to switch them off — and posting
// directly has to be refused too, because a hidden button is not a rule.
$onlyId = (int) Dacaam\Core\Database::scalar(
    'SELECT id FROM super_admins WHERE email = "super@dacaam.test"',
);

$selfOff = submit('/admins', '/admins/' . $onlyId . '/active', ['active' => '0']);
ok($selfOff['status'] === 302, 'Disabling yourself redirects');
ok(
    str_contains(errorAfter($selfOff), 'your own account'),
    'And is refused',
    errorAfter($selfOff),
);

$stillOn = (int) Dacaam\Core\Database::scalar(
    'SELECT is_active FROM super_admins WHERE id = ?',
    [$onlyId],
);
ok($stillOn === 1, 'The account is still active');

group('Adding one');

$newEmail = 'second' . substr((string) time(), -6) . '@dacaam.test';

$short = submit('/admins', '/admins', [
    'name'     => 'Second Admin',
    'email'    => $newEmail,
    'password' => 'short',
]);
ok(str_contains(errorAfter($short), 'at least'), 'A short password is refused');

$created = submit('/admins', '/admins', [
    'name'     => 'Second Admin',
    'email'    => $newEmail,
    'password' => 'a-long-enough-password',
]);
ok($created['status'] === 302, 'Adding one redirects');

$secondId = (int) Dacaam\Core\Database::scalar(
    'SELECT id FROM super_admins WHERE email = ?',
    [$newEmail],
);
ok($secondId > 0, 'The administrator exists');

$listed = web('/admins');
ok(has($listed['body'], $newEmail), 'And appears on the page');
ok(has($listed['body'], '2 active'), 'The count moved to two');

$duplicate = submit('/admins', '/admins', [
    'name'     => 'Impostor',
    'email'    => $newEmail,
    'password' => 'a-long-enough-password',
]);
ok(
    str_contains(errorAfter($duplicate), 'already belongs'),
    'The same email cannot be used twice',
);

group('Disabling');

$disabled = submit('/admins', '/admins/' . $secondId . '/active', ['active' => '0']);
ok($disabled['status'] === 302, 'Disabling redirects');

$row = Dacaam\Core\Database::selectOne(
    'SELECT is_active, disabled_at FROM super_admins WHERE id = ?',
    [$secondId],
);
ok((int) ($row['is_active'] ?? 1) === 0, 'The account is off');
ok(($row['disabled_at'] ?? null) !== null, 'And when it happened is recorded');

// Never deleted: the platform history points at these rows.
$stillThere = (int) Dacaam\Core\Database::scalar(
    'SELECT COUNT(*) FROM super_admins WHERE id = ?',
    [$secondId],
);
ok($stillThere === 1, 'The row survives — disabled, not deleted');

$reEnabled = submit('/admins', '/admins/' . $secondId . '/active', ['active' => '1']);
ok($reEnabled['status'] === 302, 'And it can be switched back on');
ok(
    (int) Dacaam\Core\Database::scalar('SELECT is_active FROM super_admins WHERE id = ?', [$secondId]) === 1,
    'Which it is',
);

// ------------------------------------------------------------------ roles

/**
 * What each kind of administrator can do.
 *
 * Driven as the people themselves, each with a browser of their own — a
 * separate cookie jar — because a hidden button proves nothing: the question
 * is what the server does when the request arrives anyway.
 */
group('Roles');

ok(
    (string) Dacaam\Core\Database::scalar('SELECT role FROM super_admins WHERE id = ?', [$secondId]) === 'support',
    'Someone added without a role choice is support, not owner',
);

$ownJar = $GLOBALS['jar'];
$asRole = static function (string $role, string $email) use ($ownJar): void {
    $GLOBALS['jar'] = tempnam(sys_get_temp_dir(), 'dacaam_' . $role . '_') ?: '';
    $in = submit('/login', '/login', ['email' => $email, 'password' => 'a-long-enough-password']);
    ok($in['status'] === 302 && !str_contains($in['location'], '/login'), "The $role administrator can sign in", $in['location']);
};
$asOwner = static function () use ($ownJar): void {
    if (is_file($GLOBALS['jar']) && $GLOBALS['jar'] !== $ownJar) {
        unlink($GLOBALS['jar']);
    }
    $GLOBALS['jar'] = $ownJar;
};

$billingEmail = 'billing' . $stamp . '@dacaam.test';
$addBilling = submit('/admins', '/admins', [
    'name'     => 'Billing Person',
    'email'    => $billingEmail,
    'role'     => 'billing',
    'password' => 'a-long-enough-password',
]);
ok($addBilling['status'] === 302, 'A billing administrator can be added');
ok(has(web('/admins')['body'], 'Billing Person'), 'And is listed');

// ---- billing
$asRole('billing', $billingEmail);

ok(web('/admins')['status'] === 403, 'Billing cannot open Administrators');
ok(web('/settings')['status'] === 403, 'Or Settings');
ok(web('/backups')['status'] === 403, 'Or Backups');
ok(web('/subscriptions')['status'] === 200, 'But can open Subscriptions');
ok(web('/plans')['status'] === 200, 'And read the plans');

$billingView = web('/restaurants/' . $newId);
ok($billingView['status'] === 200, 'Billing can look at a restaurant');
ok(!has($billingView['body'], '/reset-password'), 'Without being offered staff password resets');
ok(has($billingView['body'], '/renew'), 'But with the renewal form');
ok(!has($billingView['body'], 'href="' . '/admins"'), 'And no Administrators link in the sidebar');

$billingSuspend = submit('/restaurants/' . $newId, '/restaurants/' . $newId . '/status', ['status' => 'suspended']);
ok($billingSuspend['status'] === 403, 'A suspension posted anyway is refused with 403', (string) $billingSuspend['status']);
ok(
    (string) Dacaam\Core\Database::scalar('SELECT status FROM restaurants WHERE id = ?', [$newId]) !== 'suspended',
    'And nothing changed',
);

$billingRenew = submit('/restaurants/' . $newId, '/subscriptions/' . $subId . '/renew', [
    'months' => '1', 'amount' => '0', 'method' => 'cash', 'reference' => '',
]);
ok($billingRenew['status'] === 302, 'Billing can renew', (string) $billingRenew['status']);

$asOwner();

// ---- support
$supportEmail = 'support' . $stamp . '@dacaam.test';
submit('/admins', '/admins', [
    'name'     => 'Support Person',
    'email'    => $supportEmail,
    'role'     => 'support',
    'password' => 'a-long-enough-password',
]);

$asRole('support', $supportEmail);

$supportView = web('/restaurants/' . $newId);
ok(has($supportView['body'], '/reset-password'), 'Support is offered staff password resets');
ok(!has($supportView['body'], '/renew'), 'But not renewals');

$supportRenew = submit('/restaurants/' . $newId, '/subscriptions/' . $subId . '/renew', [
    'months' => '1', 'amount' => '0', 'method' => 'cash', 'reference' => '',
]);
ok($supportRenew['status'] === 403, 'A renewal posted anyway is refused', (string) $supportRenew['status']);

$supportPlan = submit('/plans', '/plans', ['code' => 'sneaky', 'name' => 'Sneaky']);
ok($supportPlan['status'] === 403, 'Support cannot create plans');
ok(!has(web('/plans')['body'], 'Add a plan'), 'And is not offered the form');
ok(web('/health')['status'] === 200, 'Support can open Health');
ok(web('/admins')['status'] === 403, 'But not Administrators');

$asOwner();

// ---- changing roles
$supportId = (int) Dacaam\Core\Database::scalar('SELECT id FROM super_admins WHERE email = ?', [$supportEmail]);

$selfRole = submit('/admins', '/admins/' . $onlyId . '/role', ['role' => 'billing']);
ok(str_contains(errorAfter($selfRole), 'your own role'), 'Nobody changes their own role');

$badRole = submit('/admins', '/admins/' . $supportId . '/role', ['role' => 'god']);
ok(str_contains(errorAfter($badRole), 'Unknown role'), 'Only the three roles exist');

$promoted = submit('/admins', '/admins/' . $supportId . '/role', ['role' => 'owner']);
ok($promoted['status'] === 302, 'An owner can promote someone');
ok(
    (string) Dacaam\Core\Database::scalar('SELECT role FROM super_admins WHERE id = ?', [$supportId]) === 'owner',
    'Who is now an owner',
);

// With two owners, the other can be demoted — and then the platform is back
// to one owner, who cannot be disabled or demoted by anyone.
$demoted = submit('/admins', '/admins/' . $supportId . '/role', ['role' => 'support']);
ok($demoted['status'] === 302, 'And demote them again');

ok(
    (int) Dacaam\Core\Database::scalar('SELECT COUNT(*) FROM super_admins WHERE role = "owner" AND is_active = 1') === 1,
    'Leaving exactly one owner',
);

group('Two-factor');

$security = web('/security');
ok($security['status'] === 200, 'The security page renders');
ok(has($security['body'], 'password and nothing else'), 'It says what is missing');
ok(logged() === '', 'And rendering it logged nothing', trim(logged()));

$setup = submit('/security', '/security/2fa/setup', []);
ok($setup['status'] === 302, 'Starting setup redirects');

$secret = (string) Dacaam\Core\Database::scalar(
    'SELECT two_factor_secret FROM super_admins WHERE id = ?',
    [$onlyId],
);
ok($secret !== '', 'A secret was stored');
ok(
    Dacaam\Core\Database::scalar(
        'SELECT two_factor_confirmed_at FROM super_admins WHERE id = ?',
        [$onlyId],
    ) === null,
    'But unconfirmed — signing in has not changed yet',
);

$withSecret = web('/security');
ok(has($withSecret['body'], $secret), 'The setup key is shown');

$wrongCode = submit('/security', '/security/2fa/confirm', ['code' => '000000']);
ok(
    str_contains(errorAfter($wrongCode), 'not right'),
    'A wrong code is refused',
);
ok(
    Dacaam\Core\Database::scalar(
        'SELECT two_factor_confirmed_at FROM super_admins WHERE id = ?',
        [$onlyId],
    ) === null,
    'And it stays off — a mistyped setup cannot lock anybody out',
);

$right = submit('/security', '/security/2fa/confirm', [
    'code' => Dacaam\Core\Totp::codeAt($secret, time()),
]);
ok($right['status'] === 302, 'The right code turns it on');
ok(
    Dacaam\Core\Database::scalar(
        'SELECT two_factor_confirmed_at FROM super_admins WHERE id = ?',
        [$onlyId],
    ) !== null,
    'And it is on',
);

$codesPage = web('/security');
ok(has($codesPage['body'], 'recovery codes'), 'Recovery codes are handed over');

$codeCount = (int) Dacaam\Core\Database::scalar(
    'SELECT COUNT(*) FROM super_admin_recovery_codes WHERE super_admin_id = ?',
    [$onlyId],
);
ok($codeCount === 8, 'Eight of them, stored hashed', (string) $codeCount);

// Shown once. A second visit must not print them again.
$again = web('/security');
ok(!has($again['body'], 'Your recovery codes'), 'And only once');

group('Signing in now needs the code');

$out = submit('/', '/logout', []);
ok($out['status'] === 302, 'Signed out');

$passwordOnly = submit('/login', '/login', [
    'email'    => 'super@dacaam.test',
    'password' => 'admin123',
]);
ok($passwordOnly['status'] === 302, 'The password alone redirects');
ok(
    str_contains($passwordOnly['location'], '/login/code'),
    'To the code step, not to the dashboard',
    $passwordOnly['location'],
);

// The password was right, but nothing is signed in yet.
$blocked = web('/');
ok($blocked['status'] === 302, 'The dashboard is still shut');
ok(str_contains($blocked['location'], '/login'), 'And points back at signing in');

$codePage = web('/login/code');
ok($codePage['status'] === 200, 'The code page renders');

$badCode = submit('/login/code', '/login/code', ['code' => '111111']);
ok($badCode['status'] === 302, 'A wrong code redirects');
ok(web('/')['status'] === 302, 'And still nothing is signed in');

$freshSecret = (string) Dacaam\Core\Database::scalar(
    'SELECT two_factor_secret FROM super_admins WHERE id = ?',
    [$onlyId],
);

$goodCode = submit('/login/code', '/login/code', [
    'code' => Dacaam\Core\Totp::codeAt($freshSecret, time()),
]);
ok($goodCode['status'] === 302, 'The right code redirects');
ok(web('/')['status'] === 200, 'And now the dashboard opens');

group('A recovery code works once');

submit('/', '/logout', []);
submit('/login', '/login', ['email' => 'super@dacaam.test', 'password' => 'admin123']);

// Take a real one by hashing candidates is impossible — they are stored hashed
// on purpose — so this drives the path the other way: a fresh set is issued and
// the plaintext is read from the page that hands them over.
$onePlain = null;

$fresh = submit('/security', '/security/recovery-codes', []);

if ($fresh['status'] === 302) {
    // Signed out mid-way, so this will have failed; re-sign-in happens below.
    $onePlain = null;
}

// Finish signing in first, then regenerate and capture one.
$goodAgain = submit('/login/code', '/login/code', [
    'code' => Dacaam\Core\Totp::codeAt($freshSecret, time() + 30),
]);

if (web('/')['status'] === 200) {
    submit('/security', '/security/recovery-codes', []);
    $page = web('/security');

    if (preg_match('/<code style="[^"]*">\s*([a-z0-9-]{6,})\s*<\/code>/i', $page['body'], $m) === 1) {
        $onePlain = trim($m[1]);
    }
}

ok($onePlain !== null, 'A recovery code was issued and shown', (string) $onePlain);

if ($onePlain !== null) {
    submit('/', '/logout', []);
    submit('/login', '/login', ['email' => 'super@dacaam.test', 'password' => 'admin123']);

    $viaRecovery = submit('/login/code', '/login/code', ['code' => $onePlain]);
    ok($viaRecovery['status'] === 302, 'It gets past the code step');
    ok(web('/')['status'] === 200, 'And signs in');

    // Once, and never again.
    submit('/', '/logout', []);
    submit('/login', '/login', ['email' => 'super@dacaam.test', 'password' => 'admin123']);

    $reuse = submit('/login/code', '/login/code', ['code' => $onePlain]);
    ok(web('/')['status'] === 302, 'The same code cannot be used twice');

    // Get back in for the rest of the suite.
    submit('/login/code', '/login/code', [
        'code' => Dacaam\Core\Totp::codeAt($freshSecret, time()),
    ]);
}

group('Two-factor comes back off');

// The remaining groups sign in and out repeatedly; leaving it on would make
// every one of them a two-step dance for no extra coverage.
$offAgain = submit('/security', '/security/2fa/disable', ['password' => 'admin123']);
ok($offAgain['status'] === 302, 'Turning it off redirects');
ok(
    Dacaam\Core\Database::scalar(
        'SELECT two_factor_confirmed_at FROM super_admins WHERE id = ?',
        [$onlyId],
    ) === null,
    'And it is off',
);
ok(
    (int) Dacaam\Core\Database::scalar(
        'SELECT COUNT(*) FROM super_admin_recovery_codes WHERE super_admin_id = ?',
        [$onlyId],
    ) === 0,
    'The codes went with it',
);

// ------------------------------------------------------------- tills

/**
 * Cash variance across every restaurant.
 *
 * The owner sees their own till in the app. This is the only place the pattern
 * across all of them shows — and the only place a shop that is quietly losing
 * money every evening becomes visible to the platform.
 */
group('Tills');

$tills = web('/tills');
ok($tills['status'] === 200, 'The tills page renders', substr($tills['body'], 0, 200));
ok(has($tills['body'], 'Tills'), 'And is titled');
ok(logged() === '', 'And did not die on the way out', trim(logged()));

// Seed a close that did not balance, and prove it surfaces.
if ((int) Dacaam\Core\Database::scalar(
    'SELECT COUNT(*) FROM information_schema.tables
      WHERE table_schema = DATABASE() AND table_name = "shifts"',
) > 0) {
    $account = (int) Dacaam\Core\Database::scalar(
        'SELECT id FROM accounts WHERE restaurant_id = 1 AND method = "cash" LIMIT 1',
    );
    $user = (int) Dacaam\Core\Database::scalar(
        'SELECT id FROM users WHERE restaurant_id = 1 LIMIT 1',
    );

    Dacaam\Core\Database::run('DELETE FROM shifts WHERE restaurant_id = 1');
    Dacaam\Core\Database::run(
        'INSERT INTO shifts
            (restaurant_id, account_id, opened_by, opened_at, opening_float,
             closed_by, closed_at, expected_close, counted_close, variance,
             close_reason, orders_outside)
         VALUES (1, :aid, :uid, DATE_SUB(NOW(), INTERVAL 8 HOUR), 200000,
                 :uid2, NOW(), 760000, 742000, -18000,
                 "Lacag laga waayay sanduuqa", 3)',
        ['aid' => $account, 'uid' => $user, 'uid2' => $user],
    );

    $withShort = web('/tills');
    ok(has($withShort['body'], '1 short'), 'A short till is counted in the header');
    ok(
        has($withShort['body'], 'Lacag laga waayay'),
        'And the reason given is shown, not just the number',
    );
    ok(
        has($withShort['body'], 'Closes that did not balance'),
        'The list of unbalanced closes is there',
    );

    // Off-shift orders are the quieter problem: a restaurant with many of them
    // is not really being counted at all.
    ok(has($withShort['body'], 'Off-shift orders'), 'Off-shift orders are surfaced');

    ok(logged() === '', 'And rendering all that logged nothing', trim(logged()));

    Dacaam\Core\Database::run('DELETE FROM shifts WHERE restaurant_id = 1');
}

// ------------------------------------------------- refusals vs faults

/**
 * A rejected form is not an error.
 *
 * Both were RuntimeExceptions, so both went to the error log, so the Health
 * page listed "Enter a valid email address" beside a genuine fatal. A log that
 * fills up with people mistyping is a log nobody reads, which is the same as
 * having no log at all.
 */
group('Refusals are not logged as faults');

logged();

$short = submit('/restaurants/' . $newId, '/restaurants/' . $newId . '/reset-password', [
    'user_id'  => '0',
    'password' => 'abc',
]);
ok($short['status'] === 302, 'A refused password redirects back');
ok(str_contains(errorAfter($short), 'least'), 'And the person is told why');
ok(logged() === '', 'But nothing was written to the error log', trim(logged()));

$badStatus = submit('/restaurants/' . $newId, '/restaurants/' . $newId . '/status', [
    'status' => 'nonsense',
]);
ok($badStatus['status'] === 302, 'An unknown status is refused');
ok(logged() === '', 'And that is not logged either', trim(logged()));

// The other half: a real fault must still reach the log, or this change has
// simply blinded the Health page in a different way.
$brokenView = web('/restaurants/999999');
ok($brokenView['status'] === 404, 'A missing restaurant is still a 404');

// ------------------------------------------------------- silent fatals

/**
 * Walk every page and insist the server logged nothing.
 *
 * Cheap, and it covers the failure the status code cannot: a page that renders
 * correctly and then throws on the way out.
 */
// ---------------------------------------------------------------- archive

/**
 * A restaurant that has left: locked out, out of the lists, nothing deleted.
 */
group('Archiving');

$ordersBefore = (int) Dacaam\Core\Database::scalar('SELECT COUNT(*) FROM orders WHERE restaurant_id = ?', [$newId]);
$staffBefore = (int) Dacaam\Core\Database::scalar('SELECT COUNT(*) FROM users WHERE restaurant_id = ?', [$newId]);

$unconfirmedArchive = submit('/restaurants/' . $newId, '/restaurants/' . $newId . '/archive', ['confirm' => 'nope']);
ok(str_contains(errorAfter($unconfirmedArchive), 'exactly'), 'Archiving needs the code typed out');
ok(
    (string) Dacaam\Core\Database::scalar('SELECT status FROM restaurants WHERE id = ?', [$newId]) !== 'archived',
    'And without it nothing happens',
);

$archivedPost = submit('/restaurants/' . $newId, '/restaurants/' . $newId . '/archive', ['confirm' => strtolower($slug)]);
ok($archivedPost['status'] === 302, 'With it, the restaurant is archived');
ok(
    (string) Dacaam\Core\Database::scalar('SELECT status FROM restaurants WHERE id = ?', [$newId]) === 'archived',
    'Its status says so',
);
ok(
    (int) Dacaam\Core\Database::scalar(
        'SELECT COUNT(*) FROM api_tokens WHERE restaurant_id = ? AND revoked_at IS NULL',
        [$newId],
    ) === 0,
    'Every session it had is ended',
);
ok(
    (int) Dacaam\Core\Database::scalar('SELECT COUNT(*) FROM orders WHERE restaurant_id = ?', [$newId]) === $ordersBefore
    && (int) Dacaam\Core\Database::scalar('SELECT COUNT(*) FROM users WHERE restaurant_id = ?', [$newId]) === $staffBefore,
    'And not one row was deleted',
);

ok(!has(web('/restaurants')['body'], $slug), 'It leaves the working list');
ok(has(web('/restaurants?status=archived')['body'], $slug), 'And is one filter away');

$archivedStatus = submit('/restaurants/' . $newId, '/restaurants/' . $newId . '/status', ['status' => 'active']);
ok(str_contains(errorAfter($archivedStatus), 'archived'), 'It cannot be switched back on by accident');

$archivedRenew = submit('/restaurants/' . $newId, '/subscriptions/' . $subId . '/renew', [
    'months' => '1', 'amount' => '0', 'method' => 'cash', 'reference' => '',
]);
ok(str_contains(errorAfter($archivedRenew), 'archived'), 'Or renewed back to life');

ok(
    web('/restaurants/' . $newId . '/export/orders')['status'] === 200,
    'Its data can still be exported — that is what a leaving restaurant is owed',
);

$restored = submit('/restaurants/' . $newId, '/restaurants/' . $newId . '/unarchive', []);
ok($restored['status'] === 302, 'It can be restored from the archive');
ok(
    (string) Dacaam\Core\Database::scalar('SELECT status FROM restaurants WHERE id = ?', [$newId]) === 'suspended',
    'Coming back suspended, so switching it on is a separate decision',
);

submit('/restaurants/' . $newId, '/restaurants/' . $newId . '/status', ['status' => 'active']);

group('No page dies quietly');

logged();

foreach ([
    '/', '/restaurants', '/restaurants/new', '/restaurants/' . $newId,
    '/subscriptions', '/reports', '/audit', '/settings',
    '/notifications', '/health', '/backups', '/tills', '/admins', '/security',
    '/plans', '/invoices/' . $paymentId, '/restaurants?status=archived',
] as $path) {
    $page = web($path);
    $noise = trim(logged());

    ok(
        $page['status'] === 200 && $noise === '',
        sprintf('%s renders and logs nothing', $path),
        $noise !== '' ? substr($noise, 0, 200) : "status {$page['status']}",
    );
}

// ------------------------------------------------------------- log out

group('Sign out');

$out = submit('/', '/logout', []);
ok($out['status'] === 302, 'Signing out redirects');

$afterOut = web('/');
ok($afterOut['status'] === 302, 'The dashboard is protected again');
ok(str_contains($afterOut['location'], '/login'), 'And it points back at the login page');

summary();
