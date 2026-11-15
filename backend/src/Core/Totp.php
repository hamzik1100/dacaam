<?php

declare(strict_types=1);

namespace Dacaam\Core;

/**
 * Time-based one-time passwords (RFC 6238), HMAC-SHA1, 6 digits, 30s step.
 *
 * Implemented directly rather than pulled in as a dependency: the algorithm is
 * forty lines, and the deployment target is a shared PHP host where "just add
 * Composer" is not always an option.
 *
 * Compatible with Google Authenticator, Authy, Aegis and 1Password.
 */
final class Totp
{
    private const ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
    private const DIGITS = 6;
    private const PERIOD = 30;

    /**
     * A 160-bit secret, base32 encoded — the size RFC 4226 recommends for
     * HMAC-SHA1.
     */
    public static function generateSecret(int $bytes = 20): string
    {
        return self::base32Encode(random_bytes($bytes));
    }

    /**
     * The `otpauth://` URI an authenticator app scans.
     *
     * The label carries both restaurant and user, so someone working at two
     * restaurants can tell their two entries apart.
     */
    public static function provisioningUri(
        string $secret,
        string $accountName,
        string $issuer,
    ): string {
        return sprintf(
            'otpauth://totp/%s:%s?secret=%s&issuer=%s&algorithm=SHA1&digits=%d&period=%d',
            rawurlencode($issuer),
            rawurlencode($accountName),
            $secret,
            rawurlencode($issuer),
            self::DIGITS,
            self::PERIOD,
        );
    }

    public static function codeAt(string $secret, int $timestamp): string
    {
        $counter = intdiv($timestamp, self::PERIOD);
        $binary = pack('N*', 0, $counter); // 64-bit big-endian counter
        $key = self::base32Decode($secret);

        if ($key === '') {
            return '';
        }

        $hash = hash_hmac('sha1', $binary, $key, true);

        // Dynamic truncation, RFC 4226 §5.3.
        $offset = ord($hash[19]) & 0x0F;
        $value = ((ord($hash[$offset]) & 0x7F) << 24)
            | ((ord($hash[$offset + 1]) & 0xFF) << 16)
            | ((ord($hash[$offset + 2]) & 0xFF) << 8)
            | (ord($hash[$offset + 3]) & 0xFF);

        return str_pad(
            (string) ($value % (10 ** self::DIGITS)),
            self::DIGITS,
            '0',
            STR_PAD_LEFT,
        );
    }

    /**
     * Verifies a code, allowing [$window] steps of clock drift either way.
     *
     * One step (±30s) is the usual compromise: phones drift, and a POS behind
     * a counter is often on a device nobody has ever synced.
     */
    public static function verify(
        string $secret,
        string $code,
        int $window = 1,
        ?int $now = null,
    ): bool {
        $code = preg_replace('/\D/', '', $code) ?? '';
        if (strlen($code) !== self::DIGITS) {
            return false;
        }

        $now ??= time();

        for ($i = -$window; $i <= $window; $i++) {
            $candidate = self::codeAt($secret, $now + ($i * self::PERIOD));
            // Constant-time: a timing side channel on a 6-digit code is a real
            // (if slow) oracle.
            if ($candidate !== '' && hash_equals($candidate, $code)) {
                return true;
            }
        }

        return false;
    }

    /**
     * Human-transcribable recovery codes, e.g. `4F7K-92QX`.
     *
     * @return list<string>
     */
    public static function generateRecoveryCodes(int $count = 8): array
    {
        // No 0/O/1/I: these get read off paper under kitchen lighting.
        $alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
        $codes = [];

        for ($i = 0; $i < $count; $i++) {
            $raw = '';
            for ($c = 0; $c < 8; $c++) {
                $raw .= $alphabet[random_int(0, strlen($alphabet) - 1)];
            }
            $codes[] = substr($raw, 0, 4) . '-' . substr($raw, 4, 4);
        }

        return $codes;
    }

    public static function normaliseRecoveryCode(string $code): string
    {
        return strtoupper(preg_replace('/[^A-Za-z0-9]/', '', $code) ?? '');
    }

    // ------------------------------------------------------------ base32

    public static function base32Encode(string $binary): string
    {
        if ($binary === '') {
            return '';
        }

        $bits = '';
        foreach (str_split($binary) as $char) {
            $bits .= str_pad(decbin(ord($char)), 8, '0', STR_PAD_LEFT);
        }

        $out = '';
        foreach (str_split($bits, 5) as $chunk) {
            $out .= self::ALPHABET[bindec(str_pad($chunk, 5, '0', STR_PAD_RIGHT))];
        }

        return $out;
    }

    public static function base32Decode(string $encoded): string
    {
        $encoded = strtoupper(preg_replace('/[^A-Za-z2-7]/', '', $encoded) ?? '');
        if ($encoded === '') {
            return '';
        }

        $bits = '';
        for ($i = 0, $len = strlen($encoded); $i < $len; $i++) {
            $index = strpos(self::ALPHABET, $encoded[$i]);
            if ($index === false) {
                return '';
            }
            $bits .= str_pad(decbin($index), 5, '0', STR_PAD_LEFT);
        }

        $out = '';
        foreach (str_split($bits, 8) as $chunk) {
            if (strlen($chunk) === 8) {
                $out .= chr(bindec($chunk));
            }
        }

        return $out;
    }
}
