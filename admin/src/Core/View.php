<?php

declare(strict_types=1);

namespace DacaamAdmin\Core;

use RuntimeException;

/**
 * Plain PHP templates.
 *
 * No template engine: the dashboard is a dozen server-rendered pages, and a
 * compiler plus cache directory would be more moving parts than the thing it
 * renders. `e()` is mandatory for anything that came from a database.
 */
final class View
{
    /** @param array<string,mixed> $data */
    public static function render(string $template, array $data = []): void
    {
        echo self::capture($template, $data);
    }

    /** @param array<string,mixed> $data */
    public static function page(string $template, array $data = []): void
    {
        $data['content'] = self::capture($template, $data);
        $data['admin'] ??= AdminAuth::current();
        $data['flash'] ??= Flash::pull();

        echo self::capture('layout', $data);
    }

    /** @param array<string,mixed> $data */
    public static function capture(string $template, array $data = []): string
    {
        $file = dirname(__DIR__) . '/Views/' . $template . '.php';
        if (!is_file($file)) {
            throw new RuntimeException("View not found: $template");
        }

        extract($data, EXTR_SKIP);
        ob_start();
        require $file;

        return (string) ob_get_clean();
    }
}

/** Escapes for HTML. Short name because every echo in a template uses it. */
function e(mixed $value): string
{
    return htmlspecialchars((string) $value, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
}

/** `1250000` → `SLSH 1,250,000` */
function money(mixed $value, string $prefix = 'SLSH'): string
{
    return $prefix . ' ' . number_format((float) $value, 0);
}

function shortDate(mixed $value): string
{
    $ts = strtotime((string) $value);

    return $ts === false ? '—' : date('j M Y', $ts);
}

function dateTime(mixed $value): string
{
    $ts = strtotime((string) $value);

    return $ts === false ? '—' : date('j M Y H:i', $ts);
}
