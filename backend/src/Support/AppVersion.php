<?php

declare(strict_types=1);

namespace Dacaam\Support;

use Dacaam\Core\Database;

/**
 * Which version of the mobile app the platform expects.
 *
 * The APK is handed out directly rather than through a store, so nothing tells
 * a restaurant that a newer one exists. The app asks this on start: below the
 * minimum it refuses to run and points at the download, below the latest it
 * only mentions it.
 *
 * Empty settings mean "no requirement" — which is also what a server that has
 * never been configured says, so a fresh install locks nobody out.
 */
final class AppVersion
{
    public const KEYS = [
        'min_version'    => 'app_min_version',
        'latest_version' => 'app_latest_version',
        'download_url'   => 'app_download_url',
        'message'        => 'app_update_message',
    ];

    /** @return array{min_version:string,latest_version:string,download_url:string,message:string} */
    public static function current(): array
    {
        $rows = Database::select(
            'SELECT key_name, value FROM system_settings
              WHERE key_name IN ("app_min_version", "app_latest_version",
                                 "app_download_url", "app_update_message")',
        );
        $stored = array_column($rows, 'value', 'key_name');

        $out = [];
        foreach (self::KEYS as $field => $key) {
            $out[$field] = trim((string) ($stored[$key] ?? ''));
        }

        return $out;
    }

    /** `1.2.0`, `1.2`, `2` — dotted numbers, nothing else. */
    public static function isValid(string $version): bool
    {
        return preg_match('/^\d{1,4}(\.\d{1,4}){0,2}$/', $version) === 1;
    }

    /** Negative, zero or positive, like strcmp — `1.10.0` is newer than `1.9.0`. */
    public static function compare(string $a, string $b): int
    {
        $pa = array_map('intval', explode('.', $a));
        $pb = array_map('intval', explode('.', $b));

        for ($i = 0; $i < 3; $i++) {
            $diff = ($pa[$i] ?? 0) <=> ($pb[$i] ?? 0);
            if ($diff !== 0) {
                return $diff;
            }
        }

        return 0;
    }
}
