<?php

declare(strict_types=1);

/**
 * Repairs orders that spent a customer's deposit without recording it.
 *
 *   php bin/repair_wallet_orders.php          (report only)
 *   php bin/repair_wallet_orders.php --fix    (write the missing rows)
 *
 * The defect: `chargeCustomer` treated `payment_mode = credit` as "ignore the
 * wallet" and wrote no payment row. But `balance_owed` moved by the full total
 * regardless, so a customer sitting at -200,000 who ordered 40,000 on credit
 * ended at -160,000 — their deposit was spent — while the order stayed
 * `unpaid` with nothing recording where the money went. The receipt printed a
 * balance owing on a sale that was settled.
 *
 * Nothing is guessed. Every `customer_ledger` charge carries `balance_after`,
 * so the balance *before* it is `balance_after - amount`, and if that was
 * negative the deposit covered `min(-before, amount)` of the order. That is
 * arithmetic on rows the server itself wrote, not a reconstruction.
 *
 * Idempotent: it only ever adds the wallet payment that should have been there,
 * and skips any order that already has one.
 */

use Dacaam\Core\Database;
use Dacaam\Support\Pricing;

require dirname(__DIR__) . '/bootstrap.php';

$fix = in_array('--fix', array_slice($argv, 1), true);

// Every order charge, with what the customer's balance was just before it and
// what has since been recorded as paid against that order.
$rows = Database::select(
    'SELECT l.id            AS ledger_id,
            l.restaurant_id,
            l.customer_id,
            l.source_id     AS order_id,
            l.amount,
            l.balance_after,
            l.created_by,
            c.name          AS customer_name,
            o.order_number,
            o.total,
            o.status,
            o.payment_status,
            COALESCE((
                SELECT SUM(p.amount) FROM order_payments p
                 WHERE p.order_id = l.source_id AND p.restaurant_id = l.restaurant_id
            ), 0)           AS paid
       FROM customer_ledger l
       JOIN customers c ON c.id = l.customer_id
       JOIN orders    o ON o.id = l.source_id AND o.restaurant_id = l.restaurant_id
      WHERE l.kind = "charge"
        AND l.source_type = "order"
        AND o.status <> "cancelled"
      ORDER BY l.id ASC',
);

$damaged = [];

foreach ($rows as $r) {
    $amount = Pricing::round((float) $r['amount']);
    $before = Pricing::round((float) $r['balance_after'] - $amount);

    // Only a customer who was in credit at that moment had a deposit to spend.
    if ($before >= -0.001) {
        continue;
    }

    $fromWallet = Pricing::round(min(-$before, $amount));
    $paid = Pricing::round((float) $r['paid']);
    $missing = Pricing::round($fromWallet - $paid);

    // Already recorded, in whole or in part by some other payment — leave it.
    if ($missing <= 0.001) {
        continue;
    }

    $damaged[] = $r + ['from_wallet' => $fromWallet, 'missing' => $missing];
}

if ($damaged === []) {
    echo "Waxba lama helin — dalab kasta oo jeeb laga qaatay wuu diiwaangashan yahay.\n";
    exit(0);
}

printf("%d dalab ayaa jeeb laga qaatay iyadoo aan la diiwaangelin:\n\n", count($damaged));

$total = 0.0;
foreach ($damaged as $d) {
    printf(
        "  #%-6s %-22s jeeb %10s   status %-8s\n",
        (string) $d['order_number'],
        mb_substr((string) $d['customer_name'], 0, 22),
        number_format((float) $d['missing']),
        (string) $d['payment_status'],
    );
    $total += (float) $d['missing'];
}

printf("\n  wadarta: %s\n\n", number_format($total));

if (!$fix) {
    echo "Waxba lama beddelin. Si loo saxo:  php bin/repair_wallet_orders.php --fix\n";
    exit(0);
}

$repaired = 0;

foreach ($damaged as $d) {
    Database::transaction(static function () use ($d, &$repaired): void {
        Database::insert('order_payments', [
            'restaurant_id' => (int) $d['restaurant_id'],
            'order_id'      => (int) $d['order_id'],
            'method'        => 'wallet',
            'amount'        => (float) $d['missing'],
            // Marked so the row is recognisable later as a correction rather
            // than something the till took at the time.
            'reference'     => 'wallet (sixid)',
            'received_by'   => (int) $d['created_by'],
        ]);

        // Recomputed from the payments now on the order, using the same rule
        // the server applies at checkout, so a part-covered order lands on
        // `partial` rather than being forced to `paid`.
        $paid = (float) Database::scalar(
            'SELECT COALESCE(SUM(amount), 0) FROM order_payments
              WHERE order_id = :id AND restaurant_id = :rid',
            ['id' => (int) $d['order_id'], 'rid' => (int) $d['restaurant_id']],
        );

        $outstanding = Pricing::round((float) $d['total'] - $paid);
        $status = $outstanding <= 0.001
            ? 'paid'
            : ($paid > 0.001 ? 'partial' : 'unpaid');

        Database::run(
            'UPDATE orders SET payment_status = :p WHERE id = :id AND restaurant_id = :rid',
            [
                'p'   => $status,
                'id'  => (int) $d['order_id'],
                'rid' => (int) $d['restaurant_id'],
            ],
        );

        printf(
            "  #%-6s -> %s\n",
            (string) $d['order_number'],
            $status,
        );

        $repaired++;
    });
}

printf("\n%d dalab ayaa la saxay.\n", $repaired);
printf("Hadhaagga macaamiisha lama taaban — sax buu ahaa tan iyo markii hore.\n");
