<?php

declare(strict_types=1);

/**
 * Super Admin bootstrap.
 *
 * Reuses the API's `Config` and `Database` rather than re-declaring them — one
 * connection story, one place to change credentials. Everything specific to
 * the platform dashboard lives under the `DacaamAdmin\` namespace.
 */

require dirname(__DIR__) . '/backend/bootstrap.php';

spl_autoload_register(static function (string $class): void {
    $prefix = 'DacaamAdmin\\';
    if (!str_starts_with($class, $prefix)) {
        return;
    }

    $file = __DIR__ . '/src/'
        . str_replace('\\', '/', substr($class, strlen($prefix)))
        . '.php';

    if (is_file($file)) {
        require_once $file;
    }
});

// This is a browser app, not an API: sessions carry the login. Cookie flags are
// set before the session starts, because PHP cannot change them afterwards.
if (session_status() === PHP_SESSION_NONE) {
    session_set_cookie_params([
        'lifetime' => 0,
        'path'     => '/',
        'httponly' => true,
        // Lax rather than Strict: the dashboard is navigated to from links and
        // bookmarks, and Strict would drop the session on those first hits.
        'samesite' => 'Lax',
        // Apache reports 'on', some SAPIs report '1', and a few report 'off'
        // rather than omitting it. Testing for 'on' alone quietly shipped a
        // session cookie without the Secure flag on the other two.
        'secure'   => ($_SERVER['HTTPS'] ?? '') !== ''
            && strtolower((string) $_SERVER['HTTPS']) !== 'off',
    ]);
    session_name('dacaam_admin');
    session_start();
}
