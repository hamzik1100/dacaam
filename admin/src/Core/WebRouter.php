<?php

declare(strict_types=1);

namespace DacaamAdmin\Core;

use Throwable;

/**
 * Small router for server-rendered pages.
 *
 * Separate from the API's router because the failure modes are different: this
 * one redirects to a login page and renders an HTML error, rather than
 * returning a JSON envelope.
 */
final class WebRouter
{
    /** @var list<array{method:string,regex:string,keys:list<string>,handler:callable,guest:bool,ability:?string}> */
    private array $routes = [];

    /**
     * `$ability` names what the role must hold (see Access). Declared on the
     * route, next to the handler, so a new page cannot forget to check it.
     */
    public function get(string $path, callable $handler, bool $guest = false, ?string $ability = null): void
    {
        $this->add('GET', $path, $handler, $guest, $ability);
    }

    public function post(string $path, callable $handler, bool $guest = false, ?string $ability = null): void
    {
        $this->add('POST', $path, $handler, $guest, $ability);
    }

    private function add(string $method, string $path, callable $handler, bool $guest, ?string $ability): void
    {
        $keys = [];
        $regex = preg_replace_callback(
            '/\{([a-zA-Z_][a-zA-Z0-9_]*)\}/',
            static function (array $m) use (&$keys): string {
                $keys[] = $m[1];

                return '([^/]+)';
            },
            $path,
        );

        $this->routes[] = [
            'method'  => $method,
            'regex'   => '#^' . $regex . '$#',
            'keys'    => $keys,
            'handler' => $handler,
            'guest'   => $guest,
            'ability' => $ability,
        ];
    }

    public function dispatch(string $method, string $path): void
    {
        foreach ($this->routes as $route) {
            if ($route['method'] !== $method
                || preg_match($route['regex'], $path, $matches) !== 1
            ) {
                continue;
            }

            array_shift($matches);
            $params = array_combine($route['keys'], array_map('strval', $matches));

            if (!$route['guest']) {
                $admin = AdminAuth::require();

                if ($route['ability'] !== null && !Access::allows($admin, $route['ability'])) {
                    Access::deny($admin);
                }
            }
            // Every non-idempotent request carries a token; there is no POST in
            // this app that should work without one.
            if ($method === 'POST') {
                Csrf::verify();
            }

            try {
                ($route['handler'])($params);
            } catch (Throwable $e) {
                // A refusal is the app working: somebody typed a short
                // password and was told so. Logging those alongside real
                // faults is how a genuine error, arriving once, ends up
                // buried under a hundred typos and never gets seen.
                if (!$e instanceof Refused) {
                    error_log('[dacaam-admin] ' . $e->getMessage());
                }

                Flash::error($e->getMessage());
                Response::redirect(self::backTo());
            }

            return;
        }

        Response::notFound();
    }

    /**
     * Where a failed action sends the user.
     *
     * Back to the page they submitted from, so the message lands next to the
     * form that produced it — but only when the referer is one of ours. A
     * referer is supplied by the browser on the attacker's terms, and following
     * it blindly turns every failed POST into an open redirect.
     */
    private static function backTo(): string
    {
        $referer = (string) ($_SERVER['HTTP_REFERER'] ?? '');
        if ($referer === '') {
            return '/';
        }

        $parts = parse_url($referer);
        if ($parts === false) {
            return '/';
        }

        $host = (string) ($parts['host'] ?? '');
        if (isset($parts['port'])) {
            $host .= ':' . $parts['port'];
        }
        if ($host !== (string) ($_SERVER['HTTP_HOST'] ?? '')) {
            return '/';
        }

        $path = (string) ($parts['path'] ?? '/');
        if (Response::$basePath !== '' && str_starts_with($path, Response::$basePath)) {
            $path = substr($path, strlen(Response::$basePath));
        }

        $query = (string) ($parts['query'] ?? '');

        return ($path === '' ? '/' : $path) . ($query === '' ? '' : '?' . $query);
    }
}
