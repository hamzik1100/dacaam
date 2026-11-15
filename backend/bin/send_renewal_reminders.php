<?php

declare(strict_types=1);

/**
 * Warns restaurants whose subscription is about to end, or just has.
 *
 *   php bin/send_renewal_reminders.php
 *
 * Meant for cron, once a day. Safe to run more often and safe to run by hand
 * after the cron already has: every reminder is recorded before it is sent,
 * and one that has been recorded is never sent again. The Subscriptions page
 * in the dashboard has a button that does the same thing.
 *
 * Emails are queued, not sent here — the outbox drain delivers them, so a
 * mail server that is down loses nothing.
 */

use Dacaam\Support\RenewalReminders;

require dirname(__DIR__) . '/bootstrap.php';

$result = RenewalReminders::send();

foreach ($result['sent'] as $line) {
    echo "  $line\n";
}

printf(
    "\nXusuusin: %d makhaayadood, %d maamule, %d push, %d email (%s)\n",
    $result['restaurants'],
    $result['notified'],
    $result['pushed'],
    $result['emailed'],
    date('Y-m-d'),
);
