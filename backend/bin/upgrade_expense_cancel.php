<?php

declare(strict_types=1);

/**
 * Expenses are cancelled, never deleted.
 *
 * A deleted expense leaves the books unable to answer "what happened to the
 * 400,000 that was recorded on Tuesday and is not there now" — the row is gone,
 * so the only honest answer is that nobody knows. Cancelling keeps the entry,
 * marks it void, records who did it and why, and takes it out of the totals.
 *
 * Idempotent, like the rest of the chain.
 */

use Dacaam\Core\Database;

require dirname(__DIR__) . '/bootstrap.php';

$hasColumn = static function (string $table, string $column): bool {
    return (int) Database::scalar(
        'SELECT COUNT(*) FROM information_schema.columns
          WHERE table_schema = DATABASE() AND table_name = :t AND column_name = :c',
        ['t' => $table, 'c' => $column],
    ) > 0;
};

$made = 0;

$columns = [
    'cancelled_at'    => 'DATETIME NULL DEFAULT NULL',
    'cancel_reason'   => 'VARCHAR(255) NULL DEFAULT NULL',
    'cancelled_by'    => 'INT UNSIGNED NULL DEFAULT NULL',
];

foreach ($columns as $column => $definition) {
    if ($hasColumn('expenses', $column)) {
        continue;
    }

    Database::run("ALTER TABLE `expenses` ADD COLUMN `$column` $definition");
    echo "expenses.$column: waa la daray.\n";
    $made++;
}

// Every report that sums spend now has to skip the cancelled rows, and every
// one of those queries filters on restaurant and date first. Without this the
// filter is a table scan on the busiest reporting query in the system.
$hasIndex = (int) Database::scalar(
    'SELECT COUNT(*) FROM information_schema.statistics
      WHERE table_schema = DATABASE() AND table_name = "expenses"
        AND index_name = "ix_expenses_live"',
) > 0;

if (!$hasIndex) {
    Database::run(
        'CREATE INDEX `ix_expenses_live` ON `expenses` (`restaurant_id`, `cancelled_at`, `expense_date`)',
    );
    echo "expenses: ix_expenses_live waa la abuuray.\n";
    $made++;
}

echo "\n";
echo $made === 0
    ? "Wax cusub ma jirin — horeba wuu u diyaar ahaa.\n"
    : "$made isbeddel ayaa la sameeyay.\n";
