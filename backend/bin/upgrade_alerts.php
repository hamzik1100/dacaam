<?php

declare(strict_types=1);

/**
 * Email alerts: the outbox, and the per-restaurant switches that feed it.
 *
 * Idempotent, like the rest of the chain — it checks before it acts, so the
 * deploy can run twice with the same result as running it once.
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

// ---------------------------------------------------------------- outbox

if (!$hasTable('email_outbox')) {
    // Queued, never sent inline. An SMTP server that is slow or down must not
    // be able to hold up a till: the cashier is standing in front of a customer
    // and the email is not what they are waiting for.
    //
    // `claimed_at` is what stops two workers sending the same message twice.
    // The drain claims a row with a conditional UPDATE before it touches SMTP,
    // so a second process arriving mid-send finds nothing to take.
    Database::run(
        'CREATE TABLE `email_outbox` (
          `id`            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
          `restaurant_id` INT UNSIGNED NOT NULL,
          `to_email`      VARCHAR(190)  NOT NULL,
          `subject`       VARCHAR(255)  NOT NULL,
          `body`          MEDIUMTEXT    NOT NULL,
          `event_key`     VARCHAR(64)   NOT NULL DEFAULT "",
          `record_id`     BIGINT UNSIGNED NULL DEFAULT NULL,
          `attempts`      TINYINT UNSIGNED NOT NULL DEFAULT 0,
          `last_error`    VARCHAR(255)  NULL DEFAULT NULL,
          `claimed_at`    DATETIME      NULL DEFAULT NULL,
          `sent_at`       DATETIME      NULL DEFAULT NULL,
          `created_at`    DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
          PRIMARY KEY (`id`),
          KEY `ix_outbox_pending` (`sent_at`, `claimed_at`, `attempts`),
          KEY `ix_outbox_restaurant` (`restaurant_id`, `created_at`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci',
    );
    echo "email_outbox: waa la abuuray.\n";
    $made++;
} else {
    echo "email_outbox: horeba wuu u jiray.\n";
}

// -------------------------------------------------------------- switches

// Defaults matter more than the switches do, because almost nobody changes
// them. Money and security arrive immediately; the high-volume order and menu
// traffic is summarised once a day. Emailing every line change would bury the
// cancelled-after-payment message among two hundred routine ones, which is the
// same as not sending it.
$columns = [
    'alert_email'     => 'VARCHAR(190) NULL DEFAULT NULL',
    'alerts_money'    => 'ENUM("off","digest","instant") NOT NULL DEFAULT "instant"',
    'alerts_security' => 'ENUM("off","digest","instant") NOT NULL DEFAULT "instant"',
    'alerts_orders'   => 'ENUM("off","digest","instant") NOT NULL DEFAULT "digest"',
    'alerts_menu'     => 'ENUM("off","digest","instant") NOT NULL DEFAULT "digest"',
    'alerts_last_digest' => 'DATE NULL DEFAULT NULL',
];

foreach ($columns as $column => $definition) {
    if ($hasColumn('restaurant_settings', $column)) {
        continue;
    }

    Database::run("ALTER TABLE `restaurant_settings` ADD COLUMN `$column` $definition");
    echo "restaurant_settings.$column: waa la daray.\n";
    $made++;
}

echo "\n";
echo $made === 0
    ? "Wax cusub ma jirin — horeba wuu u diyaar ahaa.\n"
    : "$made isbeddel ayaa la sameeyay.\n";
