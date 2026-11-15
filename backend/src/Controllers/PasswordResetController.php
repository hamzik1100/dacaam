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
use Dacaam\Core\Validator;
use Dacaam\Repositories\Repository;

/**
 * Self-service password reset by email.
 *
 * Both endpoints are unauthenticated by necessity — the whole point is that
 * the caller cannot sign in. That makes them the most exposed surface in the
 * API, so both answer identically whether or not the account exists.
 */
final class PasswordResetController extends Repository
{
    private const TOKEN_TTL_MINUTES = 30;

    /** @return array<string,mixed> */
    public function request(Request $request): array
    {
        $data = Validator::check($request->all(), [
            'restaurant_code' => 'required|string|min:2|max:32',
            'phone'           => 'required|phone|max:32',
        ]);

        // Always the same answer. Anything else turns this into a directory of
        // which phone numbers work at which restaurant.
        $generic = [
            'requested' => true,
            'message'   => 'If that account exists and has an email, a reset link has been sent.',
        ];

        $user = Database::selectOne(
            'SELECT u.id, u.name, u.email, r.name AS restaurant_name
               FROM users u
               JOIN restaurants r ON r.id = u.restaurant_id
              WHERE r.slug = :slug AND u.phone = :phone AND u.is_active = 1
              LIMIT 1',
            [
                'slug'  => strtoupper(trim((string) $data['restaurant_code'])),
                'phone' => Auth::normalisePhone((string) $data['phone']),
            ],
        );

        if ($user === null || ($user['email'] ?? '') === '') {
            return $generic;
        }

        if (!Mailer::isConfigured()) {
            // Honest to the operator in the log, still generic to the caller.
            error_log('[dacaam] password reset requested but SMTP is not configured');

            return $generic;
        }

        $token = bin2hex(random_bytes(32));

        Database::transaction(function () use ($user, $token, $request): void {
            // Any earlier outstanding link for this user dies now.
            Database::run(
                'UPDATE password_resets SET used_at = NOW()
                  WHERE user_id = :uid AND used_at IS NULL',
                ['uid' => $user['id']],
            );

            Database::insert('password_resets', [
                'user_id'    => (int) $user['id'],
                'token_hash' => Auth::hash($token),
                'expires_at' => date(
                    'Y-m-d H:i:s',
                    time() + self::TOKEN_TTL_MINUTES * 60,
                ),
                'ip'         => $request->ip,
            ]);
        });

        Mailer::send(
            (string) $user['email'],
            'Reset your DACAAM password',
            $this->plainBody((string) $user['name'], (string) $user['restaurant_name'], $token),
            $this->htmlBody((string) $user['name'], (string) $user['restaurant_name'], $token),
        );

        return $generic;
    }

    /** @return array<string,mixed> */
    public function reset(Request $request): array
    {
        $data = Validator::check($request->all(), [
            'token'        => 'required|string|min:32|max:128',
            'new_password' => 'required|string|min:1|max:100',
        ]);

        $row = Database::selectOne(
            'SELECT pr.id, pr.user_id, pr.expires_at, pr.used_at,
                    u.name, u.restaurant_id
               FROM password_resets pr
               JOIN users u ON u.id = pr.user_id
              WHERE pr.token_hash = :hash
              LIMIT 1',
            ['hash' => Auth::hash((string) $data['token'])],
        );

        if ($row === null || $row['used_at'] !== null) {
            throw ApiException::unauthorized('This reset link is no longer valid');
        }
        if (strtotime((string) $row['expires_at']) < time()) {
            throw ApiException::unauthorized('This reset link has expired');
        }

        $policy = new PasswordPolicy(self::settings((int) $row['restaurant_id']));
        $policy->assert((string) $data['new_password'], 'new_password');

        Database::transaction(function () use ($row, $data, $policy): void {
            Database::run(
                'UPDATE users
                    SET password_hash = :hash,
                        password_changed_at = NOW(),
                        must_change_password = 0,
                        failed_logins = 0,
                        locked_until = NULL
                  WHERE id = :id',
                [
                    'hash' => $policy->hash((string) $data['new_password']),
                    'id'   => $row['user_id'],
                ],
            );

            Database::run(
                'UPDATE password_resets SET used_at = NOW() WHERE id = :id',
                ['id' => $row['id']],
            );

            // Every existing session was authorised by the old password.
            Database::run(
                'UPDATE api_tokens SET revoked_at = NOW()
                  WHERE user_id = :uid AND revoked_at IS NULL',
                ['uid' => $row['user_id']],
            );
        });

        Audit::log(
            new AuthContext(
                userId: (int) $row['user_id'],
                restaurantId: (int) $row['restaurant_id'],
                userName: (string) $row['name'],
                restaurantSlug: '',
                permissions: [],
                ip: $request->ip,
                device: $request->device(),
            ),
            module: 'security',
            action: 'password_reset',
            recordId: (int) $row['user_id'],
        );

        return ['reset' => true];
    }

    private function plainBody(string $name, string $restaurant, string $token): string
    {
        return <<<TEXT
        Salaan $name,

        Codsi ah in la beddelo furahaaga sirta ee $restaurant ayaa la helay.

        Koodhkaaga:
        $token

        Wuxuu dhacayaa {$this->ttl()} daqiiqo gudahood. Haddii aadan adigu
        codsan, iska indho tir fariintan — furahaagu wali waa sax.

        DACAAM
        TEXT;
    }

    private function htmlBody(string $name, string $restaurant, string $token): string
    {
        $safeName = htmlspecialchars($name, ENT_QUOTES, 'UTF-8');
        $safeRestaurant = htmlspecialchars($restaurant, ENT_QUOTES, 'UTF-8');
        $ttl = $this->ttl();

        return <<<HTML
        <div style="font-family:system-ui,-apple-system,Segoe UI,Roboto,sans-serif;
                    max-width:520px;margin:0 auto;padding:24px;color:#0F172A">
          <div style="background:linear-gradient(135deg,#F97316,#F59E0B);
                      border-radius:20px;padding:24px;text-align:center;color:#fff">
            <div style="font-size:32px">🍔</div>
            <div style="font-size:20px;font-weight:700;letter-spacing:3px">DACAAM</div>
          </div>
          <p style="margin-top:24px">Salaan <strong>$safeName</strong>,</p>
          <p>Codsi ah in la beddelo furahaaga sirta ee <strong>$safeRestaurant</strong>
             ayaa la helay.</p>
          <div style="background:#F1F5F9;border-radius:14px;padding:16px;
                      font-family:ui-monospace,monospace;word-break:break-all;
                      font-size:13px">$token</div>
          <p style="color:#64748B;font-size:13px">
            Wuxuu dhacayaa $ttl daqiiqo gudahood. Haddii aadan adigu codsan,
            iska indho tir fariintan — furahaagu wali waa sax.
          </p>
        </div>
        HTML;
    }

    private function ttl(): int
    {
        return self::TOKEN_TTL_MINUTES;
    }
}
