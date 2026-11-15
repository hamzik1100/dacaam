<?php

declare(strict_types=1);

/**
 * One-off repair for rows written before the database session had a time zone.
 *
 * PDO never issued `SET time_zone`, so MySQL stamped every DEFAULT
 * CURRENT_TIMESTAMP with the host's zone — UTC on shared hosting — while PHP
 * ran on Africa/Mogadishu. An order placed at 20:23 was stored as 17:23 and
 * read back as "3 saac ka hor". Database::connection() now pins the session,
 * so new rows are right; this shifts the old ones to match.
 *
 * Only DATETIME columns filled by CURRENT_TIMESTAMP are touched, and this is
 * the whole point of the script:
 *
 *   - TIMESTAMP columns are stored internally as UTC and converted on read
 *     using the session zone. They corrected themselves the moment the session
 *     was pinned. Shifting them would push them three hours into the future.
 *
 *   - DATETIME columns with no default — expires_at on tokens, challenges and
 *     password resets — were written by PHP and were always in local time.
 *     Shifting those would move token expiry and log people out.
 *
 * Runs once. The marker in system_settings is what stops a second run turning
 * a three-hour correction into a six-hour error.
 *
 *   php bin/fix_timestamps.php --dry-run
 *   php bin/fix_timestamps.php
 */

require __DIR__ . '/../bootstrap.php';

use Dacaam\Core\Config;
use Dacaam\Core\Database;

const MARKER = 'timestamps_shifted_to_local';

$dry   = in_array('--dry-run', $argv, true);
$force = in_array('--force', $argv, true);

$schema = (string) Database::scalar('SELECT DATABASE()');

$say = static fn (string $line) => fwrite(STDOUT, $line . "\n");

// ------------------------------------------------------------ already done?

$done = Database::selectOne(
    'SELECT `value`, `updated_at` FROM system_settings WHERE key_name = :k',
    ['k' => MARKER],
);

if ($done !== null && !$force) {
    $say('Horeba waa loo maray: ' . (string) $done['updated_at']);
    $say('Mar labaad haddii la maro, 6 saac ayay guuraysaa. --force haddii aad hubto.');
    exit(0);
}

// ------------------------------------------------------------ how far to move

$offset = (new DateTimeImmutable(
    'now',
    new DateTimeZone((string) Config::get('app.timezone')),
))->format('P');

sscanf($offset, '%3d:%2d', $offsetHours, $offsetMinutes);
$minutes = ((int) $offsetHours * 60) + ((int) $offsetHours < 0 ? -(int) $offsetMinutes : (int) $offsetMinutes);

if ($minutes === 0) {
    $say('Offset-ku waa eber — waxba lama wareejinayo.');
    exit(0);
}

$say(sprintf("Database : %s", $schema));
$say(sprintf("Offset   : %s (%d daqiiqo)", $offset, $minutes));
$say($dry ? "DRY RUN — waxba lama qorayo\n" : '');

// ------------------------------------------------- only the affected columns

$columns = Database::select(
    "SELECT TABLE_NAME, COLUMN_NAME
       FROM information_schema.COLUMNS
      WHERE TABLE_SCHEMA = :s
        AND DATA_TYPE = 'datetime'
        AND COLUMN_DEFAULT LIKE '%current_timestamp%'
      ORDER BY TABLE_NAME, COLUMN_NAME",
    ['s' => $schema],
);

if ($columns === []) {
    $say('Column la wareejinayo lama helin.');
    exit(0);
}

// Rows written after the fix went live are already correct. The marker row does
// not exist yet, so the cut-off is the moment this script starts: anything
// stamped later than now-in-UTC cannot be a stale row.
$cutoff = (new DateTimeImmutable('now'))->format('Y-m-d H:i:s');

$total = 0;

foreach ($columns as $column) {
    $table = (string) $column['TABLE_NAME'];
    $col   = (string) $column['COLUMN_NAME'];

    $affected = (int) Database::scalar(
        sprintf('SELECT COUNT(*) FROM `%s` WHERE `%s` <= :cutoff', $table, $col),
        ['cutoff' => $cutoff],
    );

    if ($affected === 0) {
        $say(sprintf('  %-22s %-12s  0', $table, $col));
        continue;
    }

    if (!$dry) {
        Database::run(
            sprintf(
                'UPDATE `%s` SET `%s` = DATE_ADD(`%s`, INTERVAL :m MINUTE) WHERE `%s` <= :cutoff',
                $table,
                $col,
                $col,
                $col,
            ),
            ['m' => $minutes, 'cutoff' => $cutoff],
        );
    }

    $total += $affected;
    $say(sprintf('  %-22s %-12s  %d %s', $table, $col, $affected, $dry ? '(la wareejin lahaa)' : 'la wareejiyay'));
}

$say("\n" . str_repeat('-', 56));

if ($dry) {
    $say(sprintf('%d sadar oo la wareejin lahaa. Dib u ordi --dry-run la\'aan.', $total));
    exit(0);
}

Database::run(
    'INSERT INTO system_settings (key_name, `value`) VALUES (:k, :v)
     ON DUPLICATE KEY UPDATE `value` = :v2',
    ['k' => MARKER, 'v' => (string) $minutes, 'v2' => (string) $minutes],
);

$say(sprintf('%d sadar la wareejiyay. Mar labaad lama marayo.', $total));
