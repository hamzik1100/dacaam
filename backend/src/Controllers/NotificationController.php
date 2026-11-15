<?php

declare(strict_types=1);

namespace Dacaam\Controllers;

use Dacaam\Core\AuthContext;
use Dacaam\Core\Database;
use Dacaam\Core\Request;
use Dacaam\Core\Validator;
use Dacaam\Repositories\Repository;
use Dacaam\Support\Presenter;

/**
 * What the app asks for and what it reports back.
 *
 * Sending lives in the Super Admin dashboard, not here — this side only reads.
 * A restaurant cannot write its own notifications, which is why there is no
 * store method on it.
 */
final class NotificationController extends Repository
{
    /**
     * Everything addressed to this user, newest first.
     *
     * Three audiences overlap in one query: the whole platform
     * (`restaurant_id IS NULL`), this restaurant, and this person. A message
     * to the platform is addressed to everybody in it, so it appears for a
     * user who has never been named anywhere.
     *
     * @return list<array<string,mixed>>
     */
    public function index(Request $request, AuthContext $context): array
    {
        $rows = Database::select(
            'SELECT n.*, r.read_at
               FROM notifications n
          LEFT JOIN notification_reads r
                 ON r.notification_id = n.id AND r.user_id = :uid
              WHERE (n.restaurant_id IS NULL OR n.restaurant_id = :rid)
                AND (n.user_id IS NULL OR n.user_id = :uid2)
              ORDER BY n.created_at DESC, n.id DESC
              LIMIT 100',
            [
                'uid'  => $context->userId,
                'rid'  => $context->restaurantId,
                'uid2' => $context->userId,
            ],
        );

        return array_map(
            static fn (array $r): array => [
                'id'      => (int) $r['id'],
                'title'   => (string) $r['title'],
                'body'    => (string) $r['body'],
                'kind'    => (string) $r['kind'],
                'is_read' => $r['read_at'] !== null,
                'sent_at' => Presenter::iso($r['created_at']),
            ],
            $rows,
        );
    }

    /**
     * Marks one message read for this user, or all of them.
     *
     * INSERT IGNORE rather than a check-then-insert: two taps in quick
     * succession would otherwise race, and the unique index already says what
     * we mean — one read per person per message.
     *
     * @return array<string,mixed>
     */
    public function markRead(Request $request, AuthContext $context): array
    {
        $id = $request->intParam('id');

        Database::run(
            'INSERT IGNORE INTO notification_reads (notification_id, user_id)
             SELECT n.id, :uid FROM notifications n
              WHERE n.id = :id
                AND (n.restaurant_id IS NULL OR n.restaurant_id = :rid)
                AND (n.user_id IS NULL OR n.user_id = :uid2)',
            [
                'uid'  => $context->userId,
                'id'   => $id,
                'rid'  => $context->restaurantId,
                'uid2' => $context->userId,
            ],
        );

        return ['ok' => true];
    }

    /** @return array<string,mixed> */
    public function markAllRead(Request $request, AuthContext $context): array
    {
        Database::run(
            'INSERT IGNORE INTO notification_reads (notification_id, user_id)
             SELECT n.id, :uid FROM notifications n
              WHERE (n.restaurant_id IS NULL OR n.restaurant_id = :rid)
                AND (n.user_id IS NULL OR n.user_id = :uid2)',
            [
                'uid'  => $context->userId,
                'rid'  => $context->restaurantId,
                'uid2' => $context->userId,
            ],
        );

        return ['ok' => true];
    }

    /**
     * Remembers where to deliver.
     *
     * Called on every launch that has a session — which, because the app
     * restores its stored session automatically, is every launch after the
     * first sign-in.
     *
     * The row then outlives the session. Signing out clears the token on the
     * phone but not this row, so a handset sitting on the counter with nobody
     * logged in still receives a general message. What it cannot receive is a
     * message addressed to one person, because at that moment nobody is.
     *
     * Deliberately behind authentication. An open registration endpoint is a
     * table anybody can fill with junk, and a device that has never signed in
     * belongs to no restaurant — there is nothing meaningful to send it.
     *
     * The token is the key, not the device: Android reissues it on reinstall,
     * so the same handset can appear twice and the older row simply stops being
     * used. Re-registering an existing token moves it to whoever is signed in
     * now, which is what makes a shared counter tablet address the right person.
     *
     * @return array<string,mixed>
     */
    public function registerDevice(Request $request, AuthContext $context): array
    {
        $data = Validator::check($request->all(), [
            'token'    => 'required|string|min:10|max:255',
            'platform' => 'nullable|string|max:20',
        ]);

        Database::run(
            'INSERT INTO device_tokens (token, restaurant_id, user_id, platform)
             VALUES (:token, :rid, :uid, :platform)
             ON DUPLICATE KEY UPDATE
                restaurant_id = VALUES(restaurant_id),
                user_id       = VALUES(user_id),
                platform      = VALUES(platform),
                last_seen_at  = CURRENT_TIMESTAMP',
            [
                'token'    => (string) $data['token'],
                'rid'      => $context->restaurantId,
                'uid'      => $context->userId,
                'platform' => (string) ($data['platform'] ?? 'android'),
            ],
        );

        return ['ok' => true];
    }
}
