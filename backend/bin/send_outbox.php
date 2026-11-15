<?php

declare(strict_types=1);

/**
 * Sends whatever alerts are waiting.
 *
 *   php bin/send_outbox.php
 *
 * Meant for cron, every five minutes. Safe to run twice at once: each message
 * is claimed with a conditional UPDATE before SMTP is touched, so a second copy
 * finds nothing left to take.
 *
 * Also called opportunistically by the API on a small share of requests, so a
 * host with no cron still delivers — just less punctually.
 */

use Dacaam\Core\Mailer;
use Dacaam\Support\Alerts;

require dirname(__DIR__) . '/bootstrap.php';

if (!Mailer::isConfigured()) {
    echo "SMTP lama habayn — waxba lama dirin.\n";
    exit(0);
}

$limit = (int) ($argv[1] ?? 50);
$result = Alerts::drain($limit);

printf("La diray: %d, fashilmay: %d\n", $result['sent'], $result['failed']);

if ($result['failed'] > 0) {
    // Non-zero so a cron that mails its output actually says something. The
    // rows stay in the table either way; the dashboard shows what never went.
    exit(1);
}
