-- Phase 3 upgrade for databases created before authentication landed.
--
-- `schema.sql` is the source of truth and already contains everything below;
-- this file exists so an existing `dacaam_db` can be brought forward without
-- `--fresh` (which would drop live orders).
--
-- MariaDB-specific: `ADD COLUMN IF NOT EXISTS` keeps it re-runnable.
--
-- No USE: select the database first, the same as schema.sql.

ALTER TABLE `users`
  ADD COLUMN IF NOT EXISTS `two_factor_secret`       VARCHAR(64) NULL DEFAULT NULL AFTER `last_login_at`,
  ADD COLUMN IF NOT EXISTS `two_factor_confirmed_at` DATETIME    NULL DEFAULT NULL AFTER `two_factor_secret`,
  ADD COLUMN IF NOT EXISTS `password_changed_at`     DATETIME    NULL DEFAULT NULL AFTER `two_factor_confirmed_at`,
  ADD COLUMN IF NOT EXISTS `must_change_password`    TINYINT(1)  NOT NULL DEFAULT 0 AFTER `password_changed_at`;

ALTER TABLE `restaurant_settings`
  ADD COLUMN IF NOT EXISTS `password_min_length`      TINYINT UNSIGNED  NOT NULL DEFAULT 6,
  ADD COLUMN IF NOT EXISTS `password_require_upper`   TINYINT(1)        NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS `password_require_number`  TINYINT(1)        NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS `password_require_symbol`  TINYINT(1)        NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS `session_timeout_days`     SMALLINT UNSIGNED NOT NULL DEFAULT 30,
  ADD COLUMN IF NOT EXISTS `max_failed_logins`        TINYINT UNSIGNED  NOT NULL DEFAULT 5,
  ADD COLUMN IF NOT EXISTS `lockout_minutes`          SMALLINT UNSIGNED NOT NULL DEFAULT 15,
  ADD COLUMN IF NOT EXISTS `require_two_factor_admin` TINYINT(1)        NOT NULL DEFAULT 0;

CREATE TABLE IF NOT EXISTS `two_factor_recovery_codes` (
  `id`         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `user_id`    INT UNSIGNED NOT NULL,
  `code_hash`  CHAR(64)     NOT NULL,
  `used_at`    DATETIME     NULL DEFAULT NULL,
  `created_at` TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `ix_recovery_codes_user` (`user_id`, `used_at`),
  CONSTRAINT `fk_recovery_codes_user` FOREIGN KEY (`user_id`)
    REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `auth_challenges` (
  `id`             BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `user_id`        INT UNSIGNED NOT NULL,
  `restaurant_id`  INT UNSIGNED NOT NULL,
  `challenge_hash` CHAR(64)     NOT NULL,
  `attempts`       TINYINT UNSIGNED NOT NULL DEFAULT 0,
  `expires_at`     DATETIME     NOT NULL,
  `consumed_at`    DATETIME     NULL DEFAULT NULL,
  `ip`             VARCHAR(45)  NOT NULL DEFAULT '',
  `device`         VARCHAR(190) NOT NULL DEFAULT '',
  `created_at`     TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_auth_challenges_hash` (`challenge_hash`),
  KEY `ix_auth_challenges_expiry` (`expires_at`),
  CONSTRAINT `fk_auth_challenges_user` FOREIGN KEY (`user_id`)
    REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `two_factor_used_codes` (
  `user_id`    INT UNSIGNED NOT NULL,
  `code_hash`  CHAR(64)     NOT NULL,
  `used_at`    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`user_id`, `code_hash`),
  KEY `ix_used_codes_time` (`used_at`),
  CONSTRAINT `fk_used_codes_user` FOREIGN KEY (`user_id`)
    REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
