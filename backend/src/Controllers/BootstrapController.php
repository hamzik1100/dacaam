<?php

declare(strict_types=1);

namespace Dacaam\Controllers;

use Dacaam\Core\Auth;
use Dacaam\Core\AuthContext;
use Dacaam\Core\Database;
use Dacaam\Core\Request;
use Dacaam\Repositories\OrderRepository;
use Dacaam\Support\Shifts;
use Dacaam\Repositories\Repository;
use Dacaam\Support\Presenter;

/**
 * Everything the app needs for its first paint, in one round trip.
 *
 * A POS opens on a phone tethered to patchy mobile data; six parallel requests
 * mean six chances to half-load. One payload flips the UI from skeleton to
 * content atomically, exactly as the Redux bootstrap action expects.
 */
final class BootstrapController extends Repository
{
    /** @return array<string,mixed> */
    public function index(Request $request, AuthContext $context): array
    {
        $restaurantId = $context->restaurantId;

        $staff = Database::select(
            'SELECT u.*, r.code AS role_code, r.name AS role_name
               FROM users u
          LEFT JOIN user_roles ur ON ur.user_id = u.id
          LEFT JOIN roles r       ON r.id = ur.role_id
              WHERE u.restaurant_id = :rid AND u.is_active = 1
              ORDER BY u.id ASC',
            ['rid' => $restaurantId],
        );

        $menuController = new MenuController();
        $tableController = new TableController();
        $expenseController = new ExpenseController();
        $accountController = new AccountController();
        $draftController = new DraftController();
        $reportController = new ReportController();

        return [
            'restaurant' => Presenter::restaurant(
                Database::selectOne('SELECT * FROM restaurants WHERE id = :id', ['id' => $restaurantId]) ?? [],
            ),
            'user'        => Auth::publicUser($context->userId),
            'permissions' => $context->permissions,
            // One bit, available to everybody: is a till open?
            //
            // The POS refuses to sell without one, and a waiter has to be told
            // why — but a waiter has no shifts.manage and so cannot read the
            // shift endpoint, which carries the counting figures. This says
            // whether, and nothing about how much.
            'till_open'   => Shifts::currentTill($restaurantId) !== null,
            'settings'    => Presenter::settings(self::settings($restaurantId)),

            'staff' => array_map(
                static fn (array $row): array => Presenter::user($row),
                $staff,
            ),

            'categories'         => $menuController->categories($request, $context),
            'menu_items'         => $menuController->items($request, $context),
            'tables'             => $tableController->index($request, $context),
            'orders'             => OrderRepository::list($restaurantId, [], 100),
            'drafts'             => $draftController->index($request, $context),
            'expenses'           => $expenseController->index($request, $context),
            'expense_categories' => $expenseController->categories($request, $context),
            'accounts'           => $accountController->index($request, $context),
            'dashboard'          => $reportController->dashboard($request, $context),

            'server_time' => date('c'),
        ];
    }
}
