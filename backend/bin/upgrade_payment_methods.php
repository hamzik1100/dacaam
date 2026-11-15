<?php

declare(strict_types=1);

/**
 * Turns payment methods from a hardcoded ENUM into per-restaurant rows.
 *
 * Before: `method` was ENUM('cash','zaad','edahab','bank') in four tables, and
 * `accounts` carried UNIQUE(restaurant_id, method) — so a restaurant could hold
 * exactly one account per method and could never add a second bank, let alone a
 * method the ENUM had never heard of. Adding one meant an ALTER on four tables.
 *
 * After: a `payment_methods` table per restaurant. The `method` columns become
 * VARCHAR(32) holding the same codes they already hold, so not one existing row
 * changes meaning and nothing has to be rewritten. The unique key moves from
 * (restaurant_id, method) to (restaurant_id, name), which is the constraint that
 * was actually wanted: two banks, distinct names.
 *
 * Idempotent — every step checks information_schema first. Safe to re-run.
 *
 *   php bin/upgrade_payment_methods.php
 *   php bin/upgrade_payment_methods.php --dry-run
 */

require __DIR__ . '/../bootstrap.php';

use Dacaam\Core\Database;

$dry = in_array('--dry-run', $argv, true);

$schema = (string) Database::scalar('SELECT DATABASE()');
if ($schema === '') {
    fwrite(STDERR, "No database selected — check config.\n");
    exit(1);
}

/** Statements actually run, for the summary at the end. */
$done    = [];
$skipped = [];

$say = static function (string $line): void {
    fwrite(STDOUT, $line . "\n");
};

$exec = static function (string $sql, string $label) use ($dry, &$done, $say): void {
    if ($dry) {
        $say("  would apply: $label");
        $done[] = $label;

        return;
    }

    Database::run($sql);
    $say("  applied: $label");
    $done[] = $label;
};

$columnType = static function (string $table, string $column) use ($schema): ?string {
    return Database::scalar(
        'SELECT COLUMN_TYPE FROM information_schema.COLUMNS
          WHERE TABLE_SCHEMA = :s AND TABLE_NAME = :t AND COLUMN_NAME = :c',
        ['s' => $schema, 't' => $table, 'c' => $column],
    );
};

$indexExists = static function (string $table, string $index) use ($schema): bool {
    return (int) Database::scalar(
        'SELECT COUNT(*) FROM information_schema.STATISTICS
          WHERE TABLE_SCHEMA = :s AND TABLE_NAME = :t AND INDEX_NAME = :i',
        ['s' => $schema, 't' => $table, 'i' => $index],
    ) > 0;
};

$tableExists = static function (string $table) use ($schema): bool {
    return (int) Database::scalar(
        'SELECT COUNT(*) FROM information_schema.TABLES
          WHERE TABLE_SCHEMA = :s AND TABLE_NAME = :t',
        ['s' => $schema, 't' => $table],
    ) > 0;
};

$say(sprintf("Database: %s%s\n", $schema, $dry ? '  (DRY RUN — nothing is written)' : ''));

// ------------------------------------------------------------ 1. the table

$say('1. payment_methods table');

if ($tableExists('payment_methods')) {
    $say('  already present — skipped');
    $skipped[] = 'create payment_methods';
} else {
    $exec(
        "CREATE TABLE `payment_methods` (
          `id`            INT UNSIGNED NOT NULL AUTO_INCREMENT,
          `restaurant_id` INT UNSIGNED NOT NULL,
          `code`          VARCHAR(32)  NOT NULL COMMENT 'what lands in accounts/order_payments/expenses.method',
          `name`          VARCHAR(64)  NOT NULL,
          `is_active`     TINYINT(1)   NOT NULL DEFAULT 1,
          `is_system`     TINYINT(1)   NOT NULL DEFAULT 0 COMMENT 'renameable, never removable',
          `sort_order`    SMALLINT UNSIGNED NOT NULL DEFAULT 0,
          `created_at`    TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
          `updated_at`    TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
          PRIMARY KEY (`id`),
          UNIQUE KEY `uq_payment_methods_restaurant_code` (`restaurant_id`, `code`),
          KEY `ix_payment_methods_restaurant_active` (`restaurant_id`, `is_active`),
          CONSTRAINT `fk_payment_methods_restaurant` FOREIGN KEY (`restaurant_id`)
            REFERENCES `restaurants` (`id`) ON DELETE CASCADE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci",
        'create payment_methods',
    );
}

// --------------------------------------------------- 2. ENUM -> VARCHAR(32)

$say("\n2. method columns: ENUM -> VARCHAR(32)");

$columns = [
    ['accounts',              'method', 'NOT NULL'],
    ['order_payments',        'method', 'NOT NULL'],
    ['expenses',              'method', "NOT NULL DEFAULT 'cash'"],
    ['subscription_payments', 'method', "NOT NULL DEFAULT 'bank'"],
];

foreach ($columns as [$table, $column, $tail]) {
    if (!$tableExists($table)) {
        $say("  $table missing — skipped");
        $skipped[] = "$table.$column";
        continue;
    }

    $type = $columnType($table, $column);

    if ($type === null) {
        $say("  $table.$column missing — skipped");
        $skipped[] = "$table.$column";
        continue;
    }

    if (stripos($type, 'enum') !== 0) {
        $say("  $table.$column is already $type — skipped");
        $skipped[] = "$table.$column";
        continue;
    }

    // MODIFY on ENUM -> VARCHAR keeps every stored label verbatim.
    $exec(
        "ALTER TABLE `$table` MODIFY COLUMN `$column` VARCHAR(32) $tail",
        "$table.$column -> VARCHAR(32)",
    );
}

// -------------------------------------------------------- 3. the unique key

$say("\n3. accounts unique key");

// Order matters. fk_accounts_restaurant leans on uq_accounts_restaurant_method
// for its index — InnoDB refuses to drop the last index a foreign key can use,
// with "needed in a foreign key constraint". Put the replacement in first, then
// the old key is free to go.
if ($indexExists('accounts', 'ix_accounts_restaurant_method')) {
    $say('  KEY(restaurant_id, method) already present — skipped');
    $skipped[] = 'add ix_accounts_restaurant_method';
} else {
    $exec(
        'ALTER TABLE `accounts` ADD KEY `ix_accounts_restaurant_method` (`restaurant_id`, `method`)',
        'add KEY(restaurant_id, method)',
    );
}

if ($indexExists('accounts', 'uq_accounts_restaurant_method')) {
    $exec(
        'ALTER TABLE `accounts` DROP INDEX `uq_accounts_restaurant_method`',
        'drop UNIQUE(restaurant_id, method)',
    );
} else {
    $say('  UNIQUE(restaurant_id, method) already gone — skipped');
    $skipped[] = 'drop uq_accounts_restaurant_method';
}

if ($indexExists('accounts', 'uq_accounts_restaurant_name')) {
    $say('  UNIQUE(restaurant_id, name) already present — skipped');
    $skipped[] = 'add uq_accounts_restaurant_name';
} else {
    // Two banks are fine; two accounts both called "Bank" are not.
    $duplicates = Database::select(
        'SELECT `restaurant_id`, `name`, COUNT(*) AS n
           FROM `accounts` GROUP BY `restaurant_id`, `name` HAVING n > 1',
    );

    if ($duplicates !== []) {
        $say('  WARNING: duplicate account names exist, unique key not added:');
        foreach ($duplicates as $row) {
            $say(sprintf('    restaurant %s: "%s" x%s', $row['restaurant_id'], $row['name'], $row['n']));
        }
        $skipped[] = 'add uq_accounts_restaurant_name (duplicates present)';
    } else {
        $exec(
            'ALTER TABLE `accounts` ADD UNIQUE KEY `uq_accounts_restaurant_name` (`restaurant_id`, `name`)',
            'add UNIQUE(restaurant_id, name)',
        );
    }
}

// ------------------------------------------------------------ 4. backfill

$say("\n4. backfill payment_methods");

$defaults = [
    ['cash',   'Cash',   10],
    ['zaad',   'Zaad',   20],
    ['edahab', 'eDahab', 30],
    ['bank',   'Bank',   40],
];

$restaurants = Database::select('SELECT `id`, `slug` FROM `restaurants` ORDER BY `id`');

if ($restaurants === []) {
    $say('  no restaurants yet — nothing to backfill');
}

foreach ($restaurants as $restaurant) {
    $rid   = (int) $restaurant['id'];
    $added = 0;

    // Whatever the ENUM allowed, plus anything the data actually uses, so a
    // method already recorded against a real order never goes unnamed.
    $codes = [];
    foreach ($defaults as [$code, $name, $sort]) {
        $codes[$code] = [$name, $sort, 1];
    }

    foreach (['accounts', 'order_payments', 'expenses'] as $table) {
        if (!$tableExists($table)) {
            continue;
        }

        $used = Database::select(
            "SELECT DISTINCT `method` FROM `$table` WHERE `restaurant_id` = :rid",
            ['rid' => $rid],
        );

        foreach ($used as $row) {
            $code = (string) $row['method'];
            if ($code !== '' && !isset($codes[$code])) {
                $codes[$code] = [ucfirst($code), 90, 0];
            }
        }
    }

    // On a dry run the table above was never created, so there is nothing to
    // query — every code counts as one that would be inserted.
    $canQuery = $tableExists('payment_methods');

    foreach ($codes as $code => [$name, $sort, $system]) {
        if ($canQuery) {
            $exists = (int) Database::scalar(
                'SELECT COUNT(*) FROM `payment_methods` WHERE `restaurant_id` = :rid AND `code` = :c',
                ['rid' => $rid, 'c' => $code],
            );

            if ($exists > 0) {
                continue;
            }
        }

        if ($dry) {
            $added++;
            continue;
        }

        Database::insert('payment_methods', [
            'restaurant_id' => $rid,
            'code'          => $code,
            'name'          => $name,
            'is_system'     => $system,
            'sort_order'    => $sort,
        ]);
        $added++;
    }

    $say(sprintf('  %-8s %d method(s) added', $restaurant['slug'], $added));
}

// -------------------------------------------------------------- 5. summary

$say("\n" . str_repeat('-', 60));
$say(sprintf('%d change(s) applied, %d already in place.', count($done), count($skipped)));

if ($dry) {
    $say('Dry run — re-run without --dry-run to write.');
}
