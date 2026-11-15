<?php

declare(strict_types=1);

namespace Dacaam\Core;

/**
 * Immutable view of the incoming HTTP request.
 */
final class Request
{
    /**
     * @param array<string,mixed>  $query
     * @param array<string,mixed>  $body
     * @param array<string,string> $headers
     * @param array<string,string> $params Route parameters, e.g. {id}
     */
    private function __construct(
        public readonly string $method,
        public readonly string $path,
        public readonly array $query,
        public readonly array $body,
        public readonly array $headers,
        public readonly string $ip,
        public array $params = [],
        /**
         * The throttle bucket this request was counted against, if any.
         *
         * A handler that succeeds can clear it — twenty staff signing in from
         * one restaurant's router should not exhaust a limit meant for twenty
         * failed guesses.
         */
        public string $throttleBucket = '',
    ) {
    }

    public static function capture(): self
    {
        $method = strtoupper($_SERVER['REQUEST_METHOD'] ?? 'GET');
        $uri = (string) ($_SERVER['REQUEST_URI'] ?? '/');
        $path = parse_url($uri, PHP_URL_PATH);
        $path = is_string($path) ? $path : '/';

        // The API may be mounted under a subdirectory (XAMPP htdocs) or at the
        // root (php -S). Strip whichever prefix the front controller sits in.
        $scriptDir = str_replace('\\', '/', dirname((string) ($_SERVER['SCRIPT_NAME'] ?? '')));
        if ($scriptDir !== '' && $scriptDir !== '/' && str_starts_with($path, $scriptDir)) {
            $path = substr($path, strlen($scriptDir));
        }
        $path = '/' . trim($path, '/');

        $raw = file_get_contents('php://input');
        $body = [];
        if (is_string($raw) && $raw !== '') {
            $decoded = json_decode($raw, true);
            if (is_array($decoded)) {
                $body = $decoded;
            }
        }
        if ($body === [] && $_POST !== []) {
            $body = $_POST;
        }

        return new self(
            method: $method,
            path: $path === '' ? '/' : $path,
            query: $_GET,
            body: $body,
            headers: self::readHeaders(),
            ip: self::clientIp(),
        );
    }

    /**
     * Re-dispatches an existing request with a different body.
     *
     * Used where one endpoint legitimately delegates to another — converting a
     * draft runs the exact create-order path rather than a parallel copy of it,
     * so both routes can never drift apart.
     *
     * @param array<string,mixed> $body
     */
    public static function forInternal(self $base, array $body): self
    {
        return new self(
            method: $base->method,
            path: $base->path,
            query: $base->query,
            body: $body,
            headers: $base->headers,
            ip: $base->ip,
            params: $base->params,
        );
    }

    /** @return array<string,string> */
    private static function readHeaders(): array
    {
        $headers = [];
        foreach ($_SERVER as $key => $value) {
            if (str_starts_with((string) $key, 'HTTP_')) {
                $name = strtolower(str_replace('_', '-', substr((string) $key, 5)));
                $headers[$name] = (string) $value;
            }
        }
        if (isset($_SERVER['CONTENT_TYPE'])) {
            $headers['content-type'] = (string) $_SERVER['CONTENT_TYPE'];
        }

        return $headers;
    }

    private static function clientIp(): string
    {
        return (string) ($_SERVER['REMOTE_ADDR'] ?? '');
    }

    public function header(string $name, string $default = ''): string
    {
        return $this->headers[strtolower($name)] ?? $default;
    }

    public function bearerToken(): ?string
    {
        $header = $this->header('authorization');
        if ($header !== '' && preg_match('/^Bearer\s+(.+)$/i', $header, $m) === 1) {
            return trim($m[1]);
        }

        return null;
    }

    public function device(): string
    {
        $device = $this->header('x-device');
        if ($device === '') {
            $device = $this->header('user-agent');
        }

        return substr($device, 0, 190);
    }

    public function param(string $key, string $default = ''): string
    {
        return $this->params[$key] ?? $default;
    }

    public function intParam(string $key): int
    {
        return (int) $this->param($key, '0');
    }

    public function queryString(string $key, string $default = ''): string
    {
        $value = $this->query[$key] ?? $default;

        return is_scalar($value) ? (string) $value : $default;
    }

    public function queryInt(string $key, ?int $default = null): ?int
    {
        $value = $this->query[$key] ?? null;
        if ($value === null || $value === '') {
            return $default;
        }

        return is_numeric($value) ? (int) $value : $default;
    }

    /** @return array<string,mixed> */
    public function all(): array
    {
        return $this->body;
    }

    public function input(string $key, mixed $default = null): mixed
    {
        return $this->body[$key] ?? $default;
    }
}
