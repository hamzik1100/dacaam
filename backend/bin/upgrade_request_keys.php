<?php

declare(strict_types=1);

/**
 * Creates `request_keys`, which is what stops a retried deposit becoming two.
 *
 * Idempotent, like every other upgrade script here: it checks before it acts,
 * so running the deploy twice is the same as running it once.
 */

use Dacaam\Core\Database;

require dirname(__DIR__) . '/bootstrap.php';

$exists = (int) Database::scalar(
    'SELECT COUNT(*) FROM information_schema.tables
      WHERE table_schema = DATABASE() AND table_name = "request_keys"',
);

if ($exists > 0) {
    echo "request_keys: horeba wuu u jiray.\n";
    exit(0);
}

Database::run(
    'CREATE TABLE `request_keys` (
      `id`            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
      `restaurant_id` INT UNSIGNED NOT NULL,
      `request_key`   VARCHAR(64)  NOT NULL,
      `endpoint`      VARCHAR(120) NOT NULL,
      `response`      MEDIUMTEXT   NULL DEFAULT NULL,
      `created_at`    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (`id`),
      UNIQUE KEY `ux_request_keys` (`restaurant_id`, `request_key`),
      KEY `ix_request_keys_created` (`created_at`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci',
);

echo "request_keys: waa la abuuray.\n";
