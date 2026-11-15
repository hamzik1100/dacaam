<?php

declare(strict_types=1);

namespace Dacaam\Controllers;

use Dacaam\Core\ApiException;
use Dacaam\Core\Audit;
use Dacaam\Core\Auth;
use Dacaam\Core\AuthContext;
use Dacaam\Core\Database;
use Dacaam\Core\Request;
use Dacaam\Core\Validator;
use Dacaam\Repositories\Repository;
use Dacaam\Support\Shifts;
use Dacaam\Support\Idempotency;
use Dacaam\Support\Pricing;

/**
 * Customer accounts and the ledger behind them.
 *
 * `balance_owed` is positive when the customer owes the restaurant and negative
 * when they are in credit. Every movement is an append-only row in
 * `customer_ledger`; the balance on the customer is a cache of their sum, moved
 * in the same transaction as the row that changes it.
 *
 * Two rules hold everything together, and both are enforced here rather than
 * trusted to callers:
 *
 *   - The customer row is locked FOR UPDATE before its balance is read. Two
 *     tills serving the same person otherwise each read the old balance and
 *     the second write silently discards the first.
 *   - Nothing is ever updated or deleted in the ledger. A correction is an
 *     opposite entry, so the trail explains the balance rather than being
 *     rewritten to match it.
 */
final class CustomerController extends Repository
{
    /** @return list<array<string,mixed>> */
    public function index(Request $request, AuthContext $context): array
    {
        $where = ['c.restaurant_id = :rid'];
        $bind = ['rid' => $context->restaurantId];

        if (($search = trim($request->queryString('search'))) !== '') {
            $where[] = '(c.name LIKE :q OR c.phone LIKE :q)';
            $bind['q'] = '%' . $search . '%';
        }

        // The two lists a manager actually asks for: who owes me, and who has
        // money sitting with me.
        $filter = $request->queryString('filter');
        if ($filter === 'debtors') {
            $where[] = 'c.balance_owed > 0';
        } elseif ($filter === 'wallet') {
            $where[] = 'c.balance_owed < 0';
        }

        if ($request->queryString('include_inactive') !== '1') {
            $where[] = 'c.is_active = 1';
        }

        $rows = Database::select(
            'SELECT c.* FROM customers c
              WHERE ' . implode(' AND ', $where) . '
              ORDER BY c.balance_owed DESC, c.name ASC
              LIMIT 300',
            $bind,
        );

        return array_map([self::class, 'present'], $rows);
    }

    /** @return array<string,mixed> */
    public function show(Request $request, AuthContext $context): array
    {
        $id = $request->intParam('id');
        $customer = self::requireScoped('customers', $id, $context->restaurantId, 'Customer not found');

        return self::present($customer) + [
            'ledger' => $this->ledgerFor($context->restaurantId, $id),
        ];
    }

    /** @return list<array<string,mixed>> */
    public function ledger(Request $request, AuthContext $context): array
    {
        $id = $request->intParam('id');
        self::requireScoped('customers', $id, $context->restaurantId, 'Customer not found');

        return $this->ledgerFor($context->restaurantId, $id);
    }

    /** @return array<string,mixed> */
    public function store(Request $request, AuthContext $context): array
    {
        $data = Validator::check($request->all(), [
            'name'         => 'required|string|min:1|max:150',
            'phone'        => 'nullable|string|max:32',
            'address'      => 'nullable|string|max:255',
            'notes'        => 'nullable|string|max:500',
            'credit_limit' => 'nullable|numeric|min:0|max:100000000',
        ]);

        $phone = self::phoneOrNull((string) ($data['phone'] ?? ''));
        self::requireFreePhone($context->restaurantId, $phone, null);

        $id = Database::insert('customers', [
            'restaurant_id' => $context->restaurantId,
            'name'          => trim((string) $data['name']),
            'phone'         => $phone,
            'address'       => trim((string) ($data['address'] ?? '')),
            'notes'         => trim((string) ($data['notes'] ?? '')),
            'credit_limit'  => Pricing::round((float) ($data['credit_limit'] ?? 0)),
            'created_by'    => $context->userId,
        ]);

        Audit::log($context, 'customers', 'customer_created', $id, newValue: trim((string) $data['name']));

        return self::find($context->restaurantId, $id);
    }

    /** @return array<string,mixed> */
    public function update(Request $request, AuthContext $context): array
    {
        $data = Validator::check($request->all(), [
            'name'         => 'nullable|string|min:1|max:150',
            'phone'        => 'nullable|string|max:32',
            'address'      => 'nullable|string|max:255',
            'notes'        => 'nullable|string|max:500',
            'credit_limit' => 'nullable|numeric|min:0|max:100000000',
            'is_active'    => 'nullable|bool',
            'reason'       => 'nullable|string|max:255',
        ]);

        $id = $request->intParam('id');
        $before = self::requireScoped('customers', $id, $context->restaurantId, 'Customer not found');

        // balance_owed is absent by design. It is the sum of the ledger, and a
        // field that lets it be typed over would make the ledger decorative.
        $update = [];
        foreach (['name', 'address', 'notes'] as $field) {
            if (isset($data[$field])) {
                $update[$field] = trim((string) $data[$field]);
            }
        }
        if (isset($data['phone'])) {
            $phone = self::phoneOrNull((string) $data['phone']);
            self::requireFreePhone($context->restaurantId, $phone, $id);
            $update['phone'] = $phone;
        }
        if (array_key_exists('credit_limit', $data) && $data['credit_limit'] !== null) {
            $update['credit_limit'] = Pricing::round((float) $data['credit_limit']);
        }
        if (array_key_exists('is_active', $data) && $data['is_active'] !== null) {
            $update['is_active'] = $data['is_active'] ? 1 : 0;
        }

        if ($update !== []) {
            $set = implode(', ', array_map(
                static fn (string $c): string => "`$c` = :$c",
                array_keys($update),
            ));

            Database::run(
                "UPDATE customers SET $set WHERE id = :id AND restaurant_id = :rid",
                $update + ['id' => $id, 'rid' => $context->restaurantId],
            );

            // §6: old value, new value, who, when, why — one row per field, so
            // "the credit limit went from 0 to 500,000" is answerable later.
            Audit::diff(
                $context,
                module: 'customers',
                action: 'customer_updated',
                recordId: $id,
                before: $before,
                after: $update,
                fields: array_keys($update),
                reason: isset($data['reason']) ? trim((string) $data['reason']) : null,
            );
        }

        return self::find($context->restaurantId, $id);
    }

    /**
     * Deactivates. A customer with history is never removed — their ledger is
     * part of the restaurant's books.
     *
     * @return array<string,mixed>
     */
    public function destroy(Request $request, AuthContext $context): array
    {
        $id = $request->intParam('id');
        $customer = self::requireScoped('customers', $id, $context->restaurantId, 'Customer not found');

        $balance = Pricing::round((float) $customer['balance_owed']);

        if ($balance !== 0.0) {
            // Which way the balance points changes what has to happen first,
            // and calling both "settle the balance" told somebody holding a
            // customer's deposit to go and collect a debt that does not exist.
            throw ApiException::unprocessable(
                $balance > 0
                    ? sprintf(
                        'Collect the %s owed before closing this account',
                        number_format($balance, 0),
                    )
                    : sprintf(
                        'Refund the %s held on deposit before closing this account',
                        number_format(-$balance, 0),
                    ),
            );
        }

        Database::run(
            'UPDATE customers SET is_active = 0 WHERE id = :id AND restaurant_id = :rid',
            ['id' => $id, 'rid' => $context->restaurantId],
        );

        Audit::log(
            $context,
            'customers',
            'customer_deactivated',
            $id,
            field: 'is_active',
            oldValue: '1',
            newValue: '0',
        );

        return self::find($context->restaurantId, $id);
    }

    // ---------------------------------------------------------- the money

    /**
     * A repayment against what the customer owes.
     *
     * The money is real, so it lands in one of the restaurant's accounts at the
     * same time. This is not new revenue — the sale was already counted when
     * the food went out — it is a receivable turning into cash.
     *
     * @return array<string,mixed>
     */
    public function payment(Request $request, AuthContext $context): array
    {
        $data = Validator::check($request->all(), [
            'amount'      => 'required|numeric|min:0.01',
            'method'      => 'required|string|max:32',
            'description' => 'nullable|string|max:255',
        ]);

        $id = $request->intParam('id');
        $amount = Pricing::round((float) $data['amount']);

        // A repayment settles a debt; it cannot create a deposit. Handing over
        // more than is owed used to be accepted silently and left the customer
        // in credit, so one mistyped zero at the counter became money the
        // restaurant owed back. Taking money in advance is a deposit, and that
        // is a different button.
        $owed = Pricing::round((float) Database::scalar(
            'SELECT COALESCE(balance_owed, 0) FROM customers
              WHERE id = :id AND restaurant_id = :rid',
            ['id' => $id, 'rid' => $context->restaurantId],
        ));

        if ($owed <= 0.001) {
            throw ApiException::validation(
                ['amount' => 'This customer owes nothing — record it as a deposit instead'],
            );
        }

        if ($amount > $owed + 0.001) {
            throw ApiException::validation([
                'amount' => sprintf(
                    'That is more than the %s owed. Take the rest as a deposit if it was handed over.',
                    number_format($owed, 0),
                ),
            ]);
        }

        return Idempotency::once(
            $context->restaurantId,
            self::requestKey($request),
            'customers.payment',
            fn (): array => $this->post(
                $context,
                $id,
                kind: 'payment',
                amount: -$amount,
                method: (string) $data['method'],
                description: (string) ($data['description'] ?? 'Dayn bixin'),
            ),
        );
    }

    /**
     * Money handed over in advance, to be eaten against later.
     *
     * @return array<string,mixed>
     */
    public function deposit(Request $request, AuthContext $context): array
    {
        $data = Validator::check($request->all(), [
            'amount'      => 'required|numeric|min:0.01',
            'method'      => 'required|string|max:32',
            'description' => 'nullable|string|max:255',
        ]);

        return Idempotency::once(
            $context->restaurantId,
            self::requestKey($request),
            'customers.deposit',
            fn (): array => $this->post(
                $context,
                $request->intParam('id'),
                kind: 'deposit',
                amount: -Pricing::round((float) $data['amount']),
                method: (string) $data['method'],
                description: (string) ($data['description'] ?? 'Lacag dhigasho'),
            ),
        );
    }

    /**
     * A balance moved by hand.
     *
     * Guarded by its own permission and a mandatory reason. This is the only
     * way a debt can vanish without a payment, which makes it the first thing
     * an auditor looks at and the last thing that should be casually granted.
     *
     * @return array<string,mixed>
     */
    public function adjust(Request $request, AuthContext $context): array
    {
        $data = Validator::check($request->all(), [
            // Signed: positive adds to what they owe, negative forgives it.
            // Bounded because this is the one figure with no sale behind it:
            // an extra zero here writes off a debt nobody agreed to write off.
            'amount' => 'required|numeric|min:-100000000|max:100000000',
            'reason' => 'required|string|min:3|max:255',
        ]);

        $amount = Pricing::round((float) $data['amount']);
        if ($amount === 0.0) {
            throw ApiException::validation(['amount' => 'An adjustment of zero changes nothing']);
        }

        return Idempotency::once(
            $context->restaurantId,
            self::requestKey($request),
            'customers.adjust',
            fn (): array => $this->post(
                $context,
                $request->intParam('id'),
                kind: 'adjustment',
                amount: $amount,
                method: '',
                description: 'Sixid gacan',
                reason: trim((string) $data['reason']),
            ),
        );
    }

    // ------------------------------------------------------------- engine

    /**
     * Writes one ledger entry and moves the cached balance with it.
     *
     * Everything happens inside a transaction with the customer row locked, so
     * two tills posting at once queue rather than overwrite. `balance_after` is
     * computed from the locked balance, which is what makes the ledger
     * reconstructable line by line.
     *
     * @return array<string,mixed>
     */
    private function post(
        AuthContext $context,
        int $customerId,
        string $kind,
        float $amount,
        string $method,
        string $description,
        ?string $reason = null,
        string $sourceType = 'manual',
        ?int $sourceId = null,
    ): array {
        $restaurantId = $context->restaurantId;

        Database::transaction(function () use (
            $context, $restaurantId, $customerId, $kind, $amount,
            $method, $description, $reason, $sourceType, $sourceId
        ): void {
            $customer = Database::selectOne(
                'SELECT id, balance_owed FROM customers
                  WHERE id = :id AND restaurant_id = :rid FOR UPDATE',
                ['id' => $customerId, 'rid' => $restaurantId],
            );

            if ($customer === null) {
                throw ApiException::notFound('Customer not found');
            }

            $accountId = null;
            if ($method !== '') {
                $accountId = $this->creditAccount($context, $method, $amount, $description, $customerId);
            }

            $after = Pricing::round((float) $customer['balance_owed'] + $amount);

            Database::insert('customer_ledger', [
                'restaurant_id' => $restaurantId,
                'customer_id'   => $customerId,
                'kind'          => $kind,
                'amount'        => $amount,
                'balance_after' => $after,
                'account_id'    => $accountId,
                'method'        => $method,
                'description'   => $description,
                'source_type'   => $sourceType,
                'source_id'     => $sourceId,
                'reason'        => $reason,
                'created_by'    => $context->userId,
            ]);

            Database::run(
                'UPDATE customers SET balance_owed = :b WHERE id = :id AND restaurant_id = :rid',
                ['b' => $after, 'id' => $customerId, 'rid' => $restaurantId],
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
        });

        return self::find($restaurantId, $customerId);
    }

    /**
     * Puts the money into the restaurant's account for that method.
     *
     * A payment or deposit reduces what the customer owes (a negative ledger
     * amount) and increases the till by the same magnitude, so the sign is
     * flipped here. Returns the account it landed in.
     */
    private function creditAccount(
        AuthContext $context,
        string $method,
        float $ledgerAmount,
        string $description,
        int $customerId,
    ): ?int {
        $account = Database::selectOne(
            'SELECT id, balance FROM accounts
              WHERE restaurant_id = :rid AND method = :m AND is_active = 1
              ORDER BY id ASC LIMIT 1 FOR UPDATE',
            ['rid' => $context->restaurantId, 'm' => $method],
        );

        if ($account === null) {
            throw ApiException::validation(['method' => 'That payment method has no account']);
        }

        $cash = Pricing::round(-$ledgerAmount);
        $balance = Pricing::round((float) $account['balance'] + $cash);

        Database::run(
            'UPDATE accounts SET balance = :b WHERE id = :id AND restaurant_id = :rid',
            ['b' => $balance, 'id' => $account['id'], 'rid' => $context->restaurantId],
        );

        Database::insert('account_transactions', [
            'restaurant_id' => $context->restaurantId,
            'account_id'    => (int) $account['id'],
            'kind'          => $cash >= 0 ? 'money_in' : 'money_out',
            'amount'        => abs($cash),
            'balance_after' => $balance,
            'description'   => $description,
            'source_type'   => 'customer',
            'source_id'     => $customerId,
            'created_by'    => $context->userId,
            'shift_id'      => Shifts::currentFor($context->restaurantId, (int) $account['id']),
        ]);

        return (int) $account['id'];
    }

    // ------------------------------------------------------------ helpers

    /**
     * A normalised phone, or null when there is none.
     *
     * The column is nullable for exactly this reason. As far as the unique
     * index is concerned `''` is a value, so storing it would let the first
     * walk-in with no number block every walk-in after them. MySQL permits any
     * number of NULLs in a unique index.
     */
    /**
     * The key the client generated for this one tap, if it sent one.
     *
     * Absent is fine and means "run it": an older APK that knows nothing about
     * this still works, which matters because a shipped build cannot be
     * updated in step with the server.
     */
    private static function requestKey(Request $request): ?string
    {
        $key = $request->input('request_key');

        return is_string($key) && trim($key) !== '' ? trim($key) : null;
    }

    private static function phoneOrNull(string $raw): ?string
    {
        $phone = Auth::normalisePhone($raw);

        return $phone === '' ? null : $phone;
    }

    private static function requireFreePhone(int $restaurantId, ?string $phone, ?int $exceptId): void
    {
        if ($phone === null) {
            return;
        }

        $sql = 'SELECT COUNT(*) FROM customers WHERE restaurant_id = :rid AND phone = :phone';
        $bind = ['rid' => $restaurantId, 'phone' => $phone];

        if ($exceptId !== null) {
            $sql .= ' AND id <> :id';
            $bind['id'] = $exceptId;
        }

        if ((int) Database::scalar($sql, $bind) > 0) {
            throw ApiException::validation(['phone' => 'A customer with that phone already exists']);
        }
    }

    /** @return list<array<string,mixed>> */
    private function ledgerFor(int $restaurantId, int $customerId): array
    {
        $rows = Database::select(
            'SELECT l.*, u.name AS created_by_name,
                    o.order_number, o.status AS order_status,
                    o.payment_status, o.total AS order_total
               FROM customer_ledger l
          LEFT JOIN users u  ON u.id = l.created_by
               -- Only for rows that came from an order. A deposit joins to
               -- nothing and keeps every one of these null, which is what the
               -- client reads to decide whether to show them at all.
          LEFT JOIN orders o ON o.id = l.source_id
                            AND l.source_type = "order"
                            AND o.restaurant_id = l.restaurant_id
              WHERE l.customer_id = :id AND l.restaurant_id = :rid
              ORDER BY l.created_at DESC, l.id DESC
              LIMIT 200',
            ['id' => $customerId, 'rid' => $restaurantId],
        );

        return array_map(
            static fn (array $r): array => [
                'id'            => (int) $r['id'],
                'kind'          => (string) $r['kind'],
                'amount'        => (float) $r['amount'],
                'balance_after' => (float) $r['balance_after'],
                'method'        => (string) $r['method'],
                'description'   => (string) $r['description'],
                'source_type'   => (string) $r['source_type'],
                'source_id'     => $r['source_id'] === null ? null : (int) $r['source_id'],
                'reason'        => $r['reason'] === null ? null : (string) $r['reason'],
                'created_by'    => (string) ($r['created_by_name'] ?? ''),
                // What the order behind this line is doing, so the profile can
                // say whether it was paid, still owed, or voided — without a
                // second request per row.
                'order_number'  => $r['order_number'] === null ? null : (int) $r['order_number'],
                'order_status'  => $r['order_status'] === null ? null : (string) $r['order_status'],
                'payment_status' => $r['payment_status'] === null ? null : (string) $r['payment_status'],
                'order_total'   => $r['order_total'] === null ? null : (float) $r['order_total'],
                'created_at'    => \Dacaam\Support\Presenter::iso($r['created_at']),
            ],
            $rows,
        );
    }

    /** @return array<string,mixed> */
    private static function find(int $restaurantId, int $id): array
    {
        $row = Database::selectOne(
            'SELECT * FROM customers WHERE id = :id AND restaurant_id = :rid',
            ['id' => $id, 'rid' => $restaurantId],
        );

        return $row === null ? [] : self::present($row);
    }

    /**
     * @param  array<string,mixed> $row
     * @return array<string,mixed>
     */
    private static function present(array $row): array
    {
        $owed = (float) $row['balance_owed'];

        return [
            'id'           => (int) $row['id'],
            'name'         => (string) $row['name'],
            'phone'        => (string) ($row['phone'] ?? ''),
            'address'      => (string) $row['address'],
            'notes'        => (string) $row['notes'],
            'credit_limit' => (float) $row['credit_limit'],
            'balance_owed' => $owed,
            // Derived here so every client shows the same thing rather than
            // each one re-deciding what a negative balance means.
            'is_debtor'    => $owed > 0,
            'wallet'       => $owed < 0 ? -$owed : 0.0,
            'is_active'    => (bool) $row['is_active'],
            'created_at'   => \Dacaam\Support\Presenter::iso($row['created_at']),
        ];
    }
}
