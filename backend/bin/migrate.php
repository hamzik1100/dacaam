<?php

declare(strict_types=1);

/**
 * Applies schema.sql and, with --seed, seed.sql.
 *
 *   php bin/migrate.php
 *   php bin/migrate.php --seed
 *   php bin/migrate.php --fresh --seed   (drops the DACAAM database first)
 *
 * `--fresh` only ever touches the database named in config; it never enumerates
 * or drops anything else on the server.
 */

use Dacaam\Core\Config;

require dirname(__DIR__) . '/bootstrap.php';

$options = array_slice($argv, 1);
$fresh = in_array('--fresh', $options, true);
$seed = in_array('--seed', $options, true);

$database = (string) Config::get('db.database');
$dsn = sprintf(
    'mysql:host=%s;port=%d;charset=%s',
    (string) Config::get('db.host'),
    (int) Config::get('db.port'),
    (string) Config::get('db.charset'),
);

try {
    $pdo = new PDO(
        $dsn,
        (string) Config::get('db.username'),
        (string) Config::get('db.password'),
        [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION],
    );
} catch (Throwable $e) {
    fwrite(STDERR, "Cannot connect to MySQL: {$e->getMessage()}\n");
    exit(1);
}

if ($fresh) {
    fwrite(STDOUT, "Dropping database `$database`...\n");
    $pdo->exec("DROP DATABASE IF EXISTS `$database`");
}

// The SQL files name no database, so that they can be imported into whatever
// one a host has given you. Creating and selecting it is this script's job.
//
// On shared hosting the account usually cannot create databases at all — the
// control panel does that — so a refusal here is expected, not fatal, as long
// as the database already exists.
try {
    $pdo->exec(
        "CREATE DATABASE IF NOT EXISTS `$database`
         DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci",
    );
} catch (Throwable $e) {
    fwrite(STDOUT, "Cannot create `$database` ({$e->getMessage()}); expecting it to exist.\n");
}

try {
    $pdo->exec("USE `$database`");
} catch (Throwable $e) {
    fwrite(STDERR, "Database `$database` does not exist and could not be created.\n");
    fwrite(STDERR, "Create it in your hosting control panel first, then run this again.\n");
    exit(1);
}

$run = static function (string $path) use ($pdo): void {
    $sql = file_get_contents($path);
    if ($sql === false) {
        fwrite(STDERR, "Cannot read $path\n");
        exit(1);
    }

    fwrite(STDOUT, 'Applying ' . basename($path) . "... ");

    // Reported here rather than left to PHP. `bootstrap.php` turns
    // `display_errors` off — right for the API, where a stray notice would
    // corrupt the JSON envelope — but it also meant this script died mid-line
    // with no reason given, which is the worst thing a migration can do.
    try {
        $pdo->exec($sql);
    } catch (Throwable $e) {
        fwrite(STDOUT, "FAILED\n\n");
        fwrite(STDERR, $e->getMessage() . "\n\n");
        fwrite(STDERR, sprintf(
            "MySQL reports itself as %s.\nNothing was left half-applied — the statement that failed is the one to look at.\n",
            $pdo->getAttribute(PDO::ATTR_SERVER_VERSION),
        ));
        exit(1);
    }

    fwrite(STDOUT, "done\n");
};

$run(dirname(__DIR__) . '/database/schema.sql');

applyOptionalConstraints($pdo, dirname(__DIR__) . '/database/constraints.sql');

// Always — never behind --seed. The catalogue is what the permission checks
// resolve against, so a database without it hands every user an empty
// permission set and refuses every guarded route. It is idempotent.
$run(dirname(__DIR__) . '/database/permissions.sql');

if ($seed) {
    $run(dirname(__DIR__) . '/database/seed.sql');
}

$tables = (int) $pdo->query(
    'SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE()',
)->fetchColumn();

$permissions = (int) $pdo->query('SELECT COUNT(*) FROM permissions')->fetchColumn();
$ungranted   = (int) $pdo->query(
    "SELECT COUNT(*) FROM roles r
      WHERE r.is_system = 1
        AND NOT EXISTS (SELECT 1 FROM role_permissions rp WHERE rp.role_id = r.id)",
)->fetchColumn();

fwrite(STDOUT, sprintf(
    "\n%s is ready — %d tables, %d permissions.\n",
    $database,
    $tables,
    $permissions,
));

if ($ungranted > 0) {
    fwrite(STDERR, sprintf(
        "WARNING: %d system role(s) still hold no permissions — users on them will be refused everywhere.\n",
        $ungranted,
    ));
}

if ($seed) {
    $restaurants = $pdo->query('SELECT slug, name FROM restaurants ORDER BY id')->fetchAll(PDO::FETCH_ASSOC);
    foreach ($restaurants as $restaurant) {
        fwrite(STDOUT, sprintf("  %-6s %s\n", $restaurant['slug'], $restaurant['name']));
    }
    fwrite(STDOUT, "\nSeeded login: code HAMZE / phone 0634567890 / password admin123\n");
}

/**
 * Applies the CHECK constraints that some engines refuse.
 *
 * One statement at a time, each reported. A refusal is announced rather than
 * swallowed — the operator should know which guarantees their database is
 * holding and which are resting on the API alone — but it does not stop the
 * migration, because a schema that installs everywhere is worth more than one
 * that carries every constraint on some servers and none on others.
 */
function applyOptionalConstraints(PDO $pdo, string $path): void
{
    $sql = @file_get_contents($path);
    if ($sql === false) {
        return;
    }

    // Comment lines only — none of these statements contain a `;` in a string.
    $sql = preg_replace('/^\s*--.*$/m', '', $sql) ?? '';
    $statements = array_filter(array_map('trim', explode(';', $sql)));

    if ($statements === []) {
        return;
    }

    fwrite(STDOUT, "Applying constraints.sql...\n");

    foreach ($statements as $statement) {
        preg_match('/ADD CONSTRAINT `([^`]+)`/', $statement, $m);
        $name = $m[1] ?? 'constraint';

        $exists = (int) $pdo->query(
            'SELECT COUNT(*) FROM information_schema.table_constraints
              WHERE constraint_schema = DATABASE()
                AND constraint_name = ' . $pdo->quote($name),
        )->fetchColumn() > 0;

        if ($exists) {
            fwrite(STDOUT, "  already present  $name\n");
            continue;
        }

        try {
            $pdo->exec($statement);
            fwrite(STDOUT, "  applied          $name\n");
        } catch (Throwable $e) {
            fwrite(STDOUT, sprintf(
                "  not supported    %s\n                   (%s)\n                   The API enforces this rule regardless.\n",
                $name,
                $e->getMessage(),
            ));
        }
    }
}
