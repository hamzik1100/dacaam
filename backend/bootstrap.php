<?php

declare(strict_types=1);

/**
 * Shared bootstrap for the HTTP front controller and the CLI scripts.
 *
 * No Composer: a single PSR-4 autoloader keeps deployment to a shared PHP host
 * as simple as copying the folder.
 */

use Dacaam\Core\Config;

spl_autoload_register(static function (string $class): void {
    $prefix = 'Dacaam\\';
    if (!str_starts_with($class, $prefix)) {
        return;
    }

    $relative = substr($class, strlen($prefix));
    $file = __DIR__ . '/src/' . str_replace('\\', '/', $relative) . '.php';

    if (is_file($file)) {
        require_once $file;
    }
});

date_default_timezone_set((string) Config::get('app.timezone', 'UTC'));

// Errors are logged, never printed: a stray notice in the response body would
// corrupt the JSON envelope the client is parsing.
ini_set('display_errors', '0');
ini_set('log_errors', '1');
error_reporting(E_ALL);
