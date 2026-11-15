<?php

declare(strict_types=1);

namespace DacaamAdmin\Core;

/** One-shot messages that survive a redirect. */
final class Flash
{
    public static function success(string $message): void
    {
        $_SESSION['flash'] = ['type' => 'success', 'message' => $message];
    }

    public static function error(string $message): void
    {
        $_SESSION['flash'] = ['type' => 'error', 'message' => $message];
    }

    /** @return array{type:string,message:string}|null */
    public static function pull(): ?array
    {
        $flash = $_SESSION['flash'] ?? null;
        unset($_SESSION['flash']);

        return is_array($flash) ? $flash : null;
    }
}
