<?php

declare(strict_types=1);

namespace Dacaam\Support;

use Dacaam\Core\ApiException;
use Dacaam\Core\Database;
use Throwable;

/**
 * What a restaurant's plan allows.
 *
 * Limits are counted at the moment something is added or switched back on,
 * never applied backwards: moving a restaurant to a smaller plan does not
 * disable the staff it already has, it only stops the list growing. Turning
 * people off mid-shift because of a billing change would be the platform
 * breaking the till.
 *
 * Zero means unlimited, and so does no plan at all.
 */
final class Plans
{
    /** What each limit counts, and what a person calls it. */
    private const RESOURCES = [
        'users'  => ['column' => 'max_users', 'table' => 'users', 'label' => 'staff accounts'],
        'tables' => ['column' => 'max_tables', 'table' => 'tables', 'label' => 'tables'],
    ];

    /** @return list<array<string,mixed>> */
    public static function all(bool $activeOnly = false): array
    {
        return Database::select(
            'SELECT * FROM plans'
            . ($activeOnly ? ' WHERE is_active = 1' : '')
            . ' ORDER BY sort_order ASC, id ASC',
        );
    }

    /** @return array<string,mixed>|null */
    public static function find(string $code): ?array
    {
        return Database::selectOne(
            'SELECT * FROM plans WHERE code = :c LIMIT 1',
            ['c' => strtolower(trim($code))],
        );
    }

    /**
     * The plan behind this restaurant's subscription.
     *
     * @return array<string,mixed>|null
     */
    public static function forRestaurant(int $restaurantId): ?array
    {
        try {
            return Database::selectOne(
                'SELECT p.*
                   FROM subscriptions s
                   JOIN plans p ON p.code = s.plan
                  WHERE s.restaurant_id = :rid
                  LIMIT 1',
                ['rid' => $restaurantId],
            );
        } catch (Throwable $e) {
            // The deploy uploads code a few seconds before it creates `plans`.
            // A missing table must not stop a restaurant adding a waiter in
            // that window — no plan simply means no limit.
            error_log('[dacaam] plan lookup: ' . $e->getMessage());

            return null;
        }
    }

    /**
     * How much of each limit is in use.
     *
     * @return array{users:int,tables:int}
     */
    public static function usage(int $restaurantId): array
    {
        $usage = [];

        foreach (self::RESOURCES as $key => $resource) {
            $usage[$key] = (int) Database::scalar(
                sprintf(
                    'SELECT COUNT(*) FROM `%s` WHERE restaurant_id = :rid AND is_active = 1',
                    $resource['table'],
                ),
                ['rid' => $restaurantId],
            );
        }

        return $usage;
    }

    /**
     * Refuses when one more active `$resource` would go past the plan.
     *
     * @param 'users'|'tables' $resource
     */
    public static function assertRoom(int $restaurantId, string $resource): void
    {
        $spec = self::RESOURCES[$resource];
        $plan = self::forRestaurant($restaurantId);
        $limit = (int) ($plan[$spec['column']] ?? 0);

        if ($limit === 0) {
            return;
        }

        $used = self::usage($restaurantId)[$resource];

        if ($used < $limit) {
            return;
        }

        throw new ApiException(
            sprintf(
                'The %s plan allows %d active %s and all are in use. '
                . 'Switch one off, or contact DACAAM to upgrade.',
                (string) $plan['name'],
                $limit,
                $spec['label'],
            ),
            422,
            'plan_limit',
        );
    }
}
