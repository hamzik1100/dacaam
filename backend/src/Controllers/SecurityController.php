<?php

declare(strict_types=1);

namespace Dacaam\Controllers;

use Dacaam\Core\ApiException;
use Dacaam\Core\Audit;
use Dacaam\Core\Auth;
use Dacaam\Core\AuthContext;
use Dacaam\Core\Database;
use Dacaam\Core\Mailer;
use Dacaam\Core\PasswordPolicy;
use Dacaam\Core\Request;
use Dacaam\Core\Totp;
use Dacaam\Core\Validator;
use Dacaam\Repositories\Repository;
use Dacaam\Support\Presenter;

/**
 * Everything under Settings → Security.
 *
 * All of it is scoped to the *calling* user unless a permission says
 * otherwise: a manager may set the restaurant's password policy, but nobody
 * enrols 2FA on someone else's behalf or reads another person's sessions.
 */
final class SecurityController extends Repository
{
    /** @return array<string,mixed> */
    public function overview(Request $request, AuthContext $context): array
    {
        $settings = self::settings($context->restaurantId);
        $user = Auth::publicUser($context->userId);

        return [
            'two_factor' => [
                'enabled'                => $user['two_factor_enabled'],
                'unused_recovery_codes'  => (int) Database::scalar(
                    'SELECT COUNT(*) FROM two_factor_recovery_codes
                      WHERE user_id = :uid AND used_at IS NULL',
                    ['uid' => $context->userId],
                ),
                'required_for_admins'    => (bool) ($settings['require_two_factor_admin'] ?? false),
            ],
            'password' => [
                'policy'     => (new PasswordPolicy($settings))->toArray(),
                'changed_at' => Presenter::iso(
                    Database::scalar(
                        'SELECT password_changed_at FROM users WHERE id = :id',
                        ['id' => $context->userId],
                    ),
                ),
                'must_change' => $user['must_change_password'],
            ],
            'sessions' => [
                'active' => (int) Database::scalar(
                    'SELECT COUNT(*) FROM api_tokens
                      WHERE user_id = :uid AND revoked_at IS NULL AND expires_at > NOW()',
                    ['uid' => $context->userId],
                ),
                'timeout_days' => (int) ($settings['session_timeout_days'] ?? 30),
            ],
            'failed_logins' => (int) Database::scalar(
                'SELECT COUNT(*) FROM login_attempts
                  WHERE restaurant_id = :rid AND succeeded = 0
                    AND created_at > DATE_SUB(NOW(), INTERVAL 7 DAY)',
                ['rid' => $context->restaurantId],
            ),
        ];
    }

    // ================================================================= 2FA

    /**
     * Step one of enrolment: mint a secret and hand back the provisioning URI.
     *
     * 2FA is *not* on yet — `two_factor_confirmed_at` stays null until the user
     * proves the authenticator works, so an abandoned setup can never lock
     * anyone out of their own restaurant.
     *
     * @return array<string,mixed>
     */
    public function startTwoFactor(Request $request, AuthContext $context): array
    {
        $existing = Database::selectOne(
            'SELECT two_factor_confirmed_at FROM users WHERE id = :id',
            ['id' => $context->userId],
        );

        if (($existing['two_factor_confirmed_at'] ?? null) !== null) {
            throw ApiException::conflict('Two-factor authentication is already enabled');
        }

        $secret = Totp::generateSecret();

        Database::run(
            'UPDATE users SET two_factor_secret = :secret WHERE id = :id',
            ['secret' => $secret, 'id' => $context->userId],
        );

        $restaurant = Database::selectOne(
            'SELECT name FROM restaurants WHERE id = :id',
            ['id' => $context->restaurantId],
        );

        return [
            'secret'            => $secret,
            'otpauth_uri'       => Totp::provisioningUri(
                $secret,
                $context->userName,
                (string) ($restaurant['name'] ?? 'DACAAM'),
            ),
            'digits'            => 6,
            'period_seconds'    => 30,
        ];
    }

    /**
     * Step two: prove the authenticator produces the right code, then enable
     * 2FA and issue recovery codes.
     *
     * The plaintext codes are shown exactly once — only their hashes are kept.
     *
     * @return array<string,mixed>
     */
    public function confirmTwoFactor(Request $request, AuthContext $context): array
    {
        $data = Validator::check($request->all(), [
            'code' => 'required|string|min:6|max:10',
        ]);

        $row = Database::selectOne(
            'SELECT two_factor_secret, two_factor_confirmed_at FROM users WHERE id = :id',
            ['id' => $context->userId],
        );

        if ($row === null || ($row['two_factor_secret'] ?? '') === '') {
            throw ApiException::unprocessable('Start two-factor setup first');
        }
        if ($row['two_factor_confirmed_at'] !== null) {
            throw ApiException::conflict('Two-factor authentication is already enabled');
        }

        if (!Totp::verify((string) $row['two_factor_secret'], (string) $data['code'])) {
            throw ApiException::validation(
                ['code' => 'That code is not correct. Check your device clock.'],
            );
        }

        $codes = Totp::generateRecoveryCodes();

        Database::transaction(function () use ($context, $codes): void {
            Database::run(
                'UPDATE users SET two_factor_confirmed_at = NOW() WHERE id = :id',
                ['id' => $context->userId],
            );
            Database::run(
                'DELETE FROM two_factor_recovery_codes WHERE user_id = :uid',
                ['uid' => $context->userId],
            );

            foreach ($codes as $code) {
                Database::insert('two_factor_recovery_codes', [
                    'user_id'   => $context->userId,
                    'code_hash' => Auth::hash(Totp::normaliseRecoveryCode($code)),
                ]);
            }
        });

        Audit::log($context, 'security', 'two_factor_enabled', $context->userId);

        return [
            'enabled'        => true,
            'recovery_codes' => $codes,
        ];
    }

    /** @return array<string,mixed> */
    public function disableTwoFactor(Request $request, AuthContext $context): array
    {
        $data = Validator::check($request->all(), [
            'password' => 'required|string|min:1',
        ]);

        // Turning 2FA off is a downgrade in account security, so it costs a
        // password even though the caller is already authenticated.
        $this->assertPassword($context->userId, (string) $data['password']);

        Database::transaction(function () use ($context): void {
            Database::run(
                'UPDATE users
                    SET two_factor_secret = NULL, two_factor_confirmed_at = NULL
                  WHERE id = :id',
                ['id' => $context->userId],
            );
            Database::run(
                'DELETE FROM two_factor_recovery_codes WHERE user_id = :uid',
                ['uid' => $context->userId],
            );
        });

        Audit::log($context, 'security', 'two_factor_disabled', $context->userId);

        return ['enabled' => false];
    }

    /** @return array<string,mixed> */
    public function regenerateRecoveryCodes(Request $request, AuthContext $context): array
    {
        $data = Validator::check($request->all(), [
            'password' => 'required|string|min:1',
        ]);
        $this->assertPassword($context->userId, (string) $data['password']);

        $enabled = Database::scalar(
            'SELECT two_factor_confirmed_at FROM users WHERE id = :id',
            ['id' => $context->userId],
        );
        if ($enabled === null || $enabled === false) {
            throw ApiException::unprocessable('Two-factor authentication is not enabled');
        }

        $codes = Totp::generateRecoveryCodes();

        Database::transaction(function () use ($context, $codes): void {
            Database::run(
                'DELETE FROM two_factor_recovery_codes WHERE user_id = :uid',
                ['uid' => $context->userId],
            );
            foreach ($codes as $code) {
                Database::insert('two_factor_recovery_codes', [
                    'user_id'   => $context->userId,
                    'code_hash' => Auth::hash(Totp::normaliseRecoveryCode($code)),
                ]);
            }
        });

        Audit::log($context, 'security', 'recovery_codes_regenerated', $context->userId);

        return ['recovery_codes' => $codes];
    }

    // ============================================================ sessions

    /** @return list<array<string,mixed>> */
    public function sessions(Request $request, AuthContext $context): array
    {
        $rows = Database::select(
            'SELECT id, device, ip, created_at, last_used_at, expires_at
               FROM api_tokens
              WHERE user_id = :uid AND revoked_at IS NULL AND expires_at > NOW()
              ORDER BY last_used_at DESC, created_at DESC',
            ['uid' => $context->userId],
        );

        return array_map(
            static fn (array $r): array => [
                'id'           => (int) $r['id'],
                'device'       => (string) $r['device'],
                'ip'           => (string) $r['ip'],
                'created_at'   => Presenter::iso($r['created_at']),
                'last_used_at' => Presenter::iso($r['last_used_at']),
                'expires_at'   => Presenter::iso($r['expires_at']),
                // Lets the client label one row "this device" and refuse to
                // let the user cut the branch they are sitting on by accident.
                'is_current'   => (int) $r['id'] === $context->tokenId,
            ],
            $rows,
        );
    }

    /** @return array<string,mixed> */
    public function revokeSession(Request $request, AuthContext $context): array
    {
        $id = $request->intParam('id');

        if ($id === $context->tokenId) {
            throw ApiException::unprocessable(
                'That is this device. Use logout instead.',
            );
        }

        $affected = Database::run(
            'UPDATE api_tokens SET revoked_at = NOW()
              WHERE id = :id AND user_id = :uid AND revoked_at IS NULL',
            ['id' => $id, 'uid' => $context->userId],
        )->rowCount();

        if ($affected === 0) {
            throw ApiException::notFound('Session not found');
        }

        Audit::log($context, 'security', 'session_revoked', $id);

        return ['revoked' => true, 'id' => $id];
    }

    /** @return array<string,mixed> */
    public function revokeOtherSessions(Request $request, AuthContext $context): array
    {
        $count = Database::run(
            'UPDATE api_tokens SET revoked_at = NOW()
              WHERE user_id = :uid AND id <> :current AND revoked_at IS NULL',
            ['uid' => $context->userId, 'current' => $context->tokenId],
        )->rowCount();

        Audit::log(
            $context,
            'security',
            'sessions_revoked_all',
            $context->userId,
            newValue: (string) $count,
        );

        return ['revoked' => $count];
    }

    /** @return list<array<string,mixed>> */
    public function loginHistory(Request $request, AuthContext $context): array
    {
        // A user always sees their own history; only someone with users.view
        // can look across the whole restaurant.
        $ownOnly = !$context->can('users.view');

        $rows = Database::select(
            'SELECT la.*, u.name AS user_name
               FROM login_attempts la
          LEFT JOIN users u ON u.restaurant_id = la.restaurant_id AND u.phone = la.phone
              WHERE la.restaurant_id = :rid
                ' . ($ownOnly ? 'AND la.phone = :phone' : '') . '
              ORDER BY la.created_at DESC
              LIMIT 100',
            $ownOnly
                ? [
                    'rid'   => $context->restaurantId,
                    'phone' => (string) Database::scalar(
                        'SELECT phone FROM users WHERE id = :id',
                        ['id' => $context->userId],
                    ),
                ]
                : ['rid' => $context->restaurantId],
        );

        return array_map(
            static fn (array $r): array => [
                'id'         => (int) $r['id'],
                'phone'      => (string) $r['phone'],
                'user_name'  => (string) ($r['user_name'] ?? ''),
                'succeeded'  => (bool) $r['succeeded'],
                'ip'         => (string) $r['ip'],
                'device'     => (string) $r['device'],
                'created_at' => Presenter::iso($r['created_at']),
            ],
            $rows,
        );
    }

    // ============================================================ password

    /** @return array<string,mixed> */
    public function changePassword(Request $request, AuthContext $context): array
    {
        $data = Validator::check($request->all(), [
            'current_password' => 'required|string|min:1',
            'new_password'     => 'required|string|min:1',
        ]);

        $this->assertPassword($context->userId, (string) $data['current_password']);

        $policy = new PasswordPolicy(self::settings($context->restaurantId));
        $policy->assert((string) $data['new_password'], 'new_password');

        if (hash_equals((string) $data['current_password'], (string) $data['new_password'])) {
            throw ApiException::validation(
                ['new_password' => 'Choose a password you have not used here before'],
            );
        }

        Database::transaction(function () use ($context, $data, $policy): void {
            Database::run(
                'UPDATE users
                    SET password_hash = :hash,
                        password_changed_at = NOW(),
                        must_change_password = 0
                  WHERE id = :id',
                [
                    'hash' => $policy->hash((string) $data['new_password']),
                    'id'   => $context->userId,
                ],
            );

            // Every other device holding a session was authorised by the old
            // password. Changing it should end them.
            Database::run(
                'UPDATE api_tokens SET revoked_at = NOW()
                  WHERE user_id = :uid AND id <> :current AND revoked_at IS NULL',
                ['uid' => $context->userId, 'current' => $context->tokenId],
            );
        });

        Audit::log($context, 'security', 'password_changed', $context->userId);

        return ['changed' => true];
    }

    // ============================================================== policy

    /** @return array<string,mixed> */
    public function policy(Request $request, AuthContext $context): array
    {
        $settings = self::settings($context->restaurantId);

        return [
            'password'                 => (new PasswordPolicy($settings))->toArray(),
            'session_timeout_days'     => (int) ($settings['session_timeout_days'] ?? 30),
            'max_failed_logins'        => (int) ($settings['max_failed_logins'] ?? 5),
            'lockout_minutes'          => (int) ($settings['lockout_minutes'] ?? 15),
            'require_two_factor_admin' => (bool) ($settings['require_two_factor_admin'] ?? false),
        ];
    }

    /** @return array<string,mixed> */
    public function updatePolicy(Request $request, AuthContext $context): array
    {
        $before = self::settings($context->restaurantId);

        $data = Validator::check($request->all(), [
            'password_min_length'      => 'nullable|int|min:4|max:64',
            'password_require_upper'   => 'nullable|bool',
            'password_require_number'  => 'nullable|bool',
            'password_require_symbol'  => 'nullable|bool',
            'session_timeout_days'     => 'nullable|int|min:1|max:365',
            'max_failed_logins'        => 'nullable|int|min:3|max:20',
            'lockout_minutes'          => 'nullable|int|min:1|max:1440',
            'require_two_factor_admin' => 'nullable|bool',
        ]);

        $update = [];
        foreach (['password_min_length', 'session_timeout_days', 'max_failed_logins', 'lockout_minutes'] as $field) {
            if (array_key_exists($field, $data) && $data[$field] !== null) {
                $update[$field] = (int) $data[$field];
            }
        }
        foreach ([
            'password_require_upper',
            'password_require_number',
            'password_require_symbol',
            'require_two_factor_admin',
        ] as $flag) {
            if (array_key_exists($flag, $data) && $data[$flag] !== null) {
                $update[$flag] = $data[$flag] ? 1 : 0;
            }
        }

        if ($update !== []) {
            $assignments = implode(
                ', ',
                array_map(static fn (string $c): string => "`$c` = :$c", array_keys($update)),
            );

            Database::run(
                "UPDATE restaurant_settings SET $assignments WHERE restaurant_id = :rid",
                $update + ['rid' => $context->restaurantId],
            );

            Audit::diff(
                $context,
                module: 'security',
                action: 'policy_updated',
                recordId: $context->restaurantId,
                before: $before,
                after: $update,
                fields: array_keys($update),
            );
        }

        return $this->policy($request, $context);
    }

    // =============================================================== SMTP

    /**
     * Mail settings. Platform-level rather than per-restaurant: one server
     * sends for every tenant, and giving each restaurant its own SMTP
     * credentials would be a support burden nobody asked for.
     *
     * @return array<string,mixed>
     */
    public function smtp(Request $request, AuthContext $context): array
    {
        $c = Mailer::config();

        return [
            'host'       => $c['smtp_host'] ?? '',
            'port'       => (int) ($c['smtp_port'] ?? 587),
            'encryption' => $c['smtp_encryption'] ?? 'tls',
            'username'   => $c['smtp_username'] ?? '',
            // The password is never returned, only whether one is set.
            'has_password' => ($c['smtp_password'] ?? '') !== '',
            'from_email' => $c['smtp_from_email'] ?? '',
            'from_name'  => $c['smtp_from_name'] ?? 'DACAAM',
            'configured' => Mailer::isConfigured(),
        ];
    }

    /** @return array<string,mixed> */
    public function updateSmtp(Request $request, AuthContext $context): array
    {
        $data = Validator::check($request->all(), [
            'host'       => 'nullable|string|max:190',
            'port'       => 'nullable|int|min:1|max:65535',
            'encryption' => 'nullable|string|in:none,tls,ssl',
            'username'   => 'nullable|string|max:190',
            'password'   => 'nullable|string|max:190',
            'from_email' => 'nullable|string|max:190',
            'from_name'  => 'nullable|string|max:100',
        ]);

        $map = [
            'host'       => 'smtp_host',
            'port'       => 'smtp_port',
            'encryption' => 'smtp_encryption',
            'username'   => 'smtp_username',
            'password'   => 'smtp_password',
            'from_email' => 'smtp_from_email',
            'from_name'  => 'smtp_from_name',
        ];

        foreach ($map as $field => $key) {
            if (!array_key_exists($field, $data) || $data[$field] === null) {
                continue;
            }
            // An empty password field means "leave it alone", not "clear it" —
            // the form never receives the current value to send back.
            if ($field === 'password' && (string) $data[$field] === '') {
                continue;
            }

            Database::run(
                'INSERT INTO system_settings (key_name, value) VALUES (:k, :v)
                 ON DUPLICATE KEY UPDATE value = :v2',
                ['k' => $key, 'v' => (string) $data[$field], 'v2' => (string) $data[$field]],
            );
        }

        Mailer::forget();
        Audit::log($context, 'settings', 'smtp_updated', null);

        return $this->smtp($request, $context);
    }

    /** @return array<string,mixed> */
    public function testSmtp(Request $request, AuthContext $context): array
    {
        $data = Validator::check($request->all(), [
            'to' => 'required|string|max:190',
        ]);

        if (!Mailer::isConfigured()) {
            throw ApiException::unprocessable('SMTP is not configured yet');
        }

        $sent = Mailer::send(
            (string) $data['to'],
            'DACAAM SMTP test',
            "This is a test message from DACAAM.\n\nIf you are reading it, "
            . 'mail delivery works.',
        );

        if (!$sent) {
            throw ApiException::unprocessable(
                'The mail server rejected the message. Check the server log.',
            );
        }

        Audit::log(
            $context,
            'settings',
            'smtp_test_sent',
            null,
            newValue: (string) $data['to'],
        );

        return ['sent' => true];
    }

    // ============================================================= helpers

    private function assertPassword(int $userId, string $password): void
    {
        $hash = Database::scalar(
            'SELECT password_hash FROM users WHERE id = :id',
            ['id' => $userId],
        );

        if (!is_string($hash) || !password_verify($password, $hash)) {
            throw ApiException::validation(
                ['password' => 'That password is not correct'],
                'Password confirmation failed',
            );
        }
    }
}
