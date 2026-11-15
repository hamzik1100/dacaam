<?php

declare(strict_types=1);

namespace DacaamAdmin\Controllers;

use Dacaam\Core\Database;
use Dacaam\Core\Mailer;
use Dacaam\Support\AppVersion;
use DacaamAdmin\Core\Csv;
use DacaamAdmin\Core\Flash;
use DacaamAdmin\Core\PlatformAudit;
use DacaamAdmin\Core\Refused;
use DacaamAdmin\Core\Response;
use DacaamAdmin\Core\View;
use RuntimeException;

/** Global reports, the platform audit trail, and system settings. */
final class PlatformController
{
    public function reports(): void
    {
        $days = max(1, min(365, (int) ($_GET['days'] ?? 30)));

        $totals = Database::selectOne(
            'SELECT
                COUNT(*) AS orders,
                COALESCE(SUM(total), 0) AS sales,
                COALESCE(AVG(total), 0) AS avg_order
               FROM orders
              WHERE status <> "cancelled"
                AND created_at >= DATE_SUB(NOW(), INTERVAL :days DAY)',
            ['days' => $days],
        ) ?? [];

        $daily = Database::select(
            'SELECT DATE(created_at) AS d, COALESCE(SUM(total), 0) AS total
               FROM orders
              WHERE status <> "cancelled"
                AND created_at >= DATE_SUB(NOW(), INTERVAL :days DAY)
              GROUP BY DATE(created_at)
              ORDER BY d ASC',
            ['days' => $days],
        );

        $byRestaurant = Database::select(
            'SELECT r.id, r.name, r.slug, r.status,
                    COUNT(o.id) AS orders,
                    COALESCE(SUM(o.total), 0) AS sales
               FROM restaurants r
          LEFT JOIN orders o ON o.restaurant_id = r.id
                            AND o.status <> "cancelled"
                            AND o.created_at >= DATE_SUB(NOW(), INTERVAL :days DAY)
              GROUP BY r.id, r.name, r.slug, r.status
              ORDER BY sales DESC',
            ['days' => $days],
        );

        $growth = Database::select(
            'SELECT DATE_FORMAT(created_at, "%Y-%m") AS month, COUNT(*) AS added
               FROM restaurants
              GROUP BY month ORDER BY month DESC LIMIT 12',
        );

        if (($_GET['format'] ?? '') === 'csv') {
            PlatformAudit::log('csv_exported', detail: "reports ($days days)");

            Csv::download(
                Csv::filename("platform-volume-{$days}d"),
                ['Restaurant', 'Code', 'Status', 'Orders', 'Sales'],
                array_map(static fn (array $r): array => [
                    $r['name'], $r['slug'], $r['status'], $r['orders'], $r['sales'],
                ], $byRestaurant),
            );
        }

        View::page('reports', [
            'title'        => 'Global reports',
            'nav'          => 'reports',
            'days'         => $days,
            'totals'       => $totals,
            'daily'        => $daily,
            'byRestaurant' => $byRestaurant,
            'growth'       => $growth,
        ]);
    }

    public function audit(): void
    {
        $action = trim((string) ($_GET['action'] ?? ''));

        $where = ['1 = 1'];
        $bind = [];
        if ($action !== '') {
            $where[] = 'p.action = :action';
            $bind['action'] = $action;
        }

        $entries = Database::select(
            'SELECT p.*, r.name AS restaurant_name, r.slug
               FROM platform_audit_logs p
          LEFT JOIN restaurants r ON r.id = p.restaurant_id
              WHERE ' . implode(' AND ', $where) . '
              ORDER BY p.created_at DESC
              LIMIT 300',
            $bind,
        );

        $actions = array_column(
            Database::select(
                'SELECT DISTINCT action FROM platform_audit_logs ORDER BY action',
            ),
            'action',
        );

        View::page('audit', [
            'title'   => 'Platform audit',
            'nav'     => 'audit',
            'entries' => $entries,
            'actions' => $actions,
            'action'  => $action,
        ]);
    }

    public function settings(): void
    {
        $smtp = Mailer::config();

        // Everything that does not have its own form below.
        $system = Database::select(
            "SELECT key_name, value FROM system_settings
              WHERE key_name NOT LIKE 'smtp\_%'
                AND key_name NOT LIKE 'app\_%'
                AND key_name NOT LIKE 'invoice\_%'
              ORDER BY key_name",
        );

        $admins = Database::select(
            'SELECT id, name, email, is_active, last_login_at
               FROM super_admins ORDER BY id ASC',
        );

        View::page('settings', [
            'title'  => 'Settings',
            'nav'    => 'settings',
            'smtp'   => $smtp,
            'system' => $system,
            'admins' => $admins,
            'app'    => AppVersion::current(),
            'issuer' => InvoiceController::issuer(),
        ]);
    }

    /**
     * Which app the restaurants should be running.
     *
     * Below the minimum the app stops and points at the download; below the
     * latest it only says a newer one exists. Leaving both empty asks for
     * nothing, which is also the safe state to fall back to.
     */
    public function updateAppVersion(): void
    {
        $min = trim((string) ($_POST['min_version'] ?? ''));
        $latest = trim((string) ($_POST['latest_version'] ?? ''));
        $url = trim((string) ($_POST['download_url'] ?? ''));
        $message = trim((string) ($_POST['message'] ?? ''));

        foreach (['Minimum' => $min, 'Latest' => $latest] as $label => $version) {
            if ($version !== '' && !AppVersion::isValid($version)) {
                throw new Refused("$label version must look like 1.2.0");
            }
        }

        if ($min !== '' && $latest !== '' && AppVersion::compare($min, $latest) > 0) {
            throw new Refused('The minimum cannot be newer than the latest version');
        }

        // A minimum with nowhere to get the new app from locks every older
        // handset out with no way forward.
        if ($min !== '' && $url === '') {
            throw new Refused('Give a download link before setting a minimum version');
        }

        if ($url !== '' && (
            filter_var($url, FILTER_VALIDATE_URL) === false
            || !in_array(strtolower((string) parse_url($url, PHP_URL_SCHEME)), ['https', 'http'], true)
        )) {
            throw new Refused('The download link must be a web address starting with https://');
        }

        if (mb_strlen($message) > 300) {
            throw new Refused('Keep the message under 300 characters');
        }

        self::saveSettings([
            'app_min_version'    => $min,
            'app_latest_version' => $latest,
            'app_download_url'   => $url,
            'app_update_message' => $message,
        ]);

        PlatformAudit::log(
            'app_version_updated',
            detail: sprintf('min %s, latest %s', $min !== '' ? $min : '—', $latest !== '' ? $latest : '—'),
        );

        Flash::success('App version saved. Handsets pick it up the next time the app starts.');
        Response::redirect('/settings');
    }

    /** Who the invoices say they are from. */
    public function updateInvoiceDetails(): void
    {
        $values = [];

        foreach (array_keys(InvoiceController::SETTINGS) as $key) {
            $field = substr($key, strlen('invoice_'));
            $value = trim((string) ($_POST[$field] ?? ''));

            if (mb_strlen($value) > 255) {
                throw new Refused('Each invoice field is at most 255 characters');
            }

            $values[$key] = $value;
        }

        if ($values['invoice_business_email'] !== ''
            && filter_var($values['invoice_business_email'], FILTER_VALIDATE_EMAIL) === false
        ) {
            throw new Refused('The invoice email address is not valid');
        }

        self::saveSettings($values);

        PlatformAudit::log('invoice_details_updated', detail: $values['invoice_business_name']);

        Flash::success('Invoice details saved.');
        Response::redirect('/settings');
    }

    /** @param array<string,string> $values */
    private static function saveSettings(array $values): void
    {
        foreach ($values as $key => $value) {
            Database::run(
                'INSERT INTO system_settings (key_name, value) VALUES (:k, :v)
                 ON DUPLICATE KEY UPDATE value = :v2',
                ['k' => $key, 'v' => $value, 'v2' => $value],
            );
        }
    }

    public function updateSmtp(): void
    {
        $map = [
            'smtp_host'       => $_POST['host'] ?? '',
            'smtp_port'       => $_POST['port'] ?? '587',
            'smtp_encryption' => $_POST['encryption'] ?? 'tls',
            'smtp_username'   => $_POST['username'] ?? '',
            'smtp_from_email' => $_POST['from_email'] ?? '',
            'smtp_from_name'  => $_POST['from_name'] ?? 'DACAAM',
        ];

        // An empty password field means "leave it alone": the form never
        // receives the stored value, so it cannot send it back.
        if (($_POST['password'] ?? '') !== '') {
            $map['smtp_password'] = (string) $_POST['password'];
        }

        foreach ($map as $key => $value) {
            Database::run(
                'INSERT INTO system_settings (key_name, value) VALUES (:k, :v)
                 ON DUPLICATE KEY UPDATE value = :v2',
                ['k' => $key, 'v' => (string) $value, 'v2' => (string) $value],
            );
        }

        Mailer::forget();
        PlatformAudit::log('smtp_updated', detail: (string) $map['smtp_host']);

        Flash::success('Mail settings saved.');
        Response::redirect('/settings');
    }

    public function testSmtp(): void
    {
        $to = trim((string) ($_POST['to'] ?? ''));
        if ($to === '') {
            throw new Refused('Enter an address to send the test to');
        }
        if (!Mailer::isConfigured()) {
            throw new Refused('Set a host and a from-address first');
        }

        $sent = Mailer::send(
            $to,
            'DACAAM SMTP test',
            "This is a test message from the DACAAM platform.\n\n"
            . 'If you are reading it, mail delivery works.',
        );

        if (!$sent) {
            throw new RuntimeException(
                'The mail server rejected the message. Check the PHP error log.',
            );
        }

        PlatformAudit::log('smtp_test_sent', detail: $to);
        Flash::success('Test message sent to ' . $to);
        Response::redirect('/settings');
    }
}
