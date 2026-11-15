<?php

declare(strict_types=1);

namespace DacaamAdmin\Controllers;

use Dacaam\Core\Database;
use Dacaam\Support\Plans;
use DacaamAdmin\Core\Access;
use DacaamAdmin\Core\Csv;
use DacaamAdmin\Core\Flash;
use DacaamAdmin\Core\PlatformAudit;
use DacaamAdmin\Core\Refused;
use DacaamAdmin\Core\Response;
use DacaamAdmin\Core\View;
use DacaamAdmin\Services\Provisioner;
use RuntimeException;

final class RestaurantController
{
    public function index(): void
    {
        $search = trim((string) ($_GET['q'] ?? ''));
        $status = (string) ($_GET['status'] ?? '');

        $where = ['1 = 1'];
        $bind = [];

        if ($search !== '') {
            $where[] = '(r.name LIKE :q OR r.slug LIKE :q2 OR r.phone LIKE :q3)';
            $bind['q'] = "%$search%";
            $bind['q2'] = "%$search%";
            $bind['q3'] = "%$search%";
        }
        if (in_array($status, ['active', 'trial', 'suspended', 'archived'], true)) {
            $where[] = 'r.status = :status';
            $bind['status'] = $status;
        } else {
            // Archived restaurants have left. They stay one tab away rather
            // than in the working list, where they would be counted and chased.
            $where[] = 'r.status <> "archived"';
        }

        $restaurants = Database::select(
            'SELECT r.*,
                    s.plan, s.status AS sub_status, s.ends_on,
                    DATEDIFF(s.ends_on, CURDATE()) AS days_left,
                    (SELECT COUNT(*) FROM users u
                      WHERE u.restaurant_id = r.id AND u.is_active = 1) AS staff,
                    (SELECT COUNT(*) FROM orders o
                      WHERE o.restaurant_id = r.id AND o.status <> "cancelled") AS orders,

                    -- The three numbers that say whether a restaurant is
                    -- still alive. A shop that stopped ordering three weeks
                    -- ago is about to leave, and without this the first
                    -- anyone hears of it is when the renewal is refused.
                    (SELECT MAX(o.created_at) FROM orders o
                      WHERE o.restaurant_id = r.id AND o.status <> "cancelled") AS last_order_at,
                    (SELECT COUNT(*) FROM orders o
                      WHERE o.restaurant_id = r.id AND o.status <> "cancelled"
                        AND o.created_at >= DATE_SUB(NOW(), INTERVAL 7 DAY)) AS orders_week,
                    (SELECT COUNT(*) FROM orders o
                      WHERE o.restaurant_id = r.id AND o.status <> "cancelled"
                        AND o.created_at >= DATE_SUB(NOW(), INTERVAL 14 DAY)
                        AND o.created_at <  DATE_SUB(NOW(), INTERVAL 7 DAY)) AS orders_prev_week
               FROM restaurants r
          LEFT JOIN subscriptions s ON s.restaurant_id = r.id
              WHERE ' . implode(' AND ', $where) . '
              ORDER BY r.created_at DESC',
            $bind,
        );

        if (($_GET['format'] ?? '') === 'csv') {
            PlatformAudit::log('csv_exported', detail: 'restaurants' . ($status !== '' ? " ($status)" : ''));

            Csv::download(
                Csv::filename('restaurants' . ($status !== '' ? "-$status" : '')),
                [
                    'Name', 'Code', 'Phone', 'Address', 'Status', 'Plan', 'Subscription',
                    'Ends', 'Days left', 'Active staff', 'Orders', 'Orders this week',
                    'Orders last week', 'Last order', 'Created',
                ],
                array_map(static fn (array $r): array => [
                    $r['name'], $r['slug'], $r['phone'], $r['address'], $r['status'],
                    $r['plan'], $r['sub_status'], $r['ends_on'], $r['days_left'], $r['staff'],
                    $r['orders'], $r['orders_week'], $r['orders_prev_week'], $r['last_order_at'],
                    $r['created_at'],
                ], $restaurants),
            );
        }

        View::page('restaurants/index', [
            'title'       => 'Restaurants',
            'nav'         => 'restaurants',
            'restaurants' => $restaurants,
            'search'      => $search,
            'status'      => $status,
        ]);
    }

    public function create(): void
    {
        View::page('restaurants/create', [
            'title' => 'New restaurant',
            'nav'   => 'restaurants',
            'old'   => [],
            'plans' => Plans::all(activeOnly: true),
        ]);
    }

    public function store(): void
    {
        try {
            $plan = Plans::find((string) ($_POST['plan'] ?? ''));
            if ($plan === null || (int) $plan['is_active'] !== 1) {
                throw new Refused('Choose a plan from the list');
            }

            $id = Provisioner::create([
                'name'              => $_POST['name'] ?? '',
                'slug'              => $_POST['slug'] ?? '',
                'phone'             => $_POST['phone'] ?? '',
                'address'           => $_POST['address'] ?? '',
                'logo_emoji'        => $_POST['logo_emoji'] ?? '🍽️',
                'status'            => $_POST['status'] ?? 'trial',
                'plan'              => (string) $plan['code'],
                'subscription_days' => $_POST['subscription_days'] ?? 30,
                'amount'            => $_POST['amount'] ?? 0,
                'admin_name'        => $_POST['admin_name'] ?? '',
                'admin_phone'       => $_POST['admin_phone'] ?? '',
                'admin_email'       => $_POST['admin_email'] ?? '',
                'admin_password'    => $_POST['admin_password'] ?? '',
            ]);

            PlatformAudit::log(
                'restaurant_created',
                restaurantId: $id,
                detail: Provisioner::normaliseSlug((string) ($_POST['slug'] ?? '')),
            );

            Flash::success('Restaurant created and ready to sign in.');
            Response::redirect('/restaurants/' . $id);
        } catch (RuntimeException $e) {
            Flash::error($e->getMessage());

            View::page('restaurants/create', [
                'title' => 'New restaurant',
                'nav'   => 'restaurants',
                'old'   => $_POST,
                'plans' => Plans::all(activeOnly: true),
            ]);
        }
    }

    /** @param array<string,string> $params */
    public function show(array $params): void
    {
        $id = (int) $params['id'];
        $restaurant = self::find($id);

        $subscription = Database::selectOne(
            'SELECT *, DATEDIFF(ends_on, CURDATE()) AS days_left
               FROM subscriptions WHERE restaurant_id = :rid LIMIT 1',
            ['rid' => $id],
        );

        $stats = Database::selectOne(
            'SELECT
                (SELECT COUNT(*) FROM users WHERE restaurant_id = :r1 AND is_active = 1) AS staff,
                (SELECT COUNT(*) FROM menu_items WHERE restaurant_id = :r2 AND deleted_at IS NULL) AS items,
                (SELECT COUNT(*) FROM orders WHERE restaurant_id = :r3 AND status <> "cancelled") AS orders,
                (SELECT COALESCE(SUM(total), 0) FROM orders
                  WHERE restaurant_id = :r4 AND status <> "cancelled") AS sales',
            ['r1' => $id, 'r2' => $id, 'r3' => $id, 'r4' => $id],
        ) ?? [];

        $staff = Database::select(
            'SELECT u.id, u.name, u.phone, u.is_active, u.last_login_at,
                    COALESCE(ro.code, "waiter") AS role
               FROM users u
          LEFT JOIN user_roles ur ON ur.user_id = u.id
          LEFT JOIN roles ro      ON ro.id = ur.role_id
              WHERE u.restaurant_id = :rid
              ORDER BY u.id ASC',
            ['rid' => $id],
        );

        $payments = Database::select(
            'SELECT * FROM subscription_payments
              WHERE restaurant_id = :rid ORDER BY paid_on DESC LIMIT 20',
            ['rid' => $id],
        );

        $history = Database::select(
            'SELECT * FROM platform_audit_logs
              WHERE restaurant_id = :rid ORDER BY created_at DESC LIMIT 20',
            ['rid' => $id],
        );

        View::page('restaurants/show', [
            'title'        => (string) $restaurant['name'],
            'nav'          => 'restaurants',
            'restaurant'   => $restaurant,
            'subscription' => $subscription,
            'stats'        => $stats,
            'staff'        => $staff,
            'payments'     => $payments,
            'history'      => $history,
            // What the restaurant is seeing right now.
            //
            // Support used to begin with "send me a screenshot", because there
            // was no way to look. Read-only and nothing more: no impersonation,
            // no token, no way to act as them — the operator can see what they
            // see, and that is where it stops.
            'today' => Database::selectOne(
                'SELECT
                    COALESCE(SUM(CASE WHEN o.status <> "cancelled" THEN o.total END), 0) AS sales,
                    COUNT(CASE WHEN o.status <> "cancelled" THEN 1 END)                  AS orders,
                    COUNT(CASE WHEN o.status = "cancelled" THEN 1 END)                   AS cancelled,
                    COALESCE(SUM(CASE WHEN o.payment_status <> "paid"
                                       AND o.status <> "cancelled" THEN o.total END), 0) AS unpaid
                   FROM orders o
                  WHERE o.restaurant_id = :rid
                    AND DATE(o.created_at) = CURDATE()',
                ['rid' => $id],
            ) ?? [],

            'recent_orders' => Database::select(
                'SELECT o.order_number, o.order_type, o.status, o.payment_status,
                        o.total, o.customer_name, o.waiter_name, o.created_at
                   FROM orders o
                  WHERE o.restaurant_id = :rid
                  ORDER BY o.created_at DESC
                  LIMIT 8',
                ['rid' => $id],
            ),

            // Money owed to this restaurant by its own customers. Not the
            // platform's business to chase, but a strong signal of how the shop
            // is actually run — and the first thing they ask about when the
            // figures look wrong.
            'debtors' => Database::select(
                'SELECT c.name, c.phone, c.balance_owed
                   FROM customers c
                  WHERE c.restaurant_id = :rid AND c.balance_owed > 0
                  ORDER BY c.balance_owed DESC
                  LIMIT 5',
                ['rid' => $id],
            ),

            // This restaurant's own backups, newest first.
            'backups'  => \Dacaam\Support\Backup::forRestaurant((string) $restaurant['slug']),

            // The plan it is on, how much of it is used, and what else could
            // be sold — for the plan pickers and the "3 of 5 staff" line.
            'plan'     => Plans::forRestaurant($id),
            'usage'    => Plans::usage($id),
            'plans'    => Plans::all(),

            // Which of the page's forms this administrator may use. The routes
            // enforce it regardless; this only stops offering buttons that
            // would answer 403.
            'can' => [
                'manage'  => Access::can('restaurants.manage'),
                'billing' => Access::can('billing'),
                'backups' => Access::can('backups'),
                'archive' => Access::can('restaurants.archive'),
                'export'  => Access::can('restaurants.export'),
            ],
        ]);
    }

    /**
     * Takes a restaurant off the platform.
     *
     * Not a delete, and deliberately not offered as one. Their orders, ledger
     * and customers' debts are records a business may be asked for years
     * later, and a row-by-row delete across thirty tables is one bug away from
     * taking another tenant's rows with it. Archiving locks them out, takes
     * them out of every working list, and keeps everything.
     *
     * @param array<string,string> $params
     */
    public function archive(array $params): void
    {
        $id = (int) $params['id'];
        $restaurant = self::find($id);

        if ($restaurant['status'] === 'archived') {
            throw new Refused('This restaurant is already archived');
        }
        // Typed, not clicked: this takes a whole business offline.
        if (strtoupper(trim((string) ($_POST['confirm'] ?? ''))) !== (string) $restaurant['slug']) {
            throw new Refused('Type the restaurant code exactly to archive it');
        }

        Database::transaction(static function () use ($id): void {
            Database::run(
                'UPDATE restaurants SET status = "archived", archived_at = NOW() WHERE id = :id',
                ['id' => $id],
            );
            Database::run(
                'UPDATE subscriptions SET status = "suspended" WHERE restaurant_id = :id',
                ['id' => $id],
            );
            Database::run(
                'UPDATE api_tokens SET revoked_at = NOW()
                  WHERE restaurant_id = :id AND revoked_at IS NULL',
                ['id' => $id],
            );
        });

        PlatformAudit::log(
            'restaurant_archived',
            restaurantId: $id,
            detail: $restaurant['status'] . ' → archived',
        );

        Flash::success('Archived. Everyone is signed out, and nothing was deleted.');
        Response::redirect('/restaurants/' . $id);
    }

    /**
     * Brings one back — suspended, so that switching it on is its own
     * decision, taken with the subscription in view.
     *
     * @param array<string,string> $params
     */
    public function unarchive(array $params): void
    {
        $id = (int) $params['id'];
        $restaurant = self::find($id);

        if ($restaurant['status'] !== 'archived') {
            throw new Refused('This restaurant is not archived');
        }

        Database::run(
            'UPDATE restaurants SET status = "suspended", archived_at = NULL WHERE id = :id',
            ['id' => $id],
        );

        PlatformAudit::log('restaurant_unarchived', restaurantId: $id, detail: 'archived → suspended');

        Flash::success('Back from the archive, and suspended. Renew or activate it when they are ready.');
        Response::redirect('/restaurants/' . $id);
    }

    /** What can be exported, and the query behind each. */
    private const EXPORTS = [
        'orders' => [
            'label'   => 'Orders',
            'headers' => [
                'Order', 'Date', 'Type', 'Status', 'Payment', 'Table', 'Waiter', 'Customer',
                'Customer phone', 'Guests', 'Subtotal', 'Discount', 'Tax', 'Packaging',
                'Total', 'Notes', 'Cancel reason',
            ],
            'sql' => 'SELECT o.order_number, o.created_at, o.order_type, o.status, o.payment_status,
                             t.table_number, o.waiter_name, o.customer_name, o.customer_phone,
                             o.guests, o.subtotal, o.discount, o.tax_amount, o.packaging_fee,
                             o.total, o.notes, o.cancel_reason
                        FROM orders o
                   LEFT JOIN `tables` t ON t.id = o.table_id
                       WHERE o.restaurant_id = :rid
                       ORDER BY o.order_number ASC',
        ],
        'order-items' => [
            'label'   => 'Order lines',
            'headers' => ['Order', 'Date', 'Item', 'Unit price', 'Quantity', 'Line total', 'Notes'],
            'sql' => 'SELECT o.order_number, o.created_at, i.item_name, i.unit_price,
                             i.quantity, i.line_total, i.notes
                        FROM order_items i
                        JOIN orders o ON o.id = i.order_id
                       WHERE i.restaurant_id = :rid
                       ORDER BY o.order_number ASC, i.id ASC',
        ],
        'payments' => [
            'label'   => 'Payments',
            'headers' => ['Order', 'Date', 'Method', 'Amount', 'Reference'],
            'sql' => 'SELECT o.order_number, p.created_at, p.method, p.amount, p.reference
                        FROM order_payments p
                        JOIN orders o ON o.id = p.order_id
                       WHERE p.restaurant_id = :rid
                       ORDER BY p.created_at ASC, p.id ASC',
        ],
        'menu' => [
            'label'   => 'Menu',
            'headers' => ['Category', 'Item', 'Description', 'Price', 'Available', 'Deleted'],
            'sql' => 'SELECT c.name AS category, m.name, m.description, m.price,
                             m.is_available, m.deleted_at
                        FROM menu_items m
                        JOIN categories c ON c.id = m.category_id
                       WHERE m.restaurant_id = :rid
                       ORDER BY c.sort_order ASC, m.sort_order ASC, m.id ASC',
        ],
        'customers' => [
            'label'   => 'Customers',
            'headers' => ['Name', 'Phone', 'Address', 'Owes', 'Credit limit', 'Active', 'Notes', 'Since'],
            'sql' => 'SELECT name, phone, address, balance_owed, credit_limit, is_active, notes, created_at
                        FROM customers
                       WHERE restaurant_id = :rid
                       ORDER BY name ASC',
        ],
        'expenses' => [
            'label'   => 'Expenses',
            'headers' => ['Date', 'Expense', 'Category', 'Amount', 'Method', 'Notes'],
            'sql' => 'SELECT e.expense_date, e.name, c.name AS category, e.amount, e.method, e.notes
                        FROM expenses e
                   LEFT JOIN expense_categories c ON c.id = e.expense_category_id
                       WHERE e.restaurant_id = :rid
                       ORDER BY e.expense_date ASC, e.id ASC',
        ],
        // No password hashes, no 2FA secrets — who worked there, not how to
        // sign in as them.
        'staff' => [
            'label'   => 'Staff',
            'headers' => ['Name', 'Phone', 'Email', 'Role', 'Active', 'Last sign-in', 'Added'],
            'sql' => 'SELECT u.name, u.phone, u.email, COALESCE(ro.name, ""), u.is_active,
                             u.last_login_at, u.created_at
                        FROM users u
                   LEFT JOIN user_roles ur ON ur.user_id = u.id
                   LEFT JOIN roles ro ON ro.id = ur.role_id
                       WHERE u.restaurant_id = :rid
                       ORDER BY u.id ASC',
        ],
    ];

    /** @return array<string,string> dataset => label, for the view. */
    public static function exportable(): array
    {
        return array_map(static fn (array $e): string => $e['label'], self::EXPORTS);
    }

    /**
     * One of the restaurant's own tables, as a spreadsheet.
     *
     * What a restaurant that is leaving is owed, and what one asks for when
     * their accountant wants the year. Every download is in the platform
     * audit: it is their customers' names and phone numbers going out.
     *
     * @param array<string,string> $params
     */
    public function export(array $params): void
    {
        $id = (int) $params['id'];
        $restaurant = self::find($id);
        $dataset = (string) $params['dataset'];

        if (!isset(self::EXPORTS[$dataset])) {
            Response::notFound();
        }

        $spec = self::EXPORTS[$dataset];

        PlatformAudit::log(
            'restaurant_data_exported',
            restaurantId: $id,
            detail: $spec['label'],
        );

        Csv::download(
            Csv::filename($restaurant['slug'] . '-' . $dataset),
            $spec['headers'],
            Database::select($spec['sql'], ['rid' => $id]),
        );
    }

    /** @param array<string,string> $params */
    public function update(array $params): void
    {
        $id = (int) $params['id'];
        $restaurant = self::find($id);

        $slug = Provisioner::normaliseSlug((string) ($_POST['slug'] ?? ''));
        if ($slug === '') {
            throw new Refused('Restaurant code cannot be empty');
        }
        if (Provisioner::slugTaken($slug, $id)) {
            throw new Refused("Restaurant code $slug is already in use");
        }

        Database::run(
            'UPDATE restaurants
                SET name = :name, slug = :slug, phone = :phone,
                    address = :address, logo_emoji = :emoji
              WHERE id = :id',
            [
                'name'    => trim((string) $_POST['name']),
                'slug'    => $slug,
                'phone'   => trim((string) ($_POST['phone'] ?? '')),
                'address' => trim((string) ($_POST['address'] ?? '')),
                'emoji'   => (string) ($_POST['logo_emoji'] ?? '🍽️'),
                'id'      => $id,
            ],
        );

        if ($slug !== (string) $restaurant['slug']) {
            // Staff sign in with this code, so a change is worth recording
            // loudly — support will be asked about it.
            PlatformAudit::log(
                'restaurant_code_changed',
                restaurantId: $id,
                detail: $restaurant['slug'] . ' → ' . $slug,
            );
        }

        PlatformAudit::log('restaurant_updated', restaurantId: $id);
        Flash::success('Restaurant updated.');
        Response::redirect('/restaurants/' . $id);
    }

    /** @param array<string,string> $params */
    public function setStatus(array $params): void
    {
        $id = (int) $params['id'];
        $restaurant = self::find($id);
        $status = (string) ($_POST['status'] ?? '');

        if (!in_array($status, ['active', 'trial', 'suspended'], true)) {
            throw new Refused('Unknown status');
        }
        if ($restaurant['status'] === 'archived') {
            throw new Refused('This restaurant is archived. Restore it from the archive first.');
        }

        Database::transaction(static function () use ($id, $status): void {
            Database::run(
                'UPDATE restaurants SET status = :status WHERE id = :id',
                ['status' => $status, 'id' => $id],
            );
            Database::run(
                'UPDATE subscriptions SET status = :status WHERE restaurant_id = :id',
                ['status' => $status, 'id' => $id],
            );

            // Suspending has to bite immediately: leaving live tokens valid
            // would let a suspended restaurant keep trading until they happen
            // to sign out.
            if ($status === 'suspended') {
                Database::run(
                    'UPDATE api_tokens SET revoked_at = NOW()
                      WHERE restaurant_id = :id AND revoked_at IS NULL',
                    ['id' => $id],
                );
            }
        });

        PlatformAudit::log(
            'restaurant_status_changed',
            restaurantId: $id,
            detail: $restaurant['status'] . ' → ' . $status,
        );

        Flash::success(
            $status === 'suspended'
                ? 'Restaurant suspended. Their data is untouched.'
                : 'Restaurant is now ' . $status . '.',
        );
        Response::redirect('/restaurants/' . $id);
    }

    /** @param array<string,string> $params */
    public function resetAdminPassword(array $params): void
    {
        $id = (int) $params['id'];
        self::find($id);

        $userId = (int) ($_POST['user_id'] ?? 0);
        $password = (string) ($_POST['password'] ?? '');

        if (strlen($password) < 6) {
            throw new Refused('Password must be at least 6 characters');
        }

        $user = Database::selectOne(
            'SELECT id, name FROM users WHERE id = :id AND restaurant_id = :rid',
            ['id' => $userId, 'rid' => $id],
        );
        if ($user === null) {
            throw new Refused('That user does not belong to this restaurant');
        }

        Database::transaction(static function () use ($userId, $password): void {
            Database::run(
                'UPDATE users
                    SET password_hash = :hash,
                        password_changed_at = NOW(),
                        must_change_password = 1,
                        failed_logins = 0,
                        locked_until = NULL
                  WHERE id = :id',
                [
                    'hash' => password_hash($password, PASSWORD_BCRYPT, ['cost' => 10]),
                    'id'   => $userId,
                ],
            );

            // The platform operator now knows this password, so every session
            // ends and the user is made to replace it on next sign-in.
            Database::run(
                'UPDATE api_tokens SET revoked_at = NOW()
                  WHERE user_id = :id AND revoked_at IS NULL',
                ['id' => $userId],
            );
        });

        PlatformAudit::log(
            'user_password_reset',
            restaurantId: $id,
            detail: (string) $user['name'],
        );

        Flash::success(
            'Password reset. They will be asked to change it when they sign in.',
        );
        Response::redirect('/restaurants/' . $id);
    }

    /** @return array<string,mixed> */
    private static function find(int $id): array
    {
        $row = Database::selectOne(
            'SELECT * FROM restaurants WHERE id = :id LIMIT 1',
            ['id' => $id],
        );

        if ($row === null) {
            Response::notFound();
        }

        return $row;
    }
}
