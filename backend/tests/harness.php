<?php

declare(strict_types=1);

/**
 * Minimal test harness shared by the API suites.
 *
 * Deliberately tiny: these are end-to-end checks against a live server, and a
 * full test framework would add a dependency for `assert` and coloured output.
 */

$GLOBALS['t_base'] = rtrim($GLOBALS['argv'][1] ?? 'http://127.0.0.1:8090', '/');
$GLOBALS['t_passed'] = 0;
$GLOBALS['t_failed'] = 0;

function group(string $name): void
{
    echo "\n\033[1m$name\033[0m\n";
}

function ok(bool $condition, string $label, string $detail = ''): void
{
    if ($condition) {
        $GLOBALS['t_passed']++;
        echo "  \033[32mPASS\033[0m  $label\n";

        return;
    }

    $GLOBALS['t_failed']++;
    echo "  \033[31mFAIL\033[0m  $label";
    echo $detail === '' ? "\n" : "\n        $detail\n";
}

/**
 * @param  array<string,mixed>|null $body
 * @return array{status:int,json:array<string,mixed>}
 */
function request(string $method, string $path, ?array $body = null, ?string $token = null): array
{
    $ch = curl_init($GLOBALS['t_base'] . $path);
    $headers = ['Accept: application/json', 'X-Device: api-test'];

    if ($body !== null) {
        $headers[] = 'Content-Type: application/json';
        curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($body, JSON_UNESCAPED_UNICODE));
    }
    if ($token !== null) {
        $headers[] = 'Authorization: Bearer ' . $token;
    }

    curl_setopt_array($ch, [
        CURLOPT_CUSTOMREQUEST  => $method,
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_HTTPHEADER     => $headers,
        CURLOPT_TIMEOUT        => 20,
    ]);

    $raw = curl_exec($ch);
    $status = (int) curl_getinfo($ch, CURLINFO_HTTP_CODE);
    $error = curl_error($ch);
    curl_close($ch);

    if ($raw === false) {
        return ['status' => 0, 'json' => ['error' => ['message' => $error]]];
    }

    $json = json_decode((string) $raw, true);

    return ['status' => $status, 'json' => is_array($json) ? $json : ['raw' => $raw]];
}

/** @return array{status:int,json:array<string,mixed>} */
function login(string $code, string $phone, string $password = 'admin123'): array
{
    return request('POST', '/api/v1/auth/login', [
        'restaurant_code' => $code,
        'phone'           => $phone,
        'password'        => $password,
    ]);
}

/**
 * Opens a till, so orders can be taken.
 *
 * Nothing can be sold outside a shift — that is the point of the feature, not
 * an inconvenience — so every suite that creates an order has to open one
 * first, exactly as a restaurant does at the start of service.
 *
 * Idempotent: a till that is already open is left alone.
 */
function ensureShift(string $token, float $float = 100000): void
{
    $current = request('GET', '/api/v1/shifts/current', null, $token);

    // A database that predates the shift tables answers 404 or 403; those
    // suites simply have no till to open.
    if ($current['status'] !== 200) {
        return;
    }

    if (($current['json']['data']['shift'] ?? null) !== null) {
        return;
    }

    request('POST', '/api/v1/shifts', ['opening_float' => $float], $token);
}

function token(array $response): string
{
    return (string) ($response['json']['data']['token'] ?? '');
}

function summary(): never
{
    $passed = $GLOBALS['t_passed'];
    $failed = $GLOBALS['t_failed'];

    echo "\n";
    echo $failed === 0
        ? "\033[32m$passed passed, 0 failed\033[0m\n"
        : "\033[31m$passed passed, $failed failed\033[0m\n";

    exit($failed === 0 ? 0 : 1);
}
