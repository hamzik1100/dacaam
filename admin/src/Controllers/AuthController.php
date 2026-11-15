<?php

declare(strict_types=1);

namespace DacaamAdmin\Controllers;

use Dacaam\Core\Database;
use DacaamAdmin\Core\AdminAuth;
use DacaamAdmin\Core\Flash;
use DacaamAdmin\Core\PlatformAudit;
use DacaamAdmin\Core\Refused;
use DacaamAdmin\Core\Response;
use DacaamAdmin\Core\View;
use RuntimeException;

final class AuthController
{
    private const MIN_PASSWORD = 10;

    public function showLogin(): void
    {
        if (AdminAuth::check()) {
            Response::redirect('/');
        }

        // A fresh install has nobody who can sign in. The seed file that
        // creates a demo administrator is deliberately kept off production
        // servers — every password in it is `admin123` — so the first one has
        // to be created here instead.
        if (!self::hasAnyAdministrator()) {
            Response::redirect('/setup');
        }

        View::render('login', [
            'title' => 'Sign in',
            'flash' => Flash::pull(),
        ]);
    }

    public function showSetup(): void
    {
        self::assertSetupIsOpen();

        View::render('setup', [
            'title' => 'Create the first administrator',
            'flash' => Flash::pull(),
            'min'   => self::MIN_PASSWORD,
        ]);
    }

    public function setup(): void
    {
        self::assertSetupIsOpen();

        $name = trim((string) ($_POST['name'] ?? ''));
        $email = strtolower(trim((string) ($_POST['email'] ?? '')));
        $password = (string) ($_POST['password'] ?? '');
        $confirm = (string) ($_POST['confirm_password'] ?? '');

        if ($name === '') {
            throw new Refused('Enter a name');
        }
        if (filter_var($email, FILTER_VALIDATE_EMAIL) === false) {
            throw new Refused('Enter a valid email address');
        }
        if (strlen($password) < self::MIN_PASSWORD) {
            throw new Refused(
                'Platform passwords must be at least ' . self::MIN_PASSWORD . ' characters',
            );
        }
        if ($password !== $confirm) {
            throw new Refused('The two passwords do not match');
        }

        // Re-checked inside the write. Two people opening the setup page at
        // once would otherwise both pass the guard above and both become
        // administrators, which is exactly the situation this page exists to
        // prevent from happening by accident.
        Database::transaction(static function () use ($name, $email, $password): void {
            if ((int) Database::scalar('SELECT COUNT(*) FROM super_admins FOR UPDATE') > 0) {
                throw new Refused('An administrator already exists. Sign in instead.');
            }

            Database::insert('super_admins', [
                'name'          => $name,
                'email'         => $email,
                'password_hash' => password_hash($password, PASSWORD_BCRYPT, ['cost' => 12]),
                'is_active'     => 1,
            ]);
        });

        PlatformAudit::log('platform_installed', detail: $email);

        Flash::success('Administrator created. Sign in to continue.');
        Response::redirect('/login');
    }

    /**
     * Setup is open only while there is nobody to sign in as.
     *
     * That is the whole access control on this page, and it has to be: there
     * is no credential to check before the first credential exists. Once one
     * administrator exists the route is closed permanently.
     */
    private static function assertSetupIsOpen(): void
    {
        if (self::hasAnyAdministrator()) {
            Response::redirect('/login');
        }
    }

    private static function hasAnyAdministrator(): bool
    {
        return (int) Database::scalar('SELECT COUNT(*) FROM super_admins') > 0;
    }

    public function login(): void
    {
        $result = AdminAuth::attempt(
            (string) ($_POST['email'] ?? ''),
            (string) ($_POST['password'] ?? ''),
            (string) ($_SERVER['REMOTE_ADDR'] ?? ''),
        );

        // Right password, second factor on: nothing is signed in yet. The
        // challenge token goes into the session because it is the one thing
        // linking this browser to the half-finished sign-in — the token itself
        // is never in a URL, where it would end up in a log or a bookmark.
        if (isset($result['challenge'])) {
            $_SESSION['admin_challenge'] = $result['challenge'];

            Response::redirect('/login/code');
        }

        if (!$result['ok']) {
            Flash::error($result['error'] ?? 'Sign in failed');
            Response::redirect('/login');
        }

        Response::redirect('/');
    }

    /** The second step: the code from the authenticator, or a recovery code. */
    public function challenge(): void
    {
        if (!isset($_SESSION['admin_challenge'])) {
            Response::redirect('/login');
        }

        View::render('login_code', ['flash' => Flash::pull()]);
    }

    public function verifyChallenge(): void
    {
        $token = (string) ($_SESSION['admin_challenge'] ?? '');

        if ($token === '') {
            Response::redirect('/login');
        }

        $result = AdminAuth::verifyChallenge(
            $token,
            (string) ($_POST['code'] ?? ''),
            (string) ($_SERVER['REMOTE_ADDR'] ?? ''),
        );

        if (!$result['ok']) {
            Flash::error($result['error'] ?? 'That code is not right');

            // A spent or expired challenge sends them back to the start rather
            // than to a code box that can no longer accept anything.
            if (str_contains((string) $result['error'], 'again')) {
                unset($_SESSION['admin_challenge']);
                Response::redirect('/login');
            }

            Response::redirect('/login/code');
        }

        unset($_SESSION['admin_challenge']);
        Response::redirect('/');
    }

    public function logout(): void
    {
        PlatformAudit::log('logout');
        AdminAuth::logout();
        Response::redirect('/login');
    }

    public function changePassword(): void
    {
        $admin = AdminAuth::require();

        $current = (string) ($_POST['current_password'] ?? '');
        $next = (string) ($_POST['new_password'] ?? '');
        $confirm = (string) ($_POST['confirm_password'] ?? '');

        $hash = (string) Database::scalar(
            'SELECT password_hash FROM super_admins WHERE id = :id',
            ['id' => $admin['id']],
        );

        if (!password_verify($current, $hash)) {
            throw new Refused('Current password is not correct');
        }
        if (strlen($next) < 8) {
            throw new Refused('Platform passwords must be at least 8 characters');
        }
        if ($next !== $confirm) {
            throw new Refused('New passwords do not match');
        }

        Database::run(
            'UPDATE super_admins SET password_hash = :hash WHERE id = :id',
            [
                'hash' => password_hash($next, PASSWORD_BCRYPT, ['cost' => 12]),
                'id'   => $admin['id'],
            ],
        );

        // A password change invalidates the old session's assumptions.
        session_regenerate_id(true);

        PlatformAudit::log('platform_password_changed');
        Flash::success('Password changed.');
        Response::redirect('/settings');
    }
}
