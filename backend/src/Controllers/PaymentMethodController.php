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

/**
 * The ways a restaurant takes money.
 *
 * These used to be an ENUM in four tables, so adding one meant an ALTER and a
 * deploy. They are rows now, per restaurant — a shop that starts accepting a
 * new mobile wallet adds it here and it appears at checkout.
 *
 * Nothing is ever hard-deleted. A method named on last month's orders has to
 * keep resolving or those orders lose the record of how they were paid, so
 * removal is deactivation and the code stays.
 */
final class PaymentMethodController extends Repository
{
    /** @return list<array<string,mixed>> */
    public function index(Request $request, AuthContext $context): array
    {
        $rows = Database::select(
            'SELECT m.*,
                    (SELECT COUNT(*) FROM accounts a
                      WHERE a.restaurant_id = m.restaurant_id
                        AND a.method = m.code) AS account_count
               FROM payment_methods m
              WHERE m.restaurant_id = :rid
              ORDER BY m.sort_order ASC, m.id ASC',
            ['rid' => $context->restaurantId],
        );

        return array_map([self::class, 'present'], $rows);
    }

    /** @return array<string,mixed> */
    public function store(Request $request, AuthContext $context): array
    {
        $data = Validator::check($request->all(), [
            'name'       => 'required|string|min:1|max:64',
            'code'       => 'nullable|string|max:32',
            'sort_order' => 'nullable|int|min:0',
        ]);

        $name = trim((string) $data['name']);
        $code = self::codeFor($context->restaurantId, $data['code'] ?? null, $name);

        $id = Database::insert('payment_methods', [
            'restaurant_id' => $context->restaurantId,
            'code'          => $code,
            'name'          => $name,
            'sort_order'    => (int) ($data['sort_order'] ?? 50),
            'is_system'     => 0,
        ]);

        Audit::log($context, 'accounts', 'payment_method_created', $id, newValue: $name);

        return self::find($context->restaurantId, $id);
    }

    /** @return array<string,mixed> */
    public function update(Request $request, AuthContext $context): array
    {
        $data = Validator::check($request->all(), [
            'name'       => 'nullable|string|min:1|max:64',
            'is_active'  => 'nullable|bool',
            'sort_order' => 'nullable|int|min:0',
        ]);

        $id = $request->intParam('id');
        $method = self::requireScoped(
            'payment_methods',
            $id,
            $context->restaurantId,
            'Payment method not found',
        );

        // The code is what every order, expense and account row points at.
        // Renaming is free; re-coding would orphan all of them, so it is not
        // offered at all rather than guarded against.
        $update = [];
        if (isset($data['name']) && trim((string) $data['name']) !== '') {
            $update['name'] = trim((string) $data['name']);
        }
        if (array_key_exists('sort_order', $data) && $data['sort_order'] !== null) {
            $update['sort_order'] = (int) $data['sort_order'];
        }
        if (array_key_exists('is_active', $data) && $data['is_active'] !== null) {
            if (!$data['is_active'] && (int) $method['is_system'] === 1) {
                throw ApiException::unprocessable(
                    'A built-in payment method cannot be switched off',
                );
            }
            $update['is_active'] = $data['is_active'] ? 1 : 0;
        }

        if ($update !== []) {
            $set = implode(', ', array_map(
                static fn (string $c): string => "`$c` = :$c",
                array_keys($update),
            ));

            Database::run(
                "UPDATE payment_methods SET $set WHERE id = :id AND restaurant_id = :rid",
                $update + ['id' => $id, 'rid' => $context->restaurantId],
            );

            Audit::diff(
                $context,
                module: 'accounts',
                action: 'payment_method_updated',
                recordId: $id,
                before: $method,
                after: $update,
                fields: array_keys($update),
            );
        }

        return self::find($context->restaurantId, $id);
    }

    /**
     * Deactivates. A method already named on real money cannot be removed
     * without those records losing the answer to "how was this paid".
     *
     * @return array<string,mixed>
     */
    public function destroy(Request $request, AuthContext $context): array
    {
        $id = $request->intParam('id');
        $method = self::requireScoped(
            'payment_methods',
            $id,
            $context->restaurantId,
            'Payment method not found',
        );

        if ((int) $method['is_system'] === 1) {
            throw ApiException::unprocessable(
                'A built-in payment method cannot be removed',
            );
        }

        Database::run(
            'UPDATE payment_methods SET is_active = 0
              WHERE id = :id AND restaurant_id = :rid',
            ['id' => $id, 'rid' => $context->restaurantId],
        );

        Audit::log(
            $context,
            'accounts',
            'payment_method_deactivated',
            $id,
            field: 'is_active',
            oldValue: '1',
            newValue: '0',
        );

        return self::find($context->restaurantId, $id);
    }

    // -------------------------------------------------------------- helpers

    /**
     * A stable, unique, slug-ish code derived from the name.
     *
     * Generated rather than accepted from the client by default: the code ends
     * up in four tables and must never collide with an existing one, and a
     * caller supplying "cash" for a second time would quietly merge two
     * methods' history.
     */
    private static function codeFor(int $restaurantId, ?string $given, string $name): string
    {
        $base = strtolower(trim((string) ($given ?? $name)));
        $base = preg_replace('/[^a-z0-9]+/', '_', $base) ?? '';
        $base = trim($base, '_');

        if ($base === '') {
            $base = 'method';
        }

        $base = substr($base, 0, 28);
        $code = $base;
        $n = 2;

        while (
            (int) Database::scalar(
                'SELECT COUNT(*) FROM payment_methods
                  WHERE restaurant_id = :rid AND code = :code',
                ['rid' => $restaurantId, 'code' => $code],
            ) > 0
        ) {
            $code = $base . '_' . $n;
            $n++;
        }

        return $code;
    }

    /** @return array<string,mixed> */
    private static function find(int $restaurantId, int $id): array
    {
        $row = Database::selectOne(
            'SELECT m.*,
                    (SELECT COUNT(*) FROM accounts a
                      WHERE a.restaurant_id = m.restaurant_id
                        AND a.method = m.code) AS account_count
               FROM payment_methods m
              WHERE m.id = :id AND m.restaurant_id = :rid',
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
        return [
            'id'            => (int) $row['id'],
            'code'          => (string) $row['code'],
            'name'          => (string) $row['name'],
            'is_active'     => (bool) $row['is_active'],
            // Built-ins can be renamed but never removed — every restaurant
            // takes cash, and the seeded accounts point at these codes.
            'is_system'     => (bool) $row['is_system'],
            'sort_order'    => (int) $row['sort_order'],
            'account_count' => (int) ($row['account_count'] ?? 0),
        ];
    }
}
