<?php

declare(strict_types=1);

/**
 * One email a day, per restaurant, summarising the traffic that is not worth
 * an interruption on its own.
 *
 *   php bin/send_digest.php            yesterday, every restaurant
 *   php bin/send_digest.php 2026-08-18 a particular day
 *
 * Order edits and menu changes run into the hundreds. Sent individually they
 * train the owner to ignore the sender, and the one message that mattered goes
 * unread with the rest. Collected into a single morning summary they are
 * something a person actually reads — and the count itself carries information
 * an individual email cannot: forty voids in one day is a story, one void is a
 * Tuesday.
 *
 * Meant for cron, once a day. Idempotent per restaurant per day.
 */

use Dacaam\Core\Database;
use Dacaam\Core\Mailer;

require dirname(__DIR__) . '/bootstrap.php';

$day = $argv[1] ?? date('Y-m-d', strtotime('-1 day'));

if (preg_match('/^\d{4}-\d{2}-\d{2}$/', $day) !== 1) {
    fwrite(STDERR, "Taariikhda waa inay noqotaa YYYY-MM-DD\n");
    exit(1);
}

// Deliberately no SMTP check. This script only writes to the outbox; sending
// is the drain's job. Refusing to build the summary because the mail server is
// momentarily misconfigured would lose that day's report for good — the next
// run is for the next day, and nothing ever goes back for the one that was
// skipped. Queue it; it goes out when SMTP is working again.

/** Which audited actions belong to which digest group. */
const DIGEST = [
    'orders' => [
        'orders.item_added'          => 'Alaab lagu daray',
        'orders.item_removed'        => 'Alaab laga saaray',
        'orders.quantity_changed'    => 'Tirada la beddelay',
        'orders.order_total_changed' => 'Wadarta la beddelay',
        'orders.payment_added'       => 'Lacag la bixiyay',
        'customers.customer_created' => 'Macmiil cusub',
        'drafts.draft_updated'       => 'Draft la beddelay',
    ],
    'menu' => [
        'menu.menu_item_updated' => 'Cunto la beddelay',
        'menu.menu_item_created' => 'Cunto cusub',
        'menu.menu_item_deleted' => 'Cunto la tirtiray',
        'menu.category_deleted'  => 'Qayb la tirtiray',
    ],
];

$restaurants = Database::select(
    'SELECT r.id, r.slug, r.name,
            s.alert_email, s.alerts_orders, s.alerts_menu, s.alerts_last_digest
       FROM restaurants r
       JOIN restaurant_settings s ON s.restaurant_id = r.id
      WHERE r.status <> "suspended"',
);

$sent = 0;
$skipped = 0;

foreach ($restaurants as $restaurant) {
    $rid = (int) $restaurant['id'];

    // Already summarised for this day. Re-running the cron, or running it by
    // hand after it already fired, must not send a second copy.
    if ((string) ($restaurant['alerts_last_digest'] ?? '') === $day) {
        $skipped++;
        continue;
    }

    $wanted = [];
    foreach (['orders', 'menu'] as $group) {
        if ((string) $restaurant['alerts_' . $group] === 'digest') {
            $wanted += DIGEST[$group];
        }
    }

    if ($wanted === []) {
        $skipped++;
        continue;
    }

    $rows = Database::select(
        'SELECT module, action, user_name, COUNT(*) AS n
           FROM audit_logs
          WHERE restaurant_id = :rid AND DATE(created_at) = :day
          GROUP BY module, action, user_name
          ORDER BY n DESC',
        ['rid' => $rid, 'day' => $day],
    );

    $lines = [];
    $totals = [];

    foreach ($rows as $row) {
        $key = $row['module'] . '.' . $row['action'];

        if (!isset($wanted[$key])) {
            continue;
        }

        $label = $wanted[$key];
        $totals[$label] = ($totals[$label] ?? 0) + (int) $row['n'];
        $lines[] = sprintf('  %-26s %4d   %s', $label, (int) $row['n'], $row['user_name']);
    }

    if ($lines === []) {
        // Nothing happened. Silence is the correct report — a daily email
        // saying "no changes" is the fastest way to teach someone to filter
        // the sender into the bin.
        Database::run(
            'UPDATE restaurant_settings SET alerts_last_digest = :day WHERE restaurant_id = :rid',
            ['day' => $day, 'rid' => $rid],
        );
        $skipped++;
        continue;
    }

    $recipients = Database::select(
        'SELECT DISTINCT u.email
           FROM users u
           JOIN user_roles ur ON ur.user_id = u.id
           JOIN roles r ON r.id = ur.role_id
          WHERE u.restaurant_id = :rid AND u.is_active = 1
            AND u.email IS NOT NULL AND u.email <> "" AND r.code = "admin"',
        ['rid' => $rid],
    );

    $emails = array_column($recipients, 'email');

    $extra = trim((string) ($restaurant['alert_email'] ?? ''));
    if ($extra !== '') {
        $emails[] = $extra;
    }

    $emails = array_values(array_unique(array_filter(
        $emails,
        static fn ($e): bool => filter_var((string) $e, FILTER_VALIDATE_EMAIL) !== false,
    )));

    if ($emails === []) {
        $skipped++;
        continue;
    }

    $body = [];
    $body[] = 'Warbixinta maalinta — ' . $day;
    $body[] = $restaurant['name'] . ' (' . $restaurant['slug'] . ')';
    $body[] = str_repeat('=', 52);
    $body[] = '';

    arsort($totals);
    foreach ($totals as $label => $n) {
        $body[] = sprintf('  %-26s %4d', $label, $n);
    }

    $body[] = '';
    $body[] = 'Faahfaahin — qofkii sameeyay:';
    $body[] = str_repeat('-', 52);
    $body = array_merge($body, $lines);
    $body[] = '';
    $body[] = 'Wax kasta oo halkan ku qoran waa laga heli karaa Audit Logs.';

    $subject = sprintf('Warbixin maalmeed %s — %s', $day, $restaurant['slug']);

    foreach ($emails as $email) {
        Database::insert('email_outbox', [
            'restaurant_id' => $rid,
            'to_email'      => $email,
            'subject'       => $subject,
            'body'          => implode("\n", $body),
            'event_key'     => 'digest.daily',
        ]);
    }

    Database::run(
        'UPDATE restaurant_settings SET alerts_last_digest = :day WHERE restaurant_id = :rid',
        ['day' => $day, 'rid' => $rid],
    );

    printf("%-10s %d qoraal, %d cinwaan\n", $restaurant['slug'], count($lines), count($emails));
    $sent++;
}

printf("\nWarbixin: %d la diyaariyay, %d la dhaafay (%s)\n", $sent, $skipped, $day);
