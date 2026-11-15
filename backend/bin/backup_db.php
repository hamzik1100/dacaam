<?php

declare(strict_types=1);

/**
 * Backs the database up.
 *
 *   php bin/backup_db.php            (write a new backup, prune old ones)
 *   php bin/backup_db.php --list     (report only, changes nothing)
 *
 * A thin wrapper. The work lives in Dacaam\Support\Backup so the nightly cron,
 * the deploy and the dashboard button all run the same code — a backup taken
 * from one is exactly the thing restored from another.
 */

use Dacaam\Support\Backup;

require dirname(__DIR__) . '/bootstrap.php';

$listOnly = in_array('--list', array_slice($argv, 1), true);

if (!$listOnly) {
    try {
        $result = Backup::take();
        printf("Keyd: %s (%s) · %s\n", $result['name'], humanSize($result['size']), $result['method']);
    } catch (Throwable $e) {
        fwrite(STDERR, $e->getMessage() . "\n");
        exit(1);
    }
}

report();

function report(): void
{
    $files = Backup::all();

    if ($files === []) {
        echo "Keyd ma jiro.\n";

        return;
    }

    $newest = $files[0];
    $hours = (int) round((time() - $newest['at']) / 3600);

    printf(
        "%d keyd · kii ugu dambeeyay %s (%s, %d saacadood ka hor)\n",
        count($files),
        $newest['name'],
        humanSize($newest['size']),
        $hours,
    );

    // The number that matters. A directory nobody has written to for three days
    // looks healthy in a listing and is not.
    if ($hours > 48) {
        echo "DIGNIIN: kii ugu dambeeyay wuu duugoobay — cron-ku ma ordayo?\n";
    }
}

function humanSize(int $bytes): string
{
    return $bytes > 1048576
        ? sprintf('%.1f MB', $bytes / 1048576)
        : sprintf('%.0f KB', $bytes / 1024);
}
