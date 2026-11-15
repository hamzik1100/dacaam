<?php

declare(strict_types=1);

namespace DacaamAdmin\Core;

/**
 * Streams a table as a CSV download.
 *
 * Two details that matter more than they look:
 *
 *   - A UTF-8 byte-order mark first. Without it Excel reads the file as the
 *     local code page and every Somali name with an apostrophe, and every
 *     emoji, arrives as mojibake.
 *   - A cell that starts with = + - or @ is prefixed with an apostrophe.
 *     Restaurant and customer names are typed by other people, and a name
 *     like `=HYPERLINK(...)` would otherwise run as a formula on the desk of
 *     whoever opened the export.
 */
final class Csv
{
    /**
     * @param list<string>                  $headers
     * @param iterable<array<string,mixed>> $rows
     */
    public static function download(string $filename, array $headers, iterable $rows): never
    {
        header('Content-Type: text/csv; charset=utf-8');
        header('Content-Disposition: attachment; filename="' . $filename . '"');

        $out = fopen('php://output', 'w');
        fwrite($out, "\xEF\xBB\xBF");
        fputcsv($out, $headers, ',', '"', '');

        foreach ($rows as $row) {
            fputcsv($out, array_map([self::class, 'cell'], array_values($row)), ',', '"', '');
        }

        fclose($out);
        exit;
    }

    /** `Hamze-2026-09-25.csv` — safe in a header and a filesystem. */
    public static function filename(string $name): string
    {
        $name = preg_replace('/[^A-Za-z0-9_-]+/', '-', $name) ?? 'export';

        return trim($name, '-') . '-' . date('Y-m-d') . '.csv';
    }

    private static function cell(mixed $value): string
    {
        $text = (string) ($value ?? '');

        if ($text !== ''
            && in_array($text[0], ['=', '+', '-', '@', "\t", "\r"], true)
            && !is_numeric($text)
        ) {
            return "'" . $text;
        }

        return $text;
    }
}
