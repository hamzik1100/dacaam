<?php

declare(strict_types=1);

namespace Dacaam\Support;

use Dacaam\Core\ApiException;
use Dacaam\Core\Database;

/**
 * Order pricing — the authoritative implementation.
 *
 * The client sends *what* was ordered (item ids and quantities), never *what
 * it costs*. Prices are re-read from `menu_items` and the fee rules from
 * `restaurant_settings` on every call, so a tampered or stale client cannot
 * change a total.
 *
 * The rules, mirrored by `CartTotals` in the Flutter app:
 *   - discount comes off the subtotal before tax
 *   - tax applies only when enabled, at the rate stored at order time
 *   - the packaging fee is charged per portion on a takeaway: twenty plates
 *     go into twenty containers, so twenty fees. It used to be one flat
 *     charge for the whole order, which meant the restaurant bought
 *     nineteen boxes it never billed for
 *   - a discount can never exceed the subtotal
 */
final class Pricing
{
    /**
     * @param  list<array{menu_item_id:int,quantity:int,notes?:string}> $requestedLines
     * @param  array<string,mixed> $settings
     * @return array{
     *   lines: list<array<string,mixed>>,
     *   subtotal: float, discount: float, tax_rate: float,
     *   tax_amount: float, packaging_fee: float, total: float
     * }
     */
    public static function quote(
        int $restaurantId,
        array $requestedLines,
        string $orderType,
        float $discount,
        array $settings,
    ): array {
        if ($requestedLines === []) {
            throw ApiException::unprocessable('An order must contain at least one item');
        }

        // Merge duplicates first: two "Chicken Burger ×1" lines are one line of
        // two, which keeps totals and the receipt consistent.
        $wanted = [];
        foreach ($requestedLines as $line) {
            $id = (int) ($line['menu_item_id'] ?? 0);
            $qty = (int) ($line['quantity'] ?? 0);
            if ($id <= 0) {
                throw ApiException::unprocessable('Each line needs a menu_item_id');
            }
            if ($qty <= 0) {
                throw ApiException::unprocessable('Quantity must be greater than zero');
            }
            $wanted[$id] = ($wanted[$id] ?? 0) + $qty;
        }

        $ids = array_keys($wanted);
        $placeholders = implode(',', array_fill(0, count($ids), '?'));

        /** @var list<array<string,mixed>> $items */
        $items = Database::select(
            "SELECT id, name, price, emoji, image_url, is_available, apply_packaging_fee
               FROM menu_items
              WHERE restaurant_id = ?
                AND deleted_at IS NULL
                AND id IN ($placeholders)",
            array_merge([$restaurantId], $ids),
        );

        $byId = [];
        foreach ($items as $item) {
            $byId[(int) $item['id']] = $item;
        }

        $lines = [];
        $subtotal = 0.0;
        // Portions, not lines. Each one goes into its own container.
        $packagedUnits = 0;

        foreach ($wanted as $id => $quantity) {
            // A missing row means the id belongs to another tenant or was
            // deleted. Both are the same answer from here: it does not exist.
            if (!isset($byId[$id])) {
                throw ApiException::unprocessable(sprintf('Menu item %d is not available', $id));
            }

            $item = $byId[$id];
            if ((int) $item['is_available'] !== 1) {
                throw ApiException::unprocessable(
                    sprintf('"%s" is not available for sale', (string) $item['name']),
                );
            }

            $unitPrice = (float) $item['price'];
            $lineTotal = self::round($unitPrice * $quantity);
            $subtotal += $lineTotal;

            if ((int) $item['apply_packaging_fee'] === 1) {
                $packagedUnits += $quantity;
            }

            $lines[] = [
                'menu_item_id'        => $id,
                'item_name'           => (string) $item['name'],
                'unit_price'          => $unitPrice,
                'quantity'            => $quantity,
                'line_total'          => $lineTotal,
                'emoji'               => (string) $item['emoji'],
                'image_url'           => $item['image_url'],
                'apply_packaging_fee' => (int) $item['apply_packaging_fee'],
            ];
        }

        $subtotal = self::round($subtotal);
        $discount = self::round(max(0.0, min($discount, $subtotal)));

        $taxRate = (int) $settings['tax_enabled'] === 1 ? (float) $settings['tax_rate'] : 0.0;
        $taxable = $subtotal - $discount;
        $taxAmount = self::round($taxable * $taxRate / 100);

        $packagingApplies = $orderType === 'takeaway'
            && (int) $settings['packaging_fee_enabled'] === 1
            && $packagedUnits > 0;

        // Multiplied by the number of portions. One flat fee on an order of
        // twenty was the restaurant paying for nineteen containers out of
        // its own margin, on every large takeaway, unnoticed.
        $packagingFee = $packagingApplies
            ? self::round((float) $settings['packaging_fee'] * $packagedUnits)
            : 0.0;

        return [
            'lines'         => $lines,
            'subtotal'      => $subtotal,
            'discount'      => $discount,
            'tax_rate'      => $taxRate,
            'tax_amount'    => $taxAmount,
            'packaging_fee' => $packagingFee,
            'total'         => self::round($taxable + $taxAmount + $packagingFee),
        ];
    }

    /**
     * Two decimal places, half-up. Every money value passes through here so
     * stored totals and recomputed totals never disagree by a cent.
     */
    public static function round(float $value): float
    {
        return round($value, 2);
    }
}
