<?php

declare(strict_types=1);

namespace Dacaam\Controllers;

use Dacaam\Core\ApiException;
use Dacaam\Core\Audit;
use Dacaam\Core\AuthContext;
use Dacaam\Core\Database;
use Dacaam\Core\Request;
use Dacaam\Core\Validator;
use Dacaam\Repositories\Repository;
use Dacaam\Support\Presenter;
use Dacaam\Support\Pricing;

/**
 * Draft orders.
 *
 * A draft is not a sale. Nothing here touches accounts, reports or KPIs; that
 * only happens when `convert` turns a draft into a real order through the same
 * pricing path any other checkout uses.
 */
final class DraftController extends Repository
{
    /** @return list<array<string,mixed>> */
    public function index(Request $request, AuthContext $context): array
    {
        $where = ['d.restaurant_id = :rid'];
        $bind = ['rid' => $context->restaurantId];

        if (($status = $request->queryString('status')) !== '') {
            $where[] = 'd.status = :status';
            $bind['status'] = $status;
        }

        $rows = Database::select(
            'SELECT d.*,
                    CASE WHEN t.name <> "" THEN t.name
                         ELSE CONCAT("Table ", LPAD(t.table_number, 2, "0")) END AS table_label
               FROM draft_orders d
          LEFT JOIN `tables` t ON t.id = d.table_id
              WHERE ' . implode(' AND ', $where) . '
              ORDER BY d.created_at DESC',
            $bind,
        );

        if ($rows === []) {
            return [];
        }

        $ids = array_map(static fn (array $r): int => (int) $r['id'], $rows);
        $items = $this->itemsFor($context->restaurantId, $ids);

        return array_map(
            static fn (array $row): array => Presenter::draft($row, $items[(int) $row['id']] ?? []),
            $rows,
        );
    }

    /** @return array<string,mixed> */
    public function show(Request $request, AuthContext $context): array
    {
        $id = $request->intParam('id');
        $row = Database::selectOne(
            'SELECT d.*,
                    CASE WHEN t.name <> "" THEN t.name
                         ELSE CONCAT("Table ", LPAD(t.table_number, 2, "0")) END AS table_label
               FROM draft_orders d
          LEFT JOIN `tables` t ON t.id = d.table_id
              WHERE d.id = :id AND d.restaurant_id = :rid LIMIT 1',
            ['id' => $id, 'rid' => $context->restaurantId],
        );

        if ($row === null) {
            throw ApiException::notFound('Draft not found');
        }

        return Presenter::draft($row, $this->itemsFor($context->restaurantId, [$id])[$id] ?? []);
    }

    /** @return array<string,mixed> */
    public function store(Request $request, AuthContext $context): array
    {
        $data = Validator::check($request->all(), [
            // Customer name is the one required draft field (§22) — a draft
            // with no name cannot be handed back to anyone.
            'customer_name'  => 'required|string|min:1|max:150',
            'customer_phone' => 'nullable|string|max:32',
            'order_type'     => 'required|string|in:dine_in,takeaway',
            'items'          => 'required|array|min:1',
            'table_id'       => 'nullable|int',
            'waiter_id'      => 'nullable|int',
            'notes'          => 'nullable|string|max:500',
        ]);

        $settings = self::settings($context->restaurantId);
        $orderType = (string) $data['order_type'];
        $tableId = $orderType === 'takeaway' ? null : ($data['table_id'] ?? null);

        if ($tableId !== null) {
            self::requireScoped('tables', (int) $tableId, $context->restaurantId, 'Table not found');
        }

        /** @var list<array{menu_item_id:int,quantity:int}> $items */
        $items = $data['items'];
        $quote = Pricing::quote($context->restaurantId, $items, $orderType, 0.0, $settings);

        return Database::transaction(function () use ($context, $data, $orderType, $tableId, $quote): array {
            $id = Database::insert('draft_orders', [
                'restaurant_id'     => $context->restaurantId,
                'code'              => $this->nextCode($context->restaurantId),
                'customer_name'     => (string) $data['customer_name'],
                'customer_phone'    => (string) ($data['customer_phone'] ?? ''),
                'order_type'        => $orderType,
                'table_id'          => $tableId,
                'waiter_id'         => $data['waiter_id'] ?? $context->userId,
                'waiter_name'       => $context->userName,
                'packaging_applied' => $quote['packaging_fee'] > 0 ? 1 : 0,
                'status'            => 'draft',
                'notes'             => (string) ($data['notes'] ?? ''),
                'created_by'        => $context->userId,
            ]);

            foreach ($quote['lines'] as $line) {
                unset($line['image_url']);
                Database::insert('draft_order_items', $line + [
                    'restaurant_id'  => $context->restaurantId,
                    'draft_order_id' => $id,
                ]);
            }

            Audit::log($context, 'drafts', 'draft_created', $id, newValue: (string) $data['customer_name']);

            return $this->present($context->restaurantId, $id);
        });
    }

    /**
     * Updates a parked draft. Reprices from the live menu, because a draft
     * that sat overnight should not resurrect yesterday's prices.
     *
     * @return array<string,mixed>
     */
    public function update(Request $request, AuthContext $context): array
    {
        $id = $request->intParam('id');
        $draft = self::requireScoped('draft_orders', $id, $context->restaurantId, 'Draft not found');

        // Converted is finished: an order exists and carries the money.
        // Cancelled is finished too, and was refused here for a long time by
        // nothing at all — reviving a deliberately voided draft by editing it
        // is the same act the orders side already refuses.
        if (in_array((string) $draft['status'], ['completed', 'cancelled'], true)) {
            throw ApiException::conflict(
                (string) $draft['status'] === 'completed'
                    ? 'A converted draft cannot be edited'
                    : 'A cancelled draft cannot be edited',
            );
        }

        $data = Validator::check($request->all(), [
            'customer_name'  => 'nullable|string|min:1|max:150',
            'customer_phone' => 'nullable|string|max:32',
            'order_type'     => 'nullable|string|in:dine_in,takeaway',
            'items'          => 'nullable|array|min:1',
            'table_id'       => 'nullable|int',
            'notes'          => 'nullable|string|max:500',
            'status'         => 'nullable|string|in:draft,pending,cancelled',
        ]);

        $orderType = (string) ($data['order_type'] ?? $draft['order_type']);
        $tableId = $orderType === 'takeaway'
            ? null
            : ($data['table_id'] ?? $draft['table_id']);

        if ($tableId !== null) {
            self::requireScoped('tables', (int) $tableId, $context->restaurantId, 'Table not found');
        }

        $settings = self::settings($context->restaurantId);
        $quote = null;

        if (isset($data['items']) && is_array($data['items'])) {
            /** @var list<array{menu_item_id:int,quantity:int}> $items */
            $items = $data['items'];
            $quote = Pricing::quote($context->restaurantId, $items, $orderType, 0.0, $settings);
        }

        Database::transaction(function () use (
            $context, $id, $data, $orderType, $tableId, $quote
        ): void {
            $update = [
                'order_type' => $orderType,
                'table_id'   => $tableId,
            ];
            foreach (['customer_name', 'customer_phone', 'notes', 'status'] as $field) {
                if (isset($data[$field])) {
                    $update[$field] = $data[$field];
                }
            }
            if ($quote !== null) {
                $update['packaging_applied'] = $quote['packaging_fee'] > 0 ? 1 : 0;
            }

            Database::updateScoped('draft_orders', $update, $id, $context->restaurantId);

            if ($quote !== null) {
                Database::run(
                    'DELETE FROM draft_order_items
                      WHERE draft_order_id = :id AND restaurant_id = :rid',
                    ['id' => $id, 'rid' => $context->restaurantId],
                );

                foreach ($quote['lines'] as $line) {
                    unset($line['image_url']);
                    Database::insert('draft_order_items', $line + [
                        'restaurant_id'  => $context->restaurantId,
                        'draft_order_id' => $id,
                    ]);
                }
            }

            Audit::log($context, 'drafts', 'draft_updated', $id);
        });

        return $this->present($context->restaurantId, $id);
    }

    /** @return array<string,mixed> */
    /**
     * Marks a refused draft cancelled. It is not deleted.
     *
     * §22 lists Cancelled among the draft statuses and §46 refuses a
     * cancellation with no reason. Deleting the row — which is what this used
     * to do — threw away the one fact worth keeping: that a customer ordered
     * and then walked away, and what they said when they did.
     *
     * @return array<string,mixed>
     */
    public function cancel(Request $request, AuthContext $context): array
    {
        $data = Validator::check($request->all(), [
            'reason' => 'required|string|min:3|max:255',
        ]);

        $id = $request->intParam('id');
        $draft = self::requireScoped('draft_orders', $id, $context->restaurantId, 'Draft not found');
        $status = (string) $draft['status'];

        if ($status === 'completed') {
            throw ApiException::conflict('A converted draft cannot be cancelled');
        }

        if ($status === 'cancelled') {
            return $this->present($context->restaurantId, $id);
        }

        Database::run(
            'UPDATE draft_orders
                SET status = "cancelled", cancel_reason = :reason
              WHERE id = :id AND restaurant_id = :rid',
            ['reason' => trim((string) $data['reason']), 'id' => $id, 'rid' => $context->restaurantId],
        );

        Audit::log(
            $context,
            'drafts',
            'draft_cancelled',
            $id,
            field: 'status',
            oldValue: $status,
            newValue: 'cancelled',
            reason: trim((string) $data['reason']),
        );

        return $this->present($context->restaurantId, $id);
    }

    /**
     * Converts a draft into a real order. This is the moment a draft becomes
     * revenue, and it reprices from the live menu rather than trusting the
     * prices captured when the draft was parked.
     *
     * @return array<string,mixed>
     */
    public function convert(Request $request, AuthContext $context): array
    {
        $context->require('orders.create');

        $id = $request->intParam('id');
        $draft = self::requireScoped('draft_orders', $id, $context->restaurantId, 'Draft not found');

        if ((string) $draft['status'] === 'completed') {
            throw ApiException::conflict('This draft has already been converted');
        }

        $lines = Database::select(
            'SELECT menu_item_id, quantity FROM draft_order_items
              WHERE draft_order_id = :id AND restaurant_id = :rid',
            ['id' => $id, 'rid' => $context->restaurantId],
        );

        if ($lines === []) {
            throw ApiException::unprocessable('This draft has no items');
        }

        $payload = [
            'order_type'     => (string) $draft['order_type'],
            'table_id'       => $draft['table_id'],
            'waiter_id'      => $draft['waiter_id'],
            'customer_name'  => (string) $draft['customer_name'],
            'customer_phone' => (string) $draft['customer_phone'],
            'notes'          => (string) $draft['notes'],
            'items'          => array_map(
                static fn (array $l): array => [
                    'menu_item_id' => (int) $l['menu_item_id'],
                    'quantity'     => (int) $l['quantity'],
                ],
                $lines,
            ),
        ];

        // The caller's choices win over what the draft was parked with. A draft
        // taken as dine-in with no table cannot convert while "require table"
        // is on — the order simply fails validation — so the screen asks for
        // the missing pieces at this moment and sends them here.
        foreach ([
            'payment_method',
            'payment_reference',
            'discount',
            'guests',
            'order_type',
            'table_id',
            'waiter_id',
        ] as $passthrough) {
            if ($request->input($passthrough) !== null) {
                $payload[$passthrough] = $request->input($passthrough);
            }
        }

        // Switching to takeaway at the counter must drop the table with it:
        // the orders table has a CHECK that a takeaway holds none.
        if (($payload['order_type'] ?? '') === 'takeaway') {
            $payload['table_id'] = null;
        }

        $order = (new OrderController())->store(
            Request::forInternal($request, $payload),
            $context,
        );

        Database::run(
            'UPDATE draft_orders
                SET status = "completed", converted_order_id = :oid
              WHERE id = :id AND restaurant_id = :rid',
            ['oid' => $order['id'], 'id' => $id, 'rid' => $context->restaurantId],
        );

        Audit::log(
            $context,
            'drafts',
            'draft_converted',
            $id,
            field: 'status',
            oldValue: (string) $draft['status'],
            newValue: 'completed',
        );

        return $order;
    }

    // ----------------------------------------------------------- helpers

    /** @return array<string,mixed> */
    private function present(int $restaurantId, int $id): array
    {
        $row = Database::selectOne(
            'SELECT d.*,
                    CASE WHEN t.name <> "" THEN t.name
                         ELSE CONCAT("Table ", LPAD(t.table_number, 2, "0")) END AS table_label
               FROM draft_orders d
          LEFT JOIN `tables` t ON t.id = d.table_id
              WHERE d.id = :id AND d.restaurant_id = :rid LIMIT 1',
            ['id' => $id, 'rid' => $restaurantId],
        );

        return Presenter::draft($row ?? [], $this->itemsFor($restaurantId, [$id])[$id] ?? []);
    }

    /**
     * @param  list<int> $draftIds
     * @return array<int,list<array<string,mixed>>>
     */
    private function itemsFor(int $restaurantId, array $draftIds): array
    {
        if ($draftIds === []) {
            return [];
        }

        $placeholders = implode(',', array_fill(0, count($draftIds), '?'));
        $rows = Database::select(
            "SELECT * FROM draft_order_items
              WHERE restaurant_id = ? AND draft_order_id IN ($placeholders)
              ORDER BY id ASC",
            array_merge([$restaurantId], $draftIds),
        );

        $grouped = [];
        foreach ($rows as $row) {
            $grouped[(int) $row['draft_order_id']][] = $row;
        }

        return $grouped;
    }

    private function nextCode(int $restaurantId): string
    {
        $max = Database::scalar(
            'SELECT COALESCE(MAX(CAST(SUBSTRING(code, 3) AS UNSIGNED)), 99)
               FROM draft_orders WHERE restaurant_id = :rid',
            ['rid' => $restaurantId],
        );

        return 'D-' . ((int) $max + 1);
    }
}
