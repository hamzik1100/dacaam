-- DACAAM — Restaurant POS & Management
-- MySQL / MariaDB schema.
--
-- Tenancy: every restaurant-owned row carries `restaurant_id`. The API takes
-- that value from the authenticated token and never from a request body, so a
-- caller cannot address another tenant's rows even by guessing ids.
--
-- Money: DECIMAL(14,2) everywhere. Never floats — a 0.01 drift on a SLSH
-- 8,750,000 report is a real accounting problem.
--
-- Idempotent: safe to re-run. Nothing here drops an existing object.

-- No CREATE DATABASE and no USE, deliberately.
--
-- Shared hosting hands you a database whose name it chose (`someuser_dacaam`)
-- and a MySQL account with no rights to create another. A file that names its
-- own database can only ever be installed on a machine you fully control.
-- `bin/migrate.php` selects the database from config before running this, and
-- importing this file through phpMyAdmin puts it in whichever database you
-- already have open.

SET FOREIGN_KEY_CHECKS = 1;

-- ============================================================ tenancy

CREATE TABLE IF NOT EXISTS `restaurants` (
  `id`          INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `slug`        VARCHAR(32)  NOT NULL COMMENT 'Restaurant code used at login, e.g. HAMZE',
  `name`        VARCHAR(150) NOT NULL,
  `phone`       VARCHAR(32)  NOT NULL DEFAULT '',
  `address`     VARCHAR(255) NOT NULL DEFAULT '',
  `logo_emoji`  VARCHAR(16)  NOT NULL DEFAULT '🍽️',
  `is_open`     TINYINT(1)   NOT NULL DEFAULT 1,
  `status`      ENUM('active','suspended','trial') NOT NULL DEFAULT 'active',
  `created_at`  TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at`  TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_restaurants_slug` (`slug`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ====================================================== platform admins
-- A separate credential space from `users` on purpose: a restaurant admin
-- must never be able to escalate into the platform. Nothing joins these two
-- tables, and the Super Admin dashboard is a different application.

CREATE TABLE IF NOT EXISTS `super_admins` (
  `id`            INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `name`          VARCHAR(150) NOT NULL,
  `email`         VARCHAR(190) NOT NULL,
  `password_hash` VARCHAR(255) NOT NULL,
  `is_active`     TINYINT(1)   NOT NULL DEFAULT 1,
  `failed_logins` SMALLINT UNSIGNED NOT NULL DEFAULT 0,
  `locked_until`  DATETIME     NULL DEFAULT NULL,
  `last_login_at` DATETIME     NULL DEFAULT NULL,
  `created_at`    TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at`    TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_super_admins_email` (`email`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Platform-level trail. Deliberately not `audit_logs`: that table is scoped to
-- a restaurant and is readable by that restaurant's admins, and platform
-- actions must not be visible to tenants.
CREATE TABLE IF NOT EXISTS `platform_audit_logs` (
  `id`             BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `super_admin_id` INT UNSIGNED NULL DEFAULT NULL,
  `admin_name`     VARCHAR(150) NOT NULL DEFAULT '',
  `action`         VARCHAR(64)  NOT NULL,
  `restaurant_id`  INT UNSIGNED NULL DEFAULT NULL,
  `detail`         VARCHAR(500) NOT NULL DEFAULT '',
  `ip`             VARCHAR(45)  NOT NULL DEFAULT '',
  `created_at`     DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `ix_platform_audit_created` (`created_at`),
  KEY `ix_platform_audit_restaurant` (`restaurant_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `subscriptions` (
  `id`            INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `restaurant_id` INT UNSIGNED NOT NULL,
  `plan`          VARCHAR(64)  NOT NULL DEFAULT 'standard',
  `status`        ENUM('active','trial','expired','suspended') NOT NULL DEFAULT 'trial',
  `starts_on`     DATE         NOT NULL,
  `ends_on`       DATE         NOT NULL,
  `amount`        DECIMAL(14,2) NOT NULL DEFAULT 0,
  `created_at`    TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at`    TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `ix_subscriptions_restaurant` (`restaurant_id`),
  KEY `ix_subscriptions_status_ends` (`status`, `ends_on`),
  CONSTRAINT `fk_subscriptions_restaurant` FOREIGN KEY (`restaurant_id`)
    REFERENCES `restaurants` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Money received for a subscription. Kept separate from restaurant accounts:
-- this is the platform's revenue, not the restaurant's.
CREATE TABLE IF NOT EXISTS `subscription_payments` (
  `id`              BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `subscription_id` INT UNSIGNED NOT NULL,
  `restaurant_id`   INT UNSIGNED NOT NULL,
  `amount`          DECIMAL(14,2) NOT NULL,
  `method`          ENUM('cash','zaad','edahab','bank') NOT NULL DEFAULT 'bank',
  `reference`       VARCHAR(100) NOT NULL DEFAULT '',
  `paid_on`         DATE         NOT NULL,
  `recorded_by`     INT UNSIGNED NULL DEFAULT NULL,
  `created_at`      TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `ix_subscription_payments_sub` (`subscription_id`),
  KEY `ix_subscription_payments_paid` (`paid_on`),
  CONSTRAINT `chk_subscription_payments_amount` CHECK (`amount` >= 0),
  CONSTRAINT `fk_subscription_payments_sub` FOREIGN KEY (`subscription_id`)
    REFERENCES `subscriptions` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================ identity & authorization

CREATE TABLE IF NOT EXISTS `users` (
  `id`            INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `restaurant_id` INT UNSIGNED NOT NULL,
  `name`          VARCHAR(150) NOT NULL,
  `phone`         VARCHAR(32)  NOT NULL,
  `password_hash` VARCHAR(255) NOT NULL,
  `is_active`     TINYINT(1)   NOT NULL DEFAULT 1,
  `failed_logins` SMALLINT UNSIGNED NOT NULL DEFAULT 0,
  `locked_until`  DATETIME     NULL DEFAULT NULL,
  `last_login_at` DATETIME     NULL DEFAULT NULL,
  -- Base32 TOTP secret. Present once enrolment starts; `confirmed_at` is what
  -- actually turns 2FA on, so an abandoned setup never locks anyone out.
  `two_factor_secret`       VARCHAR(64) NULL DEFAULT NULL,
  `two_factor_confirmed_at` DATETIME    NULL DEFAULT NULL,
  `password_changed_at`     DATETIME    NULL DEFAULT NULL,
  `must_change_password`    TINYINT(1)  NOT NULL DEFAULT 0,
  -- Optional: staff sign in with a phone, so email exists only to receive a
  -- password reset. No email simply means no self-service reset.
  `email`                   VARCHAR(190) NULL DEFAULT NULL,
  `created_at`    TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at`    TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  -- Phones are unique per tenant, not globally: the same person may work at
  -- two restaurants, and login always supplies the restaurant code.
  UNIQUE KEY `uq_users_restaurant_phone` (`restaurant_id`, `phone`),
  KEY `ix_users_restaurant` (`restaurant_id`),
  KEY `ix_users_phone` (`phone`),
  CONSTRAINT `fk_users_restaurant` FOREIGN KEY (`restaurant_id`)
    REFERENCES `restaurants` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `roles` (
  `id`            INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `restaurant_id` INT UNSIGNED NOT NULL,
  `code`          VARCHAR(32)  NOT NULL COMMENT 'admin | operator | waiter | custom',
  `name`          VARCHAR(64)  NOT NULL,
  `is_system`     TINYINT(1)   NOT NULL DEFAULT 0,
  `created_at`    TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_roles_restaurant_code` (`restaurant_id`, `code`),
  CONSTRAINT `fk_roles_restaurant` FOREIGN KEY (`restaurant_id`)
    REFERENCES `restaurants` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Global catalogue: the set of things the software can do is a property of the
-- product, not of a tenant. Only the grants are per-tenant.
CREATE TABLE IF NOT EXISTS `permissions` (
  `id`     SMALLINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `code`   VARCHAR(64) NOT NULL COMMENT 'module.action, e.g. orders.cancel',
  `module` VARCHAR(32) NOT NULL,
  `action` VARCHAR(32) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_permissions_code` (`code`),
  KEY `ix_permissions_module` (`module`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `role_permissions` (
  `role_id`       INT UNSIGNED NOT NULL,
  `permission_id` SMALLINT UNSIGNED NOT NULL,
  PRIMARY KEY (`role_id`, `permission_id`),
  KEY `ix_role_permissions_permission` (`permission_id`),
  CONSTRAINT `fk_role_permissions_role` FOREIGN KEY (`role_id`)
    REFERENCES `roles` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_role_permissions_permission` FOREIGN KEY (`permission_id`)
    REFERENCES `permissions` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `user_roles` (
  `user_id` INT UNSIGNED NOT NULL,
  `role_id` INT UNSIGNED NOT NULL,
  PRIMARY KEY (`user_id`, `role_id`),
  KEY `ix_user_roles_role` (`role_id`),
  CONSTRAINT `fk_user_roles_user` FOREIGN KEY (`user_id`)
    REFERENCES `users` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_user_roles_role` FOREIGN KEY (`role_id`)
    REFERENCES `roles` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Per-user overrides on top of role grants. `granted = 0` revokes something
-- the role would otherwise allow.
CREATE TABLE IF NOT EXISTS `user_permissions` (
  `user_id`       INT UNSIGNED NOT NULL,
  `permission_id` SMALLINT UNSIGNED NOT NULL,
  `granted`       TINYINT(1) NOT NULL DEFAULT 1,
  PRIMARY KEY (`user_id`, `permission_id`),
  CONSTRAINT `fk_user_permissions_user` FOREIGN KEY (`user_id`)
    REFERENCES `users` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_user_permissions_permission` FOREIGN KEY (`permission_id`)
    REFERENCES `permissions` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `api_tokens` (
  `id`            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `user_id`       INT UNSIGNED NOT NULL,
  `restaurant_id` INT UNSIGNED NOT NULL,
  -- Only the hash is stored; a database leak must not yield usable sessions.
  `token_hash`    CHAR(64)     NOT NULL,
  `device`        VARCHAR(190) NOT NULL DEFAULT '',
  `ip`            VARCHAR(45)  NOT NULL DEFAULT '',
  `expires_at`    DATETIME     NOT NULL,
  `revoked_at`    DATETIME     NULL DEFAULT NULL,
  `last_used_at`  DATETIME     NULL DEFAULT NULL,
  `created_at`    TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_api_tokens_hash` (`token_hash`),
  KEY `ix_api_tokens_user` (`user_id`),
  KEY `ix_api_tokens_expiry` (`expires_at`),
  CONSTRAINT `fk_api_tokens_user` FOREIGN KEY (`user_id`)
    REFERENCES `users` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_api_tokens_restaurant` FOREIGN KEY (`restaurant_id`)
    REFERENCES `restaurants` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Single-use codes for when the authenticator app is lost. Stored hashed —
-- a recovery code is a password, and a database leak must not yield working
-- ones.
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

-- The short-lived ticket between "password accepted" and "OTP accepted".
-- It is not a session: it grants nothing except the right to present a code.
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

-- Blocks replay of a TOTP code inside its own validity window: the code is
-- correct for ~90 seconds, and without this a shoulder-surfed code works
-- twice.
CREATE TABLE IF NOT EXISTS `two_factor_used_codes` (
  `user_id`    INT UNSIGNED NOT NULL,
  `code_hash`  CHAR(64)     NOT NULL,
  `used_at`    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`user_id`, `code_hash`),
  KEY `ix_used_codes_time` (`used_at`),
  CONSTRAINT `fk_used_codes_user` FOREIGN KEY (`user_id`)
    REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Single-use password reset tokens, delivered by email.
CREATE TABLE IF NOT EXISTS `password_resets` (
  `id`         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `user_id`    INT UNSIGNED NOT NULL,
  `token_hash` CHAR(64)     NOT NULL,
  `expires_at` DATETIME     NOT NULL,
  `used_at`    DATETIME     NULL DEFAULT NULL,
  `ip`         VARCHAR(45)  NOT NULL DEFAULT '',
  `created_at` TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_password_resets_hash` (`token_hash`),
  KEY `ix_password_resets_user` (`user_id`, `used_at`),
  CONSTRAINT `fk_password_resets_user` FOREIGN KEY (`user_id`)
    REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `login_attempts` (
  `id`            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `restaurant_id` INT UNSIGNED NULL,
  `slug`          VARCHAR(32)  NOT NULL DEFAULT '',
  `phone`         VARCHAR(32)  NOT NULL DEFAULT '',
  `succeeded`     TINYINT(1)   NOT NULL DEFAULT 0,
  `ip`            VARCHAR(45)  NOT NULL DEFAULT '',
  `device`        VARCHAR(190) NOT NULL DEFAULT '',
  `created_at`    TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `ix_login_attempts_phone_time` (`phone`, `created_at`),
  KEY `ix_login_attempts_restaurant` (`restaurant_id`, `created_at`),
  KEY `ix_login_attempts_ip_time` (`ip`, `created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Fixed-window request throttling.
--
-- In MySQL rather than in memory because the API is expected to run on shared
-- hosting, where APCu is per-process and Redis is not on offer. One row per
-- bucket, rewritten in place — the table stays small and never needs a sweep
-- to remain correct, only to stay tidy.
CREATE TABLE IF NOT EXISTS `rate_limits` (
  `bucket`            VARCHAR(190) NOT NULL COMMENT 'e.g. login|203.0.113.9',
  `hits`              INT UNSIGNED NOT NULL DEFAULT 0,
  `window_started_at` DATETIME     NOT NULL,
  `updated_at`        TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`bucket`),
  KEY `ix_rate_limits_window` (`window_started_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================ catalogue

CREATE TABLE IF NOT EXISTS `categories` (
  `id`            INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `restaurant_id` INT UNSIGNED NOT NULL,
  `name`          VARCHAR(100) NOT NULL,
  `description`   VARCHAR(255) NOT NULL DEFAULT '',
  `emoji`         VARCHAR(16)  NOT NULL DEFAULT '🍽️',
  `color`         CHAR(7)      NOT NULL DEFAULT '#F97316',
  `is_active`     TINYINT(1)   NOT NULL DEFAULT 1,
  `sort_order`    SMALLINT     NOT NULL DEFAULT 0,
  `deleted_at`    DATETIME     NULL DEFAULT NULL,
  `created_at`    TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at`    TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `ix_categories_restaurant` (`restaurant_id`),
  KEY `ix_categories_active` (`restaurant_id`, `is_active`, `sort_order`),
  CONSTRAINT `fk_categories_restaurant` FOREIGN KEY (`restaurant_id`)
    REFERENCES `restaurants` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `menu_items` (
  `id`                  INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `restaurant_id`       INT UNSIGNED NOT NULL,
  `category_id`         INT UNSIGNED NOT NULL,
  `name`                VARCHAR(150) NOT NULL,
  `description`         VARCHAR(500) NOT NULL DEFAULT '',
  `price`               DECIMAL(14,2) NOT NULL,
  `image_url`           VARCHAR(500) NULL DEFAULT NULL,
  `emoji`               VARCHAR(16)  NOT NULL DEFAULT '🍽️',
  `is_available`        TINYINT(1)   NOT NULL DEFAULT 1,
  `apply_packaging_fee` TINYINT(1)   NOT NULL DEFAULT 1,
  `sort_order`          SMALLINT     NOT NULL DEFAULT 0,
  `deleted_at`          DATETIME     NULL DEFAULT NULL,
  `created_at`          TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at`          TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `ix_menu_items_restaurant` (`restaurant_id`),
  KEY `ix_menu_items_category` (`category_id`),
  KEY `ix_menu_items_available` (`restaurant_id`, `is_available`),
  CONSTRAINT `chk_menu_items_price` CHECK (`price` > 0),
  CONSTRAINT `fk_menu_items_restaurant` FOREIGN KEY (`restaurant_id`)
    REFERENCES `restaurants` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_menu_items_category` FOREIGN KEY (`category_id`)
    REFERENCES `categories` (`id`) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `tables` (
  `id`               INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `restaurant_id`    INT UNSIGNED NOT NULL,
  `table_number`     SMALLINT UNSIGNED NOT NULL,
  `name`             VARCHAR(64)  NOT NULL DEFAULT '',
  `capacity`         TINYINT UNSIGNED NOT NULL DEFAULT 4,
  `status`           ENUM('available','occupied','reserved','disabled') NOT NULL DEFAULT 'available',
  `current_order_id` INT UNSIGNED NULL DEFAULT NULL,
  `is_active`        TINYINT(1)   NOT NULL DEFAULT 1,
  `created_at`       TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at`       TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_tables_restaurant_number` (`restaurant_id`, `table_number`),
  KEY `ix_tables_restaurant_status` (`restaurant_id`, `status`),
  CONSTRAINT `fk_tables_restaurant` FOREIGN KEY (`restaurant_id`)
    REFERENCES `restaurants` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- =============================================================== orders

CREATE TABLE IF NOT EXISTS `orders` (
  `id`             INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `restaurant_id`  INT UNSIGNED NOT NULL,
  -- Per-tenant human-facing counter. #1025 in HAMZE and #1025 in WARFA are
  -- different orders and both are correct.
  `order_number`   INT UNSIGNED NOT NULL,
  `order_type`     ENUM('dine_in','takeaway') NOT NULL,
  -- The kitchen's view. Whether anyone has paid is a different question and
  -- lives in payment_status: a credit order is finished food and unpaid money,
  -- and one column cannot say both without lying about one of them.
  `status`         ENUM('pending','preparing','ready','completed','cancelled') NOT NULL DEFAULT 'pending',
  `payment_status` ENUM('unpaid','partial','paid') NOT NULL DEFAULT 'unpaid',
  `table_id`       INT UNSIGNED NULL DEFAULT NULL,
  `waiter_id`      INT UNSIGNED NULL DEFAULT NULL,
  `waiter_name`    VARCHAR(150) NOT NULL DEFAULT '',
  -- Set when the order is put on a registered account. Null for a walk-in,
  -- which is most of them. customer_name stays alongside it and keeps working
  -- for orders taken before customers existed — no backfill was attempted,
  -- because matching "Hamse" to "hamze A" would attach real debt to the wrong
  -- person.
  `customer_id`    INT UNSIGNED NULL DEFAULT NULL,
  `customer_name`  VARCHAR(150) NOT NULL DEFAULT '',
  `customer_phone` VARCHAR(32)  NOT NULL DEFAULT '',
  `guests`         TINYINT UNSIGNED NOT NULL DEFAULT 0,
  `subtotal`       DECIMAL(14,2) NOT NULL DEFAULT 0,
  `discount`       DECIMAL(14,2) NOT NULL DEFAULT 0,
  `tax_rate`       DECIMAL(6,3)  NOT NULL DEFAULT 0 COMMENT 'Percent snapshot at order time',
  `tax_amount`     DECIMAL(14,2) NOT NULL DEFAULT 0,
  `packaging_fee`  DECIMAL(14,2) NOT NULL DEFAULT 0,
  `total`          DECIMAL(14,2) NOT NULL DEFAULT 0,
  `notes`          VARCHAR(500) NOT NULL DEFAULT '',
  `cancel_reason`  VARCHAR(255) NULL DEFAULT NULL,
  `created_by`     INT UNSIGNED NULL DEFAULT NULL,
  `created_at`     DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at`     TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_orders_restaurant_number` (`restaurant_id`, `order_number`),
  KEY `ix_orders_restaurant` (`restaurant_id`),
  KEY `ix_orders_status` (`restaurant_id`, `status`),
  KEY `ix_orders_type` (`restaurant_id`, `order_type`),
  KEY `ix_orders_created` (`restaurant_id`, `created_at`),
  -- Covering index for the money questions: every KPI and every revenue chart
  -- is "this tenant, this date range, not cancelled, sum the total", and with
  -- `total` carried in the index those never touch the table at all.
  -- Measured on 60k orders: summary 154ms -> 34ms, daily chart 196ms -> 61ms.
  KEY `ix_orders_revenue` (`restaurant_id`, `created_at`, `status`, `total`),
  -- The Orders screen filters by status and reads newest-first. Without the
  -- trailing `created_at` that pairing costs a filesort over every match.
  KEY `ix_orders_status_created` (`restaurant_id`, `status`, `created_at`),
  KEY `ix_orders_table` (`table_id`),
  KEY `ix_orders_waiter` (`waiter_id`),
  -- Drives the top-customers report and a customer's own order history.
  KEY `ix_orders_customer` (`customer_id`, `created_at`),
  -- Two CHECK constraints belong on this table — takeaway must hold no table,
  -- and a cancelled order must carry a reason. They live in constraints.sql
  -- instead, because MariaDB 11.8 rejects a CHECK that references `table_id`
  -- (error 1901) while 10.4 accepts the same statement. A schema file that
  -- installs on one server and not another is worse than one that states the
  -- limit plainly. Both rules are enforced in the API regardless.
  CONSTRAINT `fk_orders_restaurant` FOREIGN KEY (`restaurant_id`)
    REFERENCES `restaurants` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_orders_table` FOREIGN KEY (`table_id`)
    REFERENCES `tables` (`id`) ON DELETE SET NULL,
  CONSTRAINT `fk_orders_waiter` FOREIGN KEY (`waiter_id`)
    REFERENCES `users` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `order_items` (
  `id`                  BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `restaurant_id`       INT UNSIGNED NOT NULL,
  `order_id`            INT UNSIGNED NOT NULL,
  `menu_item_id`        INT UNSIGNED NULL DEFAULT NULL,
  -- Name, price and packaging flag are snapshots. Repricing the menu next week
  -- must not rewrite what a customer was charged today.
  `item_name`           VARCHAR(150) NOT NULL,
  `unit_price`          DECIMAL(14,2) NOT NULL,
  `quantity`            SMALLINT UNSIGNED NOT NULL,
  `line_total`          DECIMAL(14,2) NOT NULL,
  `emoji`               VARCHAR(16)  NOT NULL DEFAULT '🍽️',
  `image_url`           VARCHAR(500) NULL DEFAULT NULL,
  `apply_packaging_fee` TINYINT(1)   NOT NULL DEFAULT 1,
  `notes`               VARCHAR(255) NOT NULL DEFAULT '',
  PRIMARY KEY (`id`),
  KEY `ix_order_items_order` (`order_id`),
  KEY `ix_order_items_restaurant` (`restaurant_id`),
  KEY `ix_order_items_menu_item` (`menu_item_id`),
  CONSTRAINT `chk_order_items_quantity` CHECK (`quantity` > 0),
  CONSTRAINT `fk_order_items_order` FOREIGN KEY (`order_id`)
    REFERENCES `orders` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_order_items_menu_item` FOREIGN KEY (`menu_item_id`)
    REFERENCES `menu_items` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `order_payments` (
  `id`            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `restaurant_id` INT UNSIGNED NOT NULL,
  `order_id`      INT UNSIGNED NOT NULL,
  `method`        ENUM('cash','zaad','edahab','bank') NOT NULL,
  `amount`        DECIMAL(14,2) NOT NULL,
  `reference`     VARCHAR(100) NOT NULL DEFAULT '',
  `received_by`   INT UNSIGNED NULL DEFAULT NULL,
  `created_at`    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `ix_order_payments_order` (`order_id`),
  KEY `ix_order_payments_restaurant_method` (`restaurant_id`, `method`),
  KEY `ix_order_payments_created` (`restaurant_id`, `created_at`),
  -- Negative rows are refunds. An order that gave money back has to say so,
  -- or the payment reports overstate what the restaurant actually holds.
  -- Zero is still refused: a payment of nothing is not an event.
  CONSTRAINT `chk_order_payments_amount` CHECK (`amount` <> 0),
  CONSTRAINT `fk_order_payments_order` FOREIGN KEY (`order_id`)
    REFERENCES `orders` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- =============================================================== drafts
-- Drafts are not sales. No report, KPI or account balance reads these tables.

CREATE TABLE IF NOT EXISTS `draft_orders` (
  `id`                BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `restaurant_id`     INT UNSIGNED NOT NULL,
  `code`              VARCHAR(24)  NOT NULL COMMENT 'D-102',
  `customer_name`     VARCHAR(150) NOT NULL,
  `customer_phone`    VARCHAR(32)  NOT NULL DEFAULT '',
  `order_type`        ENUM('dine_in','takeaway') NOT NULL DEFAULT 'dine_in',
  `table_id`          INT UNSIGNED NULL DEFAULT NULL,
  `waiter_id`         INT UNSIGNED NULL DEFAULT NULL,
  `waiter_name`       VARCHAR(150) NOT NULL DEFAULT '',
  `packaging_applied` TINYINT(1)   NOT NULL DEFAULT 0,
  `status`            ENUM('draft','pending','completed','cancelled') NOT NULL DEFAULT 'draft',
  -- Why the customer walked away. §46 refuses a cancellation without one, and
  -- a refused draft is kept rather than deleted so the reason survives.
  `cancel_reason`     VARCHAR(255) NULL DEFAULT NULL,
  `notes`             VARCHAR(500) NOT NULL DEFAULT '',
  `converted_order_id` INT UNSIGNED NULL DEFAULT NULL,
  `created_by`        INT UNSIGNED NULL DEFAULT NULL,
  `created_at`        DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at`        TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_draft_orders_restaurant_code` (`restaurant_id`, `code`),
  KEY `ix_draft_orders_restaurant_status` (`restaurant_id`, `status`),
  KEY `ix_draft_orders_created` (`restaurant_id`, `created_at`),
  CONSTRAINT `fk_draft_orders_restaurant` FOREIGN KEY (`restaurant_id`)
    REFERENCES `restaurants` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_draft_orders_table` FOREIGN KEY (`table_id`)
    REFERENCES `tables` (`id`) ON DELETE SET NULL,
  CONSTRAINT `fk_draft_orders_converted` FOREIGN KEY (`converted_order_id`)
    REFERENCES `orders` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `draft_order_items` (
  `id`                  BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `restaurant_id`       INT UNSIGNED NOT NULL,
  `draft_order_id`      BIGINT UNSIGNED NOT NULL,
  `menu_item_id`        INT UNSIGNED NULL DEFAULT NULL,
  `item_name`           VARCHAR(150) NOT NULL,
  `unit_price`          DECIMAL(14,2) NOT NULL,
  `quantity`            SMALLINT UNSIGNED NOT NULL,
  `line_total`          DECIMAL(14,2) NOT NULL,
  `emoji`               VARCHAR(16)  NOT NULL DEFAULT '🍽️',
  `apply_packaging_fee` TINYINT(1)   NOT NULL DEFAULT 1,
  PRIMARY KEY (`id`),
  KEY `ix_draft_order_items_draft` (`draft_order_id`),
  KEY `ix_draft_order_items_restaurant` (`restaurant_id`),
  CONSTRAINT `chk_draft_items_quantity` CHECK (`quantity` > 0),
  CONSTRAINT `fk_draft_order_items_draft` FOREIGN KEY (`draft_order_id`)
    REFERENCES `draft_orders` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================= expenses

CREATE TABLE IF NOT EXISTS `expense_categories` (
  `id`            INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `restaurant_id` INT UNSIGNED NOT NULL,
  `name`          VARCHAR(100) NOT NULL,
  `kind`          ENUM('daily','monthly') NOT NULL DEFAULT 'daily',
  `icon`          VARCHAR(64)  NOT NULL DEFAULT 'receipt',
  `color`         CHAR(7)      NOT NULL DEFAULT '#8B5CF6',
  `is_active`     TINYINT(1)   NOT NULL DEFAULT 1,
  `created_at`    TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `ix_expense_categories_restaurant` (`restaurant_id`),
  CONSTRAINT `fk_expense_categories_restaurant` FOREIGN KEY (`restaurant_id`)
    REFERENCES `restaurants` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `expenses` (
  `id`                  BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `restaurant_id`       INT UNSIGNED NOT NULL,
  `expense_category_id` INT UNSIGNED NULL DEFAULT NULL,
  `name`                VARCHAR(150) NOT NULL,
  `amount`              DECIMAL(14,2) NOT NULL,
  `kind`                ENUM('daily','monthly') NOT NULL DEFAULT 'daily',
  `method`              ENUM('cash','zaad','edahab','bank') NOT NULL DEFAULT 'cash',
  `expense_date`        DATE         NOT NULL,
  `is_recurring`        TINYINT(1)   NOT NULL DEFAULT 0,
  `notes`               VARCHAR(500) NOT NULL DEFAULT '',
  `attachment_url`      VARCHAR(500) NULL DEFAULT NULL,
  `created_by`          INT UNSIGNED NULL DEFAULT NULL,
  `created_at`          TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at`          TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `ix_expenses_restaurant` (`restaurant_id`),
  KEY `ix_expenses_date` (`restaurant_id`, `expense_date`),
  KEY `ix_expenses_category` (`expense_category_id`),
  CONSTRAINT `chk_expenses_amount` CHECK (`amount` > 0),
  CONSTRAINT `fk_expenses_restaurant` FOREIGN KEY (`restaurant_id`)
    REFERENCES `restaurants` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_expenses_category` FOREIGN KEY (`expense_category_id`)
    REFERENCES `expense_categories` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================= accounts

CREATE TABLE IF NOT EXISTS `accounts` (
  `id`            INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `restaurant_id` INT UNSIGNED NOT NULL,
  `method`        ENUM('cash','zaad','edahab','bank') NOT NULL,
  `name`          VARCHAR(64)  NOT NULL,
  `balance`       DECIMAL(14,2) NOT NULL DEFAULT 0,
  `is_active`     TINYINT(1)   NOT NULL DEFAULT 1,
  `created_at`    TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at`    TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_accounts_restaurant_method` (`restaurant_id`, `method`),
  CONSTRAINT `fk_accounts_restaurant` FOREIGN KEY (`restaurant_id`)
    REFERENCES `restaurants` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `account_transactions` (
  `id`              BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `restaurant_id`   INT UNSIGNED NOT NULL,
  `account_id`      INT UNSIGNED NOT NULL,
  `to_account_id`   INT UNSIGNED NULL DEFAULT NULL,
  `kind`            ENUM('money_in','money_out','transfer','adjustment') NOT NULL,
  `amount`          DECIMAL(14,2) NOT NULL,
  `balance_after`   DECIMAL(14,2) NOT NULL DEFAULT 0,
  `description`     VARCHAR(255) NOT NULL DEFAULT '',
  `source_type`     VARCHAR(32)  NOT NULL DEFAULT '' COMMENT 'order | expense | manual',
  `source_id`       BIGINT UNSIGNED NULL DEFAULT NULL,
  `created_by`      INT UNSIGNED NULL DEFAULT NULL,
  `created_at`      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `ix_account_transactions_account` (`account_id`, `created_at`),
  KEY `ix_account_transactions_restaurant` (`restaurant_id`, `created_at`),
  KEY `ix_account_transactions_source` (`source_type`, `source_id`),
  CONSTRAINT `fk_account_transactions_account` FOREIGN KEY (`account_id`)
    REFERENCES `accounts` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================ settings

CREATE TABLE IF NOT EXISTS `restaurant_settings` (
  `restaurant_id`            INT UNSIGNED NOT NULL,
  `language`                 CHAR(2)      NOT NULL DEFAULT 'so',
  `theme_mode`               ENUM('light','dark','system') NOT NULL DEFAULT 'light',
  `currency_prefix`          VARCHAR(12)  NOT NULL DEFAULT 'SLSH',
  `tax_rate`                 DECIMAL(6,3) NOT NULL DEFAULT 5.000,
  `tax_enabled`              TINYINT(1)   NOT NULL DEFAULT 0,
  `packaging_fee_enabled`    TINYINT(1)   NOT NULL DEFAULT 1,
  `packaging_fee`            DECIMAL(14,2) NOT NULL DEFAULT 5000.00,
  `require_table_for_dine_in` TINYINT(1)  NOT NULL DEFAULT 1,
  `guest_count_enabled`      TINYINT(1)   NOT NULL DEFAULT 1,

  -- Security policy, per restaurant. A single owner-operator and a chain with
  -- forty staff should not be forced onto the same rules.
  `password_min_length`      TINYINT UNSIGNED NOT NULL DEFAULT 6,
  `password_require_upper`   TINYINT(1)   NOT NULL DEFAULT 0,
  `password_require_number`  TINYINT(1)   NOT NULL DEFAULT 0,
  `password_require_symbol`  TINYINT(1)   NOT NULL DEFAULT 0,
  `session_timeout_days`     SMALLINT UNSIGNED NOT NULL DEFAULT 30,
  `max_failed_logins`        TINYINT UNSIGNED NOT NULL DEFAULT 5,
  `lockout_minutes`          SMALLINT UNSIGNED NOT NULL DEFAULT 15,
  -- When on, admins cannot use the app until they have enrolled in 2FA.
  `require_two_factor_admin` TINYINT(1)   NOT NULL DEFAULT 0,

  `updated_at`               TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`restaurant_id`),
  CONSTRAINT `fk_restaurant_settings_restaurant` FOREIGN KEY (`restaurant_id`)
    REFERENCES `restaurants` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `system_settings` (
  `key_name`   VARCHAR(64)  NOT NULL,
  `value`      TEXT         NULL,
  `updated_at` TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`key_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- =========================================================== audit log
-- One table for every tracked change, including an order's own timeline.
-- The Order Details screen reads it filtered by module='orders' + record_id.

CREATE TABLE IF NOT EXISTS `audit_logs` (
  `id`            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `restaurant_id` INT UNSIGNED NULL,
  `user_id`       INT UNSIGNED NULL DEFAULT NULL,
  `user_name`     VARCHAR(150) NOT NULL DEFAULT '',
  `module`        VARCHAR(32)  NOT NULL COMMENT 'orders | menu | expenses | users | settings | auth',
  `action`        VARCHAR(64)  NOT NULL COMMENT 'order_created | quantity_changed | ...',
  `record_id`     BIGINT UNSIGNED NULL DEFAULT NULL,
  `field`         VARCHAR(64)  NOT NULL DEFAULT '',
  `old_value`     VARCHAR(500) NULL DEFAULT NULL,
  `new_value`     VARCHAR(500) NULL DEFAULT NULL,
  `reason`        VARCHAR(255) NULL DEFAULT NULL,
  `ip`            VARCHAR(45)  NOT NULL DEFAULT '',
  `device`        VARCHAR(190) NOT NULL DEFAULT '',
  `created_at`    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `ix_audit_logs_restaurant` (`restaurant_id`),
  KEY `ix_audit_logs_created` (`restaurant_id`, `created_at`),
  KEY `ix_audit_logs_record` (`restaurant_id`, `module`, `record_id`),
  KEY `ix_audit_logs_user` (`user_id`)
  -- A `(restaurant_id, module, created_at)` index was tried here to remove the
  -- filesort on the module-filtered view, and rejected: at 320k rows it saved
  -- 0.3ms. This table is written on nearly every mutation, so an index that
  -- does not pay for itself on reads is a pure cost on writes.
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================= customers
--
-- A customer account is a small ledger, not an address book entry. The sign
-- convention is deliberate and the column is named for it: `balance_owed`
-- positive means the customer owes the restaurant, negative means they are in
-- credit. Calling it `balance` invited the opposite reading from anyone who
-- had seen a bank statement.

CREATE TABLE IF NOT EXISTS `customers` (
  `id`            INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `restaurant_id` INT UNSIGNED NOT NULL,
  `name`          VARCHAR(150) NOT NULL,
  -- NULL, not '', when there is no number. The unique key below treats '' as a
  -- value, so a second walk-in with no phone would collide with the first;
  -- MySQL allows any number of NULLs in a unique index.
  `phone`         VARCHAR(32)  NULL DEFAULT NULL,
  `address`       VARCHAR(255) NOT NULL DEFAULT '',
  `notes`         VARCHAR(500) NOT NULL DEFAULT '',
  -- Zero means no credit at all. A customer is trusted only after somebody
  -- decides how far, rather than by default.
  `credit_limit`  DECIMAL(14,2) NOT NULL DEFAULT 0,
  -- Cached from customer_ledger and moved in the same transaction as the entry
  -- that changes it. bin/reconcile_customers.php proves the two still agree.
  `balance_owed`  DECIMAL(14,2) NOT NULL DEFAULT 0,
  `is_active`     TINYINT(1)   NOT NULL DEFAULT 1,
  `created_by`    INT UNSIGNED NULL DEFAULT NULL,
  `created_at`    TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at`    TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  -- One row per phone per restaurant. Without it the same person is entered
  -- twice by two waiters and their debt splits across both records.
  UNIQUE KEY `uq_customers_restaurant_phone` (`restaurant_id`, `phone`),
  KEY `ix_customers_restaurant_name` (`restaurant_id`, `name`),
  KEY `ix_customers_restaurant_owed` (`restaurant_id`, `balance_owed`),
  CONSTRAINT `fk_customers_restaurant` FOREIGN KEY (`restaurant_id`)
    REFERENCES `restaurants` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Append-only. Nothing here is updated or deleted: a cancelled charge is a
-- second, opposite entry, so the trail explains every movement instead of
-- quietly losing the one that turned out to be wrong.
-- ---------------------------------------------------------------------------
-- Request keys.
--
-- A deposit sent twice is two deposits. The button is disabled while it saves,
-- but a request that times out and is retried — by the client, by a proxy, by
-- a user on a bad connection tapping again — lands twice on the server and
-- there was nothing to tell the second one apart from a genuine second
-- deposit.
--
-- The client sends a key it generated for that one action. The unique index is
-- what enforces it: the second insert fails, and the handler answers with what
-- the first one returned rather than doing the work again.
-- ---------------------------------------------------------------------------
-- ---------------------------------------------------------------------------
-- Messages from DACAAM to the restaurants running it.
--
-- `restaurant_id` null is every restaurant; `user_id` null is everyone inside
-- the one addressed. That gives the three shapes the dashboard sends — the
-- whole platform, one shop, one person — without a separate table per shape.
--
-- The row is the message. Whether a given person has read it lives in
-- `notification_reads`, because one broadcast is read by forty people at
-- forty different moments and a `read_at` on the message could only ever
-- record the last of them.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `notifications` (
  `id`            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `restaurant_id` INT UNSIGNED NULL DEFAULT NULL,
  `user_id`       INT UNSIGNED NULL DEFAULT NULL,
  `title`         VARCHAR(150)  NOT NULL,
  `body`          VARCHAR(1000) NOT NULL,
  -- What it looks like when it lands: a plain message, something that wants
  -- attention, or a warning. Drives the colour and the icon, nothing else.
  `kind`          VARCHAR(20)   NOT NULL DEFAULT 'info',
  `sent_by`       INT UNSIGNED  NULL DEFAULT NULL,
  `created_at`    DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `ix_notifications_restaurant` (`restaurant_id`, `created_at`),
  KEY `ix_notifications_user` (`user_id`, `created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `notification_reads` (
  `id`              BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `notification_id` BIGINT UNSIGNED NOT NULL,
  `user_id`         INT UNSIGNED NOT NULL,
  `read_at`         DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `ux_notification_reads` (`notification_id`, `user_id`),
  CONSTRAINT `fk_notification_reads_notification` FOREIGN KEY (`notification_id`)
    REFERENCES `notifications` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- Where to deliver.
--
-- Registered when the app starts, before anybody signs in — which is the whole
-- point: a handset that has been opened once can be reached with a general
-- message even while nobody is logged in. `user_id` is filled in at sign-in and
-- is what makes a message to one person possible.
--
-- The token is the identity, not the device: Android reissues it on reinstall
-- and occasionally on its own, so the app sends whatever it currently holds and
-- the unique index folds duplicates together.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `device_tokens` (
  `id`            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `token`         VARCHAR(255) NOT NULL,
  `restaurant_id` INT UNSIGNED NULL DEFAULT NULL,
  `user_id`       INT UNSIGNED NULL DEFAULT NULL,
  `platform`      VARCHAR(20)  NOT NULL DEFAULT 'android',
  `last_seen_at`  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `created_at`    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `ux_device_tokens_token` (`token`),
  KEY `ix_device_tokens_user` (`user_id`),
  KEY `ix_device_tokens_restaurant` (`restaurant_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
CREATE TABLE IF NOT EXISTS `request_keys` (
  `id`            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `restaurant_id` INT UNSIGNED NOT NULL,
  `request_key`   VARCHAR(64)  NOT NULL,
  `endpoint`      VARCHAR(120) NOT NULL,
  `response`      MEDIUMTEXT   NULL DEFAULT NULL,
  `created_at`    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `ux_request_keys` (`restaurant_id`, `request_key`),
  KEY `ix_request_keys_created` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
CREATE TABLE IF NOT EXISTS `customer_ledger` (
  `id`            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `restaurant_id` INT UNSIGNED NOT NULL,
  `customer_id`   INT UNSIGNED NOT NULL,
  `kind`          ENUM('charge','payment','deposit','refund','adjustment') NOT NULL,
  -- Signed like balance_owed: a charge is positive, a payment negative. The
  -- balance is the sum of this column and nothing else.
  `amount`        DECIMAL(14,2) NOT NULL,
  `balance_after` DECIMAL(14,2) NOT NULL DEFAULT 0,
  -- Which account took the money, for payments and deposits. Null on a charge:
  -- no cash moved there, only the promise of it.
  `account_id`    INT UNSIGNED NULL DEFAULT NULL,
  `method`        VARCHAR(32)  NOT NULL DEFAULT '',
  `description`   VARCHAR(255) NOT NULL DEFAULT '',
  `source_type`   VARCHAR(32)  NOT NULL DEFAULT '' COMMENT 'order, manual, reversal',
  `source_id`     BIGINT UNSIGNED NULL DEFAULT NULL,
  -- The controller requires this on an adjustment. A hand-made balance change
  -- with no reason is indistinguishable from theft.
  `reason`        VARCHAR(255) NULL DEFAULT NULL,
  `created_by`    INT UNSIGNED NULL DEFAULT NULL,
  `created_at`    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `ix_customer_ledger_customer` (`customer_id`, `created_at`),
  KEY `ix_customer_ledger_restaurant` (`restaurant_id`, `created_at`),
  KEY `ix_customer_ledger_source` (`source_type`, `source_id`),
  KEY `ix_customer_ledger_kind` (`restaurant_id`, `kind`, `created_at`),
  CONSTRAINT `fk_customer_ledger_customer` FOREIGN KEY (`customer_id`)
    REFERENCES `customers` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
