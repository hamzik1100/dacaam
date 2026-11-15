<?php

declare(strict_types=1);

namespace Dacaam\Support;

use Dacaam\Core\AuthContext;
use Dacaam\Core\Database;
use Dacaam\Core\Mailer;
use Throwable;

/**
 * Email alerts for the restaurant's owner.
 *
 * The owner is not standing at the till. Money moves, staff are added, prices
 * change, and the first they hear of it is when the day's takings do not add
 * up — by which point the audit trail can say what happened but nobody was told
 * while it was happening.
 *
 * Driven off the audit trail rather than sprinkled through the controllers.
 * Every action worth alerting on already writes an audit row, so hooking the
 * one place means a new audited action cannot quietly ship without being
 * considered here. Scattering `Mailer::send()` calls through twenty controllers
 * is how half of them end up forgotten.
 *
 * Nothing is sent inline. Alerts are queued and drained separately, because an
 * SMTP server that has gone slow must never be able to hold up a sale.
 */
final class Alerts
{
    /**
     * What each audited action is, and how loudly it should be reported.
     *
     * Four groups, because that is roughly how an owner thinks about them:
     * money leaving, someone getting access, the day's orders, and the menu.
     * Anything not listed is not alerted on at all — a trail worth reading is
     * one that leaves things out.
     */
    private const GROUPS = [
        // ---- money ----------------------------------------------------
        // An order voided after it was paid means cash left the till. A
        // balance adjusted by hand is money invented or erased outright.
        'orders.order_status_changed'   => 'money',
        'orders.order_refunded'         => 'money',
        'orders.order_put_on_account'   => 'money',
        'orders.order_from_wallet'      => 'money',
        // A balance moved by hand, with no order behind it, is money invented
        // or erased. This is the single most abusable action in the system.
        'customers.customer_adjustment' => 'money',
        'customers.customer_deactivated' => 'money',
        // Raising a credit limit is how a debt grows past what anyone agreed
        // to, so the edit is reported even though it moves no cash today.
        'customers.customer_updated'    => 'money',
        'accounts.transfer'             => 'money',
        'accounts.account_created'      => 'money',
        'expenses.expense_created'      => 'money',
        'drafts.draft_cancelled'        => 'money',
        // The variance, not the close. Every till closes every evening and
        // most of them balance; mailing all of those trains the owner to
        // ignore the sender, and then the short one arrives into a folder
        // nobody opens. Only the ones that did not balance are sent.
        'shifts.shift_variance'         => 'money',

        // ---- security -------------------------------------------------
        // Access, not cash. A new user or a disabled second factor is how a
        // till gets quietly opened to somebody who should not have it.
        'security.password_changed'     => 'security',
        'users.password_changed'        => 'security',
        'security.two_factor_disabled'  => 'security',
        'security.recovery_codes_regenerated' => 'security',
        'users.user_created'            => 'security',
        'users.user_deactivated'        => 'security',
        'users.role_created'            => 'security',
        'users.role_deleted'            => 'security',
        'settings.smtp_updated'         => 'security',

        // ---- orders ---------------------------------------------------
        // High volume by nature. Summarised daily unless the owner asks for
        // more; instant delivery here is what turns the whole feature into
        // something nobody reads.
        'orders.item_added'             => 'orders',
        'orders.item_removed'           => 'orders',
        'orders.quantity_changed'       => 'orders',
        'orders.order_total_changed'    => 'orders',
        'orders.payment_added'          => 'orders',
        'customers.customer_created'    => 'orders',
        'customers.customer_payment'    => 'orders',
        'customers.customer_deposit'    => 'orders',
        'drafts.draft_updated'          => 'orders',

        // ---- menu -----------------------------------------------------
        // A quietly lowered price is an old way to skim, so it is reported —
        // but as part of the day's summary, not one email per edit.
        'menu.menu_item_updated'        => 'menu',
        'menu.menu_item_created'        => 'menu',
        'menu.menu_item_deleted'        => 'menu',
        'menu.category_deleted'         => 'menu',
    ];

    /** Actions that are only worth an alert when the value says so. */
    private const CONDITIONAL = [
        // Every status move writes this row; only the destructive one matters.
        'orders.order_status_changed' => 'cancelled',
    ];

    /** Stops one runaway loop from mailing a thousand times. */
    private const MAX_PER_HOUR = 60;

    /**
     * Considers one audited action for an alert.
     *
     * Called from Audit::log inside whatever transaction the action is running
     * in, deliberately: an edit that rolls back takes its alert with it, and an
     * owner is never told about something that did not happen.
     */
    public static function record(
        AuthContext $context,
        string $module,
        string $action,
        ?int $recordId,
        string $field,
        ?string $oldValue,
        ?string $newValue,
        ?string $reason,
    ): void {
        // Never let alerting break the thing it is watching. A malformed
        // address or a missing column must not roll back a sale.
        try {
            $key = "$module.$action";
            $group = self::GROUPS[$key] ?? null;

            if ($group === null) {
                return;
            }

            if (isset(self::CONDITIONAL[$key])
                && (string) $newValue !== self::CONDITIONAL[$key]
            ) {
                return;
            }

            $settings = self::settings($context->restaurantId);
            $mode = (string) ($settings['alerts_' . $group] ?? 'off');

            // Digest events are read back out of audit_logs at the end of the
            // day, so there is nothing to queue for them here.
            if ($mode !== 'instant') {
                return;
            }

            $recipients = self::recipients($context->restaurantId, $settings);

            if ($recipients === []) {
                return;
            }

            if (self::sentThisHour($context->restaurantId) >= self::MAX_PER_HOUR) {
                return;
            }

            $subject = self::subject($group, $key, $context);
            $body = self::body($context, $key, $recordId, $field, $oldValue, $newValue, $reason);

            foreach ($recipients as $email) {
                Database::insert('email_outbox', [
                    'restaurant_id' => $context->restaurantId,
                    'to_email'      => $email,
                    'subject'       => $subject,
                    'body'          => $body,
                    'event_key'     => $key,
                    'record_id'     => $recordId,
                ]);
            }
        } catch (Throwable $e) {
            error_log('[dacaam] alert not queued: ' . $e->getMessage());
        }
    }

    /**
     * Sends what is waiting.
     *
     * @param  int $limit How many to attempt in this pass.
     * @return array{sent:int,failed:int}
     */
    public static function drain(int $limit = 20): array
    {
        if (!Mailer::isConfigured()) {
            return ['sent' => 0, 'failed' => 0];
        }

        $sent = 0;
        $failed = 0;

        for ($i = 0; $i < $limit; $i++) {
            $row = self::claim();

            if ($row === null) {
                break;
            }

            try {
                $ok = Mailer::send(
                    (string) $row['to_email'],
                    (string) $row['subject'],
                    (string) $row['body'],
                );
            } catch (Throwable $e) {
                $ok = false;
                $error = $e->getMessage();
            }

            if ($ok) {
                Database::run(
                    'UPDATE email_outbox SET sent_at = NOW(), last_error = NULL WHERE id = :id',
                    ['id' => $row['id']],
                );
                $sent++;
                continue;
            }

            // Released, not deleted. Four attempts and it stops being retried,
            // but the row stays so the dashboard can show that it never went —
            // a queue that silently discards is worse than no queue.
            Database::run(
                'UPDATE email_outbox
                    SET claimed_at = NULL, attempts = attempts + 1, last_error = :e
                  WHERE id = :id',
                [
                    'id' => $row['id'],
                    'e'  => substr($error ?? 'SMTP rejected the message', 0, 255),
                ],
            );
            $failed++;
        }

        return ['sent' => $sent, 'failed' => $failed];
    }

    /**
     * Takes one pending message, or null.
     *
     * The conditional UPDATE is the lock. Two workers running at once cannot
     * both claim the same row, because the second one's WHERE no longer
     * matches — no table lock, no advisory lock, no double-send.
     *
     * @return array<string,mixed>|null
     */
    private static function claim(): ?array
    {
        $id = Database::scalar(
            'SELECT id FROM email_outbox
              WHERE sent_at IS NULL
                AND attempts < 4
                AND (claimed_at IS NULL OR claimed_at < DATE_SUB(NOW(), INTERVAL 5 MINUTE))
              ORDER BY id ASC LIMIT 1',
        );

        if ($id === null) {
            return null;
        }

        $claimed = Database::run(
            'UPDATE email_outbox SET claimed_at = NOW()
              WHERE id = :id
                AND sent_at IS NULL
                AND (claimed_at IS NULL OR claimed_at < DATE_SUB(NOW(), INTERVAL 5 MINUTE))',
            ['id' => $id],
        );

        if ($claimed->rowCount() === 0) {
            return null;
        }

        return Database::selectOne('SELECT * FROM email_outbox WHERE id = :id', ['id' => $id]);
    }

    /**
     * Who hears about it.
     *
     * The restaurant's own administrators, plus whatever address the settings
     * name. An owner who does not read email at the till can point this at a
     * phone they do read.
     *
     * @param  array<string,mixed> $settings
     * @return list<string>
     */
    private static function recipients(int $restaurantId, array $settings): array
    {
        if (isset(self::$recipientCache[$restaurantId])) {
            return self::$recipientCache[$restaurantId];
        }

        $rows = Database::select(
            'SELECT DISTINCT u.email
               FROM users u
               JOIN user_roles ur ON ur.user_id = u.id
               JOIN roles r ON r.id = ur.role_id
              WHERE u.restaurant_id = :rid
                AND u.is_active = 1
                AND u.email IS NOT NULL AND u.email <> ""
                AND r.code = "admin"',
            ['rid' => $restaurantId],
        );

        $emails = array_column($rows, 'email');

        $extra = trim((string) ($settings['alert_email'] ?? ''));
        if ($extra !== '' && filter_var($extra, FILTER_VALIDATE_EMAIL) !== false) {
            $emails[] = $extra;
        }

        return self::$recipientCache[$restaurantId] = array_values(array_unique(array_filter(
            $emails,
            static fn ($e): bool => filter_var((string) $e, FILTER_VALIDATE_EMAIL) !== false,
        )));
    }

    /**
     * @var array<int,array<string,mixed>>
     *
     * One edit writes five audit rows and every one of them would otherwise
     * re-read the same settings and the same recipient list. Held for the life
     * of the request only, so a settings change still takes effect on the next
     * one.
     */
    private static array $settingsCache = [];

    /** @var array<int,list<string>> */
    private static array $recipientCache = [];

    /** Drops the caches. Tests change settings mid-request; nothing else does. */
    public static function forget(): void
    {
        self::$settingsCache = [];
        self::$recipientCache = [];
    }

    /** @return array<string,mixed> */
    private static function settings(int $restaurantId): array
    {
        if (isset(self::$settingsCache[$restaurantId])) {
            return self::$settingsCache[$restaurantId];
        }

        return self::$settingsCache[$restaurantId] = Database::selectOne(
            'SELECT alert_email, alerts_money, alerts_security, alerts_orders, alerts_menu
               FROM restaurant_settings WHERE restaurant_id = :rid',
            ['rid' => $restaurantId],
        ) ?? [];
    }

    private static function sentThisHour(int $restaurantId): int
    {
        return (int) Database::scalar(
            'SELECT COUNT(*) FROM email_outbox
              WHERE restaurant_id = :rid AND created_at > DATE_SUB(NOW(), INTERVAL 1 HOUR)',
            ['rid' => $restaurantId],
        );
    }

    private static function subject(string $group, string $key, AuthContext $context): string
    {
        $headline = self::LABELS[$key] ?? $key;
        $urgent = in_array($group, ['money', 'security'], true) ? 'DEG-DEG: ' : '';

        return sprintf('%s%s — %s', $urgent, $headline, $context->restaurantSlug);
    }

    /** Somali labels, because that is who reads them. */
    private const LABELS = [
        'orders.order_status_changed'   => 'Dalab la joojiyay',
        'orders.order_refunded'         => 'Lacag la celiyay',
        'orders.order_put_on_account'   => 'Dalab dayn lagu qoray',
        'orders.order_from_wallet'      => 'Jeeb laga qaaday',
        'customers.customer_adjustment' => 'Xisaab macmiil gacan lagu beddelay',
        'customers.customer_updated'    => 'Macmiil la beddelay (xadka daynta)',
        'customers.customer_deactivated' => 'Macmiil la xidhay',
        'accounts.transfer'             => 'Lacag miis kale loo wareejiyay',
        'accounts.account_created'      => 'Sanduuq cusub',
        'expenses.expense_created'      => 'Kharash cusub',
        'drafts.draft_cancelled'        => 'Draft la joojiyay',
        'shifts.shift_variance'         => 'Sanduuqa lacagtiisu ma dhamaystirna',
        'security.password_changed'     => 'Password la beddelay',
        'users.password_changed'        => 'Password shaqaale la beddelay',
        'security.two_factor_disabled'  => 'Labo-tallaabo la damiyay',
        'security.recovery_codes_regenerated' => 'Codes-ka gargaarka dib loo sameeyay',
        'users.user_created'            => 'Shaqaale cusub',
        'users.user_deactivated'        => 'Shaqaale la xidhay',
        'users.role_created'            => 'Door cusub',
        'users.role_deleted'            => 'Door la tirtiray',
        'settings.smtp_updated'         => 'Habaynta emailka la beddelay',
    ];

    private static function body(
        AuthContext $context,
        string $key,
        ?int $recordId,
        string $field,
        ?string $oldValue,
        ?string $newValue,
        ?string $reason,
    ): string {
        $lines = [];
        $lines[] = self::LABELS[$key] ?? $key;
        $lines[] = str_repeat('-', 44);
        $lines[] = 'Makhaayad : ' . ($context->restaurantSlug);
        $lines[] = 'Qofka     : ' . $context->userName;
        $lines[] = 'Waqtiga   : ' . date('Y-m-d H:i');

        if ($recordId !== null) {
            $lines[] = 'Lambarka  : #' . $recordId;
        }

        if ($field !== '') {
            $lines[] = 'Goobta    : ' . $field;
        }

        if ($oldValue !== null || $newValue !== null) {
            $lines[] = 'Hore      : ' . ($oldValue ?? '-');
            $lines[] = 'Hadda     : ' . ($newValue ?? '-');
        }

        if ($reason !== null && $reason !== '') {
            $lines[] = 'Sababta   : ' . $reason;
        }

        $lines[] = '';
        $lines[] = 'IP: ' . $context->ip;
        $lines[] = '';
        $lines[] = 'Haddii aanad tan aqoonsan, isla markiiba password-ka beddel.';

        return implode("\n", $lines);
    }
}
