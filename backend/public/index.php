<?php

declare(strict_types=1);

/**
 * DACAAM REST API — front controller.
 *
 *   Flutter → REST API → PHP → MySQL
 *
 * Every route below is tenant-scoped through the bearer token. The permission
 * named on each route is checked before the handler runs, so authorization is
 * declarative and visible in one place rather than scattered through
 * controllers.
 */

use Dacaam\Controllers\AccountController;
use Dacaam\Controllers\AuditController;
use Dacaam\Controllers\AuthController;
use Dacaam\Controllers\BootstrapController;
use Dacaam\Controllers\CustomerController;
use Dacaam\Controllers\DraftController;
use Dacaam\Controllers\ExpenseController;
use Dacaam\Controllers\MenuController;
use Dacaam\Controllers\NotificationController;
use Dacaam\Controllers\OrderController;
use Dacaam\Controllers\PasswordResetController;
use Dacaam\Controllers\PaymentMethodController;
use Dacaam\Controllers\ReportController;
use Dacaam\Controllers\SecurityController;
use Dacaam\Controllers\SettingsController;
use Dacaam\Controllers\ShiftController;
use Dacaam\Controllers\TableController;
use Dacaam\Controllers\UserController;
use Dacaam\Core\Config;
use Dacaam\Core\Request;
use Dacaam\Core\Router;
use Dacaam\Support\AppVersion;

require dirname(__DIR__) . '/bootstrap.php';

$router = new Router();
$api = '/api/v1';

// ------------------------------------------------------------- public

$auth = new AuthController();
$router->get('/', static fn (): array => [
    'name'    => Config::get('app.name'),
    'version' => Config::get('app.version'),
    'status'  => 'ok',
], auth: false);

$router->get($api . '/health', static fn (): array => [
    'status'      => 'ok',
    'server_time' => date('c'),
], auth: false);

// Which app version the platform expects. Public on purpose: an app too old to
// sign in is exactly the one that most needs to be told to update.
$router->get($api . '/app/version', static fn (): array => AppVersion::current(), auth: false);

// Throttles are per caller address. Per-user lockout already exists; this
// stops one address spraying a password across every phone number instead.
// The numbers are sized for a real restaurant — a till that mistypes a
// password ten times in five minutes has a bigger problem than throttling.
$router->post($api . '/auth/login', $auth->login(...), auth: false, throttle: [20, 300]);
// Unauthenticated by design: the caller holds a challenge, not a session.
$router->post($api . '/auth/2fa/verify', $auth->verifyTwoFactor(...), auth: false, throttle: [20, 300]);

// Unauthenticated by necessity — the caller cannot sign in. Both answer
// identically whether or not the account exists. Throttled harder: these send
// mail, so an unlimited endpoint is a way to use us to flood someone's inbox.
$reset = new PasswordResetController();
$router->post($api . '/auth/password/forgot', $reset->request(...), auth: false, throttle: [5, 900]);
$router->post($api . '/auth/password/reset', $reset->reset(...), auth: false, throttle: [10, 900]);
$router->post($api . '/auth/logout', $auth->logout(...));
$router->get($api . '/auth/me', $auth->me(...));

// --------------------------------------------------------- security
// Scoped to the calling user; only the policy needs a permission.

$security = new SecurityController();
$router->get($api . '/security/overview', $security->overview(...));
$router->post($api . '/security/2fa/setup', $security->startTwoFactor(...));
$router->post($api . '/security/2fa/confirm', $security->confirmTwoFactor(...));
$router->post($api . '/security/2fa/disable', $security->disableTwoFactor(...));
$router->post($api . '/security/2fa/recovery-codes', $security->regenerateRecoveryCodes(...));
$router->get($api . '/security/sessions', $security->sessions(...));
$router->delete($api . '/security/sessions/{id}', $security->revokeSession(...));
$router->post($api . '/security/sessions/revoke-others', $security->revokeOtherSessions(...));
$router->get($api . '/security/login-history', $security->loginHistory(...));
$router->post($api . '/security/password', $security->changePassword(...));
$router->get($api . '/security/policy', $security->policy(...), 'settings.view');
$router->put($api . '/security/policy', $security->updatePolicy(...), 'settings.manage');
$router->get($api . '/security/smtp', $security->smtp(...), 'settings.manage');
$router->put($api . '/security/smtp', $security->updateSmtp(...), 'settings.manage');
$router->post($api . '/security/smtp/test', $security->testSmtp(...), 'settings.manage');

// ------------------------------------------------------------ session

$router->get($api . '/bootstrap', (new BootstrapController())->index(...));

// ------------------------------------------------------------- orders

$orders = new OrderController();
$router->get($api . '/orders', $orders->index(...), 'orders.view');
$router->post($api . '/orders', $orders->store(...), 'orders.create');
$router->get($api . '/orders/{id}', $orders->show(...), 'orders.view');
$router->get($api . '/orders/{id}/history', $orders->history(...), 'orders.view');
$router->patch($api . '/orders/{id}/status', $orders->updateStatus(...), 'orders.view');
// Putting an unpaid order onto somebody's tab. orders.edit, not
// customers.edit: the thing being changed is the order, and the person doing
// it is the one who can already alter what the order contains.
$router->patch($api . '/orders/{id}/customer', $orders->attachCustomer(...), 'orders.edit');
$router->put($api . '/orders/{id}/items', $orders->updateItems(...), 'orders.edit');
$router->post($api . '/orders/{id}/payments', $orders->addPayment(...), 'orders.edit');

// ------------------------------------------------------------- drafts

$drafts = new DraftController();
$router->get($api . '/drafts', $drafts->index(...), 'orders.view');
$router->post($api . '/drafts', $drafts->store(...), 'orders.create');
$router->get($api . '/drafts/{id}', $drafts->show(...), 'orders.view');
$router->put($api . '/drafts/{id}', $drafts->update(...), 'orders.create');
$router->post($api . '/drafts/{id}/cancel', $drafts->cancel(...), 'orders.cancel');
$router->post($api . '/drafts/{id}/convert', $drafts->convert(...), 'orders.create');

// --------------------------------------------------------------- menu

$menu = new MenuController();
$router->get($api . '/menu/items', $menu->items(...), 'menu.view');
$router->post($api . '/menu/items', $menu->storeItem(...), 'menu.create');
// Photographs. menu.edit, like every other change to an item.
$router->post($api . '/menu/items/{id}/image', $menu->uploadItemImage(...), 'menu.edit');
$router->delete($api . '/menu/items/{id}/image', $menu->deleteItemImage(...), 'menu.edit');
$router->put($api . '/menu/items/{id}', $menu->updateItem(...), 'menu.edit');
$router->patch($api . '/menu/items/{id}/availability', $menu->toggleItem(...), 'menu.edit');
$router->delete($api . '/menu/items/{id}', $menu->deleteItem(...), 'menu.delete');

$router->get($api . '/menu/categories', $menu->categories(...), 'menu.view');
$router->post($api . '/menu/categories', $menu->storeCategory(...), 'menu.create');
$router->put($api . '/menu/categories/{id}', $menu->updateCategory(...), 'menu.edit');
$router->delete($api . '/menu/categories/{id}', $menu->deleteCategory(...), 'menu.delete');

// ------------------------------------------------------------- tables

$tables = new TableController();
$router->get($api . '/tables', $tables->index(...), 'tables.view');
$router->post($api . '/tables', $tables->store(...), 'tables.manage');
$router->put($api . '/tables/{id}', $tables->update(...), 'tables.manage');
$router->delete($api . '/tables/{id}', $tables->destroy(...), 'tables.manage');

// ----------------------------------------------------------- expenses

$expenses = new ExpenseController();
$router->get($api . '/expenses', $expenses->index(...), 'expenses.view');
$router->post($api . '/expenses', $expenses->store(...), 'expenses.create');
$router->put($api . '/expenses/{id}', $expenses->update(...), 'expenses.edit');
// Cancelled, never deleted. There is deliberately no DELETE here: an expense
// that can be removed leaves the books unable to explain a figure that was
// there yesterday and is gone today, and "somebody deleted it" is exactly the
// answer an audit trail exists to prevent.
$router->post($api . '/expenses/{id}/cancel', $expenses->cancel(...), 'expenses.delete');

$router->get($api . '/expense-categories', $expenses->categories(...), 'expenses.view');
$router->post($api . '/expense-categories', $expenses->storeCategory(...), 'expenses.create');
$router->delete($api . '/expense-categories/{id}', $expenses->destroyCategory(...), 'expenses.delete');

// ----------------------------------------------------------- accounts

$accounts = new AccountController();
$router->get($api . '/accounts', $accounts->index(...), 'accounts.view');
// Ahead of /accounts/{id}: a literal segment must not be swallowed by the
// wildcard, or "transactions" is read as an account id.
$router->get($api . '/accounts/transactions', $accounts->transactions(...), 'accounts.view');
$router->post($api . '/accounts/transfer', $accounts->transfer(...), 'accounts.manage');
$router->post($api . '/accounts', $accounts->store(...), 'accounts.manage');
$router->put($api . '/accounts/{id}', $accounts->update(...), 'accounts.manage');
$router->delete($api . '/accounts/{id}', $accounts->destroy(...), 'accounts.manage');

// ------------------------------------------------------ notifications

$notifications = new NotificationController();

// No permission: every user reads their own messages, and a shop where the
// waiter cannot be told the system is down has the wrong messages.
$router->get($api . '/notifications', $notifications->index(...));
$router->post($api . '/notifications/read-all', $notifications->markAllRead(...));
$router->post($api . '/notifications/{id}/read', $notifications->markRead(...));

// Where to deliver. Called on every launch.
$router->post($api . '/devices', $notifications->registerDevice(...));

// ---------------------------------------------------------- customers

$customers = new CustomerController();
$router->get($api . '/customers', $customers->index(...), 'customers.view');
$router->post($api . '/customers', $customers->store(...), 'customers.create');
$router->get($api . '/customers/{id}', $customers->show(...), 'customers.view');
$router->get($api . '/customers/{id}/ledger', $customers->ledger(...), 'customers.view');
$router->put($api . '/customers/{id}', $customers->update(...), 'customers.edit');
$router->delete($api . '/customers/{id}', $customers->destroy(...), 'customers.delete');

// Money. A repayment and a deposit are ordinary counter work, so an operator
// may take them; moving a balance by hand is not, and has its own permission.
$router->post($api . '/customers/{id}/payment', $customers->payment(...), 'customers.payment');
$router->post($api . '/customers/{id}/deposit', $customers->deposit(...), 'customers.payment');
$router->post($api . '/customers/{id}/adjust', $customers->adjust(...), 'customers.adjust');

// --------------------------------------------------- payment methods

$methods = new PaymentMethodController();
$router->get($api . '/payment-methods', $methods->index(...), 'accounts.view');
$router->post($api . '/payment-methods', $methods->store(...), 'accounts.manage');
$router->put($api . '/payment-methods/{id}', $methods->update(...), 'accounts.manage');
$router->delete($api . '/payment-methods/{id}', $methods->destroy(...), 'accounts.manage');

// ------------------------------------------------------------ reports

$reports = new ReportController();
$router->get($api . '/reports/summary', $reports->summary(...), 'reports.view');
$router->get($api . '/reports/dashboard', $reports->dashboard(...), 'reports.view');
$router->get($api . '/reports/export', $reports->export(...), 'reports.export');

// ----------------------------------------------------------- settings

$settings = new SettingsController();
$router->get($api . '/settings', $settings->show(...), 'settings.view');
$router->put($api . '/settings', $settings->update(...), 'settings.manage');
$router->put($api . '/settings/restaurant', $settings->updateRestaurant(...), 'settings.manage');

// -------------------------------------------------------------- users

$users = new UserController();
$router->get($api . '/users', $users->index(...), 'users.view');
$router->post($api . '/users', $users->store(...), 'users.create');
$router->put($api . '/users/{id}', $users->update(...), 'users.edit');
$router->put($api . '/users/{id}/permissions', $users->setPermissions(...), 'users.edit');
$router->delete($api . '/users/{id}', $users->destroy(...), 'users.delete');

$router->get($api . '/roles', $users->roles(...), 'users.view');
$router->post($api . '/roles', $users->storeRole(...), 'users.create');
$router->put($api . '/roles/{id}/permissions', $users->updateRolePermissions(...), 'users.edit');
$router->delete($api . '/roles/{id}', $users->destroyRole(...), 'users.delete');
$router->get($api . '/permissions', $users->permissions(...), 'users.view');

// ------------------------------------------------------------- shifts

// Counting the drawer. `manage` opens and closes a till; `view` carries the
// expected total and the history, and the split between them is what keeps
// the count blind — see upgrade_shifts.php.
$shifts = new ShiftController();
$router->get($api . '/shifts/current', $shifts->current(...), 'shifts.manage');
$router->post($api . '/shifts', $shifts->open(...), 'shifts.manage');
$router->post($api . '/shifts/{id}/close', $shifts->close(...), 'shifts.manage');
$router->get($api . '/shifts', $shifts->index(...), 'shifts.view');
$router->get($api . '/shifts/{id}', $shifts->peek(...), 'shifts.view');

// -------------------------------------------------------------- audit

$router->get($api . '/audit-logs', (new AuditController())->index(...), 'audit.view');

$router->run(Request::capture());

// Alerts go out after the customer has their answer, never before.
//
// SMTP costs seconds when it is healthy and a timeout when it is not, and a
// cashier with somebody waiting must not pay for either. This only runs where
// the server can hand the response over first — LiteSpeed and php-fpm both
// can — so on a host that cannot, nothing is delayed and the cron does the
// work instead. One message per request keeps the tail short.
if (function_exists('litespeed_finish_request')) {
    litespeed_finish_request();
} elseif (function_exists('fastcgi_finish_request')) {
    fastcgi_finish_request();
}

if (function_exists('litespeed_finish_request') || function_exists('fastcgi_finish_request')) {
    try {
        Dacaam\Support\Alerts::drain(1);
    } catch (Throwable $e) {
        error_log('[dacaam] outbox drain: ' . $e->getMessage());
    }
}
