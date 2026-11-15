<?php

declare(strict_types=1);

/**
 * Machine-specific overrides.
 *
 * Copy to `config.local.php` — which is gitignored — and change what you need.
 * Sections are merged over the defaults in `config.php`, so you only list the
 * keys you are overriding, not the whole file.
 *
 * Setting environment variables instead works just as well and keeps
 * credentials out of the filesystem entirely; this file exists for hosts that
 * make that awkward.
 */

return [
    'app' => [
        // 'local' keeps debug detail in error responses. Anything else turns
        // it off unless APP_DEBUG says otherwise.
        'env'   => 'production',
        'debug' => false,
    ],

    'db' => [
        'host'     => '127.0.0.1',
        'port'     => 3306,
        'database' => 'dacaam_db',
        'username' => 'dacaam',
        'password' => 'change-me',
    ],

    'auth' => [
        'token_ttl_days'    => 30,
        'max_failed_logins' => 5,
        'lockout_minutes'   => 15,
        // Raise on faster hardware. Each +1 doubles the cost of hashing, for
        // you and for anyone who steals the table.
        'bcrypt_cost'       => 12,
    ],

    'cors' => [
        // Name the web origins explicitly if you serve a Flutter web build.
        // The mobile app does not need an entry here.
        'allowed_origins' => ['https://app.example.com'],
    ],
];
