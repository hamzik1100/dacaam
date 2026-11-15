<?php

declare(strict_types=1);

namespace Dacaam\Support;

use Dacaam\Core\ApiException;
use Dacaam\Core\Database;

/**
 * Which shift a piece of money belongs to.
 *
 * Stamped at the moment a row is written rather than worked out later from
 * timestamps. Two shifts that meet at 18:00 would otherwise argue over a
 * payment taken at 18:00:00, and a handover done a minute out of order would
 * put money on the wrong person's count — which is exactly the person who then
 * has to explain it.
 */
final class Shifts
{
    /** @var array<string,?int> */
    private static array $cache = [];

    /**
     * The open shift on a till, or null when none is.
     *
     * Cached for the life of the request: one order writes several ledger rows
     * and they all belong to the same shift, so asking the database once is
     * enough.
     */
    public static function currentFor(int $restaurantId, int $accountId): ?int
    {
        $key = "$restaurantId:$accountId";

        if (array_key_exists($key, self::$cache)) {
            return self::$cache[$key];
        }

        $id = Database::scalar(
            'SELECT id FROM shifts
              WHERE restaurant_id = :rid AND account_id = :aid AND closed_at IS NULL
              LIMIT 1',
            ['rid' => $restaurantId, 'aid' => $accountId],
        );

        return self::$cache[$key] = ($id === null || $id === false) ? null : (int) $id;
    }

    /**
     * The open shift on the restaurant's cash drawer.
     *
     * Used to stamp orders, which belong to a session rather than to a
     * particular account — an order paid by Zaad still happened during
     * somebody's watch.
     */
    public static function currentTill(int $restaurantId): ?int
    {
        $key = "$restaurantId:till";

        if (array_key_exists($key, self::$cache)) {
            return self::$cache[$key];
        }

        $id = Database::scalar(
            'SELECT s.id FROM shifts s
               JOIN accounts a ON a.id = s.account_id
              WHERE s.restaurant_id = :rid AND s.closed_at IS NULL AND a.method = "cash"
              ORDER BY s.opened_at DESC LIMIT 1',
            ['rid' => $restaurantId],
        );

        return self::$cache[$key] = ($id === null || $id === false) ? null : (int) $id;
    }

    /**
     * Refuses to go on unless a till is open.
     *
     * Nothing can be sold outside a shift. The earlier design allowed it and
     * merely counted the strays, on the reasoning that a POS which refuses
     * money is worse than a hole in a report — but a hole you are allowed to
     * put money through is not a control, it is a suggestion. An order taken
     * with no till open belongs to nobody, appears in no count, and is
     * therefore the exact shape of the sale this whole feature exists to catch.
     *
     * The error carries its own code so the app can offer to open the till
     * rather than showing a dead end. Whoever hits it may not have the right to
     * open one themselves — a waiter does not — so the message says what needs
     * to happen, not what they did wrong.
     */
    public static function require(int $restaurantId): int
    {
        $id = self::currentTill($restaurantId);

        if ($id === null) {
            throw new ApiException(
                'Sanduuqa lama furin. Maamulaha ha furo si aad dalab u qaadid.',
                409,
                'shift_required',
            );
        }

        return $id;
    }

    /**
     * Refuses to touch an order whose shift has already been counted.
     *
     * A closed shift is a settled fact: the drawer was counted, the difference
     * was explained by somebody who put their name to it, and the balance was
     * corrected to match. Editing an order inside that window moves the total
     * the count was measured against — so the reconciliation silently stops
     * being true, and the variance that was signed off no longer corresponds to
     * anything. Worse, it is invisible: nothing recomputes, so the books simply
     * become quietly wrong.
     *
     * Correcting a mistake found afterwards is still possible; it is just not
     * done by rewriting a counted evening. Take it on today's shift, where it
     * lands in today's count and is explained by whoever makes it.
     */
    public static function requireOpen(int $restaurantId, ?int $shiftId): void
    {
        if ($shiftId === null) {
            return;
        }

        $closedAt = Database::scalar(
            'SELECT closed_at FROM shifts WHERE id = :id AND restaurant_id = :rid',
            ['id' => $shiftId, 'rid' => $restaurantId],
        );

        if ($closedAt === null || $closedAt === false) {
            return;
        }

        throw new ApiException(
            'Shiftkan waa la xidhay oo lacagtiisa waa la tiriyay. Dalabkan lama beddeli karo.',
            409,
            'shift_closed',
        );
    }

    /** Drops the cache. Opening or closing a shift changes the answer. */
    public static function forget(): void
    {
        self::$cache = [];
    }
}
