<?php

declare(strict_types=1);

namespace DacaamAdmin\Controllers;

use DacaamAdmin\Core\Csrf;
use DacaamAdmin\Core\Flash;
use DacaamAdmin\Core\PlatformAudit;
use DacaamAdmin\Core\Response;
use DacaamAdmin\Core\View;
use Dacaam\Core\Database;
use Dacaam\Support\Backup;
use Throwable;

/**
 * Database backups: whether they exist, how old, and one button to take one.
 *
 * The page is deliberately blunt about age. A directory with fourteen backups
 * in it looks healthy in a listing and tells you nothing; the only number that
 * matters is how long ago the newest one was written, because that is how much
 * work is lost if the disk goes now.
 *
 * Downloading is not offered. The file is the entire business — every order,
 * every debt, every password hash — and a link that hands it over on a session
 * cookie is a worse risk than the one backups exist to solve. Restoring is an
 * SSH job, done deliberately, by somebody who meant to.
 */
final class BackupController
{
    public function index(): void
    {
        $files = self::files();
        $newest = $files[0] ?? null;

        View::page('backups', [
            'title'   => 'Backups',
            'nav'     => 'backups',
            'files'   => $files,
            'hours'   => $newest === null
                ? null
                : (int) round((time() - $newest['at']) / 3600),
            'total'   => array_sum(array_column($files, 'size')),
            'command' => sprintf(
                'cd %s/dacaam/backend && php bin/backup_db.php',
                rtrim((string) (getenv('DACAAM_HOME') ?: '~/domains/dhuuh.shop'), '/'),
            ),
        ]);
    }

    /**
     * Takes one now.
     *
     * The same script the deploy and the nightly cron run — one implementation,
     * so a backup taken from this button is the same thing that gets restored.
     */
    public function run(): void
    {
        Csrf::verify();

        try {
            $result = Backup::take();
        } catch (Throwable $e) {
            // The reason matters — a missing mysqldump and a full disk need
            // different answers — so the real message is shown.
            Flash::error('Backup failed: ' . $e->getMessage());
            Response::redirect('/backups');

            return;
        }

        PlatformAudit::log(
            'backup_taken',
            null,
            sprintf('%s (%d KB, %s)', $result['name'], (int) round($result['size'] / 1024), $result['method']),
        );

        Flash::success(sprintf('Backup taken — %s.', $result['name']));

        Response::redirect('/backups');
    }

    /**
     * Backs up one restaurant.
     *
     * Separate from the nightly whole-database backup and useful for a
     * different moment: before touching one shop's data, or when a shop asks
     * for a copy of its own records.
     */
    public function takeRestaurant(array $params): void
    {
        Csrf::verify();

        $restaurant = self::restaurant((int) $params['id']);

        try {
            $result = Backup::takeRestaurant((int) $restaurant['id'], (string) $restaurant['slug']);
        } catch (Throwable $e) {
            Flash::error('Backup failed: ' . $e->getMessage());
            Response::redirect('/restaurants/' . $restaurant['id']);

            return;
        }

        PlatformAudit::log(
            'restaurant_backup_taken',
            (int) $restaurant['id'],
            sprintf('%s · %d rows across %d tables', $result['name'], $result['rows'], $result['tables']),
        );

        Flash::success(sprintf('Backed up %d rows.', $result['rows']));
        Response::redirect('/restaurants/' . $restaurant['id']);
    }

    /**
     * Puts one restaurant back to an earlier backup.
     *
     * Guarded by typing the slug, because the cost of a misclick here is one
     * restaurant's entire history. The whole-database restore has no button at
     * all and never will: that one would take every shop with it, and SSH is
     * the right amount of friction for something that final.
     */
    public function restoreRestaurant(array $params): void
    {
        Csrf::verify();

        $restaurant = self::restaurant((int) $params['id']);
        $slug = (string) $restaurant['slug'];
        $confirm = trim((string) ($_POST['confirm'] ?? ''));
        $file = (string) ($_POST['file'] ?? '');

        if (strcasecmp($confirm, $slug) !== 0) {
            Flash::error('Type the restaurant code exactly to confirm a restore.');
            Response::redirect('/restaurants/' . $restaurant['id']);

            return;
        }

        try {
            $result = Backup::restoreRestaurant($file, (int) $restaurant['id'], $slug);
        } catch (Throwable $e) {
            Flash::error('Restore failed, nothing was changed: ' . $e->getMessage());
            Response::redirect('/restaurants/' . $restaurant['id']);

            return;
        }

        PlatformAudit::log(
            'restaurant_restored',
            (int) $restaurant['id'],
            sprintf('from %s · %d rows · safety copy %s', $file, $result['restored'], $result['safety']),
        );

        Flash::success(sprintf(
            'Restored %d rows. The state before this was saved as %s.',
            $result['restored'],
            $result['safety'],
        ));

        Response::redirect('/restaurants/' . $restaurant['id']);
    }

    /** @return array<string,mixed> */
    private static function restaurant(int $id): array
    {
        $row = Database::selectOne(
            'SELECT id, slug, name FROM restaurants WHERE id = :id',
            ['id' => $id],
        );

        if ($row === null) {
            Response::notFound();
        }

        return $row;
    }

    /** @return list<array{name:string,path:string,size:int,at:int}> */
    private static function files(): array
    {
        return Backup::all();
    }
}
