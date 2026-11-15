<?php

declare(strict_types=1);

namespace DacaamAdmin\Controllers;

use DacaamAdmin\Core\AdminAuth;
use DacaamAdmin\Core\Csrf;
use DacaamAdmin\Core\Flash;
use DacaamAdmin\Core\PlatformAudit;
use DacaamAdmin\Core\Response;
use DacaamAdmin\Core\View;
use Dacaam\Core\Database;
use Dacaam\Support\Push;

/**
 * Messages from the platform to the restaurants running it.
 *
 * Three audiences, one form: everybody, one restaurant, or one person.
 *
 * The message is written to `notifications` first and pushed second, in that
 * order deliberately. A push that fails is a notification the app still shows
 * on next open; a push that succeeded against nothing saved would be a message
 * that existed for four seconds and then never again.
 */
final class NotificationController
{
    public function index(): void
    {
        $sent = Database::select(
            'SELECT n.*, r.name AS restaurant_name, u.name AS user_name,
                    (SELECT COUNT(*) FROM notification_reads nr
                      WHERE nr.notification_id = n.id) AS `reads`
               FROM notifications n
          LEFT JOIN restaurants r ON r.id = n.restaurant_id
          LEFT JOIN users u       ON u.id = n.user_id
              ORDER BY n.created_at DESC, n.id DESC
              LIMIT 50',
        );

        View::page('notifications', [
            'title'       => 'Notifications',
            'nav'         => 'notifications',
            'sent'        => $sent,
            'restaurants' => Database::select('SELECT id, name FROM restaurants ORDER BY name ASC'),
            'staff'       => Database::select(
                'SELECT u.id, u.name, u.restaurant_id FROM users u
                  WHERE u.is_active = 1 ORDER BY u.name ASC',
            ),
            'configured'  => Push::isConfigured(),
            'devices'     => (int) Database::scalar('SELECT COUNT(*) FROM device_tokens'),
        ]);
    }

    public function send(): void
    {
        Csrf::verify();

        $title = trim((string) ($_POST['title'] ?? ''));
        $body = trim((string) ($_POST['body'] ?? ''));
        $kind = (string) ($_POST['kind'] ?? 'info');

        $restaurantId = ($_POST['restaurant_id'] ?? '') === ''
            ? null
            : (int) $_POST['restaurant_id'];
        $userId = ($_POST['user_id'] ?? '') === '' ? null : (int) $_POST['user_id'];

        if ($title === '' || $body === '') {
            Flash::error('A title and a message are both required.');
            Response::redirect('/notifications');
        }

        // A person belongs to a restaurant. Addressing one without the other
        // would save a message nobody can be shown, because the app matches on
        // both columns.
        if ($userId !== null && $restaurantId === null) {
            $restaurantId = (int) Database::scalar(
                'SELECT restaurant_id FROM users WHERE id = :id',
                ['id' => $userId],
            );
        }

        $id = Database::insert('notifications', [
            'restaurant_id' => $restaurantId,
            'user_id'       => $userId,
            'title'         => $title,
            'body'          => $body,
            'kind'          => in_array($kind, ['info', 'warning', 'urgent'], true) ? $kind : 'info',
            'sent_by'       => AdminAuth::current()['id'] ?? null,
        ]);

        $delivered = Push::send(
            self::tokensFor($restaurantId, $userId),
            $title,
            $body,
            ['notification_id' => $id, 'kind' => $kind],
        );

        PlatformAudit::log(
            'notification_sent',
            $restaurantId,
            sprintf(
                '%s -> %s (%d delivered)',
                $title,
                $userId !== null
                    ? "user $userId"
                    : ($restaurantId !== null ? "restaurant $restaurantId" : 'everyone'),
                $delivered,
            ),
        );

        Flash::success(sprintf(
            'Saved. %d handset%s reached now; everyone else sees it when they next open the app.',
            $delivered,
            $delivered === 1 ? '' : 's',
        ));

        Response::redirect('/notifications');
    }

    /**
     * Which handsets this message is for.
     *
     * A device row keeps its last known user even after they sign out, which is
     * what lets a general message reach a till nobody is logged into.
     *
     * @return list<string>
     */
    private static function tokensFor(?int $restaurantId, ?int $userId): array
    {
        if ($userId !== null) {
            $rows = Database::select(
                'SELECT token FROM device_tokens WHERE user_id = :uid',
                ['uid' => $userId],
            );
        } elseif ($restaurantId !== null) {
            $rows = Database::select(
                'SELECT token FROM device_tokens WHERE restaurant_id = :rid',
                ['rid' => $restaurantId],
            );
        } else {
            $rows = Database::select('SELECT token FROM device_tokens');
        }

        return array_map(static fn (array $r): string => (string) $r['token'], $rows);
    }
}
