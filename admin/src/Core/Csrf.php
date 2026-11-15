<?php

declare(strict_types=1);

namespace DacaamAdmin\Core;

/**
 * CSRF protection for every state-changing form.
 *
 * One token per session rather than per form: the dashboard has no flows where
 * a stale form is expected to survive a re-login, and per-form tokens break
 * the back button for no security gain here.
 */
final class Csrf
{
    public static function token(): string
    {
        if (!isset($_SESSION['csrf']) || !is_string($_SESSION['csrf'])) {
            $_SESSION['csrf'] = bin2hex(random_bytes(32));
        }

        return $_SESSION['csrf'];
    }

    public static function field(): string
    {
        return sprintf(
            '<input type="hidden" name="_csrf" value="%s">',
            htmlspecialchars(self::token(), ENT_QUOTES, 'UTF-8'),
        );
    }

    /** Aborts the request when the token is missing or wrong. */
    public static function verify(): void
    {
        $sent = $_POST['_csrf'] ?? '';
        $expected = $_SESSION['csrf'] ?? '';

        if (!is_string($sent) || !is_string($expected) || $expected === ''
            || !hash_equals($expected, $sent)
        ) {
            Response::abort(
                419,
                'That form expired',
                'Reload the page you were on and submit it again.',
            );
        }
    }
}
