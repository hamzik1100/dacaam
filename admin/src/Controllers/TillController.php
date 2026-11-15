<?php

declare(strict_types=1);

namespace DacaamAdmin\Controllers;

use DacaamAdmin\Core\View;
use Dacaam\Core\Database;

/**
 * Cash variance across every restaurant.
 *
 * The owner of one restaurant sees their own till in the app. Nobody sees the
 * pattern across all of them, and the pattern is where this becomes useful: one
 * shop short on a Tuesday is a Tuesday, and one shop short on nineteen evenings
 * out of twenty while every other shop balances is not.
 *
 * Deliberately shows totals rather than accusations. A till that is short every
 * night by a similar amount is more often a float that was never counted
 * properly, or change given from the wrong drawer, than it is theft — and a page
 * that leads with the second reading gets somebody fired over an arithmetic
 * habit. What it does is put the number somewhere it can be asked about.
 */
final class TillController
{
    /** How far back the page looks. Long enough for a habit to show. */
    private const DAYS = 30;

    public function index(): void
    {
        if (!self::ready()) {
            View::page('tills', [
                'title'       => 'Tills',
                'nav'         => 'tills',
                'ready'       => false,
                'restaurants' => [],
                'recent'      => [],
                'people'      => [],
                'totals'      => ['shifts' => 0, 'short' => 0, 'over' => 0, 'net' => 0.0],
            ]);

            return;
        }

        View::page('tills', [
            'title'       => 'Tills',
            'nav'         => 'tills',
            'ready'       => true,
            'days'        => self::DAYS,
            'restaurants' => self::byRestaurant(),
            'recent'      => self::recent(),
            'people'      => self::byPerson(),
            'totals'      => self::totals(),
        ]);
    }

    /**
     * A database that has not run the shift migration yet.
     *
     * Answering with an empty page rather than a 500 matters here: this
     * dashboard is how the platform finds out it is broken, so it must not be
     * the thing that breaks.
     */
    private static function ready(): bool
    {
        return (int) Database::scalar(
            'SELECT COUNT(*) FROM information_schema.tables
              WHERE table_schema = DATABASE() AND table_name = "shifts"',
        ) > 0;
    }

    /**
     * Each restaurant's record, worst first.
     *
     * @return list<array<string,mixed>>
     */
    private static function byRestaurant(): array
    {
        return Database::select(
            'SELECT r.id, r.slug, r.name,
                    COUNT(s.id)                                        AS closes,
                    SUM(CASE WHEN s.variance < -0.01 THEN 1 ELSE 0 END) AS short_count,
                    SUM(CASE WHEN s.variance >  0.01 THEN 1 ELSE 0 END) AS over_count,
                    COALESCE(SUM(s.variance), 0)                       AS net,
                    COALESCE(SUM(CASE WHEN s.variance < 0 THEN s.variance ELSE 0 END), 0) AS shortfall,
                    COALESCE(SUM(s.orders_outside), 0)                 AS outside,
                    MAX(s.closed_at)                                   AS last_close
               FROM restaurants r
               JOIN shifts s ON s.restaurant_id = r.id AND s.closed_at IS NOT NULL
              WHERE s.closed_at >= DATE_SUB(NOW(), INTERVAL ' . self::DAYS . ' DAY)
              GROUP BY r.id, r.slug, r.name
              ORDER BY shortfall ASC',
        );
    }

    /**
     * The individual closes worth looking at.
     *
     * Only the ones that did not balance. A list that includes every clean
     * close is a list nobody scrolls to the bottom of.
     *
     * @return list<array<string,mixed>>
     */
    private static function recent(): array
    {
        return Database::select(
            'SELECT s.id, s.variance, s.expected_close, s.counted_close,
                    s.close_reason, s.closed_at, s.orders_outside,
                    s.overnight_diff,
                    r.slug, r.name AS restaurant,
                    u.name AS closed_by
               FROM shifts s
               JOIN restaurants r ON r.id = s.restaurant_id
          LEFT JOIN users u ON u.id = s.closed_by
              WHERE s.closed_at IS NOT NULL
                AND ABS(COALESCE(s.variance, 0)) > 0.01
                AND s.closed_at >= DATE_SUB(NOW(), INTERVAL ' . self::DAYS . ' DAY)
              ORDER BY s.closed_at DESC
              LIMIT 40',
        );
    }

    /**
     * By the person who counted.
     *
     * This is the column the whole page exists for. A till is a place; a
     * variance belongs to whoever was standing at it, and the same name against
     * the same sign, night after night, is the only thing here that means
     * something on its own.
     *
     * @return list<array<string,mixed>>
     */
    private static function byPerson(): array
    {
        return Database::select(
            'SELECT u.name, r.slug,
                    COUNT(s.id)                                        AS closes,
                    SUM(CASE WHEN s.variance < -0.01 THEN 1 ELSE 0 END) AS short_count,
                    COALESCE(SUM(s.variance), 0)                       AS net
               FROM shifts s
               JOIN restaurants r ON r.id = s.restaurant_id
               JOIN users u ON u.id = s.closed_by
              WHERE s.closed_at IS NOT NULL
                AND s.closed_at >= DATE_SUB(NOW(), INTERVAL ' . self::DAYS . ' DAY)
              GROUP BY u.id, u.name, r.slug
             HAVING closes >= 3
              ORDER BY net ASC
              LIMIT 20',
        );
    }

    /** @return array<string,mixed> */
    private static function totals(): array
    {
        $row = Database::selectOne(
            'SELECT COUNT(*) AS shifts,
                    SUM(CASE WHEN variance < -0.01 THEN 1 ELSE 0 END) AS `short`,
                    SUM(CASE WHEN variance >  0.01 THEN 1 ELSE 0 END) AS `over`,
                    COALESCE(SUM(variance), 0) AS net
               FROM shifts
              WHERE closed_at IS NOT NULL
                AND closed_at >= DATE_SUB(NOW(), INTERVAL ' . self::DAYS . ' DAY)',
        ) ?? [];

        return [
            'shifts' => (int) ($row['shifts'] ?? 0),
            'short'  => (int) ($row['short'] ?? 0),
            'over'   => (int) ($row['over'] ?? 0),
            'net'    => (float) ($row['net'] ?? 0),
        ];
    }
}
