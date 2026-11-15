<?php

declare(strict_types=1);

/**
 * Runtime configuration.
 *
 * Values fall back to environment variables so the same file works for local
 * XAMPP and for a deployed host without editing code. Copy `config.local.php`
 * from the example if you need machine-specific overrides — it is gitignored
 * and merged over these defaults.
 */

$env = getenv('APP_ENV') ?: 'local';

$config = [
    'app' => [
        'name'    => 'DACAAM API',
        'version' => 'v1',
        'env'     => $env,
        // Debug adds exception detail — file paths, SQL, class names — to error
        // responses. It follows the environment rather than defaulting to on,
        // so deploying without setting anything is safe; forgetting a flag
        // should not be what leaks a stack trace to the internet.
        'debug'    => filter_var(
            getenv('APP_DEBUG') ?: ($env === 'local' ? 'true' : 'false'),
            FILTER_VALIDATE_BOOL,
        ),
        'timezone' => 'Africa/Mogadishu',
    ],

    // Where uploaded menu photographs are written, and the address they are
    // served from.
    //
    // The directory has to sit under whatever the web server serves, because
    // the point is for Apache to hand the file over directly — a picture that
    // went through PHP on every request would cost more than the picture. The
    // default resolves next to the front controller, which is public_html/api
    // in production and backend/public when running locally.
    // Where database backups are written.
    //
    // Outside anything the web server serves, and outside the deploy bundle:
    // a .sql.gz of the whole business at a guessable URL would be worse than
    // having no backup at all.
    'backup' => [
        'path' => getenv('BACKUP_PATH') ?: null,
    ],

    // Push notifications.
    //
    // The service-account key Firebase issued. It lives beside config.local.php
    // — on the server, out of git — because it can send a notification to every
    // handset running DACAAM. FCM itself costs nothing; this file is the only
    // thing about it worth guarding.
    'firebase' => [
        'key_path' => getenv('FIREBASE_KEY') ?: __DIR__ . '/firebase.json',
    ],

    'uploads' => [
        'path' => getenv('UPLOAD_PATH') ?: null,
        'url'  => getenv('UPLOAD_URL') ?: null,
    ],

    'db' => [
        'host'     => getenv('DB_HOST') ?: '127.0.0.1',
        'port'     => (int) (getenv('DB_PORT') ?: 3306),
        'database' => getenv('DB_DATABASE') ?: 'dacaam_db',
        'username' => getenv('DB_USERNAME') ?: 'root',
        'password' => getenv('DB_PASSWORD') ?: '',
        'charset'  => 'utf8mb4',
    ],

    'auth' => [
        // Tokens are opaque random strings; only their SHA-256 is stored.
        'token_ttl_days'        => 30,
        'max_failed_logins'     => 5,
        'lockout_minutes'       => 15,
        'bcrypt_cost'           => 10,
    ],

    'cors' => [
        // `*` is right for the mobile app, which sends no cookies and is not
        // subject to CORS at all. If you also serve a Flutter *web* build,
        // replace this with that origin — an allowlist of one is enforced,
        // whereas `*` is not an allowlist.
        'allowed_origins' => ['*'],
        'allowed_headers' => ['Content-Type', 'Authorization', 'X-Device'],
        'allowed_methods' => ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
    ],

    'throttle' => [
        // Off only for load testing. The limits themselves live on the routes
        // in public/index.php, next to the endpoints they protect.
        'enabled' => filter_var(getenv('THROTTLE_ENABLED') ?: 'true', FILTER_VALIDATE_BOOL),
    ],
];

$localOverrides = __DIR__ . '/config.local.php';
if (is_file($localOverrides)) {
    /** @var array<string,mixed> $local */
    $local = require $localOverrides;
    foreach ($local as $section => $values) {
        $config[$section] = array_merge($config[$section] ?? [], $values);
    }
}

return $config;
