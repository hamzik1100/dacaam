<?php

declare(strict_types=1);

namespace Dacaam\Controllers;

use Dacaam\Core\ApiException;
use Dacaam\Core\Audit;
use Dacaam\Core\AuthContext;
use Dacaam\Core\Database;
use Dacaam\Core\Request;
use Dacaam\Core\Validator;
use Dacaam\Repositories\OrderRepository;
use Dacaam\Repositories\Repository;
use Dacaam\Support\Period;
use Dacaam\Support\Presenter;
use Dacaam\Support\Pricing;
use Dacaam\Support\Shifts;

final class OrderController extends Repository
{
    private const OPEN_STATUSES = ['pending', 'preparing', 'ready'];

    /** @return list<array<string,mixed>> */
    public function index(Request $request, AuthContext $context): array
    {
        $filters = [
            'status'         => $request->queryString('status'),
            'order_type'     => $request->queryString('order_type'),
            'table_id'       => $request->queryInt('table_id'),
            'waiter_id'      => $request->queryInt('waiter_id'),
            'payment_method' => $request->queryString('payment_method'),
            'search'         => $request->queryString('search'),
        ];

        $range = $request->queryString('range');
        if ($range !== '' && $range !== 'all') {
            $period = Period::resolve($range, $request->queryString('from'), $request->queryString('to'));
            $filters['from'] = $period->fromSql();
            $filters['to'] = $period->toSql();
        }

        return OrderRepository::list(
            $context->restaurantId,
            $filters,
            $request->queryInt('limit', 200) ?? 200,
        );
    }

    /** @return array<string,mixed> */
    public function show(Request $request, AuthContext $context): array
    {
        $order = OrderRepository::find(
            $context->restaurantId,
            $request->intParam('id'),
            withHistory: true,
        );

        if ($order === null) {
            throw ApiException::notFound('Order not found');
        }

        return $order;
    }

    /** @return list<array<string,mixed>> */
    public function history(Request $request, AuthContext $context): array
    {
        // Confirm the order is ours before returning its trail.
        self::requireScoped('orders', $request->intParam('id'), $context->restaurantId, 'Order not found', 'id');

        return array_map(
            [Presenter::class, 'auditEvent'],
            OrderRepository::history($context->restaurantId, $request->intParam('id')),
        );
    }

    /**
     * Creates an order. Totals are computed here from stored menu prices —
     * anything the client sent as a price or total is ignored.
     *
     * @return array<string,mixed>
     */
    public function store(Request $request, AuthContext $context): array
    {
        $data = Validator::check($request->all(), [
            'order_type'     => 'required|string|in:dine_in,takeaway',
            'items'          => 'required|array|min:1',
            'table_id'       => 'nullable|int',
            'waiter_id'      => 'nullable|int',
            'guests'         => 'nullable|int|min:0|max:255',
            'discount'       => 'nullable|numeric|min:0',
            'customer_name'  => 'nullable|string|max:150',
            'customer_phone' => 'nullable|string|max:32',
            'notes'          => 'nullable|string|max:500',
            'payment_method' => 'nullable|string|max:32',
            'payment_reference' => 'nullable|string|max:100',
            'status'         => 'nullable|string|in:pending,preparing,ready,completed',
            // Whose account this goes on, and how they are settling it.
            'customer_id'    => 'nullable|int|min:1',
            'payment_mode'   => 'nullable|string|in:cash,credit,wallet',
        ]);

        $settings = self::settings($context->restaurantId);
        $orderType = (string) $data['order_type'];
        $tableId = $data['table_id'] ?? null;

        // ---- order-type rules (§47) --------------------------------------
        if ($orderType === 'takeaway') {
            // Not an error — a takeaway simply has no table, and silently
            // dropping it beats rejecting a valid order over a stale field.
            $tableId = null;
        } elseif ((int) $settings['require_table_for_dine_in'] === 1 && empty($tableId)) {
            throw ApiException::validation(
                ['table_id' => 'A table is required for Dine In orders'],
            );
        }

        if ($tableId !== null) {
            $table = self::requireScoped('tables', (int) $tableId, $context->restaurantId, 'Table not found');
            if ((int) $table['is_active'] !== 1) {
                throw ApiException::unprocessable('That table is not active');
            }
        }

        $waiterId = $data['waiter_id'] ?? null;
        $waiterName = $context->userName;
        if ($waiterId !== null) {
            $waiter = Database::selectOne(
                'SELECT id, name FROM users WHERE id = :id AND restaurant_id = :rid LIMIT 1',
                ['id' => (int) $waiterId, 'rid' => $context->restaurantId],
            );
            if ($waiter === null) {
                throw ApiException::validation(['waiter_id' => 'Unknown waiter']);
            }
            $waiterName = (string) $waiter['name'];
        }

        /** @var list<array{menu_item_id:int,quantity:int}> $items */
        $items = $data['items'];
        $quote = Pricing::quote(
            $context->restaurantId,
            $items,
            $orderType,
            (float) ($data['discount'] ?? 0),
            $settings,
        );

        // `pending`, not `preparing`. An order that is paid for is completed a
        // few lines below and never sits here at all; the only orders that stay
        // are the unpaid ones — a converted draft, most of all — and those
        // belong under the status the Orders screen still offers as a filter.
        $status = (string) ($data['status'] ?? 'pending');
        $paymentMethod = $data['payment_method'] ?? null;
        $customerId = isset($data['customer_id']) ? (int) $data['customer_id'] : null;
        $mode = (string) ($data['payment_mode'] ?? 'cash');

        if ($customerId !== null) {
            self::requireScoped('customers', $customerId, $context->restaurantId, 'Customer not found');
        } elseif ($mode !== 'cash') {
            throw ApiException::validation(
                ['customer_id' => 'Credit and wallet need a customer account'],
            );
        }

        return Database::transaction(function () use (
            $context, $data, $orderType, $tableId, $waiterId, $waiterName,
            $quote, $status, $paymentMethod, $settings, $customerId, $mode
        ): array {
            $orderNumber = OrderRepository::nextOrderNumber($context->restaurantId);

            $orderId = Database::insert('orders', [
                'restaurant_id'  => $context->restaurantId,
                'order_number'   => $orderNumber,
                'order_type'     => $orderType,
                'status'         => $status,
                'table_id'       => $tableId,
                'waiter_id'      => $waiterId,
                'waiter_name'    => self::firstName($waiterName),
                'customer_id'    => $customerId,
                'customer_name'  => (string) ($data['customer_name'] ?? ''),
                'customer_phone' => (string) ($data['customer_phone'] ?? ''),
                'guests'         => (int) ($data['guests'] ?? 0),
                'subtotal'       => $quote['subtotal'],
                'discount'       => $quote['discount'],
                'tax_rate'       => $quote['tax_rate'],
                'tax_amount'     => $quote['tax_amount'],
                'packaging_fee'  => $quote['packaging_fee'],
                'total'          => $quote['total'],
                'notes'          => (string) ($data['notes'] ?? ''),
                'created_by'     => $context->userId,
                // Whose watch this happened on. Null when nobody opened a till,
                // which is allowed — a POS that refuses money because a button
                // was missed is worse than a gap in a report — but the close
                // counts these so the gap is visible rather than assumed away.
                // Required, not merely recorded. An order taken with no
                // till open belongs to nobody and appears in no count,
                // which is the exact shape of the sale this feature
                // exists to catch — so it is refused instead.
                'shift_id'       => Shifts::require($context->restaurantId),
            ]);

            foreach ($quote['lines'] as $line) {
                Database::insert('order_items', $line + [
                    'restaurant_id' => $context->restaurantId,
                    'order_id'      => $orderId,
                ]);
            }

            Audit::log($context, 'orders', 'order_created', $orderId);

            if ($paymentMethod !== null) {
                Database::insert('order_payments', [
                    'restaurant_id' => $context->restaurantId,
                    'order_id'      => $orderId,
                    'method'        => $paymentMethod,
                    'amount'        => $quote['total'],
                    'reference'     => (string) ($data['payment_reference'] ?? ''),
                    'received_by'   => $context->userId,
                ]);

                self::creditAccount(
                    $context,
                    (string) $paymentMethod,
                    (float) $quote['total'],
                    sprintf('Order #%d', $orderNumber),
                    $orderId,
                );

                Audit::log(
                    $context,
                    'orders',
                    'payment_added',
                    $orderId,
                    field: 'payment',
                    newValue: sprintf('%s · %s', $paymentMethod, number_format($quote['total'], 0)),
                );
            }

            // Credit and wallet. Both run against the customer's account rather
            // than the till, and both can leave the order unpaid — which is now
            // a state the order can hold rather than a contradiction.
            if ($customerId !== null && $mode !== 'cash') {
                self::chargeCustomer(
                    $context,
                    $customerId,
                    (float) $quote['total'],
                    $mode,
                    $orderId,
                    $orderNumber,
                );
            }

            if ($tableId !== null && in_array($status, self::OPEN_STATUSES, true)) {
                Database::run(
                    'UPDATE `tables` SET status = "occupied", current_order_id = :oid
                      WHERE id = :id AND restaurant_id = :rid',
                    ['oid' => $orderId, 'id' => $tableId, 'rid' => $context->restaurantId],
                );
            }

            // Paid at the counter: the sale is done the moment it is settled,
            // rather than sitting in `preparing` until somebody notices. An
            // order taken without payment stays open for the kitchen.
            self::settleIfFullyPaid($context, $orderId);

            $created = OrderRepository::find($context->restaurantId, $orderId, withHistory: true);

            return $created ?? [];
        });
    }

    /**
     * Status transition. Cancelling requires a reason — enforced here, by the
     * schema CHECK, and by the client, because a blank reason in the audit
     * trail is worse than no trail at all.
     *
     * @return array<string,mixed>
     */
    public function updateStatus(Request $request, AuthContext $context): array
    {
        $data = Validator::check($request->all(), [
            'status' => 'required|string|in:pending,preparing,ready,completed,cancelled',
            'reason' => 'nullable|string|max:255',
        ]);

        $orderId = $request->intParam('id');
        $order = self::requireScoped('orders', $orderId, $context->restaurantId, 'Order not found');

        // Cancelling refunds, which moves a till. On a counted evening that
        // till is closed and its variance already explained.
        Shifts::requireOpen($context->restaurantId, $order['shift_id'] ?? null);

        $newStatus = (string) $data['status'];
        $oldStatus = (string) $order['status'];
        $reason = isset($data['reason']) ? trim((string) $data['reason']) : '';

        if ($newStatus === $oldStatus) {
            return OrderRepository::find($context->restaurantId, $orderId, withHistory: true) ?? [];
        }

        if ($newStatus === 'cancelled') {
            $context->require('orders.cancel');
            if ($reason === '') {
                throw ApiException::validation(
                    ['reason' => 'A cancellation reason is required'],
                );
            }
        } else {
            $context->require('orders.edit');
        }

        // Cancelled is terminal — reviving a voided order would resurrect
        // revenue somebody deliberately removed.
        if ($oldStatus === 'cancelled') {
            throw ApiException::conflict('Order is already cancelled and cannot change status');
        }

        // Completed is terminal in one direction only. It cannot be walked
        // back into the kitchen, but it can be cancelled: a mistake found
        // after payment is exactly the case that needs voiding, and refusing
        // left the till with a sale nobody could remove. The money does not
        // stay behind — the reversal below takes it out of the account it
        // landed in.
        if ($oldStatus === 'completed' && $newStatus !== 'cancelled') {
            throw ApiException::conflict(
                'A completed order can only be cancelled, not reopened',
            );
        }

        Database::transaction(function () use ($context, $orderId, $order, $newStatus, $oldStatus, $reason): void {
            Database::run(
                'UPDATE orders
                    SET status = :status, cancel_reason = :reason
                  WHERE id = :id AND restaurant_id = :rid',
                [
                    'status' => $newStatus,
                    'reason' => $newStatus === 'cancelled' ? $reason : null,
                    'id'     => $orderId,
                    'rid'    => $context->restaurantId,
                ],
            );

            // A cancelled order owes nothing. §5 asks for the debt to be gone,
            // and it goes by being reversed rather than erased — the customer
            // can still see that they ordered, that it was cancelled, and why.
            if ($newStatus === 'cancelled') {
                $charged = self::chargedSoFar($context, $orderId);

                if (abs($charged) > 0.001) {
                    self::syncCustomer(
                        $context,
                        $orderId,
                        -$charged,
                        'refund',
                        'Dalab la joojiyay',
                        $reason,
                    );
                }

                // And the cash. Reversing only the customer's debt was enough
                // while cancelling was limited to unpaid orders; now that a
                // paid one can be voided, money that already reached a till
                // has to leave it, or the day keeps takings for food that was
                // struck off — which is the easiest books-cooking there is.
                self::refundPayments($context, $orderId, $reason);
            }

            // Leaving an open status frees the table for the next party.
            if ($order['table_id'] !== null && !in_array($newStatus, self::OPEN_STATUSES, true)) {
                Database::run(
                    'UPDATE `tables`
                        SET status = "available", current_order_id = NULL
                      WHERE id = :id AND restaurant_id = :rid AND current_order_id = :oid',
                    ['id' => (int) $order['table_id'], 'rid' => $context->restaurantId, 'oid' => $orderId],
                );
            }

            Audit::log(
                $context,
                'orders',
                'order_status_changed',
                $orderId,
                field: 'status',
                oldValue: $oldStatus,
                newValue: $newStatus,
                reason: $reason === '' ? null : $reason,
            );
        });

        return OrderRepository::find($context->restaurantId, $orderId, withHistory: true) ?? [];
    }

    /**
     * Puts an existing order onto a customer's account.
     *
     * The other half of making unpaid orders accountable. Reporting them was
     * the first step — an order left owing with nobody named now shows up
     * rather than hiding in the gap between sales and cash — but showing a
     * problem with no way to resolve it is only half an answer. This is the
     * way: name who is carrying it.
     *
     * Only what is genuinely outstanding moves. An order already part-paid at
     * the till puts the remainder on the tab, not the whole total, so the
     * customer is never charged for money the restaurant already has.
     *
     * @return array<string,mixed>
     */
    public function attachCustomer(Request $request, AuthContext $context): array
    {
        $data = Validator::check($request->all(), [
            'customer_id' => 'required|int|min:1',
            // Moving a debt onto somebody is exactly the kind of entry that
            // needs to answer "why" a month later.
            'reason'      => 'required|string|min:3|max:255',
        ]);

        $orderId = $request->intParam('id');
        $order = self::requireScoped('orders', $orderId, $context->restaurantId, 'Order not found');

        if ((string) $order['status'] === 'cancelled') {
            throw ApiException::conflict('A cancelled order cannot be put on an account');
        }

        // Moving an order between accounts would mean reversing one ledger and
        // charging another, and getting that wrong moves real debt onto the
        // wrong person. Refused rather than half-supported: cancel and re-ring
        // is the safe path, and it leaves a trail.
        if ($order['customer_id'] !== null) {
            throw ApiException::conflict(
                'This order is already on an account. Cancel it and ring it up again to change who carries it.',
            );
        }

        $customerId = (int) $data['customer_id'];
        $reason = trim((string) $data['reason']);

        Database::transaction(function () use ($context, $orderId, $customerId, $reason): void {
            $customer = Database::selectOne(
                'SELECT id, name, balance_owed, credit_limit, is_active FROM customers
                  WHERE id = :id AND restaurant_id = :rid FOR UPDATE',
                ['id' => $customerId, 'rid' => $context->restaurantId],
            );

            if ($customer === null) {
                throw ApiException::notFound('Customer not found');
            }

            if ((int) $customer['is_active'] !== 1) {
                throw ApiException::unprocessable(sprintf(
                    '%s is a closed account and cannot be charged',
                    (string) $customer['name'],
                ));
            }

            $order = Database::selectOne(
                'SELECT order_number, total FROM orders
                  WHERE id = :id AND restaurant_id = :rid FOR UPDATE',
                ['id' => $orderId, 'rid' => $context->restaurantId],
            );

            $paid = (float) Database::scalar(
                'SELECT COALESCE(SUM(amount), 0) FROM order_payments
                  WHERE order_id = :id AND restaurant_id = :rid',
                ['id' => $orderId, 'rid' => $context->restaurantId],
            );

            $owing = Pricing::round((float) $order['total'] - $paid);

            if ($owing <= 0.001) {
                throw ApiException::unprocessable(
                    'This order is fully paid — there is nothing to put on an account',
                );
            }

            $after = Pricing::round((float) $customer['balance_owed'] + $owing);
            $limit = Pricing::round((float) $customer['credit_limit']);

            if ($after > $limit + 0.001) {
                throw ApiException::unprocessable(sprintf(
                    'This would put %s at %s against a credit limit of %s',
                    (string) $customer['name'],
                    number_format($after, 0),
                    number_format($limit, 0),
                ));
            }

            Database::run(
                'UPDATE orders SET customer_id = :cid WHERE id = :id AND restaurant_id = :rid',
                ['cid' => $customerId, 'id' => $orderId, 'rid' => $context->restaurantId],
            );

            // Written through syncCustomer so it lands in the ledger exactly
            // like a credit sale does — same shape, same source, so the profile
            // and the reconciliation script need to know nothing new.
            self::syncCustomer(
                $context,
                $orderId,
                $owing,
                'charge',
                'Dalab dayn loo rogay',
                $reason,
            );

            Audit::log(
                $context,
                'orders',
                'order_put_on_account',
                $orderId,
                field: 'customer_id',
                oldValue: null,
                newValue: (string) $customerId,
                reason: $reason,
            );
        });

        self::settleIfFullyPaid($context, $orderId);

        return OrderRepository::find($context->restaurantId, $orderId, withHistory: true) ?? [];
    }
    /**
     * Replaces an order's lines and reprices it.
     *
     * A completed order can still change — see the note below. Only a cancelled
     * one is refused, because editing it would resurrect revenue somebody
     * deliberately voided.
     *
     * Every line-level difference is audited individually, because "the order
     * changed" is useless to a manager asking why the total moved.
     *
     * @return array<string,mixed>
     */
    public function updateItems(Request $request, AuthContext $context): array
    {
        // The reason is required, not optional. §21 wants every line change to
        // answer "why did the total move", and an audit row that says a
        // quantity went 2 → 3 with no reason is the one a manager cannot use.
        $data = Validator::check($request->all(), [
            'items'    => 'required|array|min:1',
            'discount' => 'nullable|numeric|min:0',
            'reason'   => 'required|string|min:3|max:255',
        ]);

        $orderId = $request->intParam('id');
        $order = self::requireScoped('orders', $orderId, $context->restaurantId, 'Order not found');

        // A counted evening is settled. Editing an order inside one moves
        // the total its count was measured against, and nothing recomputes —
        // the reconciliation just quietly stops being true.
        Shifts::requireOpen($context->restaurantId, $order['shift_id'] ?? null);

        // §47 does not forbid editing a completed order — it requires that the
        // change be recorded with an old value, a new value, a user and a
        // reason, which is exactly what this method already writes. Refusing
        // outright left a counter mistake uncorrectable the moment payment was
        // taken, which since orders complete on payment is nearly always.
        //
        // Cancelled is different: that order is finished, and reviving it by
        // editing its lines would resurrect revenue somebody deliberately
        // voided.
        if ((string) $order['status'] === 'cancelled') {
            throw ApiException::conflict('A cancelled order cannot be edited');
        }

        $paid = (float) Database::scalar(
            'SELECT COALESCE(SUM(amount), 0) FROM order_payments
              WHERE order_id = :id AND restaurant_id = :rid',
            ['id' => $orderId, 'rid' => $context->restaurantId],
        );

        $settings = self::settings($context->restaurantId);
        /** @var list<array{menu_item_id:int,quantity:int}> $items */
        $items = $data['items'];

        $quote = Pricing::quote(
            $context->restaurantId,
            $items,
            (string) $order['order_type'],
            (float) ($data['discount'] ?? $order['discount']),
            $settings,
        );

        // Taking items off an order that is already paid leaves the restaurant
        // holding money for food it did not serve. This used to be refused
        // outright, which made a counter mistake uncorrectable the moment
        // payment was taken — and since orders complete on payment, that is
        // nearly always. It is allowed now, and the difference goes back out of
        // the till below rather than staying in the day's takings.
        $overpaid = Pricing::round($paid - (float) $quote['total']);

        $before = Database::select(
            'SELECT menu_item_id, item_name, quantity FROM order_items
              WHERE order_id = :id AND restaurant_id = :rid',
            ['id' => $orderId, 'rid' => $context->restaurantId],
        );

        $reason = isset($data['reason']) ? trim((string) $data['reason']) : null;

        Database::transaction(function () use (
            $context, $orderId, $order, $quote, $before, $reason
        ): void {
            Database::run(
                'DELETE FROM order_items WHERE order_id = :id AND restaurant_id = :rid',
                ['id' => $orderId, 'rid' => $context->restaurantId],
            );

            foreach ($quote['lines'] as $line) {
                Database::insert('order_items', $line + [
                    'restaurant_id' => $context->restaurantId,
                    'order_id'      => $orderId,
                ]);
            }

            Database::updateScoped(
                'orders',
                [
                    'subtotal'      => $quote['subtotal'],
                    'discount'      => $quote['discount'],
                    'tax_rate'      => $quote['tax_rate'],
                    'tax_amount'    => $quote['tax_amount'],
                    'packaging_fee' => $quote['packaging_fee'],
                    'total'         => $quote['total'],
                ],
                $orderId,
                $context->restaurantId,
            );

            self::auditLineChanges($context, $orderId, $before, $quote['lines'], $reason);

            if ((float) $order['total'] !== $quote['total']) {
                Audit::log(
                    $context,
                    'orders',
                    'order_total_changed',
                    $orderId,
                    field: 'total',
                    oldValue: (string) $order['total'],
                    newValue: (string) $quote['total'],
                    reason: $reason,
                );
            }

            // Inside the transaction, not after it. syncCustomer refuses a
            // charge that would pass the credit limit, and that refusal has to
            // take the item changes with it — an edit that grew the order and
            // then failed to charge for it would leave the food recorded and
            // the debt not.
            //
            // Anything charged to a customer moves with the total, as a further
            // charge or a refund, never by editing what was already recorded.
            // §5: 100 raised to 500 adds 400; 500 dropped to 300 gives 200 back.
            $charged = self::chargedSoFar($context, $orderId);
            if (abs($charged) > 0.001) {
                $delta = Pricing::round($quote['total'] - $charged);

                self::syncCustomer(
                    $context,
                    $orderId,
                    $delta,
                    $delta > 0 ? 'charge' : 'refund',
                    $delta > 0 ? 'Dalab la kordhiyay' : 'Dalab la dhimay',
                    $reason,
                );
            }
        });

        // Money taken at the till for food now struck off the order goes back
        // out of it. Only the cash side: anything charged to a customer account
        // was already given back by syncCustomer just above, and refunding it
        // here as well would hand the same money over twice.
        if ($overpaid > 0.001) {
            self::refundToTill(
                $context,
                $orderId,
                $overpaid,
                'Celin — alaab laga saaray',
                $reason ?? '',
            );
        }

        // Where the order stands may have moved with the total. Adding a dish to
        // a settled order leaves money owed; removing one until the takings
        // cover it settles it. Deriving this from the payments keeps one rule in
        // charge of completion.
        self::restate($context, $orderId);

        return OrderRepository::find($context->restaurantId, $orderId, withHistory: true) ?? [];
    }

    /**
     * Moves a customer's balance to match a changed order total.
     *
     * §5. The original charge is never touched — a compensating entry is added
     * instead, so the trail reads "charged 100, then 400 more" rather than
     * quietly becoming "charged 500" and losing the fact that it changed. A
     * cancellation reverses the whole thing the same way.
     *
     * Does nothing for an order that was never on an account.
     */
    private static function syncCustomer(
        AuthContext $context,
        int $orderId,
        float $delta,
        string $kind,
        string $description,
        ?string $reason = null,
    ): void {
        if (abs($delta) <= 0.001) {
            return;
        }

        $order = Database::selectOne(
            'SELECT customer_id, order_number FROM orders
              WHERE id = :id AND restaurant_id = :rid',
            ['id' => $orderId, 'rid' => $context->restaurantId],
        );

        if ($order === null || $order['customer_id'] === null) {
            return;
        }

        $customerId = (int) $order['customer_id'];

        $customer = Database::selectOne(
            'SELECT name, balance_owed, credit_limit FROM customers
              WHERE id = :id AND restaurant_id = :rid FOR UPDATE',
            ['id' => $customerId, 'rid' => $context->restaurantId],
        );

        if ($customer === null) {
            return;
        }

        $after = Pricing::round((float) $customer['balance_owed'] + $delta);

        // The credit limit is not only a checkout rule. Editing an order upward
        // charges the customer exactly as a new order does, and this path had
        // no check at all: an order inside the limit could be edited to ten
        // times the size and walk the balance to six times what the restaurant
        // agreed to lend, silently.
        //
        // Only a charge is tested. A refund reduces what is owed, and refusing
        // one because the customer is over their limit would trap them there.
        if ($delta > 0.001) {
            $limit = Pricing::round((float) $customer['credit_limit']);

            if ($after > $limit + 0.001) {
                throw ApiException::unprocessable(sprintf(
                    'This would put %s at %s against a credit limit of %s',
                    (string) $customer['name'],
                    number_format($after, 0),
                    number_format($limit, 0),
                ));
            }
        }

        Database::insert('customer_ledger', [
            'restaurant_id' => $context->restaurantId,
            'customer_id'   => $customerId,
            'kind'          => $kind,
            'amount'        => Pricing::round($delta),
            'balance_after' => $after,
            'description'   => sprintf('%s · Order #%d', $description, (int) $order['order_number']),
            'source_type'   => 'order',
            'source_id'     => $orderId,
            'reason'        => $reason,
            'created_by'    => $context->userId,
        ]);

        Database::run(
            'UPDATE customers SET balance_owed = :b WHERE id = :id AND restaurant_id = :rid',
            ['b' => $after, 'id' => $customerId, 'rid' => $context->restaurantId],
        );

        Audit::log(
            $context,
            'customers',
            'customer_' . $kind,
            $customerId,
            field: 'balance_owed',
            oldValue: (string) $customer['balance_owed'],
            newValue: (string) $after,
            reason: $reason,
        );
    }

    /**
     * What the customer has already been charged for this order.
     *
     * The sum of its ledger entries, so an order charged 100 and later topped
     * up by 400 reports 500 — which is what a reversal has to undo.
     */
    private static function chargedSoFar(AuthContext $context, int $orderId): float
    {
        return Pricing::round((float) Database::scalar(
            'SELECT COALESCE(SUM(amount), 0) FROM customer_ledger
              WHERE restaurant_id = :rid AND source_type = "order" AND source_id = :id',
            ['rid' => $context->restaurantId, 'id' => $orderId],
        ));
    }

    /**
     * Re-derives an edited order's status from what has been paid against it.
     */
    private static function restate(AuthContext $context, int $orderId): void
    {
        $order = Database::selectOne(
            'SELECT status, total FROM orders WHERE id = :id AND restaurant_id = :rid',
            ['id' => $orderId, 'rid' => $context->restaurantId],
        );

        if ($order === null || (string) $order['status'] === 'cancelled') {
            return;
        }

        // One call, unconditionally. settleIfFullyPaid re-derives payment_status
        // from the payments and closes the order out if the money is now in, so
        // every case is already handled there and deciding here which cases are
        // worth calling it for only creates cases it never gets called for —
        // which is exactly what happened: an order that was completed and then
        // edited back down to a covered total matched neither branch and kept a
        // stale `partial` against takings that had settled it.
        //
        // The status itself never moves backwards. A completed order stays
        // completed: the kitchen finished, and that is what `status` records.
        // Whether the money arrived is `payment_status`. This used to bounce a
        // re-opened order to `preparing`, which put a finished sale back in the
        // kitchen queue to answer a question about money.
        self::settleIfFullyPaid($context, $orderId);
    }

    /**
     * One audit entry per line that appeared, disappeared or changed quantity.
     *
     * @param list<array<string,mixed>> $before
     * @param list<array<string,mixed>> $after
     */
    private static function auditLineChanges(
        AuthContext $context,
        int $orderId,
        array $before,
        array $after,
        ?string $reason,
    ): void {
        $old = [];
        foreach ($before as $line) {
            $old[(int) $line['menu_item_id']] = [
                'name'     => (string) $line['item_name'],
                'quantity' => (int) $line['quantity'],
            ];
        }

        $new = [];
        foreach ($after as $line) {
            $new[(int) $line['menu_item_id']] = [
                'name'     => (string) $line['item_name'],
                'quantity' => (int) $line['quantity'],
            ];
        }

        foreach ($new as $itemId => $line) {
            if (!isset($old[$itemId])) {
                Audit::log(
                    $context,
                    'orders',
                    'item_added',
                    $orderId,
                    field: 'items',
                    newValue: sprintf('%s × %d', $line['name'], $line['quantity']),
                    reason: $reason,
                );
            } elseif ($old[$itemId]['quantity'] !== $line['quantity']) {
                Audit::log(
                    $context,
                    'orders',
                    'quantity_changed',
                    $orderId,
                    field: $line['name'],
                    oldValue: (string) $old[$itemId]['quantity'],
                    newValue: (string) $line['quantity'],
                    reason: $reason,
                );
            }
        }

        foreach ($old as $itemId => $line) {
            if (!isset($new[$itemId])) {
                Audit::log(
                    $context,
                    'orders',
                    'item_removed',
                    $orderId,
                    field: 'items',
                    oldValue: sprintf('%s × %d', $line['name'], $line['quantity']),
                    reason: $reason,
                );
            }
        }
    }

    /**
     * Adds a payment to an existing order.
     *
     * @return array<string,mixed>
     */
    public function addPayment(Request $request, AuthContext $context): array
    {
        $data = Validator::check($request->all(), [
            'method'    => 'required|string|in:cash,zaad,edahab,bank',
            'amount'    => 'required|numeric|min:0.01',
            'reference' => 'nullable|string|max:100',
        ]);

        // Taking money needs an open till, for the same reason selling does:
        // cash handed over with nothing open goes into a drawer that nobody is
        // counting tonight.
        Shifts::require($context->restaurantId);

        $orderId = $request->intParam('id');
        $order = self::requireScoped('orders', $orderId, $context->restaurantId, 'Order not found');

        if ((string) $order['status'] === 'cancelled') {
            throw ApiException::conflict('A cancelled order cannot take payment');
        }

        // Money against a counted evening would land in a drawer that has
        // already been reconciled and closed.
        Shifts::requireOpen($context->restaurantId, $order['shift_id'] ?? null);

        $paid = (float) Database::scalar(
            'SELECT COALESCE(SUM(amount), 0) FROM order_payments
              WHERE order_id = :id AND restaurant_id = :rid',
            ['id' => $orderId, 'rid' => $context->restaurantId],
        );
        $amount = (float) $data['amount'];
        $outstanding = Pricing::round((float) $order['total'] - $paid);

        if ($amount > $outstanding + 0.001) {
            throw ApiException::validation([
                'amount' => sprintf('Exceeds the outstanding balance of %s', number_format($outstanding, 2)),
            ]);
        }

        Database::transaction(function () use ($context, $orderId, $order, $data, $amount): void {
            Database::insert('order_payments', [
                'restaurant_id' => $context->restaurantId,
                'order_id'      => $orderId,
                'method'        => (string) $data['method'],
                'amount'        => $amount,
                'reference'     => (string) ($data['reference'] ?? ''),
                'received_by'   => $context->userId,
            ]);

            self::creditAccount(
                $context,
                (string) $data['method'],
                $amount,
                sprintf('Order #%d', (int) $order['order_number']),
                $orderId,
            );

            Audit::log(
                $context,
                'orders',
                'payment_added',
                $orderId,
                field: 'payment',
                newValue: sprintf('%s · %s', (string) $data['method'], number_format($amount, 0)),
            );

            // An order that went on a customer's account is owed on their
            // ledger, not on the order. Taking cash for it here without
            // touching the ledger left them still owing the whole amount while
            // the order read paid — the same money counted twice, once as
            // takings and once as a receivable.
            //
            // Capped at what this order actually put on the ledger: an order
            // the customer paid cash for from the start has nothing there, and
            // handing them a credit would invent one.
            $charged = self::chargedSoFar($context, $orderId);
            if ($charged > 0.001) {
                self::syncCustomer(
                    $context,
                    $orderId,
                    -min($amount, $charged),
                    'payment',
                    'Dayn bixin',
                );
            }

            // Eat first, pay after: this is the payment that finishes the job.
            self::settleIfFullyPaid($context, $orderId);
        });

        return OrderRepository::find($context->restaurantId, $orderId, withHistory: true) ?? [];
    }

    /**
     * Posts money into the matching account and records the movement, so the
     * Accounts screen reconciles with takings without a nightly job.
     */
    public static function creditAccount(
        AuthContext $context,
        string $method,
        float $amount,
        string $description,
        int $sourceId,
    ): void {
        $account = Database::selectOne(
            // FOR UPDATE, like every other balance read in this file. Without it
            // two tills taking payment at the same moment both read the same
            // balance and the second write silently discards the first — money
            // that vanishes from the account while its movement row remains.
            'SELECT id, balance FROM accounts
              WHERE restaurant_id = :rid AND method = :method
              ORDER BY id ASC LIMIT 1 FOR UPDATE',
            ['rid' => $context->restaurantId, 'method' => $method],
        );

        if ($account === null) {
            $accountId = Database::insert('accounts', [
                'restaurant_id' => $context->restaurantId,
                'method'        => $method,
                'name'          => ucfirst($method),
                'balance'       => 0,
            ]);
            $balance = 0.0;
        } else {
            $accountId = (int) $account['id'];
            $balance = (float) $account['balance'];
        }

        $newBalance = Pricing::round($balance + $amount);

        Database::run(
            'UPDATE accounts SET balance = :balance WHERE id = :id AND restaurant_id = :rid',
            ['balance' => $newBalance, 'id' => $accountId, 'rid' => $context->restaurantId],
        );

        Database::insert('account_transactions', [
            'restaurant_id' => $context->restaurantId,
            'account_id'    => $accountId,
            'kind'          => 'money_in',
            'amount'        => $amount,
            'balance_after' => $newBalance,
            'description'   => $description,
            'source_type'   => 'order',
            'source_id'     => $sourceId,
            'created_by'    => $context->userId,
            'shift_id'      => Shifts::currentFor($context->restaurantId, (int) ($accountId)),
        ]);
    }

    /**
     * Takes back out of the tills whatever a cancelled order put into them.
     *
     * One `money_out` per payment, against the account that method resolves to,
     * so the trail reads as a refund rather than as money that quietly went
     * missing. The payment rows themselves are left alone: they are the record
     * that the customer did pay, and deleting them would leave the refund
     * pointing at nothing.
     *
     * `wallet` is skipped on purpose. That money never entered a till — it came
     * off the customer's deposit, and the ledger refund has already put it
     * back. Paying it out again here would hand the customer their deposit
     * twice.
     */
    private static function refundPayments(
        AuthContext $context,
        int $orderId,
        string $reason,
    ): void {
        $payments = Database::select(
            'SELECT method, SUM(amount) AS amount
               FROM order_payments
              WHERE order_id = :id AND restaurant_id = :rid AND method <> "wallet"
              GROUP BY method',
            ['id' => $orderId, 'rid' => $context->restaurantId],
        );

        $order = Database::selectOne(
            'SELECT order_number FROM orders WHERE id = :id AND restaurant_id = :rid',
            ['id' => $orderId, 'rid' => $context->restaurantId],
        );

        foreach ($payments as $payment) {
            self::refundToTill(
                $context,
                $orderId,
                Pricing::round((float) $payment['amount']),
                sprintf(
                    'Celin — dalab #%d la joojiyay',
                    (int) ($order['order_number'] ?? 0),
                ),
                $reason,
                (string) $payment['method'],
            );
        }
    }

    /**
     * Pays one amount back out of a till, with a movement to show for it.
     *
     * Shared by the two ways money can stop belonging to the restaurant: an
     * order cancelled after payment, and items taken off an order that was
     * already paid for. Both are refunds, and both have to be visible on the
     * Accounts screen — a balance that simply drops is indistinguishable from
     * a theft.
     *
     * [method] picks the till. Null means "wherever this order's money went",
     * which is what the edit path wants: it knows an amount but not which of
     * several payments it should come off.
     */
    private static function refundToTill(
        AuthContext $context,
        int $orderId,
        float $amount,
        string $description,
        string $reason,
        ?string $method = null,
    ): void {
        if ($amount <= 0.001) {
            return;
        }

        $method ??= (string) (Database::scalar(
            'SELECT method FROM order_payments
              WHERE order_id = :id AND restaurant_id = :rid AND method <> "wallet"
              ORDER BY amount DESC LIMIT 1',
            ['id' => $orderId, 'rid' => $context->restaurantId],
        ) ?? 'cash');

        $account = Database::selectOne(
            'SELECT id, balance FROM accounts
              WHERE restaurant_id = :rid AND method = :method
              ORDER BY id ASC LIMIT 1 FOR UPDATE',
            ['rid' => $context->restaurantId, 'method' => $method],
        );

        // No account for that method any more — it was removed after the sale.
        // The refund is still owed, so it is recorded against whichever till it
        // would go back through rather than dropped silently.
        $account ??= Database::selectOne(
            'SELECT id, balance FROM accounts
              WHERE restaurant_id = :rid AND is_active = 1
              ORDER BY id ASC LIMIT 1 FOR UPDATE',
            ['rid' => $context->restaurantId],
        );

        if ($account === null) {
            return;
        }

        // The order gave money back, so the order has to say so.
        //
        // Until now this moved the till and the ledger and left order_payments
        // untouched, which left an order recording 110,000 collected against a
        // 40,000 bill while only 40,000 of it was still in the drawer. The
        // Payment-method report sums these rows, so it overstated cash by the
        // refund — while the shift, which derives from the ledger, had it
        // right. Two screens disagreeing about the same money is the worst
        // possible answer, because neither can be trusted afterwards.
        //
        // A negative row rather than deleting the original: what was taken and
        // what was handed back are two separate facts, and the trail has to
        // hold both.
        Database::insert('order_payments', [
            'restaurant_id' => $context->restaurantId,
            'order_id'      => $orderId,
            'method'        => $method,
            'amount'        => -$amount,
            'reference'     => substr($description, 0, 100),
            'received_by'   => $context->userId,
        ]);

        $balance = Pricing::round((float) $account['balance'] - $amount);

        Database::run(
            'UPDATE accounts SET balance = :b WHERE id = :id AND restaurant_id = :rid',
            ['b' => $balance, 'id' => $account['id'], 'rid' => $context->restaurantId],
        );

        Database::insert('account_transactions', [
            'restaurant_id' => $context->restaurantId,
            'account_id'    => (int) $account['id'],
            'kind'          => 'money_out',
            'amount'        => $amount,
            'balance_after' => $balance,
            'description'   => $description,
            'source_type'   => 'order',
            'source_id'     => $orderId,
            'created_by'    => $context->userId,
            'shift_id'      => Shifts::currentFor($context->restaurantId, (int) $account['id']),
        ]);

        Audit::log(
            $context,
            'orders',
            'order_refunded',
            $orderId,
            field: 'refund',
            newValue: sprintf('%s · %s', $method, number_format($amount, 0)),
            reason: $reason === '' ? null : $reason,
        );
    }

    /**
     * Completes an order once the money is actually in.
     *
     * Both payment paths end here: the method handed over at checkout, and a
     * payment taken later against an order the kitchen already started. The
     * one that clears the balance is the one that completes the order, so
     * "pay now" and "pay after eating" finish in the same place without
     * either caller having to decide it — and a half-paid order never
     * completes just because somebody pressed a button.
     *
     * @return bool whether this call was the one that completed it
     */
    private static function settleIfFullyPaid(AuthContext $context, int $orderId): bool
    {
        $order = Database::selectOne(
            'SELECT status, payment_status, total, table_id, customer_id FROM orders
              WHERE id = :id AND restaurant_id = :rid',
            ['id' => $orderId, 'rid' => $context->restaurantId],
        );

        if ($order === null) {
            return false;
        }

        $paid = (float) Database::scalar(
            'SELECT COALESCE(SUM(amount), 0) FROM order_payments
              WHERE order_id = :id AND restaurant_id = :rid',
            ['id' => $orderId, 'rid' => $context->restaurantId],
        );

        // Rounded before comparing: several part-payments summed as floats do
        // not always land exactly on the total, and an order short by a
        // hundredth of a shilling is paid.
        $outstanding = Pricing::round((float) $order['total'] - $paid);
        $settled = $outstanding <= 0.001;

        // Payment status is recorded whatever the kitchen is doing, and it is
        // the only place the money question is answered.
        $payment = $settled ? 'paid' : ($paid > 0.001 ? 'partial' : 'unpaid');

        if ($payment !== (string) $order['payment_status']) {
            Database::run(
                'UPDATE orders SET payment_status = :p WHERE id = :id AND restaurant_id = :rid',
                ['p' => $payment, 'id' => $orderId, 'rid' => $context->restaurantId],
            );
        }

        // An order on a customer's account is finished the moment the food is:
        // the money question has already been answered by the ledger, and
        // leaving it in `preparing` would keep the kitchen looking busy.
        if ($order['customer_id'] !== null && !$settled) {
            if (in_array((string) $order['status'], self::OPEN_STATUSES, true)) {
                self::closeOut($context, $orderId, (string) $order['status'], $order['table_id']);
            }

            return false;
        }

        if (!$settled || !in_array((string) $order['status'], self::OPEN_STATUSES, true)) {
            return false;
        }

        self::closeOut($context, $orderId, (string) $order['status'], $order['table_id']);

        return true;
    }

    /**
     * Marks the order finished and hands the table back.
     *
     * Shared by the two ways an order ends: the money arriving, and the food
     * going out on somebody's account. Both free the table, and a second copy
     * of this would be the one that forgot to.
     */
    private static function closeOut(
        AuthContext $context,
        int $orderId,
        string $oldStatus,
        mixed $tableId,
    ): void {
        Database::run(
            'UPDATE orders SET status = "completed" WHERE id = :id AND restaurant_id = :rid',
            ['id' => $orderId, 'rid' => $context->restaurantId],
        );

        if ($tableId !== null) {
            Database::run(
                'UPDATE `tables`
                    SET status = "available", current_order_id = NULL
                  WHERE id = :id AND restaurant_id = :rid AND current_order_id = :oid',
                ['id' => (int) $tableId, 'rid' => $context->restaurantId, 'oid' => $orderId],
            );
        }

        Audit::log(
            $context,
            'orders',
            'order_completed',
            $orderId,
            field: 'status',
            oldValue: $oldStatus,
            newValue: 'completed',
        );
    }

    /**
     * Puts an order on a customer's account.
     *
     * Wallet first when asked for, then credit for whatever is left. §4 case B
     * is the reason it works this way round: a customer with 3,000 on deposit
     * buying 5,000 of food should not be refused, and should not have the whole
     * 5,000 taken as credit either — 3,000 comes off the wallet and 2,000
     * becomes debt, in one movement they can read back later.
     *
     * The customer row is locked for the whole of it, which is what stops two
     * tills each seeing the same wallet and spending it twice.
     */
    private static function chargeCustomer(
        AuthContext $context,
        int $customerId,
        float $total,
        string $mode,
        int $orderId,
        int $orderNumber,
    ): void {
        $customer = Database::selectOne(
            'SELECT id, name, balance_owed, credit_limit, is_active FROM customers
              WHERE id = :id AND restaurant_id = :rid FOR UPDATE',
            ['id' => $customerId, 'rid' => $context->restaurantId],
        );

        if ($customer === null) {
            throw ApiException::notFound('Customer not found');
        }

        // Closing an account is a decision to stop lending to that person. It
        // was enforced only by leaving them out of the picker, which is a
        // curtain rather than a door: the id still worked.
        if ((int) $customer['is_active'] !== 1) {
            throw ApiException::unprocessable(sprintf(
                '%s is a closed account and cannot be charged',
                (string) $customer['name'],
            ));
        }

        $owed = Pricing::round((float) $customer['balance_owed']);
        $limit = Pricing::round((float) $customer['credit_limit']);
        $wallet = $owed < 0 ? -$owed : 0.0;

        // The deposit is spent first whatever the caller asked for, because
        // with one balance column that is not a choice — it is arithmetic.
        // `balance_owed` moves by the full total either way, so a customer at
        // -200,000 who orders 40,000 ends at -160,000 no matter which mode was
        // sent. Treating credit mode as "ignore the wallet" did not stop the
        // deposit being consumed; it only stopped it being *recorded*, so the
        // order sat at unpaid for ever, the receipt printed a balance owing on
        // a settled sale, and nothing explained where the 40,000 went.
        $fromWallet = min($wallet, $total);
        $onCredit = Pricing::round($total - $fromWallet);

        // Checked against the balance this will actually produce, not against
        // the credit portion alone. Those differ whenever the wallet covers
        // part of an order, and the old check used the smaller of the two — so
        // a customer with 5,000 on deposit and a 30,000 limit could be talked
        // up to owing 35,000 and the check would still pass.
        //
        // It has to happen here, inside the lock. Doing it before the
        // transaction lets two tills both read a balance under the limit and
        // both push the customer over it.
        $after = Pricing::round($owed + $total);

        if ($after > $limit + 0.001) {
            throw ApiException::unprocessable(
                $wallet > 0.001
                    ? sprintf(
                        '%s has %s on deposit, which does not cover %s. The rest would put them at %s against a credit limit of %s',
                        (string) $customer['name'],
                        number_format($wallet, 0),
                        number_format($total, 0),
                        number_format($after, 0),
                        number_format($limit, 0),
                    )
                    : sprintf(
                        'This would put %s at %s against a credit limit of %s',
                        (string) $customer['name'],
                        number_format($after, 0),
                        number_format($limit, 0),
                    ),
            );
        }

        Database::insert('customer_ledger', [
            'restaurant_id' => $context->restaurantId,
            'customer_id'   => $customerId,
            'kind'          => 'charge',
            'amount'        => Pricing::round($total),
            'balance_after' => $after,
            // No account_id: nothing reached the till. That absence is what
            // keeps a credit sale out of the day's cash figure.
            'description'   => sprintf('Order #%d', $orderNumber),
            'source_type'   => 'order',
            'source_id'     => $orderId,
            'created_by'    => $context->userId,
        ]);

        Database::run(
            'UPDATE customers SET balance_owed = :b WHERE id = :id AND restaurant_id = :rid',
            ['b' => $after, 'id' => $customerId, 'rid' => $context->restaurantId],
        );

        // Whatever came out of the deposit is a real payment and is recorded as
        // one. The money arrived when they made the deposit; this is that money
        // being spent, and without this row the order reads as unpaid for ever
        // while the deposit it was paid from has quietly gone.
        if ($fromWallet > 0.001) {
            Database::insert('order_payments', [
                'restaurant_id' => $context->restaurantId,
                'order_id'      => $orderId,
                'method'        => 'wallet',
                'amount'        => $fromWallet,
                'reference'     => 'wallet',
                'received_by'   => $context->userId,
            ]);
        }

        Audit::log(
            $context,
            'orders',
            $onCredit > 0.001 ? 'order_on_credit' : 'order_from_wallet',
            $orderId,
            field: 'balance_owed',
            oldValue: (string) $owed,
            newValue: (string) $after,
            // The mode is recorded even though it no longer changes the
            // arithmetic, because it is what the operator chose and an auditor
            // reading this later will want to know what was intended, not only
            // what the balance did.
            reason: sprintf(
                '%s · %s · jeeb %s · dayn %s',
                (string) $customer['name'],
                $mode,
                number_format($fromWallet, 0),
                number_format($onCredit, 0),
            ),
        );
    }

    private static function firstName(string $name): string
    {
        $parts = preg_split('/\s+/', trim($name)) ?: [];

        return $parts[0] ?? $name;
    }
}
