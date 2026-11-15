<?php

declare(strict_types=1);

namespace Dacaam\Support;

/**
 * Row → JSON shaping.
 *
 * Centralised so `/bootstrap`, `/orders` and `/orders/{id}` all emit the same
 * object for the same entity — the Flutter client has one parser per model,
 * not one per endpoint.
 *
 * PDO returns DECIMAL columns as strings; every money field is cast to float
 * exactly once, here.
 */
final class Presenter
{
    /** @param array<string,mixed> $row */
    public static function restaurant(array $row): array
    {
        return [
            'id'         => (int) $row['id'],
            'slug'       => (string) $row['slug'],
            'name'       => (string) $row['name'],
            'phone'      => (string) $row['phone'],
            'address'    => (string) $row['address'],
            'logo_emoji' => (string) $row['logo_emoji'],
            'is_open'    => (bool) $row['is_open'],
            'status'     => (string) $row['status'],
        ];
    }

    /** @param array<string,mixed> $row */
    public static function user(array $row, array $permissions = []): array
    {
        return [
            'id'            => (int) $row['id'],
            'restaurant_id' => (int) $row['restaurant_id'],
            'name'          => (string) $row['name'],
            'phone'         => (string) $row['phone'],
            'is_active'     => (bool) $row['is_active'],
            'role'          => (string) ($row['role_code'] ?? 'waiter'),
            'role_name'     => (string) ($row['role_name'] ?? ''),
            'permissions'   => $permissions,
        ];
    }

    /** @param array<string,mixed> $row */
    public static function category(array $row): array
    {
        return [
            'id'          => (int) $row['id'],
            'name'        => (string) $row['name'],
            'description' => (string) $row['description'],
            'emoji'       => (string) $row['emoji'],
            'color'       => (string) $row['color'],
            'is_active'   => (bool) $row['is_active'],
            'sort_order'  => (int) $row['sort_order'],
            'item_count'  => isset($row['item_count']) ? (int) $row['item_count'] : 0,
        ];
    }

    /** @param array<string,mixed> $row */
    public static function menuItem(array $row): array
    {
        return [
            'id'                  => (int) $row['id'],
            'category_id'         => (int) $row['category_id'],
            'name'                => (string) $row['name'],
            'description'         => (string) $row['description'],
            'price'               => (float) $row['price'],
            'image_url'           => $row['image_url'] === null ? null : (string) $row['image_url'],
            'emoji'               => (string) $row['emoji'],
            'is_available'        => (bool) $row['is_available'],
            'apply_packaging_fee' => (bool) $row['apply_packaging_fee'],
            'sort_order'          => (int) $row['sort_order'],
        ];
    }

    /** @param array<string,mixed> $row */
    public static function table(array $row): array
    {
        return [
            'id'               => (int) $row['id'],
            'table_number'     => (int) $row['table_number'],
            'name'             => (string) $row['name'],
            'capacity'         => (int) $row['capacity'],
            'status'           => (string) $row['status'],
            'current_order_id' => $row['current_order_id'] === null ? null : (int) $row['current_order_id'],
            'is_active'        => (bool) $row['is_active'],
        ];
    }

    /** @param array<string,mixed> $row */
    public static function orderLine(array $row): array
    {
        return [
            'menu_item_id'        => $row['menu_item_id'] === null ? null : (int) $row['menu_item_id'],
            'item_name'           => (string) $row['item_name'],
            'unit_price'          => (float) $row['unit_price'],
            'quantity'            => (int) $row['quantity'],
            'line_total'          => (float) $row['line_total'],
            'emoji'               => (string) $row['emoji'],
            'image_url'           => ($row['image_url'] ?? null) === null ? null : (string) $row['image_url'],
            'apply_packaging_fee' => (bool) $row['apply_packaging_fee'],
            'notes'               => (string) ($row['notes'] ?? ''),
        ];
    }

    /** @param array<string,mixed> $row */
    public static function payment(array $row): array
    {
        return [
            'method'     => (string) $row['method'],
            'amount'     => (float) $row['amount'],
            'reference'  => (string) $row['reference'],
            'created_at' => self::iso($row['created_at']),
        ];
    }

    /** @param array<string,mixed> $row */
    public static function auditEvent(array $row): array
    {
        return [
            'id'         => (int) $row['id'],
            'module'     => (string) $row['module'],
            'action'     => (string) $row['action'],
            'record_id'  => $row['record_id'] === null ? null : (int) $row['record_id'],
            'field'      => (string) $row['field'],
            'old_value'  => $row['old_value'] === null ? null : (string) $row['old_value'],
            'new_value'  => $row['new_value'] === null ? null : (string) $row['new_value'],
            'reason'     => $row['reason'] === null ? null : (string) $row['reason'],
            'user_name'  => (string) $row['user_name'],
            'ip'         => (string) ($row['ip'] ?? ''),
            'device'     => (string) ($row['device'] ?? ''),
            'created_at' => self::iso($row['created_at']),
        ];
    }

    /**
     * @param array<string,mixed>       $row
     * @param list<array<string,mixed>> $lines
     * @param list<array<string,mixed>> $payments
     * @param list<array<string,mixed>> $events
     */
    public static function order(
        array $row,
        array $lines = [],
        array $payments = [],
        array $events = [],
    ): array {
        return [
            'id'             => (int) $row['id'],
            'order_number'   => (int) $row['order_number'],
            'order_type'     => (string) $row['order_type'],
            'status'         => (string) $row['status'],
            // Separate from status on purpose: the kitchen and the till are
            // answering different questions about the same order.
            'payment_status' => (string) ($row['payment_status'] ?? 'unpaid'),
            // The evening this belongs to has been counted and signed off, so
            // nothing about it can move any more. Sent so the app can say why
            // rather than offering an action the server will refuse.
            'is_locked'      => (bool) ($row['shift_closed'] ?? false),
            'table_id'       => $row['table_id'] === null ? null : (int) $row['table_id'],
            'table_label'    => ($row['table_label'] ?? null) === null ? null : (string) $row['table_label'],
            'waiter_id'      => $row['waiter_id'] === null ? null : (int) $row['waiter_id'],
            'waiter_name'    => (string) $row['waiter_name'],
            'customer_id'    => ($row['customer_id'] ?? null) === null ? null : (int) $row['customer_id'],
            'customer_name'  => (string) $row['customer_name'],
            'customer_phone' => (string) $row['customer_phone'],
            'guests'         => (int) $row['guests'],
            'subtotal'       => (float) $row['subtotal'],
            'discount'       => (float) $row['discount'],
            'tax_rate'       => (float) $row['tax_rate'],
            'tax_amount'     => (float) $row['tax_amount'],
            'packaging_fee'  => (float) $row['packaging_fee'],
            'total'          => (float) $row['total'],
            'notes'          => (string) $row['notes'],
            'cancel_reason'  => $row['cancel_reason'] === null ? null : (string) $row['cancel_reason'],
            'created_at'     => self::iso($row['created_at']),
            'items'          => array_map([self::class, 'orderLine'], $lines),
            'payments'       => array_map([self::class, 'payment'], $payments),
            'events'         => array_map([self::class, 'auditEvent'], $events),
        ];
    }

    /**
     * @param array<string,mixed>       $row
     * @param list<array<string,mixed>> $lines
     */
    public static function draft(array $row, array $lines = []): array
    {
        $subtotal = 0.0;
        foreach ($lines as $line) {
            $subtotal += (float) $line['line_total'];
        }

        return [
            'id'                => (int) $row['id'],
            'code'              => (string) $row['code'],
            'customer_name'     => (string) $row['customer_name'],
            'customer_phone'    => (string) $row['customer_phone'],
            'order_type'        => (string) $row['order_type'],
            'table_id'          => $row['table_id'] === null ? null : (int) $row['table_id'],
            'table_label'       => ($row['table_label'] ?? null) === null ? null : (string) $row['table_label'],
            'waiter_name'       => (string) $row['waiter_name'],
            'packaging_applied' => (bool) $row['packaging_applied'],
            'status'            => (string) $row['status'],
            // Null unless refused. The screen shows it beside the status, so a
            // cancelled draft explains itself rather than just sitting there.
            'cancel_reason'     => ($row['cancel_reason'] ?? null) === null
                ? null
                : (string) $row['cancel_reason'],
            'notes'             => (string) $row['notes'],
            'subtotal'          => Pricing::round($subtotal),
            'created_at'        => self::iso($row['created_at']),
            'items'             => array_map([self::class, 'orderLine'], $lines),
        ];
    }

    /** @param array<string,mixed> $row */
    public static function expense(array $row): array
    {
        return [
            'id'                  => (int) $row['id'],
            'expense_category_id' => $row['expense_category_id'] === null ? null : (int) $row['expense_category_id'],
            'category_name'       => (string) ($row['category_name'] ?? ''),
            'name'                => (string) $row['name'],
            'amount'              => (float) $row['amount'],
            'kind'                => (string) $row['kind'],
            'method'              => (string) $row['method'],
            'expense_date'        => (string) $row['expense_date'],
            'is_recurring'        => (bool) $row['is_recurring'],
            'notes'               => (string) $row['notes'],
            'created_by'          => (string) ($row['created_by_name'] ?? ''),
            // Null-coalesced so a database that predates the migration still
            // answers this endpoint instead of 500ing on a missing column.
            'is_cancelled'        => ($row['cancelled_at'] ?? null) !== null,
            'cancelled_at'        => self::iso($row['cancelled_at'] ?? null),
            'cancel_reason'       => $row['cancel_reason'] ?? null,
        ];
    }

    /** @param array<string,mixed> $row */
    public static function expenseCategory(array $row): array
    {
        return [
            'id'    => (int) $row['id'],
            'name'  => (string) $row['name'],
            'kind'  => (string) $row['kind'],
            'icon'  => (string) $row['icon'],
            'color' => (string) $row['color'],
        ];
    }

    /** @param array<string,mixed> $row */
    public static function account(array $row): array
    {
        return [
            'id'        => (int) $row['id'],
            'method'    => (string) $row['method'],
            'name'      => (string) $row['name'],
            'balance'   => (float) $row['balance'],
            'money_in'  => (float) ($row['money_in'] ?? 0),
            'money_out' => (float) ($row['money_out'] ?? 0),
        ];
    }

    /** @param array<string,mixed> $row */
    public static function settings(array $row): array
    {
        return [
            'language'                  => (string) $row['language'],
            'theme_mode'                => (string) $row['theme_mode'],
            'currency_prefix'           => (string) $row['currency_prefix'],
            'tax_rate'                  => (float) $row['tax_rate'],
            'tax_enabled'               => (bool) $row['tax_enabled'],
            'packaging_fee_enabled'     => (bool) $row['packaging_fee_enabled'],
            'packaging_fee'             => (float) $row['packaging_fee'],
            'require_table_for_dine_in' => (bool) $row['require_table_for_dine_in'],
            'guest_count_enabled'       => (bool) $row['guest_count_enabled'],
            // Null-coalesced: a database that predates the alerts migration
            // still has to answer this endpoint rather than 500 on a missing
            // column, because the app calls it on every sign-in.
            'alert_email'               => $row['alert_email'] ?? null,
            'alerts_money'              => (string) ($row['alerts_money'] ?? 'instant'),
            'alerts_security'           => (string) ($row['alerts_security'] ?? 'instant'),
            'alerts_orders'             => (string) ($row['alerts_orders'] ?? 'digest'),
            'alerts_menu'               => (string) ($row['alerts_menu'] ?? 'digest'),
        ];
    }

    /**
     * A shift.
     *
     * `blind` is the whole control. While a till is open, the person about to
     * count it must not be handed the figure they are supposed to arrive at —
     * given the number, they will type the number, and a variance that is
     * always zero is worse than no count because it looks like a control.
     *
     * @param array<string,mixed> $row
     */
    public static function shift(array $row, bool $blind = true): array
    {
        $out = [
            'id'             => (int) $row['id'],
            'account_id'     => (int) $row['account_id'],
            'account_name'   => (string) ($row['account_name'] ?? ''),
            'opened_by'      => (string) ($row['opened_by_name'] ?? ''),
            'opened_at'      => self::iso($row['opened_at']),
            'opening_float'  => (float) $row['opening_float'],
            'previous_close' => $row['previous_close'] === null ? null : (float) $row['previous_close'],
            'overnight_diff' => $row['overnight_diff'] === null ? null : (float) $row['overnight_diff'],
            'closed_by'      => (string) ($row['closed_by_name'] ?? ''),
            'closed_at'      => self::iso($row['closed_at']),
            'orders_outside' => (int) ($row['orders_outside'] ?? 0),
            'notes'          => (string) ($row['notes'] ?? ''),
            'is_open'        => $row['closed_at'] === null,
        ];

        // A closed shift's figures are history and safe to read; an open one's
        // are the answer to a question nobody has been asked yet.
        if (!$blind || $row['closed_at'] !== null) {
            $out += [
                'expected_close' => $row['expected_close'] === null ? null : (float) $row['expected_close'],
                'counted_close'  => $row['counted_close'] === null ? null : (float) $row['counted_close'],
                'variance'       => $row['variance'] === null ? null : (float) $row['variance'],
                'close_reason'   => $row['close_reason'] === null ? null : (string) $row['close_reason'],
            ];
        }

        return $out;
    }

    public static function iso(mixed $value): ?string
    {
        if ($value === null || $value === '') {
            return null;
        }
        $timestamp = strtotime((string) $value);

        return $timestamp === false ? null : date('c', $timestamp);
    }
}
