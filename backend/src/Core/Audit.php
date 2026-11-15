<?php

declare(strict_types=1);

namespace Dacaam\Core;

use Dacaam\Support\Alerts;

/**
 * Audit trail writer.
 *
 * One table backs both the global Audit Logs screen and an individual order's
 * timeline — filtering by `module` + `record_id` gives the per-order history
 * without a second, divergent log.
 */
final class Audit
{
    public static function log(
        AuthContext $context,
        string $module,
        string $action,
        ?int $recordId = null,
        string $field = '',
        ?string $oldValue = null,
        ?string $newValue = null,
        ?string $reason = null,
    ): void {
        Database::insert('audit_logs', [
            'restaurant_id' => $context->restaurantId,
            'user_id'       => $context->userId,
            'user_name'     => $context->userName,
            'module'        => $module,
            'action'        => $action,
            'record_id'     => $recordId,
            'field'         => $field,
            'old_value'     => self::truncate($oldValue),
            'new_value'     => self::truncate($newValue),
            'reason'        => $reason === null ? null : substr($reason, 0, 255),
            'ip'            => $context->ip,
            'device'        => $context->device,
        ]);

        // The owner is not at the till. Alerts hang off the audit trail rather
        // than off the controllers, so an action that is worth recording is
        // automatically an action that has been considered for an alert — and
        // a new one cannot ship having been wired into only half of them.
        //
        // Inside the caller's transaction on purpose: an edit that rolls back
        // takes its alert with it, and nobody is told about a sale that never
        // happened.
        Alerts::record(
            $context,
            $module,
            $action,
            $recordId,
            $field,
            $oldValue,
            $newValue,
            $reason,
        );
    }

    /**
     * Logs one entry per changed field. Unchanged fields are skipped so the
     * trail records what actually happened, not what was submitted.
     *
     * @param array<string,mixed> $before
     * @param array<string,mixed> $after
     * @param list<string>        $fields
     */
    public static function diff(
        AuthContext $context,
        string $module,
        string $action,
        int $recordId,
        array $before,
        array $after,
        array $fields,
        ?string $reason = null,
    ): void {
        foreach ($fields as $field) {
            if (!array_key_exists($field, $after)) {
                continue;
            }

            $old = self::stringify($before[$field] ?? null);
            $new = self::stringify($after[$field]);
            if ($old === $new) {
                continue;
            }

            self::log(
                $context,
                module: $module,
                action: $action,
                recordId: $recordId,
                field: $field,
                oldValue: $old,
                newValue: $new,
                reason: $reason,
            );
        }
    }

    private static function stringify(mixed $value): ?string
    {
        if ($value === null) {
            return null;
        }
        if (is_bool($value)) {
            return $value ? '1' : '0';
        }
        if (is_scalar($value)) {
            return (string) $value;
        }

        return json_encode($value, JSON_UNESCAPED_UNICODE) ?: null;
    }

    private static function truncate(?string $value): ?string
    {
        return $value === null ? null : substr($value, 0, 500);
    }
}
