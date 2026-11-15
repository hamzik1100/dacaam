<?php

declare(strict_types=1);

namespace Dacaam\Support;

use Dacaam\Core\Config;
use Dacaam\Core\Database;
use RuntimeException;

/**
 * Database backups.
 *
 * The files are the one thing that can be rebuilt from a developer machine in
 * an hour. The database — every order, every debt, every customer ledger —
 * existed in exactly one place, and a lost disk or one mistyped DROP would have
 * ended the business.
 *
 * Called in-process by both the CLI script and the dashboard button. It used to
 * be a script the dashboard shelled out to, which failed the moment it met a
 * real host: `exec` is in `disable_functions` on most shared hosting, so the
 * button reported an undefined function while the nightly cron ran fine. One
 * implementation, no shelling out, works in both places.
 *
 * Written to survive shared hosting rather than to be elegant:
 *
 *   - `mysqldump` first, because it is fast and correct.
 *   - A pure-PHP dump when the binary is missing or `proc_open` is disabled,
 *     which is common on cheap hosts and is exactly where a backup matters.
 *   - Outside the web root. A .sql.gz of the whole business at a guessable URL
 *     would be worse than having no backup at all.
 */
final class Backup
{
    /** Roughly a fortnight of nightly runs. */
    public const KEEP = 14;

    private function __construct()
    {
    }

    /**
     * Writes a new backup and prunes the old ones.
     *
     * @return array{name:string,size:int,method:string}
     */
    public static function take(): array
    {
        $directory = self::directory();
        $database = (string) Config::get('db.database');
        $name = sprintf('%s-%s.sql.gz', $database, date('Y-m-d-His'));
        $path = $directory . DIRECTORY_SEPARATOR . $name;

        $sql = self::dumpWithBinary($database);
        $method = $sql === null ? 'php' : 'mysqldump';

        if ($sql === null) {
            $sql = self::dumpWithPhp();
        }

        $gz = gzencode($sql, 6);

        if ($gz === false || file_put_contents($path, $gz) === false) {
            throw new RuntimeException("Could not write the backup to $path");
        }

        @chmod($path, 0600);

        // Pruned after the new one is safely written, never before: a prune that
        // ran first and a write that then failed would leave fewer backups than
        // we started with.
        self::prune();

        return ['name' => $name, 'size' => strlen($gz), 'method' => $method];
    }

    /**
     * Tables owned by a restaurant, and how each one is reached.
     *
     * Most carry `restaurant_id`. Seven do not and are reached through their
     * parent — a notification_read belongs to a restaurant only by way of the
     * notification it marks. Getting this list wrong in either direction is
     * serious: miss a table and the backup is incomplete; include a
     * platform-wide one and restoring a single shop wipes something shared.
     *
     * `permissions`, `system_settings`, `super_admins` and `rate_limits` are
     * deliberately absent. They belong to the platform, not to any tenant.
     *
     * Order matters. Parents first, so the reverse of this list deletes
     * children before the rows they point at.
     */
    private const OWNED = [
        'restaurants'  => 'id = :rid',

        'restaurant_settings'   => 'restaurant_id = :rid',
        'subscriptions'         => 'restaurant_id = :rid',
        'subscription_payments' => 'restaurant_id = :rid',
        'roles'                 => 'restaurant_id = :rid',
        'users'                 => 'restaurant_id = :rid',
        'categories'            => 'restaurant_id = :rid',
        'menu_items'            => 'restaurant_id = :rid',
        'tables'                => 'restaurant_id = :rid',
        'customers'             => 'restaurant_id = :rid',
        'customer_ledger'       => 'restaurant_id = :rid',
        'orders'                => 'restaurant_id = :rid',
        'order_items'           => 'restaurant_id = :rid',
        'order_payments'        => 'restaurant_id = :rid',
        'draft_orders'          => 'restaurant_id = :rid',
        'draft_order_items'     => 'restaurant_id = :rid',
        'expenses'              => 'restaurant_id = :rid',
        'expense_categories'    => 'restaurant_id = :rid',
        'accounts'              => 'restaurant_id = :rid',
        'account_transactions'  => 'restaurant_id = :rid',
        'payment_methods'       => 'restaurant_id = :rid',
        'audit_logs'            => 'restaurant_id = :rid',
        'notifications'         => 'restaurant_id = :rid',
        'device_tokens'         => 'restaurant_id = :rid',
        'request_keys'          => 'restaurant_id = :rid',
        'api_tokens'            => 'restaurant_id = :rid',
        'auth_challenges'       => 'restaurant_id = :rid',
        'login_attempts'        => 'restaurant_id = :rid',

        'role_permissions'          => 'role_id IN (SELECT id FROM roles WHERE restaurant_id = :rid)',
        'user_roles'                => 'user_id IN (SELECT id FROM users WHERE restaurant_id = :rid)',
        'user_permissions'          => 'user_id IN (SELECT id FROM users WHERE restaurant_id = :rid)',
        'password_resets'           => 'user_id IN (SELECT id FROM users WHERE restaurant_id = :rid)',
        'two_factor_recovery_codes' => 'user_id IN (SELECT id FROM users WHERE restaurant_id = :rid)',
        'two_factor_used_codes'     => 'user_id IN (SELECT id FROM users WHERE restaurant_id = :rid)',
        'notification_reads'        => 'notification_id IN (SELECT id FROM notifications WHERE restaurant_id = :rid)',
    ];

    /**
     * Backs up one restaurant.
     *
     * Rows only, no schema: this is restored into a live database whose tables
     * already exist and are shared with every other tenant. A dump carrying
     * CREATE TABLE would be a dump that could drop forty other restaurants on
     * its way in.
     *
     * @return array{name:string,size:int,tables:int,rows:int}
     */
    public static function takeRestaurant(int $restaurantId, string $slug): array
    {
        $out = sprintf(
            "-- DACAAM restaurant backup\n-- %s (#%d)\n-- %s\n\n",
            $slug,
            $restaurantId,
            date('c'),
        );

        $tables = 0;
        $rows = 0;

        foreach (self::OWNED as $table => $where) {
            if (!self::tableExists($table)) {
                continue;
            }

            $records = Database::select(
                sprintf('SELECT * FROM `%s` WHERE %s', $table, $where),
                ['rid' => $restaurantId],
            );

            if ($records === []) {
                continue;
            }

            $tables++;
            $out .= sprintf("-- %s (%d)\n", $table, count($records));

            foreach ($records as $record) {
                $rows++;
                $out .= sprintf(
                    "INSERT INTO `%s` (`%s`) VALUES (%s);\n",
                    $table,
                    implode('`, `', array_keys($record)),
                    implode(', ', array_map(
                        static fn ($v): string => $v === null
                            ? 'NULL'
                            : "'" . addslashes((string) $v) . "'",
                        array_values($record),
                    )),
                );
            }

            $out .= "\n";
        }

        $name = sprintf('%s-%s.rsql.gz', $slug, date('Y-m-d-His'));
        $path = self::directory() . DIRECTORY_SEPARATOR . $name;
        $gz = gzencode($out, 6);

        if ($gz === false || file_put_contents($path, $gz) === false) {
            throw new RuntimeException("Could not write the backup to $path");
        }

        @chmod($path, 0600);

        return ['name' => $name, 'size' => strlen($gz), 'tables' => $tables, 'rows' => $rows];
    }

    /**
     * Puts one restaurant back as it was.
     *
     * Everything that restaurant currently has is deleted and replaced. That is
     * the point — and it is why a fresh backup of the present state is taken
     * first, without being asked. Somebody restoring last Tuesday because of a
     * mistake made on Wednesday will sooner or later want Wednesday back.
     *
     * The whole thing is one transaction. A restore that deleted the current
     * rows and then failed halfway through the inserts would leave a shop with
     * no menu, no staff and no history — considerably worse than whatever it
     * was called in to fix.
     *
     * Foreign key checks are off inside it because the inserts arrive in table
     * order rather than dependency order, exactly as a dump does.
     *
     * @return array{restored:int,safety:string}
     */
    public static function restoreRestaurant(string $file, int $restaurantId, string $slug): array
    {
        $path = self::directory() . DIRECTORY_SEPARATOR . basename($file);

        if (!is_file($path)) {
            throw new RuntimeException('That backup no longer exists');
        }

        $sql = gzdecode((string) file_get_contents($path));

        if ($sql === false || !str_contains($sql, 'INSERT INTO')) {
            throw new RuntimeException('That file is not a readable restaurant backup');
        }

        $safety = self::takeRestaurant($restaurantId, $slug . '-before-restore');

        $statements = array_values(array_filter(
            array_map('trim', explode("\n", $sql)),
            static fn (string $line): bool => str_starts_with($line, 'INSERT INTO'),
        ));

        $restored = Database::transaction(static function () use ($restaurantId, $statements): int {
            Database::run('SET FOREIGN_KEY_CHECKS = 0');

            foreach (array_reverse(array_keys(self::OWNED)) as $table) {
                if (!self::tableExists($table)) {
                    continue;
                }

                Database::run(
                    sprintf('DELETE FROM `%s` WHERE %s', $table, self::OWNED[$table]),
                    ['rid' => $restaurantId],
                );
            }

            $count = 0;

            foreach ($statements as $statement) {
                Database::run($statement);
                $count++;
            }

            Database::run('SET FOREIGN_KEY_CHECKS = 1');

            return $count;
        });

        return ['restored' => $restored, 'safety' => $safety['name']];
    }

    /**
     * The backups belonging to one restaurant, newest first.
     *
     * @return list<array{name:string,path:string,size:int,at:int}>
     */
    public static function forRestaurant(string $slug): array
    {
        return array_values(array_filter(
            self::all('*.rsql.gz'),
            static fn (array $f): bool => str_starts_with($f['name'], $slug . '-'),
        ));
    }

    private static function tableExists(string $table): bool
    {
        static $known = null;

        if ($known === null) {
            $known = [];

            foreach (Database::select(
                'SELECT table_name t FROM information_schema.tables
                  WHERE table_schema = DATABASE() AND table_type = "BASE TABLE"',
            ) as $row) {
                $known[(string) $row['t']] = true;
            }
        }

        return isset($known[$table]);
    }

    /** @return list<array{name:string,path:string,size:int,at:int}> */
    public static function all(string $pattern = '*.sql.gz'): array
    {
        $files = [];

        foreach (glob(self::directory() . DIRECTORY_SEPARATOR . $pattern) ?: [] as $path) {
            $files[] = [
                'name' => basename($path),
                'path' => $path,
                'size' => (int) filesize($path),
                'at'   => (int) filemtime($path),
            ];
        }

        // Newest first, which is the order both pruning and reporting want.
        usort($files, static fn (array $a, array $b): int => $b['at'] <=> $a['at']);

        return $files;
    }

    public static function prune(): int
    {
        $removed = 0;

        foreach (array_slice(self::all(), self::KEEP) as $file) {
            if (@unlink($file['path'])) {
                $removed++;
            }
        }

        return $removed;
    }

    /**
     * Outside the web root, created if missing.
     *
     * `storage/backups` sits beside the code, which on this host is a directory
     * Apache never serves.
     */
    public static function directory(): string
    {
        $configured = Config::get('backup.path');

        $path = is_string($configured) && $configured !== ''
            ? $configured
            : dirname(__DIR__, 2) . '/storage/backups';

        if (!is_dir($path) && !mkdir($path, 0700, true) && !is_dir($path)) {
            throw new RuntimeException("Could not create the backup directory: $path");
        }

        // Belt and braces, in case the directory ever ends up somewhere served.
        $htaccess = $path . DIRECTORY_SEPARATOR . '.htaccess';
        if (!is_file($htaccess)) {
            @file_put_contents($htaccess, "Require all denied\n");
        }

        return $path;
    }

    /**
     * mysqldump, when the host allows it. Null when it does not, so the caller
     * falls back rather than failing.
     *
     * The password goes through the environment, never the command line:
     * arguments are readable by every other user on a shared box.
     */
    private static function dumpWithBinary(string $database): ?string
    {
        if (!function_exists('proc_open')) {
            return null;
        }

        $command = sprintf(
            'mysqldump --host=%s --port=%d --user=%s --single-transaction --quick --routines --default-character-set=utf8mb4 %s',
            escapeshellarg((string) Config::get('db.host')),
            (int) Config::get('db.port'),
            escapeshellarg((string) Config::get('db.username')),
            escapeshellarg($database),
        );

        $process = @proc_open(
            $command,
            [1 => ['pipe', 'w'], 2 => ['pipe', 'w']],
            $pipes,
            null,
            ['MYSQL_PWD' => (string) Config::get('db.password')] + $_ENV,
        );

        if (!is_resource($process)) {
            return null;
        }

        $out = (string) stream_get_contents($pipes[1]);
        fclose($pipes[1]);
        fclose($pipes[2]);

        return proc_close($process) === 0 && $out !== '' ? $out : null;
    }

    /**
     * The fallback: every table read through PDO and written as INSERTs.
     *
     * Slower and heavier than mysqldump, and perfectly adequate at this size. It
     * exists because a host without mysqldump is not a host where "no backup" is
     * an acceptable answer.
     */
    private static function dumpWithPhp(): string
    {
        $out = "-- DACAAM backup (PHP)\n"
             . '-- ' . date('c') . "\n"
             . "SET NAMES utf8mb4;\nSET FOREIGN_KEY_CHECKS = 0;\n\n";

        $tables = Database::select(
            'SELECT table_name AS t FROM information_schema.tables
              WHERE table_schema = DATABASE() AND table_type = "BASE TABLE"
              ORDER BY table_name',
        );

        foreach ($tables as $row) {
            $table = (string) $row['t'];
            $create = Database::selectOne(sprintf('SHOW CREATE TABLE `%s`', $table));

            $out .= sprintf("DROP TABLE IF EXISTS `%s`;\n", $table);
            $out .= ($create['Create Table'] ?? '') . ";\n\n";

            // Read in pages. A single fetchAll over a year of audit rows is how
            // a backup script becomes the thing that exhausts the memory limit.
            $offset = 0;

            do {
                $rows = Database::select(
                    sprintf('SELECT * FROM `%s` LIMIT 500 OFFSET %d', $table, $offset),
                );

                foreach ($rows as $record) {
                    $out .= sprintf(
                        "INSERT INTO `%s` (`%s`) VALUES (%s);\n",
                        $table,
                        implode('`, `', array_keys($record)),
                        implode(', ', array_map(
                            static fn ($v): string => $v === null
                                ? 'NULL'
                                : "'" . addslashes((string) $v) . "'",
                            array_values($record),
                        )),
                    );
                }

                $offset += 500;
            } while (count($rows) === 500);

            $out .= "\n";
        }

        return $out . "SET FOREIGN_KEY_CHECKS = 1;\n";
    }
}
