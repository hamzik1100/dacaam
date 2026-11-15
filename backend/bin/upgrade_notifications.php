<?php

declare(strict_types=1);

/**
 * Creates the notification tables on a database that predates them.
 *
 * Idempotent: it checks for each table before creating it, so the deploy can
 * run twice with the same result as running it once.
 */

use Dacaam\Core\Database;

require dirname(__DIR__) . '/bootstrap.php';

$has = static function (string $table): bool {
    return (int) Database::scalar(
        'SELECT COUNT(*) FROM information_schema.tables
          WHERE table_schema = DATABASE() AND table_name = :t',
        ['t' => $table],
    ) > 0;
};

$made = 0;

if (!$has('notifications')) {
    Database::run(
        'CREATE TABLE `notifications` (
          `id`            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
          `restaurant_id` INT UNSIGNED NULL DEFAULT NULL,
          `user_id`       INT UNSIGNED NULL DEFAULT NULL,
          `title`         VARCHAR(150)  NOT NULL,
          `body`          VARCHAR(1000) NOT NULL,
          `kind`          VARCHAR(20)   NOT NULL DEFAULT "info",
          `sent_by`       INT UNSIGNED  NULL DEFAULT NULL,
          `created_at`    DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
          PRIMARY KEY (`id`),
          KEY `ix_notifications_restaurant` (`restaurant_id`, `created_at`),
          KEY `ix_notifications_user` (`user_id`, `created_at`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci',
    );
    echo "notifications: waa la abuuray.\n";
    $made++;
}

if (!$has('notification_reads')) {
    Database::run(
        'CREATE TABLE `notification_reads` (
          `id`              BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
          `notification_id` BIGINT UNSIGNED NOT NULL,
          `user_id`         INT UNSIGNED NOT NULL,
          `read_at`         DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
          PRIMARY KEY (`id`),
          UNIQUE KEY `ux_notification_reads` (`notification_id`, `user_id`),
          CONSTRAINT `fk_notification_reads_notification` FOREIGN KEY (`notification_id`)
            REFERENCES `notifications` (`id`) ON DELETE CASCADE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci',
    );
    echo "notification_reads: waa la abuuray.\n";
    $made++;
}

if (!$has('device_tokens')) {
    Database::run(
        'CREATE TABLE `device_tokens` (
          `id`            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
          `token`         VARCHAR(255) NOT NULL,
          `restaurant_id` INT UNSIGNED NULL DEFAULT NULL,
          `user_id`       INT UNSIGNED NULL DEFAULT NULL,
          `platform`      VARCHAR(20)  NOT NULL DEFAULT "android",
          `last_seen_at`  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
          `created_at`    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
          PRIMARY KEY (`id`),
          UNIQUE KEY `ux_device_tokens_token` (`token`),
          KEY `ix_device_tokens_user` (`user_id`),
          KEY `ix_device_tokens_restaurant` (`restaurant_id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci',
    );
    echo "device_tokens: waa la abuuray.\n";
    $made++;
}

echo $made === 0
    ? "Fariimaha: horeba way u diyaar ahaayeen.\n"
    : "Fariimaha: $made miis oo cusub.\n";
