<?php

declare(strict_types=1);

namespace DacaamAdmin\Core;

use Dacaam\Core\Database;

/**
 * Platform action trail.
 *
 * Deliberately not the tenant `audit_logs` table: that one is scoped to a
 * restaurant and readable by that restaurant's admins, and "the platform
 * suspended you" is not a line a tenant should be able to read, edit around,
 * or mistake for one of their own staff's actions.
 */
final class PlatformAudit
{
    public static function log(
        string $action,
        ?int $restaurantId = null,
        string $detail = '',
        string $ip = '',
    ): void {
        $admin = $_SESSION['super_admin_id'] ?? null;
        $name = '';

        if (is_int($admin)) {
            $row = Database::selectOne(
                'SELECT name FROM super_admins WHERE id = :id',
                ['id' => $admin],
            );
            $name = (string) ($row['name'] ?? '');
        }

        Database::insert('platform_audit_logs', [
            'super_admin_id' => is_int($admin) ? $admin : null,
            'admin_name'     => $name,
            'action'         => $action,
            'restaurant_id'  => $restaurantId,
            'detail'         => substr($detail, 0, 500),
            'ip'             => $ip !== '' ? $ip : (string) ($_SERVER['REMOTE_ADDR'] ?? ''),
        ]);
    }
}
