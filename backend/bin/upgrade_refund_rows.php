<?php

declare(strict_types=1);

/**
 * Lets an order record money it gave back.
 *
 * `order_payments` carried CHECK (amount >= 0), written when a payment could
 * only ever add. Then editing a paid order down became possible: the till was
 * refunded and the ledger recorded it, but the order went on saying the full
 * amount had been collected. An order billed 40,000 sat there claiming 110,000
 * in payments, and the Payment-method report — which sums these rows — reported
 * cash the restaurant did not have, while the shift, which derives from the
 * ledger, had it right.
 *
 * Two screens disagreeing about the same money is the worst possible answer,
 * because afterwards neither can be trusted.
 *
 * A refund is now a negative row rather than an edit to the original. What was
 * taken and what was handed back are two separate facts and the trail holds
 * both; every consumer already sums the column, so the arithmetic comes out
 * right with no other change. Zero is still refused — a payment of nothing is
 * not an event.
 *
 * Idempotent, like the rest of the chain.
 */

use Dacaam\Core\Database;

require dirname(__DIR__) . '/bootstrap.php';

$constraint = Database::selectOne(
    'SELECT cc.CHECK_CLAUSE
       FROM information_schema.CHECK_CONSTRAINTS cc
       JOIN information_schema.TABLE_CONSTRAINTS tc
         ON tc.CONSTRAINT_NAME = cc.CONSTRAINT_NAME
        AND tc.CONSTRAINT_SCHEMA = cc.CONSTRAINT_SCHEMA
      WHERE cc.CONSTRAINT_SCHEMA = DATABASE()
        AND tc.TABLE_NAME = "order_payments"
        AND cc.CONSTRAINT_NAME = "chk_order_payments_amount"',
);

if ($constraint === null) {
    echo "chk_order_payments_amount: ma jiro — waxba lama beddelin.\n";
    exit(0);
}

$clause = (string) $constraint['CHECK_CLAUSE'];

// Already relaxed. The clause text is normalised by the server, so the test is
// for what it permits rather than for an exact string.
if (!str_contains($clause, '>= 0')) {
    echo "chk_order_payments_amount: horeba waa la beddelay ($clause).\n";
    exit(0);
}

Database::run('ALTER TABLE `order_payments` DROP CONSTRAINT `chk_order_payments_amount`');
Database::run(
    'ALTER TABLE `order_payments`
       ADD CONSTRAINT `chk_order_payments_amount` CHECK (`amount` <> 0)',
);

echo "chk_order_payments_amount: hadda celin waa la qori karaa.\n";
echo "\n1 isbeddel ayaa la sameeyay.\n";
