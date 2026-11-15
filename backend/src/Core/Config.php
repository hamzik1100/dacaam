<?php

declare(strict_types=1);

namespace Dacaam\Core;

final class Config
{
    /** @var array<string,mixed>|null */
    private static ?array $values = null;

    /**
     * Dot-path lookup: `Config::get('db.host')`.
     */
    public static function get(string $path, mixed $default = null): mixed
    {
        self::$values ??= require dirname(__DIR__, 2) . '/config/config.php';

        $cursor = self::$values;
        foreach (explode('.', $path) as $segment) {
            if (!is_array($cursor) || !array_key_exists($segment, $cursor)) {
                return $default;
            }
            $cursor = $cursor[$segment];
        }

        return $cursor;
    }

    public static function isDebug(): bool
    {
        return (bool) self::get('app.debug', false);
    }
}
