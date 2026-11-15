<?php

declare(strict_types=1);

/**
 * Proves every customer's cached balance still equals their ledger.
 *
 * `customers.balance_owed` is a cache. It is written in the same transaction as
 * the ledger row that moves it, so the two should never disagree — but "should
 * never" is not a guarantee, and a balance that has quietly drifted is a debt
 * somebody either loses or is wrongly chased for. The same pattern on
 * `accounts.balance` has no such check, which is exactly why this one exists.
 *
 * Read-only unless --fix is passed. Run it after any release that touches the
 * ledger, and on a schedule if you want to sleep.
 *
 *   php bin/reconcile_customers.php
 *   php bin/reconcile_customers.php --fix
 */

require __DIR__ . '/../bootstrap.php';

use Dacaam\Core\Database;
use Dacaam\Support\Pricing;

$fix = in_array('--fix', $argv, true);

$rows = Database::select(
    'SELECT c.id, c.restaurant_id, c.name, c.balance_owed,
            COALESCE((SELECT SUM(l.amount) FROM customer_ledger l
                       WHERE l.customer_id = c.id), 0) AS ledger_sum
       FROM customers c
      ORDER BY c.restaurant_id, c.id',
);

if ($rows === []) {
    fwrite(STDOUT, "Macmiil ma jiro.\n");

    return;
}

$drifted = 0;

foreach ($rows as $row) {
    $cached = Pricing::round((float) $row['balance_owed']);
    $actual = Pricing::round((float) $row['ledger_sum']);

    if (abs($cached - $actual) <= 0.001) {
        continue;
    }

    $drifted++;
    fwrite(STDOUT, sprintf(
        "  #%-4s %-24s keyd=%12s buug=%12s farqi=%s\n",
        $row['id'],
        substr((string) $row['name'], 0, 24),
        number_format($cached, 2),
        number_format($actual, 2),
        number_format($actual - $cached, 2),
    ));

    if ($fix) {
        // The ledger wins. It is the append-only record of what actually
        // happened; the cache is a convenience that got out of step.
        Database::run(
            'UPDATE customers SET balance_owed = :b WHERE id = :id',
            ['b' => $actual, 'id' => $row['id']],
        );
    }
}

fwrite(STDOUT, sprintf(
    "\n%d macmiil la baaray, %d oo kala tegey.%s\n",
    count($rows),
    $drifted,
    $drifted > 0 && !$fix ? ' Isticmaal --fix si buugga loo raaco.' : '',
));

exit($drifted > 0 && !$fix ? 1 : 0);
