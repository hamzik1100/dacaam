<?php

declare(strict_types=1);

/**
 * Counting every account, not only the cash drawer.
 *
 * The first version counted cash and reconciled nothing else, on the reasoning
 * that a Zaad balance is whatever the provider says. That was too clever: the
 * cashier can open the Zaad app and read the balance, so it can be checked —
 * and a payment recorded as Zaad that never arrived is exactly the kind of hole
 * that leaving it unchecked would keep open.
 *
 * So every active account is counted at close, each with its own expected,
 * counted and difference. Cash short by twenty thousand while Zaad is over by
 * twenty thousand nets to nothing and is two separate problems; one figure for
 * the whole till would have hidden both.
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

$made = 0;

if (!$hasTable('shift_counts')) {
    Database::run(
        'CREATE TABLE `shift_counts` (
          `id`         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
          `shift_id`   BIGINT UNSIGNED NOT NULL,
          `account_id` INT UNSIGNED NOT NULL,

          -- What the ledger says should be there, what the person found, and
          -- the gap. Stored rather than recomputed: the expected figure is a
          -- statement about a moment, and re-deriving it next week from a
          -- ledger that has moved on would quietly change history.
          `expected`   DECIMAL(14,2) NOT NULL DEFAULT 0.00,
          `counted`    DECIMAL(14,2) NOT NULL DEFAULT 0.00,
          `variance`   DECIMAL(14,2) NOT NULL DEFAULT 0.00,

          `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

          PRIMARY KEY (`id`),
          -- One count per account per shift. A retry that slipped through the
          -- double-close guard cannot post a second set of figures.
          UNIQUE KEY `ux_shift_counts` (`shift_id`, `account_id`),
          KEY `ix_shift_counts_account` (`account_id`, `created_at`),
          CONSTRAINT `fk_shift_counts_shift` FOREIGN KEY (`shift_id`)
            REFERENCES `shifts` (`id`) ON DELETE CASCADE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci',
    );
    echo "shift_counts: waa la abuuray.\n";
    $made++;
} else {
    echo "shift_counts: horeba wuu u jiray.\n";
}

// A till that is open is now required before anything can be sold, so the
// column that counted orders taken outside one no longer has anything to
// count. Left in place rather than dropped: the rows already written are a
// record of how things were before the rule changed, and dropping a column to
// tidy up is how history gets erased.
echo "\n";
echo $made === 0
    ? "Wax cusub ma jirin — horeba wuu u diyaar ahaa.\n"
    : "$made isbeddel ayaa la sameeyay.\n";
