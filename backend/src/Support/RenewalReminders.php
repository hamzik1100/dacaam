<?php

declare(strict_types=1);

namespace Dacaam\Support;

use Dacaam\Core\Database;
use Throwable;

/**
 * Tells a restaurant its subscription is about to end — before it does.
 *
 * Without this the first a restaurant hears of it is the till refusing to take
 * an order, which is the worst possible moment: a customer waiting, and the
 * person who can pay nowhere near. A week's notice and a day's notice turn
 * that into a phone call on a quiet afternoon.
 *
 * Three stages: seven days out, one day out, and once after it has ended. Only
 * the most urgent stage that applies is sent, so a restaurant provisioned with
 * two days left gets one message rather than a week's worth at once. Each
 * stage is written to `subscription_reminders` before anything goes out, and
 * the unique key on it is what makes a second run — the cron and the button on
 * the same morning — a no-op.
 *
 * Only the restaurant's admins are told. The waiters cannot pay the bill and
 * do not need the message on their handsets.
 */
final class RenewalReminders
{
    /** Days before the end date. -1 is the notice that it has ended. */
    public const STAGES = [7, 1];

    public const ENDED = -1;

    /** How long after the end the "it has ended" notice is still worth sending. */
    private const ENDED_WINDOW_DAYS = 7;

    /**
     * Subscriptions with a reminder waiting, most urgent first.
     *
     * @return list<array<string,mixed>>
     */
    public static function due(): array
    {
        $rows = Database::select(
            'SELECT s.id AS subscription_id, s.restaurant_id, s.plan, s.status,
                    s.ends_on, DATEDIFF(s.ends_on, CURDATE()) AS days_left,
                    r.name, r.slug
               FROM subscriptions s
               JOIN restaurants r ON r.id = s.restaurant_id
              WHERE s.status IN ("active", "trial", "expired")
                AND r.status NOT IN ("suspended", "archived")
                AND DATEDIFF(s.ends_on, CURDATE()) BETWEEN :from AND :to
              ORDER BY s.ends_on ASC',
            ['from' => -self::ENDED_WINDOW_DAYS, 'to' => max(self::STAGES)],
        );

        $due = [];

        foreach ($rows as $row) {
            $stage = self::stageFor((int) $row['days_left']);
            if ($stage === null) {
                continue;
            }

            $sent = Database::scalar(
                'SELECT 1 FROM subscription_reminders
                  WHERE subscription_id = :sid AND ends_on = :ends AND stage = :stage',
                ['sid' => $row['subscription_id'], 'ends' => $row['ends_on'], 'stage' => $stage],
            );

            if ($sent === false) {
                $row['stage'] = $stage;
                $due[] = $row;
            }
        }

        return $due;
    }

    /**
     * Sends every reminder that is due.
     *
     * @return array{restaurants:int,notified:int,pushed:int,emailed:int,sent:list<string>}
     */
    public static function send(): array
    {
        $summary = ['restaurants' => 0, 'notified' => 0, 'pushed' => 0, 'emailed' => 0, 'sent' => []];

        foreach (self::due() as $row) {
            // Claimed first. If another run got here in the meantime the insert
            // is ignored, and this one sends nothing.
            $claimed = Database::run(
                'INSERT IGNORE INTO subscription_reminders
                    (subscription_id, restaurant_id, ends_on, stage)
                 VALUES (:sid, :rid, :ends, :stage)',
                [
                    'sid'   => $row['subscription_id'],
                    'rid'   => $row['restaurant_id'],
                    'ends'  => $row['ends_on'],
                    'stage' => $row['stage'],
                ],
            )->rowCount();

            if ($claimed === 0) {
                continue;
            }

            [$title, $body] = self::message($row);
            $kind = match ((int) $row['stage']) {
                self::ENDED => 'urgent',
                1           => 'warning',
                default     => 'info',
            };

            $admins = Database::select(
                'SELECT DISTINCT u.id, u.email
                   FROM users u
                   JOIN user_roles ur ON ur.user_id = u.id
                   JOIN roles ro ON ro.id = ur.role_id
                  WHERE u.restaurant_id = :rid AND u.is_active = 1 AND ro.code = "admin"',
                ['rid' => $row['restaurant_id']],
            );

            foreach ($admins as $admin) {
                Database::insert('notifications', [
                    'restaurant_id' => (int) $row['restaurant_id'],
                    'user_id'       => (int) $admin['id'],
                    'title'         => $title,
                    'body'          => $body,
                    'kind'          => $kind,
                ]);
            }

            $pushed = 0;
            $ids = array_map(static fn (array $a): int => (int) $a['id'], $admins);

            if ($ids !== []) {
                $tokens = array_column(
                    Database::select(
                        sprintf(
                            'SELECT token FROM device_tokens WHERE user_id IN (%s)',
                            implode(',', $ids),
                        ),
                    ),
                    'token',
                );

                try {
                    $pushed = Push::send($tokens, $title, $body, ['kind' => $kind]);
                } catch (Throwable $e) {
                    // The notification is saved; the app shows it on next open.
                    error_log('[dacaam] renewal push: ' . $e->getMessage());
                }
            }

            $emailed = 0;
            foreach (self::emailsFor((int) $row['restaurant_id'], $admins) as $email) {
                Database::insert('email_outbox', [
                    'restaurant_id' => (int) $row['restaurant_id'],
                    'to_email'      => $email,
                    'subject'       => $title . ' — ' . $row['name'],
                    'body'          => self::emailBody($row, $body),
                    'event_key'     => 'subscription.reminder',
                    'record_id'     => (int) $row['subscription_id'],
                ]);
                $emailed++;
            }

            Database::run(
                'UPDATE subscription_reminders SET pushed = :p, emailed = :e
                  WHERE subscription_id = :sid AND ends_on = :ends AND stage = :stage',
                [
                    'p'     => $pushed,
                    'e'     => $emailed,
                    'sid'   => $row['subscription_id'],
                    'ends'  => $row['ends_on'],
                    'stage' => $row['stage'],
                ],
            );

            $summary['restaurants']++;
            $summary['notified'] += count($admins);
            $summary['pushed'] += $pushed;
            $summary['emailed'] += $emailed;
            $summary['sent'][] = sprintf('%s (%s)', $row['slug'], self::stageLabel((int) $row['stage']));
        }

        return $summary;
    }

    /** The most urgent stage that applies, or null when none does yet. */
    public static function stageFor(int $daysLeft): ?int
    {
        if ($daysLeft < 0) {
            return $daysLeft >= -self::ENDED_WINDOW_DAYS ? self::ENDED : null;
        }

        $stages = self::STAGES;
        sort($stages);

        foreach ($stages as $stage) {
            if ($daysLeft <= $stage) {
                return $stage;
            }
        }

        return null;
    }

    public static function stageLabel(int $stage): string
    {
        return $stage === self::ENDED ? 'ended' : $stage . ' day' . ($stage === 1 ? '' : 's');
    }

    /**
     * Title and body, in Somali — the language the app opens in.
     *
     * @param  array<string,mixed> $row
     * @return array{0:string,1:string}
     */
    private static function message(array $row): array
    {
        $days = (int) $row['days_left'];
        $date = date('d/m/Y', (int) strtotime((string) $row['ends_on']));
        $name = (string) $row['name'];
        $trial = (string) $row['status'] === 'trial';

        if ((int) $row['stage'] === self::ENDED) {
            return [
                'Adeeggu wuu dhacay',
                sprintf(
                    'Ishtiraakka %s wuxuu dhacay %s. Xogtaadu way badbaadsan tahay, '
                    . 'laakiin wax cusub lama gelin karo ilaa la cusboonaysiiyo. '
                    . 'Fadlan la xiriir DACAAM.',
                    $name,
                    $date,
                ),
            ];
        }

        $when = match ($days) {
            0       => 'maanta',
            1       => 'berri',
            default => $days . ' maalmood kadib',
        };

        return $trial
            ? [
                'Tijaabadu waxay dhammaanaysaa ' . $when,
                sprintf(
                    'Muddada tijaabada ee %s waxay dhammaanaysaa %s. '
                    . 'La xiriir DACAAM si aad u sii wadato.',
                    $name,
                    $date,
                ),
            ]
            : [
                'Ishtiraakku wuxuu dhacayaa ' . $when,
                sprintf(
                    'Ishtiraakka %s wuxuu dhacayaa %s. '
                    . 'Fadlan bixi si adeeggu u sii socdo.',
                    $name,
                    $date,
                ),
            ];
    }

    /** @param array<string,mixed> $row */
    private static function emailBody(array $row, string $somali): string
    {
        $days = (int) $row['days_left'];
        $english = (int) $row['stage'] === self::ENDED
            ? sprintf(
                'The DACAAM subscription for %s ended on %s. Your data is safe, but nothing '
                . 'new can be recorded until it is renewed.',
                $row['name'],
                $row['ends_on'],
            )
            : sprintf(
                'The DACAAM %s for %s ends on %s (%s). Please renew to keep the till running.',
                (string) $row['status'] === 'trial' ? 'trial' : 'subscription',
                $row['name'],
                $row['ends_on'],
                $days === 0 ? 'today' : ($days === 1 ? 'tomorrow' : "in $days days"),
            );

        return $somali . "\n\n" . $english . "\n\n— DACAAM";
    }

    /**
     * The admins' own addresses, plus the restaurant's alert address.
     *
     * @param  list<array<string,mixed>> $admins
     * @return list<string>
     */
    private static function emailsFor(int $restaurantId, array $admins): array
    {
        $emails = array_column($admins, 'email');

        try {
            $emails[] = (string) Database::scalar(
                'SELECT alert_email FROM restaurant_settings WHERE restaurant_id = :rid',
                ['rid' => $restaurantId],
            );
        } catch (Throwable) {
            // Older schema without alert settings: the admins alone will do.
        }

        return array_values(array_unique(array_filter(
            array_map(static fn ($e): string => strtolower(trim((string) $e)), $emails),
            static fn (string $e): bool => filter_var($e, FILTER_VALIDATE_EMAIL) !== false,
        )));
    }
}
