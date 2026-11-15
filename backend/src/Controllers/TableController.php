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
use Dacaam\Support\Plans;
use Dacaam\Support\Presenter;

final class TableController extends Repository
{
    /** @return list<array<string,mixed>> */
    public function index(Request $request, AuthContext $context): array
    {
        return array_map(
            [Presenter::class, 'table'],
            Database::select(
                'SELECT * FROM `tables` WHERE restaurant_id = :rid ORDER BY table_number ASC',
                ['rid' => $context->restaurantId],
            ),
        );
    }

    /** @return array<string,mixed> */
    public function store(Request $request, AuthContext $context): array
    {
        $data = Validator::check($request->all(), [
            'table_number' => 'required|int|min:1|max:9999',
            'capacity'     => 'required|int|min:1|max:100',
            'name'         => 'nullable|string|max:64',
            'is_active'    => 'nullable|bool',
        ]);

        $taken = Database::scalar(
            'SELECT 1 FROM `tables` WHERE restaurant_id = :rid AND table_number = :n LIMIT 1',
            ['rid' => $context->restaurantId, 'n' => (int) $data['table_number']],
        );
        if ($taken !== false) {
            throw ApiException::validation(['table_number' => 'That table number already exists']);
        }

        if ($data['is_active'] ?? true) {
            Plans::assertRoom($context->restaurantId, 'tables');
        }

        $id = Database::insert('tables', [
            'restaurant_id' => $context->restaurantId,
            'table_number'  => (int) $data['table_number'],
            'capacity'      => (int) $data['capacity'],
            'name'          => (string) ($data['name'] ?? ''),
            'is_active'     => ($data['is_active'] ?? true) ? 1 : 0,
        ]);

        Audit::log($context, 'tables', 'table_created', $id, newValue: (string) $data['table_number']);

        return Presenter::table(
            self::requireScoped('tables', $id, $context->restaurantId, 'Table not found'),
        );
    }

    /** @return array<string,mixed> */
    public function update(Request $request, AuthContext $context): array
    {
        $id = $request->intParam('id');
        $before = self::requireScoped('tables', $id, $context->restaurantId, 'Table not found');

        $data = Validator::check($request->all(), [
            'table_number' => 'nullable|int|min:1|max:9999',
            'capacity'     => 'nullable|int|min:1|max:100',
            'name'         => 'nullable|string|max:64',
            'status'       => 'nullable|string|in:available,occupied,reserved,disabled',
            'is_active'    => 'nullable|bool',
        ]);

        $update = [];
        foreach (['table_number', 'capacity', 'name', 'status'] as $field) {
            if (array_key_exists($field, $data) && $data[$field] !== null) {
                $update[$field] = $data[$field];
            }
        }
        if (array_key_exists('is_active', $data)) {
            if ($data['is_active'] && (int) $before['is_active'] !== 1) {
                Plans::assertRoom($context->restaurantId, 'tables');
            }
            $update['is_active'] = $data['is_active'] ? 1 : 0;
        }

        // Freeing a table by hand must also drop its order link, or the floor
        // view keeps showing a ghost order on an empty table.
        if (($update['status'] ?? null) === 'available') {
            $update['current_order_id'] = null;
        }

        if ($update !== []) {
            Database::updateScoped('tables', $update, $id, $context->restaurantId);
            Audit::diff($context, 'tables', 'table_updated', $id, $before, $update, array_keys($update));
        }

        return Presenter::table(
            self::requireScoped('tables', $id, $context->restaurantId, 'Table not found'),
        );
    }

    /** @return array<string,mixed> */
    public function destroy(Request $request, AuthContext $context): array
    {
        $id = $request->intParam('id');
        $table = self::requireScoped('tables', $id, $context->restaurantId, 'Table not found');

        if ((string) $table['status'] === 'occupied') {
            throw ApiException::conflict('Close the open order before removing this table');
        }

        // Deactivate rather than delete: past orders point at this row.
        Database::updateScoped(
            'tables',
            ['is_active' => 0, 'status' => 'disabled', 'current_order_id' => null],
            $id,
            $context->restaurantId,
        );

        Audit::log($context, 'tables', 'table_disabled', $id, oldValue: (string) $table['table_number']);

        return ['disabled' => true, 'id' => $id];
    }
}
