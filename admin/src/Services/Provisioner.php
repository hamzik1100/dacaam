<?php

declare(strict_types=1);

namespace DacaamAdmin\Services;

use Dacaam\Core\Database;
use DacaamAdmin\Core\Refused;
use RuntimeException;

/**
 * Creates a restaurant and everything it needs to be usable on day one.
 *
 * Entirely transactional. A half-provisioned tenant — a restaurant row with no
 * admin user, or roles with no permissions — is worse than no tenant at all:
 * it exists in the list, nobody can sign into it, and the only fix is manual
 * SQL. Either all of it lands or none of it does.
 *
 * What a new restaurant gets:
 *   - the tenant row and its slug
 *   - a subscription (trial by default)
 *   - the three built-in roles, with the same permission sets the seed uses
 *   - one admin user
 *   - default settings, the four money accounts, and starter categories
 */
final class Provisioner
{
    private const OPERATOR_PERMISSIONS = [
        'orders.view', 'orders.create', 'orders.edit', 'orders.cancel',
        'menu.view', 'menu.create', 'menu.edit',
        'expenses.view', 'expenses.create',
        'reports.view',
        'tables.view', 'tables.manage',
        'accounts.view',
        'settings.view',
    ];

    private const WAITER_PERMISSIONS = [
        'orders.view', 'orders.create', 'menu.view', 'tables.view',
    ];

    private const DEFAULT_CATEGORIES = [
        ['Burgers', '🍔', '#F97316'],
        ['Pizzas', '🍕', '#F59E0B'],
        ['Chicken', '🍗', '#14B8A6'],
        ['Drinks', '🥤', '#3B82F6'],
        ['Desserts', '🍰', '#8B5CF6'],
        ['Sides', '🍟', '#10B981'],
    ];

    private const DEFAULT_EXPENSE_CATEGORIES = [
        ['Food Supplies', 'daily', 'local_grocery_store', '#F97316'],
        ['Cleaning', 'daily', 'cleaning_services', '#3B82F6'],
        ['Transport', 'daily', 'local_shipping', '#14B8A6'],
        ['Rent', 'monthly', 'home_work', '#8B5CF6'],
        ['Salary', 'monthly', 'groups', '#F59E0B'],
        ['Electricity', 'monthly', 'bolt', '#EF4444'],
    ];

    /**
     * @param  array<string,mixed> $input
     * @return int New restaurant id
     */
    public static function create(array $input): int
    {
        $slug = self::normaliseSlug((string) $input['slug']);

        if ($slug === '') {
            throw new Refused('Restaurant code cannot be empty');
        }
        if (self::slugTaken($slug)) {
            throw new Refused("Restaurant code $slug is already in use");
        }

        $adminPhone = preg_replace('/[^0-9+]/', '', (string) $input['admin_phone']) ?? '';
        if (strlen($adminPhone) < 7) {
            throw new Refused('Admin phone is not valid');
        }
        if (strlen((string) $input['admin_password']) < 6) {
            throw new Refused('Admin password must be at least 6 characters');
        }

        return Database::transaction(static function () use ($input, $slug, $adminPhone): int {
            $restaurantId = Database::insert('restaurants', [
                'slug'       => $slug,
                'name'       => trim((string) $input['name']),
                'phone'      => trim((string) ($input['phone'] ?? '')),
                'address'    => trim((string) ($input['address'] ?? '')),
                'logo_emoji' => (string) ($input['logo_emoji'] ?? '🍽️'),
                'status'     => (string) ($input['status'] ?? 'trial'),
            ]);

            $plan = (string) ($input['plan'] ?? 'trial');
            $days = max(1, (int) ($input['subscription_days'] ?? 30));

            Database::run(
                'INSERT INTO subscriptions
                    (restaurant_id, plan, status, starts_on, ends_on, amount)
                 VALUES (:rid, :plan, :status, CURDATE(),
                         DATE_ADD(CURDATE(), INTERVAL :days DAY), :amount)',
                [
                    'rid'    => $restaurantId,
                    'plan'   => $plan,
                    'status' => (string) ($input['status'] ?? 'trial'),
                    'days'   => $days,
                    'amount' => (float) ($input['amount'] ?? 0),
                ],
            );

            Database::insert('restaurant_settings', ['restaurant_id' => $restaurantId]);

            self::createRoles($restaurantId);
            $userId = self::createAdminUser($restaurantId, $input, $adminPhone);
            self::createAccounts($restaurantId);
            self::createCategories($restaurantId);
            self::createExpenseCategories($restaurantId);

            // A restaurant with no admin is unreachable; fail loudly rather
            // than leaving one in the list that nobody can open.
            if ($userId <= 0) {
                throw new RuntimeException('Failed to create the admin user');
            }

            return $restaurantId;
        });
    }

    private static function createRoles(int $restaurantId): void
    {
        $roles = [
            'admin'    => 'Maamule',
            'operator' => 'Hawlwadeen',
            'waiter'   => 'Adeege',
        ];

        foreach ($roles as $code => $name) {
            $roleId = Database::insert('roles', [
                'restaurant_id' => $restaurantId,
                'code'          => $code,
                'name'          => $name,
                'is_system'     => 1,
            ]);

            $codes = match ($code) {
                'admin'    => null, // everything
                'operator' => self::OPERATOR_PERMISSIONS,
                default    => self::WAITER_PERMISSIONS,
            };

            if ($codes === null) {
                Database::run(
                    'INSERT INTO role_permissions (role_id, permission_id)
                     SELECT :rid, id FROM permissions',
                    ['rid' => $roleId],
                );
                continue;
            }

            $placeholders = implode(',', array_fill(0, count($codes), '?'));
            Database::run(
                "INSERT INTO role_permissions (role_id, permission_id)
                 SELECT ?, id FROM permissions WHERE code IN ($placeholders)",
                array_merge([$roleId], $codes),
            );
        }
    }

    /** @param array<string,mixed> $input */
    private static function createAdminUser(
        int $restaurantId,
        array $input,
        string $phone,
    ): int {
        $userId = Database::insert('users', [
            'restaurant_id'        => $restaurantId,
            'name'                 => trim((string) $input['admin_name']),
            'phone'                => $phone,
            'email'                => ($input['admin_email'] ?? '') !== ''
                ? trim((string) $input['admin_email'])
                : null,
            'password_hash'        => password_hash(
                (string) $input['admin_password'],
                PASSWORD_BCRYPT,
                ['cost' => 10],
            ),
            'password_changed_at'  => date('Y-m-d H:i:s'),
            // The platform operator chose this password, so the restaurant's
            // own admin replaces it on first sign-in.
            'must_change_password' => 1,
        ]);

        $roleId = Database::scalar(
            'SELECT id FROM roles WHERE restaurant_id = :rid AND code = "admin"',
            ['rid' => $restaurantId],
        );

        Database::insert('user_roles', [
            'user_id' => $userId,
            'role_id' => (int) $roleId,
        ]);

        return $userId;
    }

    private static function createAccounts(int $restaurantId): void
    {
        foreach (['cash' => 'Cash', 'zaad' => 'Zaad', 'edahab' => 'eDahab', 'bank' => 'Bank'] as $method => $name) {
            Database::insert('accounts', [
                'restaurant_id' => $restaurantId,
                'method'        => $method,
                'name'          => $name,
                'balance'       => 0,
            ]);
        }
    }

    private static function createCategories(int $restaurantId): void
    {
        $sort = 1;
        foreach (self::DEFAULT_CATEGORIES as [$name, $emoji, $color]) {
            Database::insert('categories', [
                'restaurant_id' => $restaurantId,
                'name'          => $name,
                'emoji'         => $emoji,
                'color'         => $color,
                'sort_order'    => $sort++,
            ]);
        }
    }

    private static function createExpenseCategories(int $restaurantId): void
    {
        foreach (self::DEFAULT_EXPENSE_CATEGORIES as [$name, $kind, $icon, $color]) {
            Database::insert('expense_categories', [
                'restaurant_id' => $restaurantId,
                'name'          => $name,
                'kind'          => $kind,
                'icon'          => $icon,
                'color'         => $color,
            ]);
        }
    }

    public static function normaliseSlug(string $slug): string
    {
        return strtoupper(
            preg_replace('/[^A-Za-z0-9]/', '', trim($slug)) ?? '',
        );
    }

    public static function slugTaken(string $slug, ?int $exceptId = null): bool
    {
        $sql = 'SELECT 1 FROM restaurants WHERE slug = :slug';
        $bind = ['slug' => $slug];

        if ($exceptId !== null) {
            $sql .= ' AND id <> :id';
            $bind['id'] = $exceptId;
        }

        return Database::scalar($sql . ' LIMIT 1', $bind) !== false;
    }
}
