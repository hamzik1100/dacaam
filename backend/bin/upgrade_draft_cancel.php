<?php

declare(strict_types=1);

/**
 * Gives draft_orders somewhere to record why a draft was refused.
 *
 * §22 lists Cancelled among the draft statuses and §46 requires a reason, but
 * the column was never added and `destroy` hard-deleted the row instead. A
 * customer who changes their mind left no trace at all — the draft simply
 * vanished, and nobody could later ask how often that happens or why.
 *
 * Idempotent: checks information_schema first, so it is safe on every deploy.
 *
 *   php bin/upgrade_draft_cancel.php
 */

require __DIR__ . '/../bootstrap.php';

use Dacaam\Core\Database;

$schema = (string) Database::scalar('SELECT DATABASE()');

$has = static function (string $table, string $column) use ($schema): bool {
    return (int) Database::scalar(
        'SELECT COUNT(*) FROM information_schema.COLUMNS
          WHERE TABLE_SCHEMA = :s AND TABLE_NAME = :t AND COLUMN_NAME = :c',
        ['s' => $schema, 't' => $table, 'c' => $column],
    ) > 0;
};

if ($has('draft_orders', 'cancel_reason')) {
    fwrite(STDOUT, "draft_orders.cancel_reason horeba wuu jiray.\n");

    return;
}

Database::run(
    "ALTER TABLE `draft_orders`
       ADD COLUMN `cancel_reason` VARCHAR(255) NULL DEFAULT NULL AFTER `status`",
);

fwrite(STDOUT, "draft_orders.cancel_reason waa la daray.\n");
