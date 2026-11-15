<?php

declare(strict_types=1);

/**
 * Links orders to customer accounts.
 *
 * `orders.customer_name` is free text and stays that way — it is what every
 * order taken before customers existed has, and it still reads fine on a
 * receipt. `customer_id` is the new, optional link to a real account, set only
 * when an order is put on somebody's tab.
 *
 * No backfill is attempted, deliberately. Matching "Hamse" against "hamze A"
 * would attach a real debt to the wrong person, and a wrong debt is worse than
 * no history.
 *
 * Idempotent — checks information_schema before touching anything.
 *
 *   php bin/upgrade_customer_orders.php
 */

require __DIR__ . '/../bootstrap.php';

use Dacaam\Core\Database;

$schema = (string) Database::scalar('SELECT DATABASE()');

$hasColumn = static function (string $table, string $column) use ($schema): bool {
    return (int) Database::scalar(
        'SELECT COUNT(*) FROM information_schema.COLUMNS
          WHERE TABLE_SCHEMA = :s AND TABLE_NAME = :t AND COLUMN_NAME = :c',
        ['s' => $schema, 't' => $table, 'c' => $column],
    ) > 0;
};

$hasIndex = static function (string $table, string $index) use ($schema): bool {
    return (int) Database::scalar(
        'SELECT COUNT(*) FROM information_schema.STATISTICS
          WHERE TABLE_SCHEMA = :s AND TABLE_NAME = :t AND INDEX_NAME = :i',
        ['s' => $schema, 't' => $table, 'i' => $index],
    ) > 0;
};

if ($hasColumn('orders', 'customer_id')) {
    fwrite(STDOUT, "orders.customer_id horeba wuu jiray.\n");
} else {
    Database::run(
        'ALTER TABLE `orders`
           ADD COLUMN `customer_id` INT UNSIGNED NULL DEFAULT NULL AFTER `waiter_name`',
    );
    fwrite(STDOUT, "orders.customer_id waa la daray.\n");
}

if ($hasIndex('orders', 'ix_orders_customer')) {
    fwrite(STDOUT, "ix_orders_customer horeba wuu jiray.\n");
} else {
    Database::run(
        'ALTER TABLE `orders` ADD KEY `ix_orders_customer` (`customer_id`, `created_at`)',
    );
    fwrite(STDOUT, "ix_orders_customer waa la daray.\n");
}
