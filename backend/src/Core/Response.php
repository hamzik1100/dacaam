<?php

declare(strict_types=1);

namespace Dacaam\Core;

/**
 * JSON response envelope.
 *
 * Success: `{"data": ..., "meta": {...}}`
 * Failure: `{"error": {"code": "...", "message": "...", "fields": {...}}}`
 *
 * The shape never varies, so the Flutter client has exactly one parser.
 */
final class Response
{
    public static function json(mixed $data, int $status = 200, array $meta = []): void
    {
        $payload = ['data' => $data];
        if ($meta !== []) {
            $payload['meta'] = $meta;
        }

        self::emit($payload, $status);
    }

    /** @param array<string,string> $fields */
    public static function error(
        string $message,
        int $status = 400,
        string $code = 'bad_request',
        array $fields = [],
        ?string $debug = null,
    ): void {
        $error = ['code' => $code, 'message' => $message];
        if ($fields !== []) {
            $error['fields'] = $fields;
        }
        if ($debug !== null && Config::isDebug()) {
            $error['debug'] = $debug;
        }

        self::emit(['error' => $error], $status);
    }

    public static function noContent(): void
    {
        http_response_code(204);
        self::securityHeaders();
        self::cors();
        exit;
    }

    /**
     * CORS.
     *
     * When the config names specific origins, an origin that is not on the
     * list gets no header at all — the browser then blocks the response, which
     * is the entire point. Echoing back whatever `Origin` arrived would have
     * meant the allowlist permitted every site on the internet while looking
     * like it permitted four.
     */
    public static function cors(): void
    {
        $allowed = (array) Config::get('cors.allowed_origins', ['*']);
        $requested = (string) ($_SERVER['HTTP_ORIGIN'] ?? '');

        if (in_array('*', $allowed, true)) {
            header('Access-Control-Allow-Origin: *');
        } elseif ($requested !== '' && in_array($requested, $allowed, true)) {
            header('Access-Control-Allow-Origin: ' . $requested);
            // The answer varies by origin, so a shared cache must not serve
            // one site's response to another.
            header('Vary: Origin');
        }

        header('Access-Control-Allow-Headers: ' . implode(', ', (array) Config::get('cors.allowed_headers', [])));
        header('Access-Control-Allow-Methods: ' . implode(', ', (array) Config::get('cors.allowed_methods', [])));
        header('Access-Control-Max-Age: 86400');
    }

    /**
     * Headers every response carries.
     *
     * The API answers with tenant data under a bearer token, so nothing it
     * returns may be cached by a proxy or replayed from a browser's back/
     * forward cache, and nothing it returns should ever be framed or sniffed
     * into being treated as HTML.
     */
    public static function securityHeaders(): void
    {
        header('X-Content-Type-Options: nosniff');
        header('X-Frame-Options: DENY');
        header('Referrer-Policy: no-referrer');
        header('Cache-Control: no-store, private');
        header('Pragma: no-cache');

        if (self::isHttps()) {
            header('Strict-Transport-Security: max-age=31536000; includeSubDomains');
        }
    }

    private static function isHttps(): bool
    {
        return ($_SERVER['HTTPS'] ?? '') !== ''
            && strtolower((string) $_SERVER['HTTPS']) !== 'off';
    }

    private static function emit(array $payload, int $status): void
    {
        http_response_code($status);
        header('Content-Type: application/json; charset=utf-8');
        self::securityHeaders();
        self::cors();

        echo json_encode(
            $payload,
            JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_PRESERVE_ZERO_FRACTION,
        );
        exit;
    }
}
