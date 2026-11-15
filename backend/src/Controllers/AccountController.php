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
use Dacaam\Support\Shifts;
use Dacaam\Support\Period;
use Dacaam\Support\Pricing;

final class AccountController extends Repository
{
    /** Mirrors the account_transactions.kind ENUM. */
    private const KINDS = ["money_in", "money_out", "transfer", "adjustment"];

    /** @return list<array<string,mixed>> */
    public function index(Request $request, AuthContext $context): array
    {
        // money_in / money_out are today's movements, which is what the
        // Accounts screen shows beside each balance.
        return array_map(
            [Presenter::class, 'account'],
            Database::select(
                'SELECT a.*,
                        COALESCE((SELECT SUM(t.amount) FROM account_transactions t
                                   WHERE t.account_id = a.id AND t.kind = "money_in"
                                     AND DATE(t.created_at) = CURDATE()), 0) AS money_in,
                        COALESCE((SELECT SUM(t.amount) FROM account_transactions t
                                   WHERE t.account_id = a.id AND t.kind = "money_out"
                                     AND DATE(t.created_at) = CURDATE()), 0) AS money_out
                   FROM accounts a
                  WHERE a.restaurant_id = :rid AND a.is_active = 1
                  ORDER BY a.id ASC',
                ['rid' => $context->restaurantId],
            ),
        );
    }

    /** @return list<array<string,mixed>> */
    public function transactions(Request $request, AuthContext $context): array
    {
        $where = ['t.restaurant_id = :rid'];
        $bind = ['rid' => $context->restaurantId];

        if (($accountId = $request->queryInt('account_id')) !== null) {
            $where[] = 't.account_id = :aid';
            $bind['aid'] = $accountId;
        }

        // Money in, money out, transfers, adjustments — the four kinds a
        // manager actually reconciles against, one at a time.
        $kind = $request->queryString('kind');
        if ($kind !== '' && in_array($kind, self::KINDS, true)) {
            $where[] = 't.kind = :kind';
            $bind['kind'] = $kind;
        }

        // `all` skips the date window entirely: a balance query is often "when
        // did this account last move", and clamping it to a week hides that.
        $range = $request->queryString('range', 'all');
        if ($range !== 'all') {
            $period = Period::resolve(
                $range,
                $request->queryString('from'),
                $request->queryString('to'),
            );
            $where[] = 't.created_at BETWEEN :from AND :to';
            $bind['from'] = $period->from->format('Y-m-d H:i:s');
            $bind['to']   = $period->to->format('Y-m-d H:i:s');
        }

        if (($search = trim($request->queryString('search'))) !== '') {
            $where[] = 't.description LIKE :search';
            $bind['search'] = '%' . $search . '%';
        }

        $rows = Database::select(
            'SELECT t.*, a.method, a.name AS account_name, u.name AS created_by_name
               FROM account_transactions t
               JOIN accounts a ON a.id = t.account_id
          LEFT JOIN users u    ON u.id = t.created_by
              WHERE ' . implode(' AND ', $where) . '
              ORDER BY t.created_at DESC, t.id DESC
              LIMIT 200',
            $bind,
        );

        return array_map(
            static fn (array $r): array => [
                'id'            => (int) $r['id'],
                'account_id'    => (int) $r['account_id'],
                'account_name'  => (string) $r['account_name'],
                'method'        => (string) $r['method'],
                'kind'          => (string) $r['kind'],
                'amount'        => (float) $r['amount'],
                'balance_after' => (float) $r['balance_after'],
                'description'   => (string) $r['description'],
                'source_type'   => (string) $r['source_type'],
                'created_by'    => (string) ($r['created_by_name'] ?? ''),
                'created_at'    => Presenter::iso($r['created_at']),
            ],
            $rows,
        );
    }

    /**
     * Account-to-account transfer. Both legs and both balances move inside one
     * transaction — a half-applied transfer would silently invent or destroy
     * money.
     *
     * @return array<string,mixed>
     */
    public function transfer(Request $request, AuthContext $context): array
    {
        $data = Validator::check($request->all(), [
            'from_account_id' => 'required|int|min:1',
            'to_account_id'   => 'required|int|min:1',
            'amount'          => 'required|numeric|min:0.01',
            'description'     => 'nullable|string|max:255',
        ]);

        $fromId = (int) $data['from_account_id'];
        $toId = (int) $data['to_account_id'];

        if ($fromId === $toId) {
            throw ApiException::validation(['to_account_id' => 'Choose a different destination account']);
        }

        $from = self::requireScoped('accounts', $fromId, $context->restaurantId, 'Source account not found');
        $to = self::requireScoped('accounts', $toId, $context->restaurantId, 'Destination account not found');

        $amount = Pricing::round((float) $data['amount']);
        if ((float) $from['balance'] < $amount) {
            throw ApiException::unprocessable('Insufficient balance in the source account');
        }

        $description = (string) ($data['description'] ?? sprintf('%s → %s', $from['name'], $to['name']));

        Database::transaction(function () use ($context, $from, $to, $amount, $description): void {
            $fromBalance = Pricing::round((float) $from['balance'] - $amount);
            $toBalance = Pricing::round((float) $to['balance'] + $amount);

            Database::run(
                'UPDATE accounts SET balance = :b WHERE id = :id AND restaurant_id = :rid',
                ['b' => $fromBalance, 'id' => $from['id'], 'rid' => $context->restaurantId],
            );
            Database::run(
                'UPDATE accounts SET balance = :b WHERE id = :id AND restaurant_id = :rid',
                ['b' => $toBalance, 'id' => $to['id'], 'rid' => $context->restaurantId],
            );

            Database::insert('account_transactions', [
                'restaurant_id' => $context->restaurantId,
                'account_id'    => (int) $from['id'],
                'to_account_id' => (int) $to['id'],
                'kind'          => 'transfer',
                'amount'        => $amount,
                'balance_after' => $fromBalance,
                'description'   => $description,
                'source_type'   => 'transfer',
                'created_by'    => $context->userId,
                'shift_id'      => Shifts::currentFor($context->restaurantId, (int) $from['id']),
            ]);

            // `kind` stays money_in — from this account's own point of view
            // that is what happened, and the Accounts screen should say so.
            // `source_type` is what marks it as the far leg of a transfer, and
            // it is how the cash report knows to leave it out. Without it,
            // shuffling money from the till to the bank read as a sale.
            Database::insert('account_transactions', [
                'restaurant_id' => $context->restaurantId,
                'account_id'    => (int) $to['id'],
                'kind'          => 'money_in',
                'amount'        => $amount,
                'balance_after' => $toBalance,
                'description'   => $description,
                'source_type'   => 'transfer',
                'created_by'    => $context->userId,
                'shift_id'      => Shifts::currentFor($context->restaurantId, (int) $to['id']),
            ]);

            Audit::log(
                $context,
                'accounts',
                'transfer',
                (int) $from['id'],
                field: 'balance',
                oldValue: (string) $from['balance'],
                newValue: (string) $fromBalance,
                reason: $description,
            );
        });

        return ['transferred' => true, 'accounts' => $this->index($request, $context)];
    }

    /**
     * Opens an account against one of the restaurant's payment methods.
     *
     * Two accounts may share a method — a shop with a Dahabshiil account and a
     * Salaam Bank account has two banks, and the old UNIQUE(restaurant_id,
     * method) made that impossible. Names are what must differ.
     *
     * @return array<string,mixed>
     */
    public function store(Request $request, AuthContext $context): array
    {
        $data = Validator::check($request->all(), [
            'name'    => 'required|string|min:1|max:64',
            'method'  => 'required|string|max:32',
            'balance' => 'nullable|numeric|min:0',
        ]);

        $method = (string) $data['method'];
        self::requireMethod($context->restaurantId, $method);

        $name = trim((string) $data['name']);
        self::requireFreeName($context->restaurantId, $name, null);

        // An opening balance is money that already exists in a drawer or on a
        // SIM, so it is recorded as an adjustment rather than appearing from
        // nowhere the first time the account is reconciled.
        $opening = Pricing::round((float) ($data['balance'] ?? 0));

        $id = Database::transaction(
            static function () use ($context, $name, $method, $opening): int {
                $id = Database::insert('accounts', [
                    'restaurant_id' => $context->restaurantId,
                    'method'        => $method,
                    'name'          => $name,
                    'balance'       => $opening,
                ]);

                if ($opening > 0) {
                    Database::insert('account_transactions', [
                        'restaurant_id' => $context->restaurantId,
                        'account_id'    => $id,
                        'kind'          => 'adjustment',
                        'amount'        => $opening,
                        'balance_after' => $opening,
                        'description'   => 'Haraaga bilowga',
                        'source_type'   => 'manual',
                        'created_by'    => $context->userId,
                        'shift_id'      => Shifts::currentFor($context->restaurantId, (int) ($id)),
                    ]);
                }

                return $id;
            },
        );

        Audit::log($context, 'accounts', 'account_created', $id, newValue: $name);

        return self::find($context->restaurantId, $id);
    }

    /** @return array<string,mixed> */
    public function update(Request $request, AuthContext $context): array
    {
        $data = Validator::check($request->all(), [
            'name'      => 'nullable|string|min:1|max:64',
            'is_active' => 'nullable|bool',
        ]);

        $id = $request->intParam('id');
        $account = self::requireScoped('accounts', $id, $context->restaurantId, 'Account not found');

        // The balance is deliberately absent. It is the sum of what has moved
        // through the account, and letting it be typed over would break that
        // relationship silently — a correction is a transfer or an adjustment.
        $update = [];
        if (isset($data['name']) && trim((string) $data['name']) !== '') {
            $name = trim((string) $data['name']);
            self::requireFreeName($context->restaurantId, $name, $id);
            $update['name'] = $name;
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
                "UPDATE accounts SET $set WHERE id = :id AND restaurant_id = :rid",
                $update + ['id' => $id, 'rid' => $context->restaurantId],
            );

            Audit::diff(
                $context,
                module: 'accounts',
                action: 'account_updated',
                recordId: $id,
                before: $account,
                after: $update,
                fields: array_keys($update),
            );
        }

        return self::find($context->restaurantId, $id);
    }

    /**
     * Closes an account. Deleted outright only if nothing ever touched it.
     *
     * @return array<string,mixed>
     */
    public function destroy(Request $request, AuthContext $context): array
    {
        $id = $request->intParam('id');
        $account = self::requireScoped('accounts', $id, $context->restaurantId, 'Account not found');

        if (Pricing::round((float) $account['balance']) > 0.001) {
            throw ApiException::unprocessable(
                'Move the balance out of this account before closing it',
            );
        }

        $movements = (int) Database::scalar(
            'SELECT COUNT(*) FROM account_transactions
              WHERE account_id = :id AND restaurant_id = :rid',
            ['id' => $id, 'rid' => $context->restaurantId],
        );

        if ($movements > 0) {
            Database::run(
                'UPDATE accounts SET is_active = 0 WHERE id = :id AND restaurant_id = :rid',
                ['id' => $id, 'rid' => $context->restaurantId],
            );

            Audit::log(
                $context,
                'accounts',
                'account_closed',
                $id,
                field: 'is_active',
                oldValue: '1',
                newValue: '0',
            );

            return ['closed' => true, 'deleted' => false, 'id' => $id];
        }

        // Never used, never reconciled — an account opened by mistake, and
        // keeping a row nobody can explain is worse than removing it.
        Database::run(
            'DELETE FROM accounts WHERE id = :id AND restaurant_id = :rid',
            ['id' => $id, 'rid' => $context->restaurantId],
        );

        Audit::log(
            $context,
            'accounts',
            'account_deleted',
            $id,
            oldValue: (string) $account['name'],
        );

        return ['closed' => true, 'deleted' => true, 'id' => $id];
    }

    // -------------------------------------------------------------- helpers

    private static function requireMethod(int $restaurantId, string $code): void
    {
        $exists = (int) Database::scalar(
            'SELECT COUNT(*) FROM payment_methods
              WHERE restaurant_id = :rid AND code = :code AND is_active = 1',
            ['rid' => $restaurantId, 'code' => $code],
        );

        if ($exists === 0) {
            throw ApiException::validation(
                ['method' => 'That payment method does not exist'],
            );
        }
    }

    private static function requireFreeName(int $restaurantId, string $name, ?int $exceptId): void
    {
        $sql = 'SELECT COUNT(*) FROM accounts WHERE restaurant_id = :rid AND name = :name';
        $bind = ['rid' => $restaurantId, 'name' => $name];

        if ($exceptId !== null) {
            $sql .= ' AND id <> :id';
            $bind['id'] = $exceptId;
        }

        if ((int) Database::scalar($sql, $bind) > 0) {
            throw ApiException::validation(
                ['name' => 'An account with that name already exists'],
            );
        }
    }

    /** @return array<string,mixed> */
    private static function find(int $restaurantId, int $id): array
    {
        $row = Database::selectOne(
            'SELECT * FROM accounts WHERE id = :id AND restaurant_id = :rid',
            ['id' => $id, 'rid' => $restaurantId],
        );

        return $row === null ? [] : Presenter::account($row);
    }
}
