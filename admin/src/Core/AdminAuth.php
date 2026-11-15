<?php

declare(strict_types=1);

namespace DacaamAdmin\Core;

use Dacaam\Core\ApiException;
use Dacaam\Core\Database;
use Dacaam\Core\Totp;
use Dacaam\Core\RateLimiter;

/**
 * Platform-level authentication.
 *
 * Entirely separate from tenant `users`: a restaurant admin holds no
 * credential that means anything here, and nothing in this class ever consults
 * the `users` table. That separation is the point — the blast radius of a
 * compromised restaurant account stops at that restaurant.
 */
final class AdminAuth
{
    private const MAX_FAILURES = 5;
    private const LOCKOUT_MINUTES = 15;

    /** @return array<string,mixed>|null */
    public static function current(): ?array
    {
        $id = $_SESSION['super_admin_id'] ?? null;
        if (!is_int($id)) {
            return null;
        }

        try {
            $row = Database::selectOne(
                'SELECT id, name, email, role, is_active FROM super_admins WHERE id = :id LIMIT 1',
                ['id' => $id],
            );
        } catch (\PDOException) {
            // The deploy uploads code seconds before the upgrade adds `role`.
            // Without this, that window signs every administrator out on every
            // page; with it they are owners until the column arrives, which
            // is what the upgrade makes them anyway.
            $row = Database::selectOne(
                'SELECT id, name, email, is_active FROM super_admins WHERE id = :id LIMIT 1',
                ['id' => $id],
            );
        }

        if ($row === null || (int) $row['is_active'] !== 1) {
            self::logout();

            return null;
        }

        return $row;
    }

    public static function check(): bool
    {
        return self::current() !== null;
    }

    /** Redirects to the login page unless signed in. */
    public static function require(): array
    {
        $admin = self::current();
        if ($admin === null) {
            Response::redirect('/login');
        }

        return $admin;
    }

    /**
     * @return array{ok:bool,error:?string}
     */
    /** How long a half-finished sign-in stays open, in seconds. */
    private const CHALLENGE_TTL = 300;

    /** Guesses allowed against one challenge before it is spent. */
    private const MAX_CHALLENGE_ATTEMPTS = 5;

    public static function attempt(string $email, string $password, string $ip): array
    {
        $email = strtolower(trim($email));

        // Per-account lockout below does not stop one address working through
        // a list of addresses, so the caller is limited too. Six platform
        // administrators exist; nobody legitimate needs thirty tries an hour.
        $bucket = RateLimiter::forIp('admin-login', $ip);

        try {
            RateLimiter::hit($bucket, 30, 3600);
        } catch (ApiException) {
            return [
                'ok'    => false,
                'error' => 'Too many sign-in attempts from this device. Try again later.',
            ];
        }

        $admin = Database::selectOne(
            'SELECT id, name, password_hash, is_active, failed_logins, locked_until,
                    two_factor_confirmed_at
               FROM super_admins WHERE email = :email LIMIT 1',
            ['email' => $email],
        );

        // Unknown email and wrong password fail identically.
        $generic = ['ok' => false, 'error' => 'Email or password is incorrect'];

        if ($admin === null) {
            return $generic;
        }

        if ($admin['locked_until'] !== null
            && strtotime((string) $admin['locked_until']) > time()
        ) {
            return [
                'ok' => false,
                'error' => 'Too many failed attempts. Try again later.',
            ];
        }

        if (!password_verify($password, (string) $admin['password_hash'])) {
            $failures = (int) $admin['failed_logins'] + 1;

            if ($failures >= self::MAX_FAILURES) {
                Database::run(
                    'UPDATE super_admins
                        SET failed_logins = :n,
                            locked_until = DATE_ADD(NOW(), INTERVAL :m MINUTE)
                      WHERE id = :id',
                    ['n' => $failures, 'm' => self::LOCKOUT_MINUTES, 'id' => $admin['id']],
                );
            } else {
                Database::run(
                    'UPDATE super_admins SET failed_logins = :n WHERE id = :id',
                    ['n' => $failures, 'id' => $admin['id']],
                );
            }

            return $generic;
        }

        if ((int) $admin['is_active'] !== 1) {
            return ['ok' => false, 'error' => 'This account is disabled'];
        }

        Database::run(
            'UPDATE super_admins
                SET failed_logins = 0, locked_until = NULL, last_login_at = NOW()
              WHERE id = :id',
            ['id' => $admin['id']],
        );

        RateLimiter::clear($bucket);

        // With a second factor on, the password has bought a challenge rather
        // than a session. Nothing is signed in until the code is right.
        //
        // The challenge lives in its own table rather than in the session: a
        // half-finished sign-in that survives in a cookie is one that can be
        // carried to another browser, and one that never expires on its own.
        if ($admin['two_factor_confirmed_at'] !== null) {
            $token = bin2hex(random_bytes(32));

            Database::insert('super_admin_challenges', [
                'super_admin_id' => (int) $admin['id'],
                'token_hash'     => hash('sha256', $token),
                'ip'             => $ip,
                'expires_at'     => date('Y-m-d H:i:s', time() + self::CHALLENGE_TTL),
            ]);

            PlatformAudit::log('login_challenged', detail: $email, ip: $ip);

            return ['ok' => false, 'error' => null, 'challenge' => $token];
        }

        self::adopt((int) $admin['id'], $email, $ip);

        return ['ok' => true, 'error' => null];
    }

    /**
     * Finishes a sign-in that was held for a code.
     *
     * @return array{ok:bool,error:?string}
     */
    public static function verifyChallenge(string $token, string $code, string $ip): array
    {
        $generic = ['ok' => false, 'error' => 'That code is not right'];

        // Expired rows are cleared on the way past rather than by a cron. There
        // are a handful of platform administrators; this costs nothing and
        // means an abandoned challenge cannot sit around being guessable.
        Database::run('DELETE FROM super_admin_challenges WHERE expires_at < NOW()');

        $row = Database::selectOne(
            'SELECT c.id, c.super_admin_id, c.attempts,
                    a.email, a.two_factor_secret, a.is_active
               FROM super_admin_challenges c
               JOIN super_admins a ON a.id = c.super_admin_id
              WHERE c.token_hash = :hash AND c.expires_at > NOW()
              LIMIT 1',
            ['hash' => hash('sha256', $token)],
        );

        if ($row === null) {
            return ['ok' => false, 'error' => 'That sign-in expired. Start again.'];
        }

        // Five tries and the challenge is spent. Without this the code is six
        // digits standing alone: a million guesses is an afternoon.
        if ((int) $row['attempts'] >= self::MAX_CHALLENGE_ATTEMPTS) {
            Database::run('DELETE FROM super_admin_challenges WHERE id = :id', ['id' => $row['id']]);

            return ['ok' => false, 'error' => 'Too many attempts. Sign in again.'];
        }

        Database::run(
            'UPDATE super_admin_challenges SET attempts = attempts + 1 WHERE id = :id',
            ['id' => $row['id']],
        );

        $code = trim($code);
        $adminId = (int) $row['super_admin_id'];

        // The authenticator code, or one of the paper codes.
        $ok = Totp::verify((string) $row['two_factor_secret'], $code);

        if (!$ok) {
            $ok = self::consumeRecoveryCode($adminId, $code);

            if ($ok) {
                PlatformAudit::log(
                    'recovery_code_used',
                    detail: (string) $row['email'],
                    ip: $ip,
                );
            }
        }

        if (!$ok) {
            return $generic;
        }

        if ((int) $row['is_active'] !== 1) {
            return ['ok' => false, 'error' => 'This account is disabled'];
        }

        Database::run('DELETE FROM super_admin_challenges WHERE id = :id', ['id' => $row['id']]);

        self::adopt($adminId, (string) $row['email'], $ip);

        return ['ok' => true, 'error' => null];
    }

    /**
     * Spends one recovery code, if it matches.
     *
     * Single use: a code that still works after being used is a password
     * written on a piece of paper.
     */
    private static function consumeRecoveryCode(int $adminId, string $code): bool
    {
        $normalised = Totp::normaliseRecoveryCode($code);

        if ($normalised === '') {
            return false;
        }

        $hash = hash('sha256', $normalised);

        return Database::run(
            'UPDATE super_admin_recovery_codes
                SET used_at = NOW()
              WHERE super_admin_id = :id AND code_hash = :hash AND used_at IS NULL',
            ['id' => $adminId, 'hash' => $hash],
        )->rowCount() > 0;
    }

    /** Starts the session. Everything before this is still a stranger. */
    private static function adopt(int $adminId, string $email, string $ip): void
    {
        // A fresh id on privilege change closes session-fixation.
        session_regenerate_id(true);
        $_SESSION['super_admin_id'] = $adminId;

        PlatformAudit::log('login', detail: $email, ip: $ip);
    }

    public static function logout(): void
    {
        $_SESSION = [];
        if (session_status() === PHP_SESSION_ACTIVE) {
            session_destroy();
        }
    }
}
