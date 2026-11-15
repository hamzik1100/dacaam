<?php

declare(strict_types=1);

namespace Dacaam\Repositories;

use Dacaam\Core\ApiException;
use Dacaam\Core\Database;

/**
 * Shared tenant-scoped reads.
 *
 * Every lookup here requires a restaurant id. There is no `find($id)` without
 * a tenant anywhere in the codebase, which is what stops a mistyped join or a
 * copy-pasted query from leaking across restaurants.
 */
abstract class Repository
{
    /** @return array<string,mixed> */
    protected static function requireScoped(
        string $table,
        int $id,
        int $restaurantId,
        string $notFoundMessage,
        string $columns = '*',
    ): array {
        $row = Database::selectOne(
            sprintf('SELECT %s FROM `%s` WHERE id = :id AND restaurant_id = :rid LIMIT 1', $columns, $table),
            ['id' => $id, 'rid' => $restaurantId],
        );

        // Deliberately a 404, not a 403: confirming that a row exists but
        // belongs elsewhere would itself leak information across tenants.
        if ($row === null) {
            throw ApiException::notFound($notFoundMessage);
        }

        return $row;
    }

    /** @return array<string,mixed> */
    public static function settings(int $restaurantId): array
    {
        $row = Database::selectOne(
            'SELECT * FROM restaurant_settings WHERE restaurant_id = :rid LIMIT 1',
            ['rid' => $restaurantId],
        );

        if ($row === null) {
            // A tenant without a settings row would silently price everything
            // at zero tax and no packaging; create the documented defaults.
            Database::insert('restaurant_settings', ['restaurant_id' => $restaurantId]);

            $row = Database::selectOne(
                'SELECT * FROM restaurant_settings WHERE restaurant_id = :rid LIMIT 1',
                ['rid' => $restaurantId],
            ) ?? [];
        }

        return $row;
    }
}
