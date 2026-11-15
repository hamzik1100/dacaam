<?php

declare(strict_types=1);

/**
 * Builds a clean upload folder for a hosting account.
 *
 *   php bin/bundle.php            → ../dist
 *   php bin/bundle.php D:/upload  → D:/upload
 *
 * Copies the backend and the Super Admin dashboard, and leaves out everything
 * a server has no business holding: the test suites, the seed data, the local
 * config, git metadata and the mobile app.
 *
 * The exclusions are the point. `seed.sql` creates two demo restaurants whose
 * every password is `admin123`, and `config.local.php` is your database
 * credentials — both have ended up on production servers before, in projects
 * that copied the whole folder up over FTP because that was the quick way.
 */

const EXCLUDED_DIRS = ['.git', 'tests', 'node_modules', 'vendor', '.idea', '.vscode'];

const EXCLUDED_FILES = [
    'config.local.php',   // your credentials
    'seed.sql',           // demo tenants, all with the password admin123
    '.DS_Store',
    'Thumbs.db',
];

// `gz` covers the database backups in storage/backups: they are the whole
// business in one file, they belong on the server only, and a deploy that
// shipped them both ways would be the slowest possible way to leak everything.
const EXCLUDED_EXTENSIONS = ['log', 'jks', 'keystore', 'gz', 'sql'];

$root = dirname(__DIR__, 2);
$target = rtrim($argv[1] ?? ($root . '/dist'), '/\\');

if (is_dir($target)) {
    fwrite(STDERR, "Target already exists: $target\n");
    fwrite(STDERR, "Delete it first, so a stale file cannot survive into the bundle.\n");
    exit(1);
}

$copied = 0;
$skipped = 0;
$bytes = 0;

/** @var array<string,string> $sources source directory => path inside the bundle */
$sources = [
    $root . '/backend' => 'backend',
    $root . '/admin'   => 'admin',
];

foreach ($sources as $from => $to) {
    if (!is_dir($from)) {
        continue;
    }

    $iterator = new RecursiveIteratorIterator(
        new RecursiveDirectoryIterator($from, FilesystemIterator::SKIP_DOTS),
        RecursiveIteratorIterator::SELF_FIRST,
    );

    foreach ($iterator as $item) {
        /** @var SplFileInfo $item */
        $relative = str_replace('\\', '/', substr($item->getPathname(), strlen($from) + 1));

        if (isExcluded($relative, $item->isDir())) {
            $skipped++;
            continue;
        }

        $destination = "$target/$to/$relative";

        if ($item->isDir()) {
            @mkdir($destination, 0755, true);
            continue;
        }

        @mkdir(dirname($destination), 0755, true);
        copy($item->getPathname(), $destination);

        $copied++;
        $bytes += $item->getSize();
    }
}

// The example is the one config file worth shipping: it tells whoever deploys
// this what the real file has to contain.
$example = $root . '/backend/config/config.local.example.php';
if (is_file($example)) {
    copy($example, "$target/backend/config/config.local.example.php");
}

file_put_contents("$target/READ-ME-FIRST.txt", <<<TXT
DACAAM — upload bundle
======================

Upload the two folders in here to your hosting account, then:

  1. Create a MySQL database and user in the control panel.
  2. Copy backend/config/config.local.example.php to config.local.php and fill
     in the database name, user and password the panel gave you.
     Set 'env' => 'production' and 'debug' => false.
  3. Import backend/database/schema.sql through phpMyAdmin, with your new
     database selected. It names no database of its own, so it will install
     into whichever one you have open.
  4. Point your domains at the PUBLIC folders only:
       api.yourdomain.com   -> backend/public
       admin.yourdomain.com -> admin/public
     Nothing above those folders may be reachable over HTTP.
  5. Create your first platform administrator — see backend/README.md.

NOT in this bundle, on purpose:
  - seed.sql       demo restaurants whose every password is admin123
  - config.local.php   your local database credentials
  - tests/         no reason for a server to hold them

Built: %s
TXT
);

file_put_contents(
    "$target/READ-ME-FIRST.txt",
    str_replace('%s', date('Y-m-d H:i'), file_get_contents("$target/READ-ME-FIRST.txt")),
);

printf(
    "Bundle written to %s\n  %d files (%.1f MB), %d excluded\n",
    $target,
    $copied,
    $bytes / 1048576,
    $skipped,
);

function isExcluded(string $relative, bool $isDir): bool
{
    $segments = explode('/', $relative);

    foreach ($segments as $segment) {
        if (in_array($segment, EXCLUDED_DIRS, true)) {
            return true;
        }
    }

    if ($isDir) {
        return false;
    }

    $name = basename($relative);

    return in_array($name, EXCLUDED_FILES, true)
        || in_array(strtolower(pathinfo($name, PATHINFO_EXTENSION)), EXCLUDED_EXTENSIONS, true);
}
