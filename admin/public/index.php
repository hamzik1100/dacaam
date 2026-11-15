<?php

declare(strict_types=1);

/**
 * DACAAM Super Admin — front controller.
 *
 * A server-rendered dashboard, deliberately not a second Flutter app: it is
 * used by a handful of people on a desktop, and a page of HTML loads faster
 * and breaks in fewer ways than a SPA would for that audience.
 */

use DacaamAdmin\Controllers\AdminUserController;
use DacaamAdmin\Controllers\AuthController;
use DacaamAdmin\Controllers\DashboardController;
use DacaamAdmin\Controllers\BackupController;
use DacaamAdmin\Controllers\HealthController;
use DacaamAdmin\Controllers\InvoiceController;
use DacaamAdmin\Controllers\NotificationController;
use DacaamAdmin\Controllers\PlanController;
use DacaamAdmin\Controllers\PlatformController;
use DacaamAdmin\Controllers\RestaurantController;
use DacaamAdmin\Controllers\TillController;
use DacaamAdmin\Controllers\SubscriptionController;
use DacaamAdmin\Core\Response;
use DacaamAdmin\Core\WebRouter;

// The built-in server routes *everything* through this script, including
// requests for files that exist on disk — so `php -S` would answer the
// stylesheet with the 404 page. Apache already excludes real files in
// .htaccess; this is the same rule for the dev server.
if (PHP_SAPI === 'cli-server') {
    $requested = (string) parse_url((string) ($_SERVER['REQUEST_URI'] ?? '/'), PHP_URL_PATH);
    $candidate = realpath(__DIR__ . $requested);

    if ($candidate !== false
        && is_file($candidate)
        && str_starts_with($candidate, __DIR__ . DIRECTORY_SEPARATOR)
        && basename($candidate) !== 'index.php'
    ) {
        return false;
    }
}

require dirname(__DIR__) . '/bootstrap.php';

header('X-Content-Type-Options: nosniff');
header('X-Frame-Options: DENY');
header('Referrer-Policy: same-origin');
header('Cache-Control: no-store, private');

// The dashboard ships no JavaScript at all, so `script-src 'none'` costs
// nothing and turns any future injected <script> into a blocked request
// instead of a working one. Inline *styles* are allowed because the views use
// style attributes for one-off spacing.
header(
    "Content-Security-Policy: default-src 'none'; "
    . "style-src 'self' 'unsafe-inline'; img-src 'self' data:; "
    . "form-action 'self'; frame-ancestors 'none'; base-uri 'none'",
);

// The Secure flag on the session cookie is set in bootstrap.php — cookie
// params have to be decided before the session starts, and by here it has.
if (($_SERVER['HTTPS'] ?? '') !== '' && strtolower((string) $_SERVER['HTTPS']) !== 'off') {
    header('Strict-Transport-Security: max-age=31536000; includeSubDomains');
}

// The dashboard may live at the web root (php -S) or under a subdirectory
// (Apache alias). Everything the templates emit goes through Response::url().
$scriptDir = str_replace('\\', '/', dirname((string) ($_SERVER['SCRIPT_NAME'] ?? '')));
Response::$basePath = ($scriptDir === '/' || $scriptDir === '.') ? '' : $scriptDir;

$path = parse_url((string) ($_SERVER['REQUEST_URI'] ?? '/'), PHP_URL_PATH);
$path = is_string($path) ? $path : '/';
if (Response::$basePath !== '' && str_starts_with($path, Response::$basePath)) {
    $path = substr($path, strlen(Response::$basePath));
}
$path = '/' . trim($path, '/');
if ($path === '/') {
    $path = '/';
}

$router = new WebRouter();

$auth = new AuthController();
$router->get('/login', $auth->showLogin(...), guest: true);
$router->post('/login', $auth->login(...), guest: true);
// The second step. Guest routes: nothing is signed in until the code lands.
$router->get('/login/code', $auth->challenge(...), guest: true);
$router->post('/login/code', $auth->verifyChallenge(...), guest: true);
// Open only while `super_admins` is empty, and closed permanently after.
$router->get('/setup', $auth->showSetup(...), guest: true);
$router->post('/setup', $auth->setup(...), guest: true);
$router->post('/logout', $auth->logout(...));
$router->post('/password', $auth->changePassword(...));

// ---------------------------------------------------------- platform staff

// Who can run the platform, and the lock on the account that can reach every
// restaurant. There used to be exactly one administrator, created at setup
// and unmanageable thereafter, with a password and nothing else.
//
// The last argument on a route is the ability its role must hold (Access).
// Reading is open to every role; acting mostly is not.
$admins = new AdminUserController();
$router->get('/admins', $admins->index(...), ability: 'admins');
$router->post('/admins', $admins->store(...), ability: 'admins');
$router->post('/admins/{id}/active', $admins->setActive(...), ability: 'admins');
$router->post('/admins/{id}/role', $admins->setRole(...), ability: 'admins');

// Your own account — every role has one.
$router->get('/security', $admins->security(...));
$router->post('/security/2fa/setup', $admins->startTwoFactor(...));
$router->post('/security/2fa/confirm', $admins->confirmTwoFactor(...));
$router->post('/security/2fa/disable', $admins->disableTwoFactor(...));
$router->post('/security/recovery-codes', $admins->regenerateCodes(...));

$router->get('/', (new DashboardController())->index(...));

$restaurants = new RestaurantController();
$router->get('/restaurants', $restaurants->index(...));
$router->get('/restaurants/new', $restaurants->create(...), ability: 'restaurants.manage');
$router->post('/restaurants', $restaurants->store(...), ability: 'restaurants.manage');
$router->get('/restaurants/{id}', $restaurants->show(...));
$router->post('/restaurants/{id}', $restaurants->update(...), ability: 'restaurants.manage');
$router->post('/restaurants/{id}/status', $restaurants->setStatus(...), ability: 'restaurants.manage');
$router->post('/restaurants/{id}/reset-password', $restaurants->resetAdminPassword(...), ability: 'restaurants.manage');
// Leaving the platform, and coming back. Nothing is deleted either way.
$router->post('/restaurants/{id}/archive', $restaurants->archive(...), ability: 'restaurants.archive');
$router->post('/restaurants/{id}/unarchive', $restaurants->unarchive(...), ability: 'restaurants.archive');
// Their own records as spreadsheets — what a leaving restaurant is owed.
$router->get('/restaurants/{id}/export/{dataset}', $restaurants->export(...), ability: 'restaurants.export');

$subscriptions = new SubscriptionController();
$router->get('/subscriptions', $subscriptions->index(...));
// Before `/subscriptions/{id}`, which would otherwise take "reminders" for an id.
$router->post('/subscriptions/reminders', $subscriptions->sendReminders(...), ability: 'billing');
$router->post('/subscriptions/{id}', $subscriptions->update(...), ability: 'billing');
$router->post('/subscriptions/{id}/renew', $subscriptions->renew(...), ability: 'billing');

// What can be sold, at what price, with what limits.
$plans = new PlanController();
$router->get('/plans', $plans->index(...));
$router->post('/plans', $plans->store(...), ability: 'plans.manage');
$router->post('/plans/{id}', $plans->update(...), ability: 'plans.manage');

// A receipt for every subscription payment.
$invoices = new InvoiceController();
$router->get('/invoices/{id}', $invoices->show(...));
$router->post('/invoices/{id}/email', $invoices->email(...), ability: 'billing');

$platform = new PlatformController();
// Messages to the restaurants. Saved first, pushed second.
$notifications = new NotificationController();
$router->get('/notifications', $notifications->index(...), ability: 'notifications');
$router->post('/notifications', $notifications->send(...), ability: 'notifications');

// Backups. The one page whose absence is a business risk rather than a
// missing feature.
$backups = new BackupController();
// Errors, as they happen — rather than when a restaurant telephones.
// Cash variance across every restaurant. The owner sees their own till in
// the app; nobody saw the pattern across all of them until this page.
$router->get('/tills', (new TillController())->index(...), ability: 'operations');
$router->get('/health', (new HealthController())->index(...), ability: 'operations');

$router->get('/backups', $backups->index(...), ability: 'backups');
$router->post('/backups', $backups->run(...), ability: 'backups');

$router->post('/restaurants/{id}/backup', $backups->takeRestaurant(...), ability: 'backups');
$router->post('/restaurants/{id}/restore', $backups->restoreRestaurant(...), ability: 'backups');

$router->get('/reports', $platform->reports(...));
$router->get('/audit', $platform->audit(...), ability: 'audit');
$router->get('/settings', $platform->settings(...), ability: 'settings');
$router->post('/settings/smtp', $platform->updateSmtp(...), ability: 'settings');
$router->post('/settings/smtp/test', $platform->testSmtp(...), ability: 'settings');
$router->post('/settings/app-version', $platform->updateAppVersion(...), ability: 'settings');
$router->post('/settings/invoice', $platform->updateInvoiceDetails(...), ability: 'settings');

$router->dispatch(
    strtoupper((string) ($_SERVER['REQUEST_METHOD'] ?? 'GET')),
    $path,
);
