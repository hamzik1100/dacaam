<?php

declare(strict_types=1);

namespace Dacaam\Core;

use DateTimeImmutable;

/**
 * Authentication, tenant resolution and the two-step login flow.
 *
 * Login takes a restaurant code, a phone and a password. The code selects the
 * tenant *before* the user lookup, so the same phone number can belong to
 * staff at two different restaurants without ambiguity.
 *
 * When a user has confirmed 2FA, the password step returns a short-lived
 * *challenge* rather than a session. A challenge grants nothing except the
 * right to present an OTP:
 *
 *   restaurant code + phone + password  →  challenge
 *   challenge + OTP (or recovery code)  →  session token
 */
final class Auth
{
    private const CHALLENGE_TTL_MINUTES = 5;
    private const MAX_CHALLENGE_ATTEMPTS = 5;

    public static function authenticate(Request $request): AuthContext
    {
        $token = $request->bearerToken();
        if ($token === null || $token === '') {
            throw ApiException::unauthorized('Missing bearer token');
        }

        $row = Database::selectOne(
            'SELECT t.id AS token_id, t.user_id, t.restaurant_id, t.expires_at, t.revoked_at,
                    u.name AS user_name, u.is_active, r.slug, r.status AS restaurant_status,
                    s.status AS subscription_status, s.ends_on
               FROM api_tokens t
               JOIN users u        ON u.id = t.user_id
               JOIN restaurants r  ON r.id = t.restaurant_id
          LEFT JOIN subscriptions s ON s.restaurant_id = r.id
              WHERE t.token_hash = :hash
              LIMIT 1',
            ['hash' => self::hash($token)],
        );

        if ($row === null) {
            throw ApiException::unauthorized('Invalid token');
        }
        if ($row['revoked_at'] !== null) {
            throw ApiException::unauthorized('Session has been revoked');
        }
        if (new DateTimeImmutable((string) $row['expires_at']) < new DateTimeImmutable()) {
            throw ApiException::unauthorized('Session expired');
        }
        if ((int) $row['is_active'] !== 1) {
            throw ApiException::forbidden('This account is disabled');
        }
        // Suspension is the platform switching a tenant off, and it is total.
        // Data is untouched either way — neither state deletes anything.
        if ((string) $row['restaurant_status'] === 'suspended') {
            throw ApiException::forbidden('This restaurant is suspended');
        }
        // Archived is a restaurant that has left the platform. Same lock as
        // suspension, and the same promise: every row is still there.
        if ((string) $row['restaurant_status'] === 'archived') {
            throw ApiException::forbidden('This restaurant is no longer active on DACAAM');
        }

        [$readOnly, $reason] = self::subscriptionState($row);

        Database::run(
            'UPDATE api_tokens SET last_used_at = NOW() WHERE id = :id',
            ['id' => $row['token_id']],
        );

        return new AuthContext(
            userId: (int) $row['user_id'],
            restaurantId: (int) $row['restaurant_id'],
            userName: (string) $row['user_name'],
            restaurantSlug: (string) $row['slug'],
            permissions: self::permissionsFor((int) $row['user_id']),
            ip: $request->ip,
            device: $request->device(),
            tokenId: (int) $row['token_id'],
            readOnly: $readOnly,
            readOnlyReason: $reason,
        );
    }

    /**
     * Whether a lapsed subscription should hold this tenant to reads.
     *
     * Expiry is a date passing, not an action anyone takes, so it cannot be
     * enforced by revoking tokens the way suspension is — it has to be
     * decided on each request.
     *
     * A restaurant with no subscription row at all is left alone: that is a
     * provisioning gap, and locking a working restaurant out over our own
     * missing record would be the wrong way round.
     *
     * @param  array<string,mixed> $row
     * @return array{0:bool,1:string}
     */
    private static function subscriptionState(array $row): array
    {
        $status = (string) ($row['subscription_status'] ?? '');
        $endsOn = $row['ends_on'] ?? null;

        if ($status === '' || $endsOn === null) {
            return [false, ''];
        }

        if (in_array($status, ['expired', 'suspended'], true)) {
            return [true, 'This restaurant\'s subscription has ended'];
        }

        $ended = new DateTimeImmutable((string) $endsOn . ' 23:59:59')
            < new DateTimeImmutable();

        return $ended
            ? [true, 'This restaurant\'s subscription ended on ' . $endsOn]
            : [false, ''];
    }

    /**
     * Effective permissions: everything the user's roles grant, plus per-user
     * grants, minus per-user revocations.
     *
     * @return list<string>
     */
    public static function permissionsFor(int $userId): array
    {
        $rows = Database::select(
            'SELECT p.code
               FROM user_roles ur
               JOIN role_permissions rp ON rp.role_id = ur.role_id
               JOIN permissions p       ON p.id = rp.permission_id
              WHERE ur.user_id = :uid
              UNION
             SELECT p.code
               FROM user_permissions up
               JOIN permissions p ON p.id = up.permission_id
              WHERE up.user_id = :uid2 AND up.granted = 1',
            ['uid' => $userId, 'uid2' => $userId],
        );

        $granted = array_column($rows, 'code');

        $revoked = array_column(
            Database::select(
                'SELECT p.code
                   FROM user_permissions up
                   JOIN permissions p ON p.id = up.permission_id
                  WHERE up.user_id = :uid AND up.granted = 0',
                ['uid' => $userId],
            ),
            'code',
        );

        return array_values(array_diff($granted, $revoked));
    }

    // ================================================================ login

    /** @return array<string,mixed> */
    public static function login(
        string $slug,
        string $phone,
        string $password,
        Request $request,
    ): array {
        $slug = strtoupper(trim($slug));
        $phone = self::normalisePhone($phone);

        $restaurant = Database::selectOne(
            'SELECT id, slug, name, phone, address, logo_emoji, is_open, status
               FROM restaurants WHERE slug = :slug LIMIT 1',
            ['slug' => $slug],
        );

        // A wrong restaurant code and a wrong password fail identically, so the
        // endpoint cannot be used to enumerate which restaurants exist.
        if ($restaurant === null) {
            self::recordAttempt(null, $slug, $phone, false, $request);
            throw ApiException::unauthorized('Restaurant code, phone or password is incorrect');
        }

        $user = Database::selectOne(
            'SELECT id, name, phone, password_hash, is_active, failed_logins, locked_until,
                    two_factor_confirmed_at, must_change_password
               FROM users
              WHERE restaurant_id = :rid AND phone = :phone
              LIMIT 1',
            ['rid' => $restaurant['id'], 'phone' => $phone],
        );

        if ($user === null) {
            self::recordAttempt((int) $restaurant['id'], $slug, $phone, false, $request);
            throw ApiException::unauthorized('Restaurant code, phone or password is incorrect');
        }

        $settings = self::securitySettings((int) $restaurant['id']);

        if ($user['locked_until'] !== null
            && new DateTimeImmutable((string) $user['locked_until']) > new DateTimeImmutable()
        ) {
            throw ApiException::forbidden('Too many failed attempts. Try again later.');
        }

        if (!password_verify($password, (string) $user['password_hash'])) {
            self::registerFailure($user, $settings, $request, $restaurant, $slug, $phone);
            throw ApiException::unauthorized('Restaurant code, phone or password is incorrect');
        }

        if ((int) $user['is_active'] !== 1) {
            throw ApiException::forbidden('This account is disabled');
        }

        Database::run(
            'UPDATE users SET failed_logins = 0, locked_until = NULL WHERE id = :id',
            ['id' => $user['id']],
        );

        // The password was right, but it is not a session yet.
        if ($user['two_factor_confirmed_at'] !== null) {
            // A correct password is not a guess either, even when a second
            // factor is still owed.
            if ($request->throttleBucket !== '') {
                RateLimiter::clear($request->throttleBucket);
            }

            self::recordAttempt((int) $restaurant['id'], $slug, $phone, false, $request, 'password_ok_awaiting_otp');

            return [
                'requires_two_factor' => true,
                'challenge'           => self::issueChallenge(
                    (int) $user['id'],
                    (int) $restaurant['id'],
                    $request,
                ),
                'expires_in_seconds'  => self::CHALLENGE_TTL_MINUTES * 60,
                'user_name'           => (string) $user['name'],
                'restaurant_name'     => (string) $restaurant['name'],
            ];
        }

        return self::establishSession($user, $restaurant, $settings, $request);
    }

    /**
     * Second step: exchange a challenge plus an OTP for a session.
     *
     * @return array<string,mixed>
     */
    public static function verifyTwoFactor(
        string $challenge,
        string $code,
        Request $request,
    ): array {
        $row = Database::selectOne(
            'SELECT c.id, c.user_id, c.restaurant_id, c.attempts, c.expires_at, c.consumed_at,
                    u.two_factor_secret, u.is_active
               FROM auth_challenges c
               JOIN users u ON u.id = c.user_id
              WHERE c.challenge_hash = :hash
              LIMIT 1',
            ['hash' => self::hash($challenge)],
        );

        if ($row === null || $row['consumed_at'] !== null) {
            throw ApiException::unauthorized('This sign-in attempt is no longer valid');
        }
        if (new DateTimeImmutable((string) $row['expires_at']) < new DateTimeImmutable()) {
            throw ApiException::unauthorized('The code request expired. Sign in again.');
        }
        if ((int) $row['attempts'] >= self::MAX_CHALLENGE_ATTEMPTS) {
            self::consumeChallenge((int) $row['id']);
            throw ApiException::forbidden('Too many incorrect codes. Sign in again.');
        }

        $userId = (int) $row['user_id'];
        $accepted = self::acceptsCode($userId, (string) $row['two_factor_secret'], $code);

        if (!$accepted) {
            Database::run(
                'UPDATE auth_challenges SET attempts = attempts + 1 WHERE id = :id',
                ['id' => $row['id']],
            );
            throw ApiException::unauthorized('That code is not correct');
        }

        self::consumeChallenge((int) $row['id']);

        $user = Database::selectOne(
            'SELECT id, name, phone, is_active, must_change_password
               FROM users WHERE id = :id LIMIT 1',
            ['id' => $userId],
        );
        $restaurant = Database::selectOne(
            'SELECT id, slug, name, phone, address, logo_emoji, is_open, status
               FROM restaurants WHERE id = :id LIMIT 1',
            ['id' => $row['restaurant_id']],
        );

        if ($user === null || $restaurant === null || (int) $user['is_active'] !== 1) {
            throw ApiException::forbidden('This account is disabled');
        }

        return self::establishSession(
            $user,
            $restaurant,
            self::securitySettings((int) $restaurant['id']),
            $request,
        );
    }

    /**
     * Accepts either a current TOTP code or an unused recovery code.
     *
     * A correct TOTP is burned immediately: it stays valid for roughly ninety
     * seconds, and without this a code read over someone's shoulder works
     * twice.
     */
    private static function acceptsCode(int $userId, string $secret, string $code): bool
    {
        $code = trim($code);

        if ($secret !== '' && Totp::verify($secret, $code)) {
            $codeHash = self::hash($code);
            $replayed = Database::scalar(
                'SELECT 1 FROM two_factor_used_codes
                  WHERE user_id = :uid AND code_hash = :hash LIMIT 1',
                ['uid' => $userId, 'hash' => $codeHash],
            );
            if ($replayed !== false) {
                return false;
            }

            Database::run(
                'INSERT INTO two_factor_used_codes (user_id, code_hash) VALUES (:uid, :hash)',
                ['uid' => $userId, 'hash' => $codeHash],
            );
            // Keep the table small; anything older than a few minutes can no
            // longer be replayed anyway.
            Database::run(
                'DELETE FROM two_factor_used_codes WHERE used_at < DATE_SUB(NOW(), INTERVAL 10 MINUTE)',
            );

            return true;
        }

        return self::consumeRecoveryCode($userId, $code);
    }

    private static function consumeRecoveryCode(int $userId, string $code): bool
    {
        $normalised = Totp::normaliseRecoveryCode($code);
        if ($normalised === '') {
            return false;
        }

        $match = Database::selectOne(
            'SELECT id FROM two_factor_recovery_codes
              WHERE user_id = :uid AND code_hash = :hash AND used_at IS NULL
              LIMIT 1',
            ['uid' => $userId, 'hash' => self::hash($normalised)],
        );

        if ($match === null) {
            return false;
        }

        Database::run(
            'UPDATE two_factor_recovery_codes SET used_at = NOW() WHERE id = :id',
            ['id' => $match['id']],
        );

        return true;
    }

    // ============================================================= session

    /**
     * @param  array<string,mixed> $user
     * @param  array<string,mixed> $restaurant
     * @param  array<string,mixed> $settings
     * @return array<string,mixed>
     */
    private static function establishSession(
        array $user,
        array $restaurant,
        array $settings,
        Request $request,
    ): array {
        Database::run(
            'UPDATE users SET last_login_at = NOW() WHERE id = :id',
            ['id' => $user['id']],
        );

        // The sign-in throttle exists to bound guessing, and a success is not
        // a guess. Without this, a restaurant whose twenty staff clock in from
        // one router would spend the morning locked out of their own till.
        if ($request->throttleBucket !== '') {
            RateLimiter::clear($request->throttleBucket);
        }

        $issued = self::issueToken(
            (int) $user['id'],
            (int) $restaurant['id'],
            (int) ($settings['session_timeout_days'] ?? 30),
            $request,
        );

        self::recordAttempt(
            (int) $restaurant['id'],
            (string) $restaurant['slug'],
            (string) $user['phone'],
            true,
            $request,
        );

        $context = new AuthContext(
            userId: (int) $user['id'],
            restaurantId: (int) $restaurant['id'],
            userName: (string) $user['name'],
            restaurantSlug: (string) $restaurant['slug'],
            permissions: [],
            ip: $request->ip,
            device: $request->device(),
        );
        Audit::log($context, module: 'auth', action: 'login', recordId: (int) $user['id']);

        $publicUser = self::publicUser((int) $user['id']);

        return [
            'requires_two_factor' => false,
            'token'       => $issued['token'],
            'expires_at'  => $issued['expires_at'],
            'user'        => $publicUser,
            'restaurant'  => [
                'id'         => (int) $restaurant['id'],
                'slug'       => (string) $restaurant['slug'],
                'name'       => (string) $restaurant['name'],
                'phone'      => (string) $restaurant['phone'],
                'address'    => (string) $restaurant['address'],
                'logo_emoji' => (string) $restaurant['logo_emoji'],
                'is_open'    => (bool) $restaurant['is_open'],
                'status'     => (string) $restaurant['status'],
            ],
            'permissions' => $publicUser['permissions'],
            // The client uses these to route straight to the screen that
            // resolves the obligation, instead of letting the user work and
            // then blocking them later.
            'must_change_password'   => (bool) ($user['must_change_password'] ?? false),
            'must_enrol_two_factor'  => self::mustEnrolTwoFactor(
                (int) $user['id'],
                $settings,
            ),
        ];
    }

    /**
     * True when the restaurant requires 2FA for admins and this admin has not
     * enrolled. Sign-in still succeeds — blocking it outright would leave no
     * way to enrol.
     *
     * @param array<string,mixed> $settings
     */
    private static function mustEnrolTwoFactor(int $userId, array $settings): bool
    {
        if ((int) ($settings['require_two_factor_admin'] ?? 0) !== 1) {
            return false;
        }

        $row = Database::selectOne(
            'SELECT u.two_factor_confirmed_at, r.code AS role_code
               FROM users u
          LEFT JOIN user_roles ur ON ur.user_id = u.id
          LEFT JOIN roles r       ON r.id = ur.role_id
              WHERE u.id = :id LIMIT 1',
            ['id' => $userId],
        );

        return $row !== null
            && (string) ($row['role_code'] ?? '') === 'admin'
            && $row['two_factor_confirmed_at'] === null;
    }

    /** @return array<string,mixed> */
    public static function publicUser(int $userId): array
    {
        $row = Database::selectOne(
            'SELECT u.id, u.restaurant_id, u.name, u.phone, u.is_active,
                    u.two_factor_confirmed_at, u.must_change_password, u.last_login_at,
                    COALESCE(r.code, "waiter") AS role_code,
                    COALESCE(r.name, "Adeege") AS role_name
               FROM users u
          LEFT JOIN user_roles ur ON ur.user_id = u.id
          LEFT JOIN roles r       ON r.id = ur.role_id
              WHERE u.id = :id
              LIMIT 1',
            ['id' => $userId],
        );

        if ($row === null) {
            throw ApiException::notFound('User not found');
        }

        return [
            'id'                 => (int) $row['id'],
            'restaurant_id'      => (int) $row['restaurant_id'],
            'name'               => (string) $row['name'],
            'phone'              => (string) $row['phone'],
            'is_active'          => (bool) $row['is_active'],
            'role'               => (string) $row['role_code'],
            'role_name'          => (string) $row['role_name'],
            'two_factor_enabled' => $row['two_factor_confirmed_at'] !== null,
            'must_change_password' => (bool) $row['must_change_password'],
            'last_login_at'      => $row['last_login_at'] === null
                ? null
                : date('c', (int) strtotime((string) $row['last_login_at'])),
            'permissions'        => self::permissionsFor($userId),
        ];
    }

    public static function logout(AuthContext $context): void
    {
        Database::run(
            'UPDATE api_tokens SET revoked_at = NOW() WHERE id = :id',
            ['id' => $context->tokenId],
        );

        Audit::log($context, module: 'auth', action: 'logout', recordId: $context->userId);
    }

    /** @return array<string,mixed> Security-relevant settings for a tenant. */
    public static function securitySettings(int $restaurantId): array
    {
        return Database::selectOne(
            'SELECT * FROM restaurant_settings WHERE restaurant_id = :rid LIMIT 1',
            ['rid' => $restaurantId],
        ) ?? [];
    }

    // ============================================================ internals

    /** @return array{token:string,expires_at:string} */
    private static function issueToken(
        int $userId,
        int $restaurantId,
        int $ttlDays,
        Request $request,
    ): array {
        $token = bin2hex(random_bytes(32));
        $ttlDays = max(1, min($ttlDays, 365));
        $expiresAt = (new DateTimeImmutable())
            ->modify("+{$ttlDays} days")
            ->format('Y-m-d H:i:s');

        Database::insert('api_tokens', [
            'user_id'       => $userId,
            'restaurant_id' => $restaurantId,
            'token_hash'    => self::hash($token),
            'device'        => $request->device(),
            'ip'            => $request->ip,
            'expires_at'    => $expiresAt,
        ]);

        return ['token' => $token, 'expires_at' => $expiresAt];
    }

    private static function issueChallenge(
        int $userId,
        int $restaurantId,
        Request $request,
    ): string {
        // Any older pending challenge for this user is dead the moment a new
        // password step succeeds.
        Database::run(
            'UPDATE auth_challenges SET consumed_at = NOW()
              WHERE user_id = :uid AND consumed_at IS NULL',
            ['uid' => $userId],
        );

        $challenge = bin2hex(random_bytes(32));

        Database::insert('auth_challenges', [
            'user_id'        => $userId,
            'restaurant_id'  => $restaurantId,
            'challenge_hash' => self::hash($challenge),
            'expires_at'     => (new DateTimeImmutable())
                ->modify('+' . self::CHALLENGE_TTL_MINUTES . ' minutes')
                ->format('Y-m-d H:i:s'),
            'ip'             => $request->ip,
            'device'         => $request->device(),
        ]);

        return $challenge;
    }

    private static function consumeChallenge(int $challengeId): void
    {
        Database::run(
            'UPDATE auth_challenges SET consumed_at = NOW() WHERE id = :id',
            ['id' => $challengeId],
        );
    }

    /**
     * @param array<string,mixed> $user
     * @param array<string,mixed> $settings
     * @param array<string,mixed> $restaurant
     */
    private static function registerFailure(
        array $user,
        array $settings,
        Request $request,
        array $restaurant,
        string $slug,
        string $phone,
    ): void {
        $failures = (int) $user['failed_logins'] + 1;
        $max = (int) ($settings['max_failed_logins'] ?? 5);
        $lockMinutes = (int) ($settings['lockout_minutes'] ?? 15);

        if ($failures >= $max) {
            Database::run(
                'UPDATE users
                    SET failed_logins = :n,
                        locked_until = DATE_ADD(NOW(), INTERVAL :mins MINUTE)
                  WHERE id = :id',
                ['n' => $failures, 'mins' => $lockMinutes, 'id' => $user['id']],
            );
        } else {
            Database::run(
                'UPDATE users SET failed_logins = :n WHERE id = :id',
                ['n' => $failures, 'id' => $user['id']],
            );
        }

        self::recordAttempt((int) $restaurant['id'], $slug, $phone, false, $request);
    }

    private static function recordAttempt(
        ?int $restaurantId,
        string $slug,
        string $phone,
        bool $succeeded,
        Request $request,
        string $device = '',
    ): void {
        Database::insert('login_attempts', [
            'restaurant_id' => $restaurantId,
            'slug'          => $slug,
            'phone'         => $phone,
            'succeeded'     => $succeeded ? 1 : 0,
            'ip'            => $request->ip,
            'device'        => $device !== '' ? $device : $request->device(),
        ]);
    }

    /**
     * Strips spaces and dashes so `063 456 7890` and `0634567890` are the same
     * account. Staff type it differently every time.
     */
    public static function normalisePhone(string $phone): string
    {
        return preg_replace('/[^0-9+]/', '', $phone) ?? $phone;
    }

    public static function hash(string $value): string
    {
        return hash('sha256', $value);
    }
}
