<?php

declare(strict_types=1);

namespace DacaamAdmin\Core;

/**
 * What each platform role may do.
 *
 * Every administrator used to be able to do everything, so giving the person
 * who records payments an account also gave them restore-from-backup and the
 * power to add more administrators. Three roles now:
 *
 *   - owner   — everything, including other administrators and settings;
 *   - support — looks after restaurants: edits, suspensions, staff passwords,
 *               backups, messages;
 *   - billing — money: renewals, plans' prices on invoices, reminders.
 *
 * Reading is open to all three. What is gated is acting, plus the few pages
 * that are themselves an action or a secret (settings, administrators).
 * Owners are not listed below — they pass every check.
 */
final class Access
{
    public const ROLES = [
        'owner'   => 'Owner',
        'support' => 'Support',
        'billing' => 'Billing',
    ];

    /** Ability => the roles besides owner that hold it. */
    private const ABILITIES = [
        'restaurants.manage'  => ['support'],
        'restaurants.export'  => ['support'],
        // Taking a restaurant off the platform is an owner's decision.
        'restaurants.archive' => [],
        'backups'             => ['support'],
        'notifications'       => ['support'],
        'operations'          => ['support'],
        'audit'               => ['support'],
        'billing'             => ['billing'],
        'plans.manage'        => [],
        'admins'              => [],
        'settings'            => [],
    ];

    /** @param array<string,mixed>|null $admin */
    public static function allows(?array $admin, string $ability): bool
    {
        if ($admin === null) {
            return false;
        }

        $role = self::role($admin);

        if ($role === 'owner') {
            return true;
        }

        return in_array($role, self::ABILITIES[$ability] ?? [], true);
    }

    /** Checks the signed-in administrator, for views. */
    public static function can(string $ability): bool
    {
        return self::allows(AdminAuth::current(), $ability);
    }

    /** @param array<string,mixed> $admin */
    public static function role(array $admin): string
    {
        $role = (string) ($admin['role'] ?? 'owner');

        return isset(self::ROLES[$role]) ? $role : 'owner';
    }

    /** Stops the request with a 403 that says why. */
    public static function deny(array $admin): never
    {
        Response::abort(
            403,
            'Not allowed',
            sprintf(
                'Your role (%s) cannot do this. Ask a platform owner if you need it.',
                self::ROLES[self::role($admin)],
            ),
        );
    }
}
