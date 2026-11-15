<?php

declare(strict_types=1);

/**
 * Plans, invoices, renewal reminders, platform roles and archiving.
 *
 *   - `plans`: a plan used to be whatever was typed into a text box, so
 *     "standard", "Standard" and "standad" were three plans with no price and
 *     no limits behind any of them.
 *   - `subscription_payments` learns what a payment bought (plan, months,
 *     period), so an invoice can say it.
 *   - `subscription_reminders`: one row per reminder sent, so the daily run can
 *     never send the same one twice.
 *   - `super_admins.role`: every administrator could do everything.
 *   - `restaurants.status` gains `archived`, for a restaurant that has left —
 *     hidden from the working lists, locked out, and nothing deleted.
 *
 * Idempotent, like the rest of the chain. Existing administrators become
 * owners and existing plans get no limits, so nothing that worked yesterday
 * stops working today.
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

$hasTable = static function (string $table): bool {
    return (int) Database::scalar(
        'SELECT COUNT(*) FROM information_schema.tables
          WHERE table_schema = DATABASE() AND table_name = :t',
        ['t' => $table],
    ) > 0;
};

$made = 0;

// ---------------------------------------------------------------- plans

if (!$hasTable('plans')) {
    // `subscriptions.plan` keeps holding the code rather than gaining a foreign
    // key: the text is already there on every row, and a subscription whose
    // plan was later retired must still read back what it was sold as.
    //
    // Zero in a limit means unlimited. That is also the default, so a plan
    // nobody has configured restricts nobody.
    Database::run(
        'CREATE TABLE `plans` (
          `id`          INT UNSIGNED NOT NULL AUTO_INCREMENT,
          `code`        VARCHAR(64)  NOT NULL,
          `name`        VARCHAR(100) NOT NULL,
          `price`       DECIMAL(14,2) NOT NULL DEFAULT 0 COMMENT "Per month",
          `max_users`   SMALLINT UNSIGNED NOT NULL DEFAULT 0 COMMENT "0 = unlimited",
          `max_tables`  SMALLINT UNSIGNED NOT NULL DEFAULT 0 COMMENT "0 = unlimited",
          `description` VARCHAR(255) NOT NULL DEFAULT "",
          `is_active`   TINYINT(1)   NOT NULL DEFAULT 1,
          `sort_order`  SMALLINT     NOT NULL DEFAULT 0,
          `created_at`  TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
          `updated_at`  TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
          PRIMARY KEY (`id`),
          UNIQUE KEY `uq_plans_code` (`code`),
          CONSTRAINT `chk_plans_price` CHECK (`price` >= 0)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci',
    );
    echo "plans: waa la abuuray.\n";
    $made++;
} else {
    echo "plans: horeba wuu u jiray.\n";
}

// Every plan already in use becomes a real one, with no price and no limits —
// the administrator fills those in. Inventing a price here would put a number
// on an invoice that nobody agreed to.
$codes = array_column(
    Database::select('SELECT DISTINCT plan FROM subscriptions WHERE plan <> ""'),
    'plan',
);
$codes = array_values(array_unique(array_merge(['trial', 'standard'], $codes)));

foreach ($codes as $i => $code) {
    $code = strtolower(trim((string) $code));
    if ($code === '') {
        continue;
    }

    $inserted = Database::run(
        'INSERT IGNORE INTO plans (code, name, sort_order) VALUES (:c, :n, :s)',
        ['c' => $code, 'n' => ucfirst($code), 's' => $i * 10],
    )->rowCount();

    if ($inserted > 0) {
        echo "plans: '$code' waa la daray.\n";
        $made++;
    }
}

// Existing subscriptions may say "Standard" where the plan row says
// "standard". One spelling, so the limits lookup finds it.
Database::run('UPDATE subscriptions SET plan = LOWER(TRIM(plan)) WHERE plan <> LOWER(TRIM(plan))');

// ------------------------------------------------------------ invoices

$paymentColumns = [
    // What the money bought, captured when it was paid. Reading it back from
    // the subscription later would describe today's plan, not the one paid for.
    'plan'         => 'VARCHAR(64) NULL DEFAULT NULL',
    'months'       => 'SMALLINT UNSIGNED NULL DEFAULT NULL',
    'period_start' => 'DATE NULL DEFAULT NULL',
    'period_end'   => 'DATE NULL DEFAULT NULL',
];

foreach ($paymentColumns as $column => $definition) {
    if ($hasColumn('subscription_payments', $column)) {
        continue;
    }

    Database::run("ALTER TABLE `subscription_payments` ADD COLUMN `$column` $definition");
    echo "subscription_payments.$column: waa la daray.\n";
    $made++;
}

// ----------------------------------------------------------- reminders

if (!$hasTable('subscription_reminders')) {
    // Keyed on the end date as well as the stage: renewing moves `ends_on`, so
    // the next term earns its own reminders without anyone clearing the old
    // ones. `stage` is days before the end; -1 is the "it has ended" notice.
    Database::run(
        'CREATE TABLE `subscription_reminders` (
          `id`              BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
          `subscription_id` INT UNSIGNED NOT NULL,
          `restaurant_id`   INT UNSIGNED NOT NULL,
          `ends_on`         DATE NOT NULL,
          `stage`           SMALLINT NOT NULL,
          `pushed`          SMALLINT UNSIGNED NOT NULL DEFAULT 0,
          `emailed`         SMALLINT UNSIGNED NOT NULL DEFAULT 0,
          `created_at`      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
          PRIMARY KEY (`id`),
          UNIQUE KEY `ux_subscription_reminders` (`subscription_id`, `ends_on`, `stage`),
          KEY `ix_subscription_reminders_created` (`created_at`),
          CONSTRAINT `fk_subscription_reminders_sub` FOREIGN KEY (`subscription_id`)
            REFERENCES `subscriptions` (`id`) ON DELETE CASCADE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci',
    );
    echo "subscription_reminders: waa la abuuray.\n";
    $made++;
}

// -------------------------------------------------------- platform roles

if (!$hasColumn('super_admins', 'role')) {
    // Everyone who exists today keeps everything they had. Narrower roles are
    // for the people added from now on.
    Database::run(
        "ALTER TABLE `super_admins`
           ADD COLUMN `role` ENUM('owner','support','billing') NOT NULL DEFAULT 'owner'
           AFTER `email`",
    );
    echo "super_admins.role: waa la daray (dhammaan waa owner).\n";
    $made++;
}

// ------------------------------------------------------------- archive

$statusType = (string) Database::scalar(
    'SELECT COLUMN_TYPE FROM information_schema.columns
      WHERE table_schema = DATABASE() AND table_name = "restaurants" AND column_name = "status"',
);

if (!str_contains($statusType, "'archived'")) {
    Database::run(
        "ALTER TABLE `restaurants`
           MODIFY `status` ENUM('active','suspended','trial','archived') NOT NULL DEFAULT 'active'",
    );
    echo "restaurants.status: 'archived' waa la daray.\n";
    $made++;
}

if (!$hasColumn('restaurants', 'archived_at')) {
    Database::run('ALTER TABLE `restaurants` ADD COLUMN `archived_at` DATETIME NULL DEFAULT NULL');
    echo "restaurants.archived_at: waa la daray.\n";
    $made++;
}

echo "\n";
echo $made === 0
    ? "Wax cusub ma jirin — horeba wuu u diyaar ahaa.\n"
    : "$made isbeddel ayaa la sameeyay.\n";
