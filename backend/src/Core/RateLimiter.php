<?php

declare(strict_types=1);

namespace Dacaam\Core;

/**
 * Fixed-window request throttling.
 *
 * Guards the endpoints that can be attacked without a token — sign-in, the
 * 2FA exchange, password reset — where the only other cost to an attacker is
 * bandwidth. Per-user lockout already exists (five bad passwords locks the
 * account); this is the other half, because an attacker spraying one password
 * across a thousand phone numbers never trips a per-user counter.
 *
 * Fixed windows, not a sliding log: a sliding window means storing every hit,
 * and the extra precision buys nothing when the limits are this coarse. The
 * documented cost is that a caller can spend a full window's budget at the end
 * of one window and again at the start of the next.
 */
final class RateLimiter
{
    /** How often, roughly, a request also sweeps away stale buckets. */
    private const PRUNE_ODDS = 200;

    /**
     * Counts one hit against `$bucket` and throws 429 once `$max` is exceeded.
     *
     * The increment and the read are two statements, so a burst arriving in
     * the same millisecond can slip one or two extra requests through. That is
     * acceptable for a throttle — it bounds an attacker to roughly the limit,
     * which is the point — and the alternative is holding a row lock across
     * every login on the system.
     */
    public static function hit(string $bucket, int $max, int $windowSeconds): void
    {
        if (!Config::get('throttle.enabled', true)) {
            return;
        }

        $bucket = substr($bucket, 0, 190);

        Database::run(
            'INSERT INTO rate_limits (bucket, hits, window_started_at)
             VALUES (:bucket, 1, NOW())
             ON DUPLICATE KEY UPDATE
               hits = IF(window_started_at <= DATE_SUB(NOW(), INTERVAL :expiry SECOND), 1, hits + 1),
               window_started_at = IF(window_started_at <= DATE_SUB(NOW(), INTERVAL :expiry2 SECOND), NOW(), window_started_at)',
            [
                'bucket'  => $bucket,
                'expiry'  => $windowSeconds,
                'expiry2' => $windowSeconds,
            ],
        );

        $row = Database::selectOne(
            'SELECT hits,
                    TIMESTAMPDIFF(SECOND, window_started_at, NOW()) AS age
               FROM rate_limits WHERE bucket = :bucket',
            ['bucket' => $bucket],
        );

        self::pruneOccasionally();

        if ($row === null || (int) $row['hits'] <= $max) {
            return;
        }

        $retryAfter = max(1, $windowSeconds - (int) $row['age']);
        header('Retry-After: ' . $retryAfter);

        throw new ApiException(
            'Too many attempts. Try again in ' . self::humanise($retryAfter) . '.',
            429,
            'rate_limited',
        );
    }

    /** Clears a bucket after a success, so one good sign-in resets the count. */
    public static function clear(string $bucket): void
    {
        Database::run(
            'DELETE FROM rate_limits WHERE bucket = :bucket',
            ['bucket' => substr($bucket, 0, 190)],
        );
    }

    /** Bucket key for a caller's address. */
    public static function forIp(string $name, string $ip): string
    {
        return $name . '|' . ($ip === '' ? 'unknown' : $ip);
    }

    /**
     * Bucket key for a claimed identity.
     *
     * Hashed because the raw value is a phone number and a restaurant code,
     * and a throttling table is not a place to accumulate a directory of who
     * banks where.
     */
    public static function forIdentity(string $name, string $identity): string
    {
        return $name . '|' . substr(hash('sha256', strtolower(trim($identity))), 0, 32);
    }

    /**
     * Rows outlive their window by design — the next hit rewrites them in
     * place — so this is housekeeping, not correctness.
     */
    private static function pruneOccasionally(): void
    {
        if (random_int(1, self::PRUNE_ODDS) !== 1) {
            return;
        }

        Database::run(
            'DELETE FROM rate_limits WHERE window_started_at < DATE_SUB(NOW(), INTERVAL 1 DAY)',
        );
    }

    private static function humanise(int $seconds): string
    {
        if ($seconds < 60) {
            return $seconds . ' second' . ($seconds === 1 ? '' : 's');
        }

        $minutes = (int) ceil($seconds / 60);

        return $minutes . ' minute' . ($minutes === 1 ? '' : 's');
    }
}
