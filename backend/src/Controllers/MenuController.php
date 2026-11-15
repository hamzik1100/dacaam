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
use Dacaam\Support\ImageStore;
use Dacaam\Support\Presenter;

final class MenuController extends Repository
{
    // ------------------------------------------------------------ items

    /** @return list<array<string,mixed>> */
    public function items(Request $request, AuthContext $context): array
    {
        $where = ['restaurant_id = :rid', 'deleted_at IS NULL'];
        $bind = ['rid' => $context->restaurantId];

        if (($categoryId = $request->queryInt('category_id')) !== null) {
            $where[] = 'category_id = :cid';
            $bind['cid'] = $categoryId;
        }
        if (($search = $request->queryString('search')) !== '') {
            $where[] = '(name LIKE :q OR description LIKE :q2)';
            $bind['q'] = "%$search%";
            $bind['q2'] = "%$search%";
        }
        if ($request->queryString('available') === '1') {
            $where[] = 'is_available = 1';
        }

        return array_map(
            [Presenter::class, 'menuItem'],
            Database::select(
                'SELECT * FROM menu_items WHERE ' . implode(' AND ', $where)
                . ' ORDER BY sort_order ASC, name ASC',
                $bind,
            ),
        );
    }

    /** @return array<string,mixed> */
    /**
     * Attaches a photograph to a menu item.
     *
     * The picture arrives already small — the phone resizes to 800px before it
     * sends — so this validates it, writes it to disk, and points the item at
     * the address it now serves from. The previous file is removed in the same
     * breath, because a menu photographed twice a season would otherwise leave
     * every earlier attempt on the disk for ever.
     *
     * @return array<string,mixed>
     */
    public function uploadItemImage(Request $request, AuthContext $context): array
    {
        $data = Validator::check($request->all(), [
            'image' => 'required|string',
        ]);

        $id = $request->intParam('id');
        $item = self::requireScoped('menu_items', $id, $context->restaurantId, 'Item not found');

        $url = ImageStore::putMenuImage((string) $data['image'], $context->restaurantId);
        $previous = $item['image_url'] === null ? null : (string) $item['image_url'];

        Database::run(
            'UPDATE menu_items SET image_url = :url WHERE id = :id AND restaurant_id = :rid',
            ['url' => $url, 'id' => $id, 'rid' => $context->restaurantId],
        );

        // Only after the row points at the new one. Losing the old file before
        // the update lands would leave an item showing a broken picture.
        if ($previous !== null && $previous !== $url) {
            ImageStore::forget($previous);
        }

        Audit::log(
            $context,
            'menu',
            'item_image_changed',
            $id,
            field: 'image_url',
            oldValue: $previous,
            newValue: $url,
        );

        return Presenter::menuItem(
            self::requireScoped('menu_items', $id, $context->restaurantId, 'Item not found'),
        );
    }

    /**
     * Takes the photograph off again, leaving the emoji in its place.
     *
     * @return array<string,mixed>
     */
    public function deleteItemImage(Request $request, AuthContext $context): array
    {
        $id = $request->intParam('id');
        $item = self::requireScoped('menu_items', $id, $context->restaurantId, 'Item not found');

        Database::run(
            'UPDATE menu_items SET image_url = NULL WHERE id = :id AND restaurant_id = :rid',
            ['id' => $id, 'rid' => $context->restaurantId],
        );

        ImageStore::forget($item['image_url'] === null ? null : (string) $item['image_url']);

        Audit::log(
            $context,
            'menu',
            'item_image_removed',
            $id,
            field: 'image_url',
            oldValue: $item['image_url'] === null ? null : (string) $item['image_url'],
        );

        return Presenter::menuItem(
            self::requireScoped('menu_items', $id, $context->restaurantId, 'Item not found'),
        );
    }
    public function storeItem(Request $request, AuthContext $context): array
    {
        $data = $this->validateItem($request);
        $this->assertCategoryBelongs($context, (int) $data['category_id']);

        $id = Database::insert('menu_items', [
            'restaurant_id'       => $context->restaurantId,
            'category_id'         => (int) $data['category_id'],
            'name'                => (string) $data['name'],
            'description'         => (string) ($data['description'] ?? ''),
            'price'               => (float) $data['price'],
            'image_url'           => $data['image_url'] ?? null,
            'emoji'               => (string) ($data['emoji'] ?? '🍽️'),
            'is_available'        => ($data['is_available'] ?? true) ? 1 : 0,
            'apply_packaging_fee' => ($data['apply_packaging_fee'] ?? true) ? 1 : 0,
            'sort_order'          => (int) ($data['sort_order'] ?? 0),
        ]);

        Audit::log($context, 'menu', 'menu_item_created', $id, newValue: (string) $data['name']);

        return Presenter::menuItem(
            self::requireScoped('menu_items', $id, $context->restaurantId, 'Item not found'),
        );
    }

    /** @return array<string,mixed> */
    public function updateItem(Request $request, AuthContext $context): array
    {
        $id = $request->intParam('id');
        $before = self::requireScoped('menu_items', $id, $context->restaurantId, 'Item not found');

        $data = $this->validateItem($request, partial: true);
        if (isset($data['category_id'])) {
            $this->assertCategoryBelongs($context, (int) $data['category_id']);
        }

        $update = [];
        foreach (['category_id', 'name', 'description', 'price', 'image_url', 'emoji', 'sort_order'] as $field) {
            if (array_key_exists($field, $data)) {
                $update[$field] = $data[$field];
            }
        }
        foreach (['is_available', 'apply_packaging_fee'] as $flag) {
            if (array_key_exists($flag, $data)) {
                $update[$flag] = $data[$flag] ? 1 : 0;
            }
        }

        if ($update !== []) {
            Database::updateScoped('menu_items', $update, $id, $context->restaurantId);

            // A price change is the single most audited event in the module —
            // §37 shows it as the worked example.
            Audit::diff(
                $context,
                module: 'menu',
                action: 'menu_item_updated',
                recordId: $id,
                before: $before,
                after: $update,
                fields: array_keys($update),
                reason: $request->input('reason') === null ? null : (string) $request->input('reason'),
            );
        }

        return Presenter::menuItem(
            self::requireScoped('menu_items', $id, $context->restaurantId, 'Item not found'),
        );
    }

    /** @return array<string,mixed> */
    public function toggleItem(Request $request, AuthContext $context): array
    {
        $id = $request->intParam('id');
        $item = self::requireScoped('menu_items', $id, $context->restaurantId, 'Item not found');
        $next = (int) $item['is_available'] === 1 ? 0 : 1;

        Database::updateScoped('menu_items', ['is_available' => $next], $id, $context->restaurantId);

        Audit::log(
            $context,
            'menu',
            'menu_item_availability_changed',
            $id,
            field: 'is_available',
            oldValue: (string) $item['is_available'],
            newValue: (string) $next,
        );

        return Presenter::menuItem(
            self::requireScoped('menu_items', $id, $context->restaurantId, 'Item not found'),
        );
    }

    /** @return array<string,mixed> */
    public function deleteItem(Request $request, AuthContext $context): array
    {
        $id = $request->intParam('id');
        $item = self::requireScoped('menu_items', $id, $context->restaurantId, 'Item not found');

        // Soft delete: order_items reference this row, and historical receipts
        // must keep resolving even after an item leaves the menu.
        Database::updateScoped(
            'menu_items',
            ['deleted_at' => date('Y-m-d H:i:s'), 'is_available' => 0],
            $id,
            $context->restaurantId,
        );

        Audit::log($context, 'menu', 'menu_item_deleted', $id, oldValue: (string) $item['name']);

        return ['deleted' => true, 'id' => $id];
    }

    // ------------------------------------------------------- categories

    /** @return list<array<string,mixed>> */
    public function categories(Request $request, AuthContext $context): array
    {
        return array_map(
            [Presenter::class, 'category'],
            Database::select(
                'SELECT c.*,
                        (SELECT COUNT(*) FROM menu_items m
                          WHERE m.category_id = c.id AND m.deleted_at IS NULL) AS item_count
                   FROM categories c
                  WHERE c.restaurant_id = :rid AND c.deleted_at IS NULL
                  ORDER BY c.sort_order ASC, c.name ASC',
                ['rid' => $context->restaurantId],
            ),
        );
    }

    /** @return array<string,mixed> */
    public function storeCategory(Request $request, AuthContext $context): array
    {
        $data = Validator::check($request->all(), [
            'name'        => 'required|string|min:1|max:100',
            'description' => 'nullable|string|max:255',
            'emoji'       => 'nullable|string|max:16',
            'color'       => 'nullable|string|max:7',
            'sort_order'  => 'nullable|int|min:0',
            'is_active'   => 'nullable|bool',
        ]);

        $id = Database::insert('categories', [
            'restaurant_id' => $context->restaurantId,
            'name'          => (string) $data['name'],
            'description'   => (string) ($data['description'] ?? ''),
            'emoji'         => (string) ($data['emoji'] ?? '🍽️'),
            'color'         => (string) ($data['color'] ?? '#F97316'),
            'sort_order'    => (int) ($data['sort_order'] ?? 0),
            'is_active'     => ($data['is_active'] ?? true) ? 1 : 0,
        ]);

        Audit::log($context, 'menu', 'category_created', $id, newValue: (string) $data['name']);

        return Presenter::category(
            self::requireScoped('categories', $id, $context->restaurantId, 'Category not found'),
        );
    }

    /** @return array<string,mixed> */
    public function updateCategory(Request $request, AuthContext $context): array
    {
        $id = $request->intParam('id');
        $before = self::requireScoped('categories', $id, $context->restaurantId, 'Category not found');

        $data = Validator::check($request->all(), [
            'name'        => 'nullable|string|min:1|max:100',
            'description' => 'nullable|string|max:255',
            'emoji'       => 'nullable|string|max:16',
            'color'       => 'nullable|string|max:7',
            'sort_order'  => 'nullable|int|min:0',
            'is_active'   => 'nullable|bool',
        ]);

        $update = [];
        foreach (['name', 'description', 'emoji', 'color', 'sort_order'] as $field) {
            if (array_key_exists($field, $data) && $data[$field] !== null) {
                $update[$field] = $data[$field];
            }
        }
        if (array_key_exists('is_active', $data)) {
            $update['is_active'] = $data['is_active'] ? 1 : 0;
        }

        if ($update !== []) {
            Database::updateScoped('categories', $update, $id, $context->restaurantId);
            Audit::diff($context, 'menu', 'category_updated', $id, $before, $update, array_keys($update));
        }

        return Presenter::category(
            self::requireScoped('categories', $id, $context->restaurantId, 'Category not found'),
        );
    }

    /** @return array<string,mixed> */
    public function deleteCategory(Request $request, AuthContext $context): array
    {
        $id = $request->intParam('id');
        $category = self::requireScoped('categories', $id, $context->restaurantId, 'Category not found');

        $liveItems = (int) Database::scalar(
            'SELECT COUNT(*) FROM menu_items
              WHERE category_id = :cid AND restaurant_id = :rid AND deleted_at IS NULL',
            ['cid' => $id, 'rid' => $context->restaurantId],
        );

        if ($liveItems > 0) {
            throw ApiException::conflict(
                sprintf('Move or delete the %d item(s) in this category first', $liveItems),
            );
        }

        Database::updateScoped(
            'categories',
            ['deleted_at' => date('Y-m-d H:i:s'), 'is_active' => 0],
            $id,
            $context->restaurantId,
        );

        Audit::log($context, 'menu', 'category_deleted', $id, oldValue: (string) $category['name']);

        return ['deleted' => true, 'id' => $id];
    }

    // ----------------------------------------------------------- helpers

    /** @return array<string,mixed> */
    private function validateItem(Request $request, bool $partial = false): array
    {
        $required = $partial ? 'nullable' : 'required';

        return Validator::check($request->all(), [
            'category_id'         => "$required|int|min:1",
            'name'                => "$required|string|min:1|max:150",
            // Price must be > 0 — the same rule the client enforces (§46).
            'price'               => "$required|numeric|min:0.01",
            'description'         => 'nullable|string|max:500',
            'image_url'           => 'nullable|string|max:500',
            'emoji'               => 'nullable|string|max:16',
            'is_available'        => 'nullable|bool',
            'apply_packaging_fee' => 'nullable|bool',
            'sort_order'          => 'nullable|int|min:0',
        ]);
    }

    private function assertCategoryBelongs(AuthContext $context, int $categoryId): void
    {
        $exists = Database::scalar(
            'SELECT 1 FROM categories
              WHERE id = :id AND restaurant_id = :rid AND deleted_at IS NULL LIMIT 1',
            ['id' => $categoryId, 'rid' => $context->restaurantId],
        );

        if ($exists === false) {
            throw ApiException::validation(['category_id' => 'Unknown category']);
        }
    }
}
