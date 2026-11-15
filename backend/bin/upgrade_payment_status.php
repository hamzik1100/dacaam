<?php

declare(strict_types=1);

/**
 * Separates "is the food done" from "has anyone paid".
 *
 * `orders.status` carried both until now, which worked only while every order
 * was paid at the counter. A credit order breaks it: the food is finished and
 * the money is not there, and the single column has to choose which fact to
 * record. It chose wrong in both directions — a credit order either sat in
 * `preparing` forever or claimed to be settled.
 *
 * Existing rows are backfilled from what was actually paid against them, so
 * history keeps its meaning rather than defaulting to a guess.
 *
 * Idempotent.
 *
 *   php bin/upgrade_payment_status.php
 */

require __DIR__ . '/../bootstrap.php';

use Dacaam\Core\Database;

$schema = (string) Database::scalar('SELECT DATABASE()');

$has = (int) Database::scalar(
    'SELECT COUNT(*) FROM information_schema.COLUMNS
      WHERE TABLE_SCHEMA = :s AND TABLE_NAME = "orders" AND COLUMN_NAME = "payment_status"',
    ['s' => $schema],
) > 0;

if ($has) {
    fwrite(STDOUT, "orders.payment_status horeba wuu jiray.\n");

    return;
}

Database::run(
    "ALTER TABLE `orders`
       ADD COLUMN `payment_status` ENUM('unpaid','partial','paid')
       NOT NULL DEFAULT 'unpaid' AFTER `status`",
);

fwrite(STDOUT, "orders.payment_status waa la daray.\n");

// Backfill from the payments themselves. Rounded to two places before
// comparing: several part-payments summed as DECIMAL can land a hundredth of a
// shilling short of the total, and an order short by that is paid.
$updated = Database::run(
    'UPDATE orders o
        SET o.payment_status = CASE
            WHEN COALESCE((SELECT ROUND(SUM(p.amount), 2) FROM order_payments p
                            WHERE p.order_id = o.id), 0) >= ROUND(o.total, 2) THEN "paid"
            WHEN COALESCE((SELECT SUM(p.amount) FROM order_payments p
                            WHERE p.order_id = o.id), 0) > 0 THEN "partial"
            ELSE "unpaid"
        END',
)->rowCount();

fwrite(STDOUT, sprintf("%d dalab oo la buuxiyay.\n", $updated));

$counts = Database::select(
    'SELECT payment_status, COUNT(*) AS n FROM orders GROUP BY payment_status',
);

foreach ($counts as $row) {
    fwrite(STDOUT, sprintf("  %-8s %d\n", $row['payment_status'], $row['n']));
}
