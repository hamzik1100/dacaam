<?php

declare(strict_types=1);

namespace Dacaam\Core;

use Throwable;

/**
 * Minimal pattern router.
 *
 * Routes declare the permission they need — and any throttle — alongside the
 * handler, so authorization and rate limiting are part of the route table
 * rather than something each controller remembers to do.
 */
final class Router
{
    /**
     * Writes a lapsed tenant may still make.
     *
     * Signing out has to keep working whatever the billing situation: leaving
     * someone unable to end their own session because an invoice is overdue
     * would be punitive and pointless.
     */
    private const READ_ONLY_EXEMPT = ['/api/v1/auth/logout'];

    /** @var list<array{method:string,path:string,regex:string,keys:list<string>,handler:callable,auth:bool,permission:?string,throttle:?array{0:int,1:int}}> */
    private array $routes = [];

    /** @param ?array{0:int,1:int} $throttle max hits, window in seconds */
    public function get(string $path, callable $handler, ?string $permission = null, bool $auth = true, ?array $throttle = null): void
    {
        $this->add('GET', $path, $handler, $permission, $auth, $throttle);
    }

    /** @param ?array{0:int,1:int} $throttle max hits, window in seconds */
    public function post(string $path, callable $handler, ?string $permission = null, bool $auth = true, ?array $throttle = null): void
    {
        $this->add('POST', $path, $handler, $permission, $auth, $throttle);
    }

    /** @param ?array{0:int,1:int} $throttle max hits, window in seconds */
    public function put(string $path, callable $handler, ?string $permission = null, bool $auth = true, ?array $throttle = null): void
    {
        $this->add('PUT', $path, $handler, $permission, $auth, $throttle);
    }

    /** @param ?array{0:int,1:int} $throttle max hits, window in seconds */
    public function patch(string $path, callable $handler, ?string $permission = null, bool $auth = true, ?array $throttle = null): void
    {
        $this->add('PATCH', $path, $handler, $permission, $auth, $throttle);
    }

    /** @param ?array{0:int,1:int} $throttle max hits, window in seconds */
    public function delete(string $path, callable $handler, ?string $permission = null, bool $auth = true, ?array $throttle = null): void
    {
        $this->add('DELETE', $path, $handler, $permission, $auth, $throttle);
    }

    /** @param ?array{0:int,1:int} $throttle */
    private function add(
        string $method,
        string $path,
        callable $handler,
        ?string $permission,
        bool $auth,
        ?array $throttle = null,
    ): void {
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
            'method'     => $method,
            'path'       => $path,
            'regex'      => '#^' . $regex . '$#',
            'keys'       => $keys,
            'handler'    => $handler,
            'auth'       => $auth,
            'permission' => $permission,
            'throttle'   => $throttle,
        ];
    }

    public function dispatch(Request $request): void
    {
        if ($request->method === 'OPTIONS') {
            Response::noContent();
        }

        $pathMatched = false;

        foreach ($this->routes as $route) {
            if (preg_match($route['regex'], $request->path, $matches) !== 1) {
                continue;
            }
            $pathMatched = true;

            if ($route['method'] !== $request->method) {
                continue;
            }

            array_shift($matches);
            $request->params = array_combine($route['keys'], array_map('strval', $matches));

            // Throttling runs before authentication: the endpoints worth
            // limiting are the ones a caller reaches without a token, and a
            // limit applied after the password check would still let an
            // attacker spend the database's time on every guess.
            if ($route['throttle'] !== null) {
                $request->throttleBucket = RateLimiter::forIp(
                    $route['method'] . ' ' . $route['path'],
                    $request->ip,
                );
                RateLimiter::hit(
                    $request->throttleBucket,
                    $route['throttle'][0],
                    $route['throttle'][1],
                );
            }

            $context = null;
            if ($route['auth']) {
                $context = Auth::authenticate($request);
                if ($route['permission'] !== null && !$context->can($route['permission'])) {
                    throw ApiException::forbidden(
                        sprintf('Missing permission: %s', $route['permission']),
                    );
                }
                $this->assertWritable($context, $request, $route['path']);
            }

            $result = ($route['handler'])($request, $context);
            if ($result !== null) {
                Response::json($result);
            }

            return;
        }

        throw new ApiException(
            $pathMatched ? 'Method not allowed' : 'Endpoint not found',
            $pathMatched ? 405 : 404,
            $pathMatched ? 'method_not_allowed' : 'not_found',
        );
    }

    /**
     * Stops a lapsed tenant from writing, while leaving every read open.
     *
     * The code is distinct from a plain 403 so the app can tell "you are not
     * allowed to do this" apart from "the restaurant needs to renew" and say
     * something useful about the second.
     */
    private function assertWritable(AuthContext $context, Request $request, string $path): void
    {
        if (!$context->readOnly
            || $request->method === 'GET'
            || in_array($path, self::READ_ONLY_EXEMPT, true)
        ) {
            return;
        }

        throw new ApiException(
            $context->readOnlyReason . '. Everything is still here and still readable — renewing restores it unchanged.',
            403,
            'subscription_expired',
        );
    }

    /**
     * Runs the request and converts anything thrown into the error envelope.
     */
    public function run(Request $request): void
    {
        try {
            $this->dispatch($request);
        } catch (ApiException $e) {
            Response::error(
                $e->getMessage(),
                $e->status(),
                $e->errorCode(),
                $e->fields(),
            );
        } catch (Throwable $e) {
            error_log(sprintf(
                '[dacaam] %s: %s in %s:%d',
                $e::class,
                $e->getMessage(),
                $e->getFile(),
                $e->getLine(),
            ));

            Response::error(
                'An unexpected error occurred',
                500,
                'server_error',
                debug: $e->getMessage() . ' @ ' . $e->getFile() . ':' . $e->getLine(),
            );
        }
    }

    /** @return list<array{method:string,path:string,permission:?string}> */
    public function table(): array
    {
        return array_map(
            static fn (array $r): array => [
                'method'     => $r['method'],
                'path'       => $r['path'],
                'permission' => $r['permission'],
            ],
            $this->routes,
        );
    }
}
