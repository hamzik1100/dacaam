<?php

declare(strict_types=1);

/**
 * Two-factor and proper management for the platform administrators.
 *
 * The account that controls every restaurant had a password and nothing else,
 * while the staff inside those restaurants could already turn on 2FA. The most
 * valuable credential on the platform was the least protected one.
 *
 * And there was only ever one of it: `super_admins` was written once, at
 * first-run setup, and never again. No second administrator, no way to disable
 * one, no path at all if that person leaves or their account is taken.
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

$hasTable = static function (string $table): bool {
    return (int) Database::scalar(
        'SELECT COUNT(*) FROM information_schema.tables
          WHERE table_schema = DATABASE() AND table_name = :t',
        ['t' => $table],
    ) > 0;
};

$made = 0;

// ------------------------------------------------------- second factor

$columns = [
    'two_factor_secret'       => 'VARCHAR(64) NULL DEFAULT NULL',
    'two_factor_confirmed_at' => 'DATETIME NULL DEFAULT NULL',
    // Who added them, so the trail says where a platform account came from.
    // Null on the first-run account, which nobody invited.
    'created_by'              => 'INT UNSIGNED NULL DEFAULT NULL',
    'disabled_at'             => 'DATETIME NULL DEFAULT NULL',
];

foreach ($columns as $column => $definition) {
    if ($hasColumn('super_admins', $column)) {
        continue;
    }

    Database::run("ALTER TABLE `super_admins` ADD COLUMN `$column` $definition");
    echo "super_admins.$column: waa la daray.\n";
    $made++;
}

// ------------------------------------------------------ recovery codes

if (!$hasTable('super_admin_recovery_codes')) {
    // Its own table rather than sharing the staff one.
    //
    // That table is keyed on `user_id`, and a column meaning two different
    // things depending on who is asking is exactly how one person's recovery
    // code ends up unlocking somebody else's account.
    //
    // These matter more here than anywhere else in the system: a platform
    // administrator who loses their phone with no codes and no second
    // administrator has locked the entire platform out of itself.
    Database::run(
        'CREATE TABLE `super_admin_recovery_codes` (
          `id`             BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
          `super_admin_id` INT UNSIGNED NOT NULL,
          `code_hash`      CHAR(64) NOT NULL,
          `used_at`        DATETIME NULL DEFAULT NULL,
          `created_at`     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
          PRIMARY KEY (`id`),
          KEY `ix_sarc_admin` (`super_admin_id`, `used_at`),
          CONSTRAINT `fk_sarc_admin` FOREIGN KEY (`super_admin_id`)
            REFERENCES `super_admins` (`id`) ON DELETE CASCADE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci',
    );
    echo "super_admin_recovery_codes: waa la abuuray.\n";
    $made++;
} else {
    echo "super_admin_recovery_codes: horeba wuu u jiray.\n";
}

// --------------------------------------------------- sign-in challenges

if (!$hasTable('super_admin_challenges')) {
    // The half-signed-in state between password and code.
    //
    // Held server-side rather than in the session, so a challenge cannot be
    // replayed from another browser and expires on its own whether or not the
    // person ever comes back to finish.
    Database::run(
        'CREATE TABLE `super_admin_challenges` (
          `id`             BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
          `super_admin_id` INT UNSIGNED NOT NULL,
          `token_hash`     CHAR(64) NOT NULL,
          `ip`             VARCHAR(45) NOT NULL DEFAULT "",
          `attempts`       TINYINT UNSIGNED NOT NULL DEFAULT 0,
          `expires_at`     DATETIME NOT NULL,
          `created_at`     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
          PRIMARY KEY (`id`),
          UNIQUE KEY `ux_sac_token` (`token_hash`),
          KEY `ix_sac_expiry` (`expires_at`),
          CONSTRAINT `fk_sac_admin` FOREIGN KEY (`super_admin_id`)
            REFERENCES `super_admins` (`id`) ON DELETE CASCADE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci',
    );
    echo "super_admin_challenges: waa la abuuray.\n";
    $made++;
}

echo "\n";
echo $made === 0
    ? "Wax cusub ma jirin — horeba wuu u diyaar ahaa.\n"
    : "$made isbeddel ayaa la sameeyay.\n";
