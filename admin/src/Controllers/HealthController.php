<?php

declare(strict_types=1);

namespace DacaamAdmin\Controllers;

use DacaamAdmin\Core\View;
use Dacaam\Core\Database;

/**
 * Errors, as they happen.
 *
 * Until now the platform learned about its own bugs when a restaurant phoned.
 * That is how the last several were found — a 500 on every route, a reserved
 * word in a query, a page returning null — each one live for hours before
 * anybody said so.
 *
 * This reads the PHP error log the API already writes to. Not a monitoring
 * system; just the difference between finding out today and finding out when
 * somebody complains.
 */
final class HealthController
{
    /** Enough to see a pattern without reading a novel. */
    private const LINES = 4000;

    public function index(): void
    {
        $entries = self::recent();

        View::page('health', [
            'title'    => 'Health',
            'nav'      => 'health',
            'entries'  => $entries,
            'counts'   => $counts = self::summarise($entries),
            // The newest error of any kind. A page reporting twelve
            // faults none of which has happened since Tuesday is
            // reporting history, and should say so.
            'freshest' => $counts === [] ? null : min(array_filter(
                array_column($counts, 'age'),
                static fn ($a): bool => $a !== null,
            ) ?: [null]),
            'log'      => self::logPath() ?? '',
            'database' => self::database(),
            'email'    => self::email(),
        ]);
    }

    /**
     * The tail of the log, newest first.
     *
     * Read backwards from the end rather than loaded whole: a log left to grow
     * for a year is not a file to pull into memory on a shared host.
     *
     * @return list<array{at:string,message:string}>
     */
    private static function recent(): array
    {
        $path = self::logPath();

        if ($path === null || !is_readable($path)) {
            return [];
        }

        $handle = @fopen($path, 'r');

        if ($handle === false) {
            return [];
        }

        $lines = [];
        $buffer = '';
        $chunk = 8192;

        fseek($handle, 0, SEEK_END);
        $position = ftell($handle);

        while ($position > 0 && count($lines) < self::LINES) {
            $read = (int) min($chunk, $position);
            $position -= $read;

            fseek($handle, $position);
            $buffer = fread($handle, $read) . $buffer;

            $lines = explode("\n", $buffer);
        }

        fclose($handle);

        $out = [];

        foreach (array_reverse($lines) as $line) {
            $line = trim($line);

            // Only ours, and only the ones that matter. A PHP notice from a
            // dependency is noise; a fatal in DACAAM is the thing this page
            // exists for.
            if ($line === '' || !preg_match('/dacaam|Fatal|Uncaught|PHP Warning/i', $line)) {
                continue;
            }

            $at = '';
            if (preg_match('/^\[(.*?)\]/', $line, $m) === 1) {
                $at = $m[1];
                $line = trim(substr($line, strlen($m[0])));
            }

            $out[] = ['at' => $at, 'message' => $line];

            if (count($out) >= 200) {
                break;
            }
        }

        return $out;
    }

    /**
     * How often each distinct error appears.
     *
     * The same fatal five hundred times is one bug, and a list of five hundred
     * identical lines hides the other four.
     *
     * @param  list<array{at:string,message:string}> $entries
     * @return list<array{message:string,count:int,last:string}>
     */
    private static function summarise(array $entries): array
    {
        $counts = [];

        foreach ($entries as $entry) {
            // Line numbers and ids move; the shape of the message does not.
            $key = preg_replace('/\d+/', 'N', $entry['message']) ?? $entry['message'];
            $key = substr($key, 0, 160);

            if (!isset($counts[$key])) {
                // Entries arrive newest first, so the first one seen is
                // the most recent — which is the whole answer to whether
                // this is a live problem or one already fixed.
                $counts[$key] = [
                    'message' => $entry['message'],
                    'count'   => 0,
                    'last'    => $entry['at'],
                    'age'     => self::age($entry['at']),
                ];
            }

            $counts[$key]['count']++;
        }

        usort($counts, static fn (array $a, array $b): int => $b['count'] <=> $a['count']);

        return array_slice(array_values($counts), 0, 20);
    }

    /**
     * Hours since a log timestamp, or null when it cannot be read.
     *
     * PHP writes the configured timezone into the line — "Africa/Mogadishu" —
     * which strtotime handles, but a host that logs in some other format should
     * degrade to "unknown" rather than to a wrong number.
     */
    private static function age(string $at): ?int
    {
        if ($at === '') {
            return null;
        }

        $time = strtotime($at);

        return $time === false ? null : (int) floor((time() - $time) / 3600);
    }

    private static function logPath(): ?string
    {
        // Whatever PHP itself was told to use. Guessing a path would be a page
        // that quietly shows nothing on a host that arranges things differently.
        $configured = ini_get('error_log');

        if (is_string($configured) && $configured !== '' && is_file($configured)) {
            return $configured;
        }

        foreach ([
            dirname(__DIR__, 3) . '/backend/storage/logs/error.log',
            ($_SERVER['HOME'] ?? '') . '/.logs/error_log_api_dhuuh_shop',
            ($_SERVER['HOME'] ?? '') . '/.logs/error_log',
        ] as $candidate) {
            if ($candidate !== '/.logs/error_log' && is_file($candidate)) {
                return $candidate;
            }
        }

        return null;
    }

    /**
     * The alert outbox.
     *
     * Email that fails to send fails quietly — there is no browser to show an
     * error to and nobody is waiting on it. An owner who is not being told
     * about voided orders has no way to discover that, because the symptom of
     * a broken alert is silence, which is also the symptom of a quiet week.
     *
     * @return array<string,mixed>
     */
    private static function email(): array
    {
        if ((int) Database::scalar(
            'SELECT COUNT(*) FROM information_schema.tables
              WHERE table_schema = DATABASE() AND table_name = "email_outbox"',
        ) === 0) {
            return ['ready' => false];
        }

        return [
            'ready'   => true,
            'pending' => (int) Database::scalar(
                'SELECT COUNT(*) FROM email_outbox WHERE sent_at IS NULL AND attempts < 4',
            ),
            // Four attempts and it is not tried again. These are the ones an
            // owner never received and never will unless somebody looks.
            'stuck'   => (int) Database::scalar(
                'SELECT COUNT(*) FROM email_outbox WHERE sent_at IS NULL AND attempts >= 4',
            ),
            'sent_today' => (int) Database::scalar(
                'SELECT COUNT(*) FROM email_outbox WHERE DATE(sent_at) = CURDATE()',
            ),
            'last_sent' => Database::scalar(
                'SELECT MAX(sent_at) FROM email_outbox',
            ),
            'failures' => Database::select(
                'SELECT o.to_email, o.subject, o.attempts, o.last_error, o.created_at, r.slug
                   FROM email_outbox o
                   LEFT JOIN restaurants r ON r.id = o.restaurant_id
                  WHERE o.sent_at IS NULL AND o.last_error IS NOT NULL
                  ORDER BY o.id DESC LIMIT 10',
            ),
        ];
    }

    /** @return array<string,mixed> */
    private static function database(): array
    {
        return [
            'size' => (float) Database::scalar(
                'SELECT COALESCE(SUM(data_length + index_length), 0) / 1048576
                   FROM information_schema.tables WHERE table_schema = DATABASE()',
            ),
            'tables' => (int) Database::scalar(
                'SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE()',
            ),
            'orders' => (int) Database::scalar('SELECT COUNT(*) FROM orders'),
            'audit'  => (int) Database::scalar('SELECT COUNT(*) FROM audit_logs'),
        ];
    }
}
