<?php

declare(strict_types=1);

namespace Dacaam\Core;

use RuntimeException;

/**
 * Minimal SMTP client.
 *
 * Speaks enough SMTP to authenticate and send one message: EHLO, optional
 * STARTTLS, AUTH LOGIN, MAIL FROM, RCPT TO, DATA. Written directly rather than
 * pulled in as a dependency for the same reason as `Totp` — the deployment
 * target is shared hosting where adding Composer is not always an option, and
 * PHP's own `mail()` is unusable on most of them.
 *
 * Configuration lives in `system_settings` and is managed by the Super Admin,
 * because SMTP credentials are a platform concern, not a per-restaurant one.
 */
final class Mailer
{
    /** @var array<string,string>|null */
    private static ?array $config = null;

    /** @return array<string,string> */
    public static function config(): array
    {
        if (self::$config !== null) {
            return self::$config;
        }

        $rows = Database::select(
            "SELECT key_name, value FROM system_settings WHERE key_name LIKE 'smtp_%'",
        );

        $config = [];
        foreach ($rows as $row) {
            $config[(string) $row['key_name']] = (string) ($row['value'] ?? '');
        }

        return self::$config = $config;
    }

    public static function isConfigured(): bool
    {
        $c = self::config();

        return ($c['smtp_host'] ?? '') !== '' && ($c['smtp_from_email'] ?? '') !== '';
    }

    /** Forces a re-read after the Super Admin saves new settings. */
    public static function forget(): void
    {
        self::$config = null;
    }

    /**
     * Sends one plain-text + HTML message.
     *
     * Returns false rather than throwing when SMTP is not configured: a
     * restaurant with no mail server should still be able to run, it just
     * cannot offer password reset by email.
     */
    public static function send(
        string $toEmail,
        string $subject,
        string $textBody,
        ?string $htmlBody = null,
    ): bool {
        if (!self::isConfigured()) {
            return false;
        }

        $c = self::config();
        $host = $c['smtp_host'];
        $port = (int) ($c['smtp_port'] ?: 587);
        $encryption = strtolower($c['smtp_encryption'] ?? 'tls');
        $timeout = 15;

        $transport = $encryption === 'ssl' ? "ssl://$host" : $host;
        $socket = @fsockopen($transport, $port, $errno, $errstr, $timeout);

        if ($socket === false) {
            error_log("[dacaam] SMTP connect failed: $errstr ($errno)");

            return false;
        }

        stream_set_timeout($socket, $timeout);

        try {
            self::expect($socket, '220');
            self::command($socket, 'EHLO ' . self::hostname(), '250');

            if ($encryption === 'tls') {
                self::command($socket, 'STARTTLS', '220');
                if (!stream_socket_enable_crypto(
                    $socket,
                    true,
                    STREAM_CRYPTO_METHOD_TLS_CLIENT,
                )) {
                    throw new RuntimeException('STARTTLS negotiation failed');
                }
                // EHLO again: the server's capability list changes after TLS.
                self::command($socket, 'EHLO ' . self::hostname(), '250');
            }

            if (($c['smtp_username'] ?? '') !== '') {
                self::command($socket, 'AUTH LOGIN', '334');
                self::command($socket, base64_encode($c['smtp_username']), '334');
                self::command($socket, base64_encode($c['smtp_password'] ?? ''), '235');
            }

            self::command($socket, 'MAIL FROM:<' . $c['smtp_from_email'] . '>', '250');
            self::command($socket, 'RCPT TO:<' . $toEmail . '>', '250');
            self::command($socket, 'DATA', '354');

            fwrite($socket, self::message($c, $toEmail, $subject, $textBody, $htmlBody));
            self::expect($socket, '250');

            self::command($socket, 'QUIT', '221');

            return true;
        } catch (RuntimeException $e) {
            error_log('[dacaam] SMTP: ' . $e->getMessage());

            return false;
        } finally {
            if (is_resource($socket)) {
                fclose($socket);
            }
        }
    }

    /** @param array<string,string> $c */
    private static function message(
        array $c,
        string $to,
        string $subject,
        string $text,
        ?string $html,
    ): string {
        $boundary = 'dacaam-' . bin2hex(random_bytes(8));
        $from = sprintf(
            '%s <%s>',
            $c['smtp_from_name'] ?: 'DACAAM',
            $c['smtp_from_email'],
        );

        $headers = [
            'From: ' . $from,
            'To: <' . $to . '>',
            'Subject: =?UTF-8?B?' . base64_encode($subject) . '?=',
            'Date: ' . date('r'),
            'MIME-Version: 1.0',
            'Message-ID: <' . bin2hex(random_bytes(12)) . '@' . self::hostname() . '>',
        ];

        if ($html === null) {
            $headers[] = 'Content-Type: text/plain; charset=UTF-8';
            $headers[] = 'Content-Transfer-Encoding: base64';
            $body = chunk_split(base64_encode($text));
        } else {
            $headers[] = 'Content-Type: multipart/alternative; boundary="' . $boundary . '"';
            $body = "--$boundary\r\n"
                . "Content-Type: text/plain; charset=UTF-8\r\n"
                . "Content-Transfer-Encoding: base64\r\n\r\n"
                . chunk_split(base64_encode($text)) . "\r\n"
                . "--$boundary\r\n"
                . "Content-Type: text/html; charset=UTF-8\r\n"
                . "Content-Transfer-Encoding: base64\r\n\r\n"
                . chunk_split(base64_encode($html)) . "\r\n"
                . "--$boundary--\r\n";
        }

        // A lone "." would end DATA early; SMTP requires it doubled.
        $body = preg_replace('/^\./m', '..', $body) ?? $body;

        return implode("\r\n", $headers) . "\r\n\r\n" . $body . "\r\n.\r\n";
    }

    /** @param resource $socket */
    private static function command($socket, string $line, string $expected): void
    {
        fwrite($socket, $line . "\r\n");
        self::expect($socket, $expected);
    }

    /** @param resource $socket */
    private static function expect($socket, string $code): void
    {
        $response = '';
        while (($line = fgets($socket, 515)) !== false) {
            $response .= $line;
            // Multi-line replies use "250-"; the last one uses "250 ".
            if (strlen($line) < 4 || $line[3] !== '-') {
                break;
            }
        }

        if (!str_starts_with($response, $code)) {
            throw new RuntimeException(
                sprintf('expected %s, got: %s', $code, trim($response)),
            );
        }
    }

    private static function hostname(): string
    {
        $host = $_SERVER['SERVER_NAME'] ?? gethostname();

        return is_string($host) && $host !== '' ? $host : 'localhost';
    }
}
