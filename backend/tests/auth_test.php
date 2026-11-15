<?php

declare(strict_types=1);

/**
 * Phase 3 — authentication, two-factor, sessions, policy, roles.
 *
 *   php bin/migrate.php --fresh --seed
 *   php -S 127.0.0.1:8090 -t public public/index.php
 *   php tests/auth_test.php http://127.0.0.1:8090
 *
 * Requires a freshly seeded database: several checks deliberately lock an
 * account or enable 2FA and do not undo it.
 */

require __DIR__ . '/harness.php';
require dirname(__DIR__) . '/bootstrap.php';

use Dacaam\Core\Totp;

/** Waits for a fresh TOTP step when the current one is nearly over. */
function freshCode(string $secret): string
{
    $secondsIntoStep = time() % 30;
    if ($secondsIntoStep > 27) {
        sleep(30 - $secondsIntoStep + 1);
    }

    return Totp::codeAt($secret, time());
}

// ============================================================ password policy

group('Password policy');

$admin = token(login('HAMZE', '0634567890'));
ok($admin !== '', 'HAMZE admin signs in without 2FA');

$policy = request('GET', '/api/v1/security/policy', null, $admin);
ok($policy['status'] === 200, 'the policy is readable');
ok(($policy['json']['data']['password']['min_length'] ?? 0) === 6, 'HAMZE requires 6 characters');

$warfa = token(login('WARFA', '0637778899'));
$warfaPolicy = request('GET', '/api/v1/security/policy', null, $warfa);
ok(
    ($warfaPolicy['json']['data']['password']['min_length'] ?? 0) === 8
    && ($warfaPolicy['json']['data']['password']['require_number'] ?? false) === true,
    'WARFA carries its own stricter policy',
);

$weak = request('POST', '/api/v1/users', [
    'name'      => 'Weak Password',
    'phone'     => '0639998887',
    'password'  => 'abcdefgh', // long enough, but WARFA needs a number
    'role_code' => 'waiter',
], $warfa);
ok($weak['status'] === 422, 'WARFA rejects a password with no number');
ok(
    str_contains(strtolower($weak['json']['error']['fields']['password'] ?? ''), 'number'),
    'and says which rule failed',
    $weak['json']['error']['fields']['password'] ?? '',
);

$short = request('POST', '/api/v1/users', [
    'name'      => 'Short Password',
    'phone'     => '0639998886',
    'password'  => 'ab1',
    'role_code' => 'waiter',
], $warfa);
ok($short['status'] === 422, 'a too-short password is rejected');

$goodUser = request('POST', '/api/v1/users', [
    'name'      => 'Cabdi Nuur',
    'phone'     => '0639998885',
    'password'  => 'goodpass1',
    'role_code' => 'waiter',
], $warfa);
ok($goodUser['status'] === 200, 'a compliant password is accepted');
ok(
    ($goodUser['json']['data']['must_change_password'] ?? false) === true,
    'a password set by an admin must be changed on first use',
);

// ================================================================= lockout

group('Account lockout');

for ($i = 0; $i < 5; $i++) {
    login('HAMZE', '0633344556', 'wrong-password'); // Omar Jaamac
}
$locked = login('HAMZE', '0633344556');
ok($locked['status'] === 403, 'the account locks after five failures', 'got ' . $locked['status']);
ok(
    str_contains(strtolower($locked['json']['error']['message'] ?? ''), 'too many'),
    'and the message says why',
);

$others = login('HAMZE', '0632233445');
ok($others['status'] === 200, 'other accounts are unaffected');

// =================================================== change own password

group('Change password');

$waiter = token($others);

$wrongCurrent = request('POST', '/api/v1/security/password', [
    'current_password' => 'not-my-password',
    'new_password'     => 'brand-new-1',
], $waiter);
ok($wrongCurrent['status'] === 422, 'the current password must be correct');

$secondSession = token(login('HAMZE', '0632233445'));
ok($secondSession !== '', 'a second device signs in');

$changed = request('POST', '/api/v1/security/password', [
    'current_password' => 'admin123',
    'new_password'     => 'newpass456',
], $waiter);
ok($changed['status'] === 200, 'the password changes');

$oldPassword = login('HAMZE', '0632233445', 'admin123');
ok($oldPassword['status'] === 401, 'the old password stops working');

$newPassword = login('HAMZE', '0632233445', 'newpass456');
ok($newPassword['status'] === 200, 'the new password works');

$otherDevice = request('GET', '/api/v1/orders', null, $secondSession);
ok(
    $otherDevice['status'] === 401,
    'changing the password ends sessions on other devices',
    'got ' . $otherDevice['status'],
);

$sameDevice = request('GET', '/api/v1/orders', null, $waiter);
ok($sameDevice['status'] === 200, 'but not the device that changed it');

// ================================================================ sessions

group('Session management');

$deviceA = token(login('HAMZE', '0634567890'));
$deviceB = token(login('HAMZE', '0634567890'));
$deviceC = token(login('HAMZE', '0634567890'));

$sessions = request('GET', '/api/v1/security/sessions', null, $deviceC)['json']['data'] ?? [];
ok(count($sessions) >= 3, 'all active sessions are listed', 'got ' . count($sessions));

$current = array_values(array_filter($sessions, static fn (array $s): bool => $s['is_current']));
ok(count($current) === 1, 'exactly one is flagged as the current device');

$revokeSelf = request(
    'DELETE',
    '/api/v1/security/sessions/' . $current[0]['id'],
    null,
    $deviceC,
);
ok($revokeSelf['status'] === 422, 'you cannot revoke the session you are using');

$target = array_values(array_filter($sessions, static fn (array $s): bool => !$s['is_current']))[0];
$revoked = request('DELETE', '/api/v1/security/sessions/' . $target['id'], null, $deviceC);
ok($revoked['status'] === 200, 'another session can be revoked');

// The listing holds session ids, not tokens, and earlier groups in this file
// left sessions of their own — so verify by id rather than guessing which
// token the revoked row belonged to.
$afterRevoke = request('GET', '/api/v1/security/sessions', null, $deviceC)['json']['data'] ?? [];
ok(
    !in_array($target['id'], array_column($afterRevoke, 'id'), true),
    'the revoked session disappears from the list',
);

$revokeOthers = request('POST', '/api/v1/security/sessions/revoke-others', null, $deviceC);
ok($revokeOthers['status'] === 200, 'all other sessions can be revoked at once');
ok(request('GET', '/api/v1/orders', null, $deviceC)['status'] === 200, 'the current one survives');
ok(
    request('GET', '/api/v1/orders', null, $deviceA)['status'] === 401
    && request('GET', '/api/v1/orders', null, $deviceB)['status'] === 401,
    'and the revoked tokens stop working',
);

$after = request('GET', '/api/v1/security/sessions', null, $deviceC)['json']['data'] ?? [];
ok(count($after) === 1, 'only the current session remains', 'got ' . count($after));

// ============================================================ login history

group('Login history');

$history = request('GET', '/api/v1/security/login-history', null, $deviceC)['json']['data'] ?? [];
ok($history !== [], 'login history is recorded');
ok(
    count(array_filter($history, static fn (array $h): bool => $h['succeeded'] === false)) > 0,
    'failed attempts are recorded too',
);
ok(
    isset($history[0]['ip'], $history[0]['device'], $history[0]['created_at']),
    'each entry carries IP, device and time',
);

$waiterHistory = request('GET', '/api/v1/security/login-history', null, $waiter)['json']['data'] ?? [];
$phones = array_unique(array_column($waiterHistory, 'phone'));
ok(
    count($phones) <= 1,
    'a user without users.view sees only their own history',
    implode(',', $phones),
);

// =================================================================== 2FA

group('Two-factor authentication');

$admin = token(login('HAMZE', '0634567890'));

$overview = request('GET', '/api/v1/security/overview', null, $admin);
ok($overview['status'] === 200, 'the security overview loads');
ok(($overview['json']['data']['two_factor']['enabled'] ?? true) === false, '2FA starts disabled');

$setup = request('POST', '/api/v1/security/2fa/setup', null, $admin);
ok($setup['status'] === 200, 'setup returns a secret');
$secret = (string) ($setup['json']['data']['secret'] ?? '');
ok(strlen($secret) === 32, 'the secret is a 160-bit base32 string', 'len ' . strlen($secret));
ok(
    str_starts_with((string) ($setup['json']['data']['otpauth_uri'] ?? ''), 'otpauth://totp/'),
    'and a provisioning URI an authenticator can scan',
);

$stillOff = login('HAMZE', '0634567890');
ok(
    ($stillOff['json']['data']['requires_two_factor'] ?? true) === false,
    'an unconfirmed setup does not switch 2FA on',
);

$badConfirm = request('POST', '/api/v1/security/2fa/confirm', ['code' => '000000'], $admin);
ok($badConfirm['status'] === 422, 'confirmation rejects a wrong code');

$confirm = request('POST', '/api/v1/security/2fa/confirm', [
    'code' => freshCode($secret),
], $admin);
ok($confirm['status'] === 200, 'confirmation accepts a real code', json_encode($confirm['json']));

$recoveryCodes = $confirm['json']['data']['recovery_codes'] ?? [];
ok(count($recoveryCodes) === 8, 'eight recovery codes are issued');
ok(
    preg_match('/^[A-Z0-9]{4}-[A-Z0-9]{4}$/', $recoveryCodes[0] ?? '') === 1,
    'formatted for reading off paper',
    $recoveryCodes[0] ?? '',
);

$reconfirm = request('POST', '/api/v1/security/2fa/confirm', ['code' => '123456'], $admin);
ok($reconfirm['status'] === 409, 'it cannot be confirmed twice');

// ------------------------------------------------------- two-step sign-in

$step1 = login('HAMZE', '0634567890');
ok($step1['status'] === 200, 'the password step still succeeds');
ok(($step1['json']['data']['requires_two_factor'] ?? false) === true, 'but it now asks for a code');
ok(($step1['json']['data']['token'] ?? null) === null, 'and issues no session token');

$challenge = (string) ($step1['json']['data']['challenge'] ?? '');
ok($challenge !== '', 'a challenge is returned instead');

$noSession = request('GET', '/api/v1/bootstrap', null, $challenge);
ok($noSession['status'] === 401, 'the challenge is not usable as a token');

$wrongOtp = request('POST', '/api/v1/auth/2fa/verify', [
    'challenge' => $challenge,
    'code'      => '000000',
], null);
ok($wrongOtp['status'] === 401, 'a wrong code is rejected');

$code = freshCode($secret);
$verify = request('POST', '/api/v1/auth/2fa/verify', [
    'challenge' => $challenge,
    'code'      => $code,
], null);
ok($verify['status'] === 200, 'the right code completes sign-in', json_encode($verify['json']));
$twoFactorToken = token($verify);
ok($twoFactorToken !== '', 'and issues a real session token');
ok(
    request('GET', '/api/v1/bootstrap', null, $twoFactorToken)['status'] === 200,
    'which works against the API',
);

$reuseChallenge = request('POST', '/api/v1/auth/2fa/verify', [
    'challenge' => $challenge,
    'code'      => freshCode($secret),
], null);
ok($reuseChallenge['status'] === 401, 'a consumed challenge cannot be reused');

// --------------------------------------------------------- replay & retry

$step1b = login('HAMZE', '0634567890');
$challengeB = (string) ($step1b['json']['data']['challenge'] ?? '');

$replay = request('POST', '/api/v1/auth/2fa/verify', [
    'challenge' => $challengeB,
    'code'      => $code, // the code already used above
], null);
ok(
    $replay['status'] === 401,
    'the same TOTP code cannot be used twice inside its window',
    'got ' . $replay['status'],
);

// The replay above already counted as one wrong attempt, so the challenge is
// killed part-way through this loop rather than after it.
$sawLockout = false;
for ($i = 0; $i < 6; $i++) {
    $attempt = request('POST', '/api/v1/auth/2fa/verify', [
        'challenge' => $challengeB,
        'code'      => '111111',
    ], null);
    if ($attempt['status'] === 403) {
        $sawLockout = true;
        break;
    }
}
ok($sawLockout, 'a challenge is killed once its attempts run out');

$afterLockout = request('POST', '/api/v1/auth/2fa/verify', [
    'challenge' => $challengeB,
    'code'      => freshCode($secret),
], null);
ok(
    $afterLockout['status'] === 401,
    'and a correct code no longer revives it',
    'got ' . $afterLockout['status'],
);

// -------------------------------------------------------- recovery codes

$step1c = login('HAMZE', '0634567890');
$challengeC = (string) ($step1c['json']['data']['challenge'] ?? '');

$recovery = request('POST', '/api/v1/auth/2fa/verify', [
    'challenge' => $challengeC,
    'code'      => $recoveryCodes[0],
], null);
ok($recovery['status'] === 200, 'a recovery code completes sign-in');

$step1d = login('HAMZE', '0634567890');
$reusedRecovery = request('POST', '/api/v1/auth/2fa/verify', [
    'challenge' => (string) ($step1d['json']['data']['challenge'] ?? ''),
    'code'      => $recoveryCodes[0],
], null);
ok($reusedRecovery['status'] === 401, 'a recovery code works exactly once');

$remaining = request('GET', '/api/v1/security/overview', null, $twoFactorToken);
ok(
    ($remaining['json']['data']['two_factor']['unused_recovery_codes'] ?? 0) === 7,
    'the used code is marked spent',
    'got ' . ($remaining['json']['data']['two_factor']['unused_recovery_codes'] ?? '?'),
);

// ------------------------------------------------------------- disabling

$disableNoPassword = request('POST', '/api/v1/security/2fa/disable', [
    'password' => 'wrong',
], $twoFactorToken);
ok($disableNoPassword['status'] === 422, 'disabling 2FA needs the account password');

$disabled = request('POST', '/api/v1/security/2fa/disable', [
    'password' => 'admin123',
], $twoFactorToken);
ok($disabled['status'] === 200, 'with the password it turns off');

$afterDisable = login('HAMZE', '0634567890');
ok(
    ($afterDisable['json']['data']['requires_two_factor'] ?? true) === false,
    'sign-in returns to one step',
);

// =============================================== roles & granular permissions

group('Roles and granular permissions');

$admin = token($afterDisable);

$roles = request('GET', '/api/v1/roles', null, $admin)['json']['data'] ?? [];
ok(count($roles) === 3, 'the three built-in roles exist');

$adminRole = array_values(array_filter($roles, static fn (array $r): bool => $r['code'] === 'admin'))[0];
// Against the catalogue, not a number typed in once. Every permission added
// since — customers, payments, notifications — silently left this assertion
// wrong, and a hardcoded count fails loudest exactly when it matters least.
$catalogue = request('GET', '/api/v1/permissions', null, $admin)['json']['data'] ?? [];
$allCodes = [];
foreach ($catalogue as $entry) {
    // The endpoint groups by module, so flatten whichever shape comes back.
    if (isset($entry['code'])) {
        $allCodes[] = (string) $entry['code'];
        continue;
    }

    foreach ((array) ($entry['permissions'] ?? $entry) as $permission) {
        if (isset($permission['code'])) {
            $allCodes[] = (string) $permission['code'];
        }
    }
}

$allCodes = array_unique($allCodes);
$missing = array_diff($allCodes, array_column($adminRole['permissions'], 'code') ?: $adminRole['permissions']);

ok($allCodes !== [], 'the permission catalogue is readable', (string) count($allCodes));
ok(
    $missing === [],
    'admin holds every permission in the catalogue',
    count($allCodes) . ' defined, admin has ' . count($adminRole['permissions'])
        . ', missing: ' . implode(', ', $missing),
);

$waiterRole = array_values(array_filter($roles, static fn (array $r): bool => $r['code'] === 'waiter'))[0];
ok(!in_array('reports.view', $waiterRole['permissions'], true), 'waiter cannot see reports');

$newRole = request('POST', '/api/v1/roles', [
    'code'        => 'cashier',
    'name'        => 'Lacag Qaade',
    'permissions' => ['orders.view', 'orders.create', 'accounts.view'],
], $admin);
ok($newRole['status'] === 200, 'a custom role can be created');
ok(count($newRole['json']['data']['permissions'] ?? []) === 3, 'with the permissions given');
$roleId = (int) ($newRole['json']['data']['id'] ?? 0);

$duplicate = request('POST', '/api/v1/roles', [
    'code' => 'cashier',
    'name' => 'Another',
], $admin);
ok($duplicate['status'] === 422, 'role codes are unique per restaurant');

$repermissioned = request('PUT', "/api/v1/roles/$roleId/permissions", [
    'permissions' => ['orders.view'],
], $admin);
ok(count($repermissioned['json']['data']['permissions'] ?? []) === 1, 'role permissions can be replaced');

$deleteSystem = request('DELETE', '/api/v1/roles/' . $adminRole['id'], null, $admin);
ok($deleteSystem['status'] === 409, 'built-in roles cannot be deleted');

$deleteCustom = request('DELETE', "/api/v1/roles/$roleId", null, $admin);
ok($deleteCustom['status'] === 200, 'an unused custom role can be deleted');

// ------------------------------------------------------ per-user overrides

// Abdullahi (id 3) is a waiter: no reports, no cancelling.
$before = request('GET', '/api/v1/users', null, $admin)['json']['data'] ?? [];
$abdullahi = array_values(array_filter($before, static fn (array $u): bool => (int) $u['id'] === 3))[0];
ok(!in_array('orders.cancel', $abdullahi['permissions'], true), 'the waiter cannot cancel by default');

$granted = request('PUT', '/api/v1/users/3/permissions', [
    'permissions' => ['orders.cancel' => true],
], $admin);
ok($granted['status'] === 200, 'a single extra permission can be granted');
ok(
    in_array('orders.cancel', $granted['json']['data']['permissions'] ?? [], true),
    'and it shows on the user',
);

$waiterToken = token(login('HAMZE', '0632233445', 'newpass456'));
$stillNoReports = request('GET', '/api/v1/reports/summary', null, $waiterToken);
ok($stillNoReports['status'] === 403, 'the override does not grant anything else');

// Now revoke something the role does allow.
$revokedPerm = request('PUT', '/api/v1/users/3/permissions', [
    'permissions' => ['menu.view' => false],
], $admin);
ok(
    !in_array('menu.view', $revokedPerm['json']['data']['permissions'] ?? [], true),
    'a role-granted permission can be revoked for one user',
);

$waiterToken = token(login('HAMZE', '0632233445', 'newpass456'));
$menuBlocked = request('GET', '/api/v1/menu/items', null, $waiterToken);
ok($menuBlocked['status'] === 403, 'and the API enforces the revocation', 'got ' . $menuBlocked['status']);

// ----------------------------------------------------------- lockout guard

$selfLockout = request('PUT', '/api/v1/users/1/permissions', [
    'permissions' => ['users.edit' => false],
], $admin);
ok(
    $selfLockout['status'] === 409,
    'the last user who can manage users cannot be stripped of it',
    'got ' . $selfLockout['status'],
);

$stillWorks = request('GET', '/api/v1/users', null, $admin);
ok($stillWorks['status'] === 200, 'and the rejected change was rolled back');

summary();
