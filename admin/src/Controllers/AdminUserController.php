<?php

declare(strict_types=1);

namespace DacaamAdmin\Controllers;

use DacaamAdmin\Core\Access;
use DacaamAdmin\Core\AdminAuth;
use DacaamAdmin\Core\Csrf;
use DacaamAdmin\Core\Flash;
use DacaamAdmin\Core\PlatformAudit;
use DacaamAdmin\Core\Refused;
use DacaamAdmin\Core\Response;
use DacaamAdmin\Core\View;
use Dacaam\Core\Database;
use Dacaam\Core\Totp;

/**
 * The people who can run the platform.
 *
 * There used to be exactly one, written at first-run setup and never touched
 * again — no second administrator, no way to disable one, nothing at all if
 * that person left or their account was taken. The account with power over
 * every restaurant was also the only account nobody could manage.
 *
 * Two rules run through everything here, and both exist to stop the platform
 * locking itself out:
 *
 *   - an administrator is disabled, never deleted, so the audit trail keeps
 *     pointing at somebody real;
 *   - the last active administrator cannot be disabled, and nobody can disable
 *     themselves.
 */
final class AdminUserController
{
    /** Platform passwords are longer than a restaurant's. */
    private const MIN_PASSWORD = 10;

    public function index(): void
    {
        View::page('admins', [
            'title'  => 'Administrators',
            'nav'    => 'admins',
            'admins' => Database::select(
                'SELECT a.id, a.name, a.email, a.role, a.is_active, a.last_login_at,
                        a.created_at, a.disabled_at,
                        a.two_factor_confirmed_at,
                        c.name AS invited_by,
                        (SELECT COUNT(*) FROM super_admin_recovery_codes r
                          WHERE r.super_admin_id = a.id AND r.used_at IS NULL) AS codes_left
                   FROM super_admins a
              LEFT JOIN super_admins c ON c.id = a.created_by
                  ORDER BY a.is_active DESC, a.id ASC',
            ),
            'me'     => AdminAuth::require(),
            'active' => self::activeCount(),
            'owners' => self::activeOwners(),
        ]);
    }

    /**
     * Changes what somebody may do.
     *
     * Not your own role — the easiest way to leave a platform with no owner is
     * the last owner demoting themselves by mistake. And never the last active
     * owner's, for the same reason from the other side.
     *
     * @param array<string,string> $params
     */
    public function setRole(array $params): void
    {
        $me = AdminAuth::require();
        $id = (int) $params['id'];
        $role = (string) ($_POST['role'] ?? '');

        if (!isset(Access::ROLES[$role])) {
            throw new Refused('Unknown role');
        }

        $admin = Database::selectOne(
            'SELECT id, name, email, role, is_active FROM super_admins WHERE id = :id',
            ['id' => $id],
        );

        if ($admin === null) {
            Response::notFound();
        }

        if ($id === (int) $me['id']) {
            throw new Refused('You cannot change your own role — ask another owner');
        }

        if ($admin['role'] === 'owner' && $role !== 'owner'
            && (int) $admin['is_active'] === 1 && self::activeOwners() <= 1
        ) {
            throw new Refused('This is the last active owner. Make someone else an owner first.');
        }

        Database::run(
            'UPDATE super_admins SET role = :role WHERE id = :id',
            ['role' => $role, 'id' => $id],
        );

        PlatformAudit::log(
            'platform_admin_role_changed',
            null,
            sprintf('%s: %s → %s', $admin['email'], $admin['role'], $role),
        );

        Flash::success(sprintf('%s is now %s.', (string) $admin['name'], Access::ROLES[$role]));
        Response::redirect('/admins');
    }

    /**
     * Adds one.
     *
     * They set their own password on first sign-in — this one is temporary and
     * handed over in person. Emailing it would put a working credential into a
     * mailbox neither of you controls.
     */
    public function store(): void
    {
        Csrf::verify();

        $me = AdminAuth::require();

        $name = trim((string) ($_POST['name'] ?? ''));
        $email = strtolower(trim((string) ($_POST['email'] ?? '')));
        $password = (string) ($_POST['password'] ?? '');
        $role = (string) ($_POST['role'] ?? 'support');

        if ($name === '') {
            throw new Refused('Enter a name');
        }

        if (!isset(Access::ROLES[$role])) {
            throw new Refused('Unknown role');
        }

        if (filter_var($email, FILTER_VALIDATE_EMAIL) === false) {
            throw new Refused('Enter a valid email address');
        }

        if (strlen($password) < self::MIN_PASSWORD) {
            throw new Refused(
                'Platform passwords must be at least ' . self::MIN_PASSWORD . ' characters',
            );
        }

        $taken = (int) Database::scalar(
            'SELECT COUNT(*) FROM super_admins WHERE email = :e',
            ['e' => $email],
        ) > 0;

        if ($taken) {
            throw new Refused('That email already belongs to an administrator');
        }

        $id = Database::insert('super_admins', [
            'name'          => $name,
            'email'         => $email,
            'role'          => $role,
            'password_hash' => password_hash($password, PASSWORD_DEFAULT),
            'created_by'    => (int) $me['id'],
        ]);

        PlatformAudit::log('platform_admin_created', null, "$email ($role)");

        Flash::success(sprintf(
            '%s can now sign in as %s. Hand them the password in person.',
            $name,
            Access::ROLES[$role],
        ));
        Response::redirect('/admins');
    }

    /**
     * Switches one off, or back on.
     *
     * Never a delete. Half the audit trail points at these rows, and a platform
     * whose history says "administrator 3" with nothing behind it is a history
     * that cannot be read.
     */
    public function setActive(array $params): void
    {
        Csrf::verify();

        $me = AdminAuth::require();
        $id = (int) $params['id'];
        $enable = ($_POST['active'] ?? '') === '1';

        $admin = Database::selectOne(
            'SELECT id, name, email, role, is_active FROM super_admins WHERE id = :id',
            ['id' => $id],
        );

        if ($admin === null) {
            Response::notFound();
        }

        if (!$enable) {
            // Three ways to lock the platform out of itself, all closed here.
            if ($id === (int) $me['id']) {
                throw new Refused('You cannot disable your own account');
            }

            if (self::activeCount() <= 1) {
                throw new Refused('Somebody has to be able to sign in — this is the last active administrator');
            }

            // Support and billing cannot add administrators, so without an
            // owner nobody could ever manage this page again.
            if ($admin['role'] === 'owner' && (int) $admin['is_active'] === 1 && self::activeOwners() <= 1) {
                throw new Refused('This is the last active owner. Make someone else an owner first.');
            }
        }

        Database::run(
            'UPDATE super_admins
                SET is_active = :active,
                    disabled_at = :disabled
              WHERE id = :id',
            [
                'active'   => $enable ? 1 : 0,
                'disabled' => $enable ? null : date('Y-m-d H:i:s'),
                'id'       => $id,
            ],
        );

        // A disabled account must not keep a live session, and must not be able
        // to finish a sign-in it had already started.
        if (!$enable) {
            Database::run(
                'DELETE FROM super_admin_challenges WHERE super_admin_id = :id',
                ['id' => $id],
            );
        }

        PlatformAudit::log(
            $enable ? 'platform_admin_enabled' : 'platform_admin_disabled',
            null,
            (string) $admin['email'],
        );

        Flash::success(sprintf(
            '%s is now %s.',
            (string) $admin['name'],
            $enable ? 'active' : 'disabled',
        ));

        Response::redirect('/admins');
    }

    // ------------------------------------------------------ second factor

    /**
     * Starts setting up an authenticator.
     *
     * The secret is stored unconfirmed. Until a code proves the phone actually
     * has it, nothing changes about signing in — otherwise a mistyped setup
     * would lock somebody out of the account they were trying to protect.
     */
    public function startTwoFactor(): void
    {
        Csrf::verify();

        $me = AdminAuth::require();

        if (self::twoFactorOn((int) $me['id'])) {
            throw new Refused('Two-factor is already on for this account');
        }

        $secret = Totp::generateSecret();

        Database::run(
            'UPDATE super_admins
                SET two_factor_secret = :s, two_factor_confirmed_at = NULL
              WHERE id = :id',
            ['s' => $secret, 'id' => (int) $me['id']],
        );

        Response::redirect('/security');
    }

    /** Proves the phone has it, and turns it on. */
    public function confirmTwoFactor(): void
    {
        Csrf::verify();

        $me = AdminAuth::require();

        $secret = (string) Database::scalar(
            'SELECT two_factor_secret FROM super_admins WHERE id = :id',
            ['id' => (int) $me['id']],
        );

        if ($secret === '') {
            throw new Refused('Start the setup first');
        }

        if (!Totp::verify($secret, trim((string) ($_POST['code'] ?? '')))) {
            throw new Refused('That code is not right. Check the clock on the phone.');
        }

        // The codes are generated here, shown once, and stored only as hashes.
        //
        // For a platform administrator these are not a convenience. One person
        // with a lost phone and no codes, and no second administrator, has shut
        // the whole platform out of itself with no way back except the database.
        $codes = Totp::generateRecoveryCodes();

        Database::transaction(function () use ($me, $codes): void {
            Database::run(
                'UPDATE super_admins SET two_factor_confirmed_at = NOW() WHERE id = :id',
                ['id' => (int) $me['id']],
            );

            Database::run(
                'DELETE FROM super_admin_recovery_codes WHERE super_admin_id = :id',
                ['id' => (int) $me['id']],
            );

            foreach ($codes as $code) {
                Database::insert('super_admin_recovery_codes', [
                    'super_admin_id' => (int) $me['id'],
                    'code_hash'      => hash('sha256', Totp::normaliseRecoveryCode($code)),
                ]);
            }
        });

        PlatformAudit::log('platform_2fa_enabled', null, (string) $me['email']);

        // Shown once, on the next page, and never again.
        $_SESSION['recovery_codes'] = $codes;

        Response::redirect('/security');
    }

    /** Turns it off. Password required — a borrowed session must not suffice. */
    public function disableTwoFactor(): void
    {
        Csrf::verify();

        $me = AdminAuth::require();

        $hash = (string) Database::scalar(
            'SELECT password_hash FROM super_admins WHERE id = :id',
            ['id' => (int) $me['id']],
        );

        if (!password_verify((string) ($_POST['password'] ?? ''), $hash)) {
            throw new Refused('That password is not correct');
        }

        Database::transaction(function () use ($me): void {
            Database::run(
                'UPDATE super_admins
                    SET two_factor_secret = NULL, two_factor_confirmed_at = NULL
                  WHERE id = :id',
                ['id' => (int) $me['id']],
            );

            Database::run(
                'DELETE FROM super_admin_recovery_codes WHERE super_admin_id = :id',
                ['id' => (int) $me['id']],
            );
        });

        PlatformAudit::log('platform_2fa_disabled', null, (string) $me['email']);

        Flash::success('Two-factor is off for your account.');
        Response::redirect('/security');
    }

    /** A fresh set, when the old ones have been used or lost. */
    public function regenerateCodes(): void
    {
        Csrf::verify();

        $me = AdminAuth::require();

        if (!self::twoFactorOn((int) $me['id'])) {
            throw new Refused('Turn two-factor on first');
        }

        $codes = Totp::generateRecoveryCodes();

        Database::transaction(function () use ($me, $codes): void {
            Database::run(
                'DELETE FROM super_admin_recovery_codes WHERE super_admin_id = :id',
                ['id' => (int) $me['id']],
            );

            foreach ($codes as $code) {
                Database::insert('super_admin_recovery_codes', [
                    'super_admin_id' => (int) $me['id'],
                    'code_hash'      => hash('sha256', Totp::normaliseRecoveryCode($code)),
                ]);
            }
        });

        PlatformAudit::log('platform_recovery_codes_regenerated', null, (string) $me['email']);

        $_SESSION['recovery_codes'] = $codes;
        Response::redirect('/security');
    }

    /** The signed-in administrator's own security page. */
    public function security(): void
    {
        $me = AdminAuth::require();

        $row = Database::selectOne(
            'SELECT two_factor_secret, two_factor_confirmed_at, email
               FROM super_admins WHERE id = :id',
            ['id' => (int) $me['id']],
        ) ?? [];

        // Handed over once, then gone from the session for good.
        $codes = $_SESSION['recovery_codes'] ?? null;
        unset($_SESSION['recovery_codes']);

        $secret = (string) ($row['two_factor_secret'] ?? '');
        $on = ($row['two_factor_confirmed_at'] ?? null) !== null;

        View::page('security', [
            'title'      => 'Security',
            'nav'        => 'security',
            'on'         => $on,
            'pending'    => !$on && $secret !== '',
            'secret'     => $secret,
            'uri'        => $secret === '' ? '' : Totp::provisioningUri(
                $secret,
                (string) ($row['email'] ?? ''),
                'DACAAM Platform',
            ),
            'codes'      => $codes,
            'codes_left' => (int) Database::scalar(
                'SELECT COUNT(*) FROM super_admin_recovery_codes
                  WHERE super_admin_id = :id AND used_at IS NULL',
                ['id' => (int) $me['id']],
            ),
        ]);
    }

    private static function twoFactorOn(int $id): bool
    {
        return Database::scalar(
            'SELECT two_factor_confirmed_at FROM super_admins WHERE id = :id',
            ['id' => $id],
        ) !== null;
    }

    private static function activeCount(): int
    {
        return (int) Database::scalar('SELECT COUNT(*) FROM super_admins WHERE is_active = 1');
    }

    private static function activeOwners(): int
    {
        return (int) Database::scalar(
            'SELECT COUNT(*) FROM super_admins WHERE is_active = 1 AND role = "owner"',
        );
    }
}
