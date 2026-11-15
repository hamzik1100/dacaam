<?php

declare(strict_types=1);

namespace Dacaam\Support;

use Dacaam\Core\Config;
use Dacaam\Core\Database;
use RuntimeException;
use Throwable;

/**
 * Sends a notification to handsets through Firebase Cloud Messaging.
 *
 * FCM is a delivery pipe and nothing more. The data stays in MySQL and the API
 * stays PHP; this makes one HTTPS call so that a phone with the app closed
 * still lights up, which is the one thing a server cannot do on its own —
 * Android keeps a socket open only for Google Play Services, so a push has to
 * travel through it.
 *
 * No SDK. The v1 API wants an OAuth2 token, that wants a signed JWT, and PHP
 * signs one with `openssl_sign` in a dozen lines. Pulling in a dependency tree
 * to save those lines would be a poor trade on shared hosting.
 *
 * Every failure is swallowed and logged. A notification that does not arrive
 * must never take down the thing that triggered it: the message is already
 * saved in `notifications`, so the app shows it on next open even if Google is
 * unreachable.
 */
final class Push
{
    private const SCOPE = 'https://www.googleapis.com/auth/firebase.messaging';

    private function __construct()
    {
    }

    public static function isConfigured(): bool
    {
        $path = (string) Config::get('firebase.key_path');

        return $path !== '' && is_file($path);
    }

    /**
     * Delivers one message to many handsets. Returns how many were accepted.
     *
     * A token Google reports as unregistered — the app was uninstalled, or
     * Android reissued it — is deleted here. That is the only maintenance
     * `device_tokens` ever needs.
     *
     * @param list<string>         $tokens
     * @param array<string,scalar> $data
     */
    public static function send(
        array $tokens,
        string $title,
        string $body,
        array $data = [],
    ): int {
        $tokens = array_values(array_unique(array_filter($tokens)));

        if ($tokens === [] || !self::isConfigured()) {
            return 0;
        }

        try {
            $credentials = self::credentials();
            $accessToken = self::accessToken($credentials);
        } catch (Throwable $e) {
            error_log('[dacaam] push not sent: ' . $e->getMessage());

            return 0;
        }

        $url = sprintf(
            'https://fcm.googleapis.com/v1/projects/%s/messages:send',
            (string) ($credentials['project_id'] ?? ''),
        );

        $sent = 0;
        $dead = [];

        foreach ($tokens as $token) {
            $payload = [
                'message' => [
                    'token'        => $token,
                    'notification' => ['title' => $title, 'body' => $body],
                    // Carried alongside so the app can open the right screen
                    // when somebody taps the notification.
                    'data'         => array_map('strval', $data),
                    'android'      => [
                        'priority'     => 'high',
                        'notification' => ['channel_id' => 'dacaam_messages'],
                    ],
                ],
            ];

            [$status, $response] = self::post($url, $payload, $accessToken);

            if ($status >= 200 && $status < 300) {
                $sent++;
                continue;
            }

            // Both of these mean the handset will never receive anything again.
            if ($status === 404 || str_contains($response, 'UNREGISTERED')) {
                $dead[] = $token;
                continue;
            }

            error_log(sprintf('[dacaam] push rejected (%d): %s', $status, substr($response, 0, 200)));
        }

        self::forget($dead);

        return $sent;
    }

    /** @param list<string> $tokens */
    private static function forget(array $tokens): void
    {
        if ($tokens === []) {
            return;
        }

        $placeholders = implode(',', array_fill(0, count($tokens), '?'));

        Database::run(
            sprintf('DELETE FROM device_tokens WHERE token IN (%s)', $placeholders),
            $tokens,
        );
    }

    /** @return array<string,mixed> */
    private static function credentials(): array
    {
        $raw = @file_get_contents((string) Config::get('firebase.key_path'));
        $json = $raw === false ? null : json_decode($raw, true);

        if (!is_array($json) || !isset($json['client_email'], $json['private_key'])) {
            throw new RuntimeException('The Firebase key file is missing or unreadable');
        }

        return $json;
    }

    /**
     * Exchanges the service account for an access token.
     *
     * Held in a static for the life of the request: tokens last an hour, and a
     * broadcast to two hundred handsets is one request, so this is fetched once
     * rather than two hundred times.
     *
     * @param array<string,mixed> $credentials
     */
    private static function accessToken(array $credentials): string
    {
        static $cached = null;

        if ($cached !== null) {
            return $cached;
        }

        $now = time();
        $header = self::base64url((string) json_encode(['alg' => 'RS256', 'typ' => 'JWT']));
        $claim = self::base64url((string) json_encode([
            'iss'   => $credentials['client_email'],
            'scope' => self::SCOPE,
            'aud'   => 'https://oauth2.googleapis.com/token',
            'iat'   => $now,
            'exp'   => $now + 3600,
        ]));

        $signature = '';
        if (!openssl_sign(
            $header . '.' . $claim,
            $signature,
            (string) $credentials['private_key'],
            OPENSSL_ALGO_SHA256,
        )) {
            throw new RuntimeException('Could not sign the Firebase token request');
        }

        $ch = curl_init('https://oauth2.googleapis.com/token');
        curl_setopt_array($ch, [
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_POST           => true,
            CURLOPT_TIMEOUT        => 15,
            CURLOPT_POSTFIELDS     => http_build_query([
                'grant_type' => 'urn:ietf:params:oauth:grant-type:jwt-bearer',
                'assertion'  => $header . '.' . $claim . '.' . self::base64url($signature),
            ]),
        ]);

        $response = (string) curl_exec($ch);
        curl_close($ch);

        $token = json_decode($response, true)['access_token'] ?? null;

        if (!is_string($token) || $token === '') {
            throw new RuntimeException('Firebase refused the key: ' . substr($response, 0, 200));
        }

        return $cached = $token;
    }

    /**
     * @param  array<string,mixed> $payload
     * @return array{0:int,1:string}
     */
    private static function post(string $url, array $payload, string $accessToken): array
    {
        $ch = curl_init($url);
        curl_setopt_array($ch, [
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_POST           => true,
            CURLOPT_TIMEOUT        => 15,
            CURLOPT_HTTPHEADER     => [
                'Authorization: Bearer ' . $accessToken,
                'Content-Type: application/json',
            ],
            CURLOPT_POSTFIELDS     => (string) json_encode($payload),
        ]);

        $response = (string) curl_exec($ch);
        $status = (int) curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);

        return [$status, $response];
    }

    private static function base64url(string $value): string
    {
        return rtrim(strtr(base64_encode($value), '+/', '-_'), '=');
    }
}
