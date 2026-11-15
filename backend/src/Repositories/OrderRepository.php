<?php

declare(strict_types=1);

namespace Dacaam\Repositories;

use Dacaam\Core\Database;
use Dacaam\Support\Presenter;

/**
 * Order reads. Writes live in OrderController so the transaction boundary and
 * the audit entries stay next to the business rules that produce them.
 */
final class OrderRepository extends Repository
{
    private const SELECT = 'SELECT o.*,
               CASE WHEN t.name <> "" THEN t.name
                    ELSE CONCAT("Table ", LPAD(t.table_number, 2, "0")) END AS table_label,
               -- Whether the evening this order belongs to has been counted.
               -- A settled shift cannot be edited, so the app is told before
               -- it offers a button that would only ever be refused.
               (sh.id IS NOT NULL AND sh.closed_at IS NOT NULL) AS shift_closed
          FROM orders o
     LEFT JOIN `tables` t ON t.id = o.table_id
     LEFT JOIN shifts sh ON sh.id = o.shift_id';

    /**
     * @param  array<string,mixed> $filters
     * @return list<array<string,mixed>>
     */
    public static function list(int $restaurantId, array $filters = [], int $limit = 200): array
    {
        $where = ['o.restaurant_id = :rid'];
        $bind = ['rid' => $restaurantId];

        if (!empty($filters['status'])) {
            $where[] = 'o.status = :status';
            $bind['status'] = $filters['status'];
        }
        if (!empty($filters['order_type'])) {
            $where[] = 'o.order_type = :otype';
            $bind['otype'] = $filters['order_type'];
        }
        if (!empty($filters['table_id'])) {
            $where[] = 'o.table_id = :tid';
            $bind['tid'] = (int) $filters['table_id'];
        }
        if (!empty($filters['waiter_id'])) {
            $where[] = 'o.waiter_id = :wid';
            $bind['wid'] = (int) $filters['waiter_id'];
        }
        if (!empty($filters['from'])) {
            $where[] = 'o.created_at >= :from';
            $bind['from'] = $filters['from'];
        }
        if (!empty($filters['to'])) {
            $where[] = 'o.created_at <= :to';
            $bind['to'] = $filters['to'];
        }
        if (!empty($filters['payment_method'])) {
            $where[] = 'EXISTS (SELECT 1 FROM order_payments p
                                 WHERE p.order_id = o.id AND p.method = :pmethod)';
            $bind['pmethod'] = $filters['payment_method'];
        }
        if (!empty($filters['search'])) {
            $where[] = '(o.order_number LIKE :q OR o.waiter_name LIKE :q2 OR o.customer_name LIKE :q3)';
            $like = '%' . $filters['search'] . '%';
            $bind['q'] = $like;
            $bind['q2'] = $like;
            $bind['q3'] = $like;
        }

        $rows = Database::select(
            self::SELECT . ' WHERE ' . implode(' AND ', $where)
            . ' ORDER BY o.created_at DESC, o.id DESC LIMIT ' . max(1, min($limit, 500)),
            $bind,
        );

        if ($rows === []) {
            return [];
        }

        $ids = array_map(static fn (array $r): int => (int) $r['id'], $rows);
        $items = self::itemsFor($restaurantId, $ids);
        $payments = self::paymentsFor($restaurantId, $ids);

        return array_map(
            static fn (array $row): array => Presenter::order(
                $row,
                $items[(int) $row['id']] ?? [],
                $payments[(int) $row['id']] ?? [],
            ),
            $rows,
        );
    }

    /** @return array<string,mixed>|null */
    public static function find(int $restaurantId, int $orderId, bool $withHistory = false): ?array
    {
        $row = Database::selectOne(
            self::SELECT . ' WHERE o.restaurant_id = :rid AND o.id = :id LIMIT 1',
            ['rid' => $restaurantId, 'id' => $orderId],
        );

        if ($row === null) {
            return null;
        }

        $events = $withHistory ? self::history($restaurantId, $orderId) : [];

        return Presenter::order(
            $row,
            self::itemsFor($restaurantId, [$orderId])[$orderId] ?? [],
            self::paymentsFor($restaurantId, [$orderId])[$orderId] ?? [],
            $events,
        );
    }

    /** @return list<array<string,mixed>> */
    public static function history(int $restaurantId, int $orderId): array
    {
        return Database::select(
            'SELECT * FROM audit_logs
              WHERE restaurant_id = :rid AND module = "orders" AND record_id = :id
              ORDER BY created_at ASC, id ASC',
            ['rid' => $restaurantId, 'id' => $orderId],
        );
    }

    /**
     * @param  list<int> $orderIds
     * @return array<int,list<array<string,mixed>>>
     */
    private static function itemsFor(int $restaurantId, array $orderIds): array
    {
        if ($orderIds === []) {
            return [];
        }

        $placeholders = implode(',', array_fill(0, count($orderIds), '?'));
        $rows = Database::select(
            "SELECT * FROM order_items
              WHERE restaurant_id = ? AND order_id IN ($placeholders)
              ORDER BY id ASC",
            array_merge([$restaurantId], $orderIds),
        );

        $grouped = [];
        foreach ($rows as $row) {
            $grouped[(int) $row['order_id']][] = $row;
        }

        return $grouped;
    }

    /**
     * @param  list<int> $orderIds
     * @return array<int,list<array<string,mixed>>>
     */
    private static function paymentsFor(int $restaurantId, array $orderIds): array
    {
        if ($orderIds === []) {
            return [];
        }

        $placeholders = implode(',', array_fill(0, count($orderIds), '?'));
        $rows = Database::select(
            "SELECT * FROM order_payments
              WHERE restaurant_id = ? AND order_id IN ($placeholders)
              ORDER BY id ASC",
            array_merge([$restaurantId], $orderIds),
        );

        $grouped = [];
        foreach ($rows as $row) {
            $grouped[(int) $row['order_id']][] = $row;
        }

        return $grouped;
    }

    /**
     * Next per-tenant order number. Called inside the create transaction so two
     * simultaneous checkouts cannot both claim the same number.
     */
    public static function nextOrderNumber(int $restaurantId): int
    {
        $max = Database::scalar(
            'SELECT COALESCE(MAX(order_number), 1000) FROM orders WHERE restaurant_id = :rid FOR UPDATE',
            ['rid' => $restaurantId],
        );

        return (int) $max + 1;
    }
}
