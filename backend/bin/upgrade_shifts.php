<?php

declare(strict_types=1);

/**
 * Shift close — counting the drawer against what the system says.
 *
 * Everything else in this system watches actions that were recorded. The theft
 * that beats all of it is the sale nobody entered, and no audit trail can see
 * that one: there is nothing to audit. Counting the cash can, because the
 * drawer does not lie.
 *
 * Idempotent, like the rest of the chain.
 */

use Dacaam\Core\Database;

require dirname(__DIR__) . '/bootstrap.php';

$hasTable = static function (string $table): bool {
    return (int) Database::scalar(
        'SELECT COUNT(*) FROM information_schema.tables
          WHERE table_schema = DATABASE() AND table_name = :t',
        ['t' => $table],
    ) > 0;
};

$hasColumn = static function (string $table, string $column): bool {
    return (int) Database::scalar(
        'SELECT COUNT(*) FROM information_schema.columns
          WHERE table_schema = DATABASE() AND table_name = :t AND column_name = :c',
        ['t' => $table, 'c' => $column],
    ) > 0;
};

$made = 0;

// ---------------------------------------------------------------- shifts

if (!$hasTable('shifts')) {
    Database::run(
        'CREATE TABLE `shifts` (
          `id`              BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
          `restaurant_id`   INT UNSIGNED NOT NULL,
          `account_id`      INT UNSIGNED NOT NULL,

          `opened_by`       INT UNSIGNED NOT NULL,
          `opened_at`       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
          `opening_float`   DECIMAL(14,2) NOT NULL DEFAULT 0.00,

          -- What the previous shift said it left behind, and the gap between
          -- that and what was actually found this morning. Money that goes
          -- missing overnight is a different problem from a shift being short,
          -- and rolling the two together hides both.
          `previous_close`  DECIMAL(14,2) NULL DEFAULT NULL,
          `overnight_diff`  DECIMAL(14,2) NULL DEFAULT NULL,

          `closed_by`       INT UNSIGNED NULL DEFAULT NULL,
          `closed_at`       DATETIME NULL DEFAULT NULL,

          -- float + money in - money out, taken from account_transactions so
          -- the shift agrees with the Accounts screen by construction rather
          -- than by a second calculation that can drift from the first.
          `expected_close`  DECIMAL(14,2) NULL DEFAULT NULL,
          `counted_close`   DECIMAL(14,2) NULL DEFAULT NULL,
          `variance`        DECIMAL(14,2) NULL DEFAULT NULL,
          `close_reason`    VARCHAR(255) NULL DEFAULT NULL,

          -- Orders taken while no shift was open. Not blocked — a till that
          -- refuses money is worse than a gap in a report — but counted, so
          -- the gap is visible to whoever reads the close.
          `orders_outside`  INT UNSIGNED NOT NULL DEFAULT 0,

          `notes`           VARCHAR(500) NOT NULL DEFAULT "",

          -- The one-open-shift-per-till rule, enforced by the database rather
          -- than by a check the application might forget. Holds the account id
          -- while open and NULL once closed, and NULLs do not collide in a
          -- unique index — so a second open on the same till is impossible even
          -- if two requests arrive at the same instant.
          `open_marker`     INT UNSIGNED NULL DEFAULT NULL,

          `created_at`      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

          PRIMARY KEY (`id`),
          UNIQUE KEY `ux_shifts_one_open` (`open_marker`),
          KEY `ix_shifts_restaurant` (`restaurant_id`, `opened_at`),
          KEY `ix_shifts_account` (`account_id`, `opened_at`),
          KEY `ix_shifts_who` (`restaurant_id`, `closed_by`, `closed_at`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci',
    );
    echo "shifts: waa la abuuray.\n";
    $made++;
} else {
    echo "shifts: horeba wuu u jiray.\n";
}

// ------------------------------------------------- which shift a row belongs to

// Stamped on the ledger rather than worked out from timestamps at read time:
// a shift that is edited, or a row posted a second late, would otherwise fall
// on the wrong side of a boundary and make two closes disagree.
if (!$hasColumn('account_transactions', 'shift_id')) {
    Database::run(
        'ALTER TABLE `account_transactions`
           ADD COLUMN `shift_id` BIGINT UNSIGNED NULL DEFAULT NULL,
           ADD KEY `ix_txn_shift` (`shift_id`)',
    );
    echo "account_transactions.shift_id: waa la daray.\n";
    $made++;
}

if (!$hasColumn('orders', 'shift_id')) {
    Database::run(
        'ALTER TABLE `orders`
           ADD COLUMN `shift_id` BIGINT UNSIGNED NULL DEFAULT NULL,
           ADD KEY `ix_orders_shift` (`shift_id`)',
    );
    echo "orders.shift_id: waa la daray.\n";
    $made++;
}

// ------------------------------------------------------- the tolerance

if (!$hasColumn('restaurant_settings', 'variance_tolerance')) {
    // Below this, a difference is a rounding slip and is taken silently. Above
    // it, somebody has to say what happened. Forcing a reason for two hundred
    // shillings teaches staff to type "rounding" every day, and then nobody
    // reads any of them.
    Database::run(
        'ALTER TABLE `restaurant_settings`
           ADD COLUMN `variance_tolerance` DECIMAL(14,2) NOT NULL DEFAULT 1000.00',
    );
    echo "restaurant_settings.variance_tolerance: waa la daray.\n";
    $made++;
}

// ----------------------------------------------------------- permissions

$permissions = [
    ['shifts.view', 'shifts', 'view'],
    ['shifts.manage', 'shifts', 'manage'],
];

foreach ($permissions as [$code, $module, $action]) {
    $exists = (int) Database::scalar(
        'SELECT COUNT(*) FROM permissions WHERE code = :c',
        ['c' => $code],
    ) > 0;

    if ($exists) {
        continue;
    }

    Database::run(
        'INSERT INTO permissions (`code`, `module`, `action`) VALUES (:c, :m, :a)',
        ['c' => $code, 'm' => $module, 'a' => $action],
    );
    echo "permission $code: waa la daray.\n";
    $made++;
}

// The split between these two is the blind count, and it is deliberate.
//
// `shifts.manage` opens and closes a till. `shifts.view` sees what the system
// expected to be in it. Somebody who can read the expected figure before they
// count will type the expected figure — the count stops being a count and the
// variance is always zero, which is worse than not counting at all because it
// looks like a control.
//
// So the operator standing at the drawer gets manage and not view. The expected
// total is revealed to them by closing, after the number they counted is in.
Database::run(
    'INSERT IGNORE INTO role_permissions (role_id, permission_id)
     SELECT r.id, p.id FROM roles r JOIN permissions p
        ON p.code IN ("shifts.view", "shifts.manage")
      WHERE r.code = "admin" AND r.is_system = 1',
);

Database::run(
    'INSERT IGNORE INTO role_permissions (role_id, permission_id)
     SELECT r.id, p.id FROM roles r JOIN permissions p
        ON p.code = "shifts.manage"
      WHERE r.code = "operator" AND r.is_system = 1',
);

echo "\n";
echo $made === 0
    ? "Wax cusub ma jirin — horeba wuu u diyaar ahaa.\n"
    : "$made isbeddel ayaa la sameeyay.\n";
