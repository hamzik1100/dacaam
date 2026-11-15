<?php

declare(strict_types=1);

namespace Dacaam\Support;

use Dacaam\Core\Database;
use PDOException;

/**
 * Makes a money request safe to send twice.
 *
 * A deposit that reaches the server twice is two deposits, and the second one
 * is indistinguishable from a real second deposit — same customer, same amount,
 * same minute. The client cannot tell either: a request that times out may have
 * been applied or may not, and both retrying and not retrying can be wrong.
 *
 * So the client names the action instead. It generates a key once, for that one
 * tap, and reuses it on every retry of that tap. The unique index on
 * `request_keys` decides: the first insert wins and does the work, and any
 * later one finds the row and replays what the first returned.
 *
 * Deliberately opt-in per endpoint. Only the handlers that move money need it,
 * and a key on a read would be noise.
 */
final class Idempotency
{
    private function __construct()
    {
    }

    /**
     * Runs [work] once for a given key.
     *
     * With no key the work simply runs — older clients keep working, which
     * matters because a shipped APK cannot be updated in step with the server.
     *
     * @template T of array<string,mixed>
     * @param  callable():array<string,mixed> $work
     * @return array<string,mixed>
     */
    public static function once(
        int $restaurantId,
        ?string $key,
        string $endpoint,
        callable $work,
    ): array {
        $key = $key === null ? '' : trim($key);

        if ($key === '' || mb_strlen($key) > 64) {
            return $work();
        }

        try {
            Database::insert('request_keys', [
                'restaurant_id' => $restaurantId,
                'request_key'   => $key,
                'endpoint'      => $endpoint,
            ]);
        } catch (PDOException $e) {
            // 23000 is the integrity-constraint family, which here means the
            // unique index rejected a key we have already seen. Anything else
            // is a real database problem and belongs upstairs.
            if (!str_starts_with((string) $e->getCode(), '23')) {
                throw $e;
            }

            return self::replay($restaurantId, $key);
        }

        $result = $work();

        // Stored after the work, so a failure leaves no key claiming success —
        // the row exists but with a null response, and a retry gets the same
        // answer it would have without idempotency rather than a false one.
        Database::run(
            'UPDATE request_keys SET response = :r
              WHERE restaurant_id = :rid AND request_key = :k',
            [
                'r'   => json_encode($result),
                'rid' => $restaurantId,
                'k'   => $key,
            ],
        );

        return $result;
    }

    /** @return array<string,mixed> */
    private static function replay(int $restaurantId, string $key): array
    {
        $stored = Database::scalar(
            'SELECT response FROM request_keys
              WHERE restaurant_id = :rid AND request_key = :k',
            ['rid' => $restaurantId, 'k' => $key],
        );

        // A null response means the first attempt claimed the key and then
        // failed or is still running. Saying so is better than replaying an
        // empty success or repeating the work behind its back.
        if ($stored === null || $stored === '') {
            throw \Dacaam\Core\ApiException::conflict(
                'That request is already being processed',
            );
        }

        $decoded = json_decode((string) $stored, true);

        return is_array($decoded) ? $decoded : [];
    }
}
