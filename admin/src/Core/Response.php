<?php

declare(strict_types=1);

namespace DacaamAdmin\Core;

final class Response
{
    /** Base path the dashboard is mounted at, e.g. `/admin` under Apache. */
    public static string $basePath = '';

    public static function url(string $path): string
    {
        return self::$basePath . $path;
    }

    public static function redirect(string $path): never
    {
        header('Location: ' . self::url($path));
        exit;
    }

    public static function notFound(): never
    {
        self::abort(404, 'Not found', 'That page, restaurant or subscription does not exist.');
    }

    /**
     * Ends the request with a status that means what it says.
     *
     * A rejected request is not a redirect: bouncing to `/` with a flash would
     * report 302 to anything reading the response, which hides genuine failures
     * from logs and from tests.
     */
    public static function abort(int $status, string $heading, string $message): never
    {
        http_response_code($status);
        View::render('errors/message', [
            'heading' => $heading,
            'message' => $message,
        ]);
        exit;
    }
}
