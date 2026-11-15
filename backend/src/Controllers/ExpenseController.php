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
use Dacaam\Support\Period;
use Dacaam\Support\Presenter;
use Dacaam\Support\Pricing;
use Dacaam\Support\Shifts;

final class ExpenseController extends Repository
{
    /** @return list<array<string,mixed>> */
    public function index(Request $request, AuthContext $context): array
    {
        $where = ['e.restaurant_id = :rid'];
        $bind = ['rid' => $context->restaurantId];

        // Cancelled entries stay in the list — struck through, with the reason
        // visible — because hiding them recreates the problem cancelling was
        // meant to solve. `?cancelled=hide` is there for a screen that wants
        // only live spend.
        if ($request->queryString('cancelled') === 'hide') {
            $where[] = 'e.cancelled_at IS NULL';
        }

        if (($kind = $request->queryString('kind')) !== '') {
            $where[] = 'e.kind = :kind';
            $bind['kind'] = $kind;
        }

        $range = $request->queryString('range');
        if ($range !== '' && $range !== 'all') {
            $period = Period::resolve($range, $request->queryString('from'), $request->queryString('to'));
            $where[] = 'e.expense_date BETWEEN :from AND :to';
            $bind['from'] = $period->from->format('Y-m-d');
            $bind['to'] = $period->to->format('Y-m-d');
        }

        return array_map(
            [Presenter::class, 'expense'],
            Database::select(
                'SELECT e.*, c.name AS category_name, u.name AS created_by_name
                   FROM expenses e
              LEFT JOIN expense_categories c ON c.id = e.expense_category_id
              LEFT JOIN users u              ON u.id = e.created_by
                  WHERE ' . implode(' AND ', $where) . '
                  ORDER BY e.expense_date DESC, e.id DESC',
                $bind,
            ),
        );
    }

    /** @return list<array<string,mixed>> */
    public function categories(Request $request, AuthContext $context): array
    {
        return array_map(
            [Presenter::class, 'expenseCategory'],
            Database::select(
                'SELECT * FROM expense_categories
                  WHERE restaurant_id = :rid AND is_active = 1
                  ORDER BY kind ASC, name ASC',
                ['rid' => $context->restaurantId],
            ),
        );
    }

    /** @return array<string,mixed> */
    public function store(Request $request, AuthContext $context): array
    {
        $data = Validator::check($request->all(), [
            'name'                => 'required|string|min:1|max:150',
            'amount'              => 'required|numeric|min:0.01',
            'kind'                => 'required|string|in:daily,monthly',
            'method'              => 'required|string|in:cash,zaad,edahab,bank',
            'expense_date'        => 'nullable|date',
            'expense_category_id' => 'nullable|int',
            'notes'               => 'nullable|string|max:500',
            'is_recurring'        => 'nullable|bool',
        ]);

        if (!empty($data['expense_category_id'])) {
            self::requireScoped(
                'expense_categories',
                (int) $data['expense_category_id'],
                $context->restaurantId,
                'Expense category not found',
            );
        }

        $amount = Pricing::round((float) $data['amount']);

        $id = Database::transaction(function () use ($context, $data, $amount): int {
            $id = Database::insert('expenses', [
                'restaurant_id'       => $context->restaurantId,
                'expense_category_id' => $data['expense_category_id'] ?? null,
                'name'                => (string) $data['name'],
                'amount'              => $amount,
                'kind'                => (string) $data['kind'],
                'method'              => (string) $data['method'],
                'expense_date'        => isset($data['expense_date'])
                    ? date('Y-m-d', (int) strtotime((string) $data['expense_date']))
                    : date('Y-m-d'),
                'is_recurring'        => ($data['is_recurring'] ?? false) ? 1 : 0,
                'notes'               => (string) ($data['notes'] ?? ''),
                'created_by'          => $context->userId,
            ]);

            // Spending real money moves a real account balance; otherwise the
            // Accounts screen and the Expenses screen tell different stories.
            $this->debitAccount($context, (string) $data['method'], $amount, (string) $data['name'], $id);

            Audit::log($context, 'expenses', 'expense_created', $id, newValue: (string) $data['name']);

            return $id;
        });

        return $this->present($context->restaurantId, $id);
    }

    /**
     * Edits an expense and re-settles the account it was paid from.
     *
     * Amount and method both move real money, so the old posting is reversed
     * and a new one made rather than patched — the ledger keeps both entries,
     * which is what makes the balance explainable afterwards.
     *
     * @return array<string,mixed>
     */
    public function update(Request $request, AuthContext $context): array
    {
        $id = $request->intParam('id');
        $before = self::requireScoped('expenses', $id, $context->restaurantId, 'Expense not found');

        // A void entry is a historical fact. Editing one would rewrite what the
        // books say happened, and the refund has already gone back to the till
        // at the old amount — changing it now would leave the two disagreeing.
        if (($before['cancelled_at'] ?? null) !== null) {
            throw ApiException::conflict('A cancelled expense cannot be edited');
        }

        $data = Validator::check($request->all(), [
            'name'                => 'nullable|string|min:1|max:150',
            'amount'              => 'nullable|numeric|min:0.01',
            'kind'                => 'nullable|string|in:daily,monthly',
            'method'              => 'nullable|string|in:cash,zaad,edahab,bank',
            'expense_date'        => 'nullable|date',
            'expense_category_id' => 'nullable|int',
            'notes'               => 'nullable|string|max:500',
            'is_recurring'        => 'nullable|bool',
            'reason'              => 'nullable|string|max:255',
        ]);

        if (!empty($data['expense_category_id'])) {
            self::requireScoped(
                'expense_categories',
                (int) $data['expense_category_id'],
                $context->restaurantId,
                'Expense category not found',
            );
        }

        $update = [];
        foreach (['name', 'kind', 'method', 'notes', 'expense_category_id'] as $field) {
            if (array_key_exists($field, $data) && $data[$field] !== null) {
                $update[$field] = $data[$field];
            }
        }
        if (isset($data['amount'])) {
            $update['amount'] = Pricing::round((float) $data['amount']);
        }
        if (isset($data['expense_date'])) {
            $update['expense_date'] = date(
                'Y-m-d',
                (int) strtotime((string) $data['expense_date']),
            );
        }
        if (array_key_exists('is_recurring', $data) && $data['is_recurring'] !== null) {
            $update['is_recurring'] = $data['is_recurring'] ? 1 : 0;
        }

        if ($update === []) {
            return $this->present($context->restaurantId, $id);
        }

        $reason = isset($data['reason']) ? (string) $data['reason'] : null;

        Database::transaction(function () use ($context, $id, $before, $update, $reason): void {
            $oldAmount = (float) $before['amount'];
            $oldMethod = (string) $before['method'];
            $newAmount = (float) ($update['amount'] ?? $oldAmount);
            $newMethod = (string) ($update['method'] ?? $oldMethod);

            Database::updateScoped('expenses', $update, $id, $context->restaurantId);

            if ($oldAmount !== $newAmount || $oldMethod !== $newMethod) {
                $this->creditAccount(
                    $context,
                    $oldMethod,
                    $oldAmount,
                    sprintf('Reversal: %s', (string) $before['name']),
                    $id,
                );
                $this->debitAccount(
                    $context,
                    $newMethod,
                    $newAmount,
                    (string) ($update['name'] ?? $before['name']),
                    $id,
                );
            }

            Audit::diff(
                $context,
                'expenses',
                'expense_updated',
                $id,
                $before,
                $update,
                array_keys($update),
                $reason,
            );
        });

        return $this->present($context->restaurantId, $id);
    }

    /** @return array<string,mixed> */
    /**
     * Voids an expense. It is never removed.
     *
     * A deleted row cannot answer the question the books will eventually ask:
     * an entry of 400,000 was recorded on Tuesday and is not there now, so
     * either it was a mistake or somebody covered something up, and a missing
     * row cannot tell the two apart. The entry stays, marked void, with a name
     * against it and a reason — and drops out of every total.
     *
     * @return array<string,mixed>
     */
    public function cancel(Request $request, AuthContext $context): array
    {
        $id = $request->intParam('id');

        $data = Validator::check($request->all(), [
            // Required, not optional. "Why is this 400,000 struck through" is
            // the only question anyone will ever ask about a cancelled expense,
            // and it has to be answerable a year later by somebody who was not
            // there.
            'reason' => 'required|string|min:3|max:255',
        ]);

        $expense = self::requireScoped('expenses', $id, $context->restaurantId, 'Expense not found');

        // Cancelling twice would put the money back twice. The row is re-read
        // and locked inside the transaction rather than trusting the copy
        // fetched above, because two taps on a slow connection arrive as two
        // requests and both would otherwise pass this check.
        $reason = trim((string) $data['reason']);

        Database::transaction(function () use ($context, $id, $expense, $reason): void {
            $locked = Database::selectOne(
                'SELECT cancelled_at FROM expenses
                  WHERE id = :id AND restaurant_id = :rid FOR UPDATE',
                ['id' => $id, 'rid' => $context->restaurantId],
            );

            if ($locked === null) {
                throw ApiException::notFound('Expense not found');
            }

            if ($locked['cancelled_at'] !== null) {
                throw ApiException::conflict('This expense has already been cancelled');
            }

            Database::run(
                'UPDATE expenses
                    SET cancelled_at = NOW(), cancel_reason = :reason, cancelled_by = :uid
                  WHERE id = :id AND restaurant_id = :rid',
                [
                    'reason' => $reason,
                    'uid'    => $context->userId,
                    'id'     => $id,
                    'rid'    => $context->restaurantId,
                ],
            );

            // Money that was never really spent goes back to the account it
            // came out of, with a ledger entry saying why.
            $this->creditAccount(
                $context,
                (string) $expense['method'],
                (float) $expense['amount'],
                sprintf('La joojiyay: %s', (string) $expense['name']),
                $id,
            );

            Audit::log(
                $context,
                'expenses',
                'expense_cancelled',
                $id,
                field: 'cancelled_at',
                oldValue: (string) $expense['name'],
                newValue: (string) $expense['amount'],
                reason: $reason,
            );
        });

        return $this->present($context->restaurantId, $id);
    }

    // ------------------------------------------------- expense categories

    /** @return array<string,mixed> */
    public function storeCategory(Request $request, AuthContext $context): array
    {
        $data = Validator::check($request->all(), [
            'name'  => 'required|string|min:1|max:100',
            'kind'  => 'required|string|in:daily,monthly',
            'icon'  => 'nullable|string|max:64',
            'color' => 'nullable|string|max:7',
        ]);

        $id = Database::insert('expense_categories', [
            'restaurant_id' => $context->restaurantId,
            'name'          => (string) $data['name'],
            'kind'          => (string) $data['kind'],
            'icon'          => (string) ($data['icon'] ?? 'receipt'),
            'color'         => (string) ($data['color'] ?? '#8B5CF6'),
        ]);

        Audit::log(
            $context,
            'expenses',
            'expense_category_created',
            $id,
            newValue: (string) $data['name'],
        );

        return Presenter::expenseCategory(
            self::requireScoped(
                'expense_categories',
                $id,
                $context->restaurantId,
                'Category not found',
            ),
        );
    }

    /** @return array<string,mixed> */
    public function destroyCategory(Request $request, AuthContext $context): array
    {
        $id = $request->intParam('id');
        $category = self::requireScoped(
            'expense_categories',
            $id,
            $context->restaurantId,
            'Category not found',
        );

        // Expenses keep pointing at it, so retire rather than delete: past
        // spend must stay attributable.
        Database::updateScoped(
            'expense_categories',
            ['is_active' => 0],
            $id,
            $context->restaurantId,
        );

        Audit::log(
            $context,
            'expenses',
            'expense_category_retired',
            $id,
            oldValue: (string) $category['name'],
        );

        return ['retired' => true, 'id' => $id];
    }

    /** @return array<string,mixed> */
    private function present(int $restaurantId, int $id): array
    {
        return Presenter::expense(
            Database::selectOne(
                'SELECT e.*, c.name AS category_name, u.name AS created_by_name
                   FROM expenses e
              LEFT JOIN expense_categories c ON c.id = e.expense_category_id
              LEFT JOIN users u              ON u.id = e.created_by
                  WHERE e.id = :id AND e.restaurant_id = :rid',
                ['id' => $id, 'rid' => $restaurantId],
            ) ?? [],
        );
    }

    private function creditAccount(
        AuthContext $context,
        string $method,
        float $amount,
        string $description,
        int $sourceId,
    ): void {
        $account = Database::selectOne(
            'SELECT id, balance FROM accounts WHERE restaurant_id = :rid AND method = :m LIMIT 1',
            ['rid' => $context->restaurantId, 'm' => $method],
        );
        if ($account === null) {
            return;
        }

        $newBalance = Pricing::round((float) $account['balance'] + $amount);

        Database::run(
            'UPDATE accounts SET balance = :b WHERE id = :id AND restaurant_id = :rid',
            ['b' => $newBalance, 'id' => $account['id'], 'rid' => $context->restaurantId],
        );

        Database::insert('account_transactions', [
            'restaurant_id' => $context->restaurantId,
            'account_id'    => (int) $account['id'],
            'kind'          => 'adjustment',
            'amount'        => $amount,
            'balance_after' => $newBalance,
            'description'   => $description,
            'source_type'   => 'expense',
            'source_id'     => $sourceId,
            'created_by'    => $context->userId,
            'shift_id'      => Shifts::currentFor($context->restaurantId, (int) $account['id']),
        ]);
    }

    private function debitAccount(
        AuthContext $context,
        string $method,
        float $amount,
        string $description,
        int $sourceId,
    ): void {
        $account = Database::selectOne(
            'SELECT id, balance FROM accounts WHERE restaurant_id = :rid AND method = :m LIMIT 1',
            ['rid' => $context->restaurantId, 'm' => $method],
        );

        if ($account === null) {
            return;
        }

        $newBalance = Pricing::round((float) $account['balance'] - $amount);

        Database::run(
            'UPDATE accounts SET balance = :b WHERE id = :id AND restaurant_id = :rid',
            ['b' => $newBalance, 'id' => $account['id'], 'rid' => $context->restaurantId],
        );

        Database::insert('account_transactions', [
            'restaurant_id' => $context->restaurantId,
            'account_id'    => (int) $account['id'],
            'kind'          => 'money_out',
            'amount'        => $amount,
            'balance_after' => $newBalance,
            'description'   => $description,
            'source_type'   => 'expense',
            'source_id'     => $sourceId,
            'created_by'    => $context->userId,
            'shift_id'      => Shifts::currentFor($context->restaurantId, (int) $account['id']),
        ]);
    }
}
