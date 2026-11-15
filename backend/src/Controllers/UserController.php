<?php

declare(strict_types=1);

namespace Dacaam\Controllers;

use Dacaam\Core\ApiException;
use Dacaam\Core\Audit;
use Dacaam\Core\Auth;
use Dacaam\Core\AuthContext;
use Dacaam\Core\Database;
use Dacaam\Core\PasswordPolicy;
use Dacaam\Core\Request;
use Dacaam\Core\Validator;
use Dacaam\Repositories\Repository;
use Dacaam\Support\Plans;
use Dacaam\Support\Presenter;

final class UserController extends Repository
{
    /** @return list<array<string,mixed>> */
    public function index(Request $request, AuthContext $context): array
    {
        $rows = Database::select(
            'SELECT u.*, r.code AS role_code, r.name AS role_name
               FROM users u
          LEFT JOIN user_roles ur ON ur.user_id = u.id
          LEFT JOIN roles r       ON r.id = ur.role_id
              WHERE u.restaurant_id = :rid
              ORDER BY u.id ASC',
            ['rid' => $context->restaurantId],
        );

        return array_map(
            static fn (array $row): array => Presenter::user(
                $row,
                Auth::permissionsFor((int) $row['id']),
            ),
            $rows,
        );
    }

    /** @return list<array<string,mixed>> */
    public function roles(Request $request, AuthContext $context): array
    {
        $rows = Database::select(
            'SELECT r.id, r.code, r.name, r.is_system,
                    (SELECT COUNT(*) FROM user_roles ur WHERE ur.role_id = r.id) AS user_count
               FROM roles r
              WHERE r.restaurant_id = :rid
              ORDER BY r.id ASC',
            ['rid' => $context->restaurantId],
        );

        return array_map(
            static fn (array $r): array => [
                'id'          => (int) $r['id'],
                'code'        => (string) $r['code'],
                'name'        => (string) $r['name'],
                'is_system'   => (bool) $r['is_system'],
                'user_count'  => (int) $r['user_count'],
                'permissions' => array_column(
                    Database::select(
                        'SELECT p.code FROM role_permissions rp
                           JOIN permissions p ON p.id = rp.permission_id
                          WHERE rp.role_id = :rid',
                        ['rid' => (int) $r['id']],
                    ),
                    'code',
                ),
            ],
            $rows,
        );
    }

    /** @return list<array<string,mixed>> */
    public function permissions(Request $request, AuthContext $context): array
    {
        return array_map(
            static fn (array $p): array => [
                'code'   => (string) $p['code'],
                'module' => (string) $p['module'],
                'action' => (string) $p['action'],
            ],
            Database::select('SELECT code, module, action FROM permissions ORDER BY module, action'),
        );
    }

    /** @return array<string,mixed> */
    public function store(Request $request, AuthContext $context): array
    {
        $data = Validator::check($request->all(), [
            'name'      => 'required|string|min:2|max:150',
            'phone'     => 'required|phone|max:32',
            'password'  => 'required|string|min:1|max:100',
            'role_code' => 'required|string|in:admin,operator,waiter',
            'is_active' => 'nullable|bool',
            'must_change_password' => 'nullable|bool',
        ]);

        $phone = Auth::normalisePhone((string) $data['phone']);

        $taken = Database::scalar(
            'SELECT 1 FROM users WHERE restaurant_id = :rid AND phone = :phone LIMIT 1',
            ['rid' => $context->restaurantId, 'phone' => $phone],
        );
        if ($taken !== false) {
            throw ApiException::validation(['phone' => 'That phone is already registered here']);
        }

        $role = Database::selectOne(
            'SELECT id FROM roles WHERE restaurant_id = :rid AND code = :code LIMIT 1',
            ['rid' => $context->restaurantId, 'code' => (string) $data['role_code']],
        );
        if ($role === null) {
            throw ApiException::validation(['role_code' => 'Unknown role']);
        }

        $policy = new PasswordPolicy(self::settings($context->restaurantId));
        $policy->assert((string) $data['password']);

        // An inactive account costs the plan nothing, so only an active one
        // needs room.
        if ($data['is_active'] ?? true) {
            Plans::assertRoom($context->restaurantId, 'users');
        }

        $userId = Database::transaction(function () use ($context, $data, $phone, $role, $policy): int {
            $userId = Database::insert('users', [
                'restaurant_id'        => $context->restaurantId,
                'name'                 => (string) $data['name'],
                'phone'                => $phone,
                'password_hash'        => $policy->hash((string) $data['password']),
                'is_active'            => ($data['is_active'] ?? true) ? 1 : 0,
                'password_changed_at'  => date('Y-m-d H:i:s'),
                // An admin choosing someone else's first password means the
                // admin knows it; the user is made to replace it on first use.
                'must_change_password' => ($data['must_change_password'] ?? true) ? 1 : 0,
            ]);

            Database::insert('user_roles', ['user_id' => $userId, 'role_id' => (int) $role['id']]);

            return $userId;
        });

        Audit::log($context, 'users', 'user_created', $userId, newValue: (string) $data['name']);

        return Auth::publicUser($userId);
    }

    /** @return array<string,mixed> */
    public function update(Request $request, AuthContext $context): array
    {
        $id = $request->intParam('id');
        $before = self::requireScoped('users', $id, $context->restaurantId, 'User not found');

        $data = Validator::check($request->all(), [
            'name'      => 'nullable|string|min:2|max:150',
            'phone'     => 'nullable|phone|max:32',
            'password'  => 'nullable|string|min:1|max:100',
            'role_code' => 'nullable|string|in:admin,operator,waiter',
            'is_active' => 'nullable|bool',
        ]);

        $update = [];
        if (!empty($data['name'])) {
            $update['name'] = (string) $data['name'];
        }
        if (!empty($data['phone'])) {
            $update['phone'] = Auth::normalisePhone((string) $data['phone']);
        }
        if (!empty($data['password'])) {
            $policy = new PasswordPolicy(self::settings($context->restaurantId));
            $policy->assert((string) $data['password']);

            $update['password_hash'] = $policy->hash((string) $data['password']);
            $update['password_changed_at'] = date('Y-m-d H:i:s');
            // A password an admin set for someone else must be replaced by
            // that person before it counts as theirs.
            $update['must_change_password'] = $id === $context->userId ? 0 : 1;
        }
        if (array_key_exists('is_active', $data) && $data['is_active'] !== null) {
            // Locking yourself out mid-shift is a support call nobody wants.
            if ($id === $context->userId && !$data['is_active']) {
                throw ApiException::unprocessable('You cannot deactivate your own account');
            }
            // Switching someone back on takes a place on the plan.
            if ($data['is_active'] && (int) $before['is_active'] !== 1) {
                Plans::assertRoom($context->restaurantId, 'users');
            }
            $update['is_active'] = $data['is_active'] ? 1 : 0;
        }

        if ($update !== []) {
            Database::updateScoped('users', $update, $id, $context->restaurantId);

            Audit::diff(
                $context,
                'users',
                'user_updated',
                $id,
                $before,
                // The hash itself never reaches the audit trail.
                array_diff_key($update, ['password_hash' => null]),
                array_keys(array_diff_key($update, ['password_hash' => null])),
            );

            if (isset($update['password_hash'])) {
                Audit::log($context, 'users', 'password_changed', $id, field: 'password');
                // Any live session for that user is no longer trustworthy.
                Database::run(
                    'UPDATE api_tokens SET revoked_at = NOW()
                      WHERE user_id = :uid AND revoked_at IS NULL',
                    ['uid' => $id],
                );
            }
        }

        if (!empty($data['role_code'])) {
            $role = Database::selectOne(
                'SELECT id, code FROM roles WHERE restaurant_id = :rid AND code = :code LIMIT 1',
                ['rid' => $context->restaurantId, 'code' => (string) $data['role_code']],
            );
            if ($role === null) {
                throw ApiException::validation(['role_code' => 'Unknown role']);
            }

            Database::run('DELETE FROM user_roles WHERE user_id = :uid', ['uid' => $id]);
            Database::insert('user_roles', ['user_id' => $id, 'role_id' => (int) $role['id']]);

            Audit::log(
                $context,
                'users',
                'role_changed',
                $id,
                field: 'role',
                newValue: (string) $role['code'],
            );
        }

        return Auth::publicUser($id);
    }

    // ======================================================== permissions

    /**
     * Per-user overrides on top of the role's grants.
     *
     * Payload: `{"permissions": {"orders.cancel": true, "reports.view": false}}`
     * A value matching what the role already says is stored as an explicit
     * override anyway — that is what makes "this one waiter may cancel" and
     * "this one operator may not see reports" both expressible.
     *
     * @return array<string,mixed>
     */
    public function setPermissions(Request $request, AuthContext $context): array
    {
        $id = $request->intParam('id');
        self::requireScoped('users', $id, $context->restaurantId, 'User not found');

        $input = $request->input('permissions');
        if (!is_array($input)) {
            throw ApiException::validation(
                ['permissions' => 'Expected a map of permission code to true/false'],
            );
        }

        $codes = array_column(
            Database::select('SELECT id, code FROM permissions'),
            'id',
            'code',
        );

        $before = Auth::permissionsFor($id);

        // The guard runs inside the transaction so a change that would lock the
        // restaurant out is rolled back rather than merely reported.
        $after = Database::transaction(function () use ($id, $input, $codes, $context): array {
            Database::run('DELETE FROM user_permissions WHERE user_id = :uid', ['uid' => $id]);

            foreach ($input as $code => $granted) {
                $permissionId = $codes[(string) $code] ?? null;
                if ($permissionId === null) {
                    // Unknown codes are ignored rather than rejected: a newer
                    // client may know permissions this server does not.
                    continue;
                }

                Database::insert('user_permissions', [
                    'user_id'       => $id,
                    'permission_id' => (int) $permissionId,
                    'granted'       => filter_var($granted, FILTER_VALIDATE_BOOL) ? 1 : 0,
                ]);
            }

            $this->assertRestaurantKeepsAnAdmin($context);

            return Auth::permissionsFor($id);
        });

        Audit::log(
            $context,
            'users',
            'permissions_changed',
            $id,
            field: 'permissions',
            oldValue: implode(',', $before),
            newValue: implode(',', $after),
        );

        return Auth::publicUser($id);
    }

    // ============================================================== roles

    /** @return array<string,mixed> */
    public function storeRole(Request $request, AuthContext $context): array
    {
        $data = Validator::check($request->all(), [
            'code'        => 'required|string|min:2|max:32',
            'name'        => 'required|string|min:2|max:64',
            'permissions' => 'nullable|array',
        ]);

        $code = strtolower(preg_replace('/[^a-z0-9_]/i', '_', (string) $data['code']) ?? '');

        $taken = Database::scalar(
            'SELECT 1 FROM roles WHERE restaurant_id = :rid AND code = :code LIMIT 1',
            ['rid' => $context->restaurantId, 'code' => $code],
        );
        if ($taken !== false) {
            throw ApiException::validation(['code' => 'That role code already exists']);
        }

        $roleId = Database::transaction(function () use ($context, $code, $data): int {
            $roleId = Database::insert('roles', [
                'restaurant_id' => $context->restaurantId,
                'code'          => $code,
                'name'          => (string) $data['name'],
                'is_system'     => 0,
            ]);

            if (isset($data['permissions']) && is_array($data['permissions'])) {
                $this->replaceRolePermissions($roleId, $data['permissions']);
            }

            return $roleId;
        });

        Audit::log($context, 'users', 'role_created', $roleId, newValue: $code);

        return $this->roleById($context, $roleId);
    }

    /** @return array<string,mixed> */
    public function updateRolePermissions(Request $request, AuthContext $context): array
    {
        $roleId = $request->intParam('id');
        $role = self::requireScoped('roles', $roleId, $context->restaurantId, 'Role not found');

        $input = $request->input('permissions');
        if (!is_array($input)) {
            throw ApiException::validation(
                ['permissions' => 'Expected a list of permission codes'],
            );
        }

        $before = array_column(
            Database::select(
                'SELECT p.code FROM role_permissions rp
                   JOIN permissions p ON p.id = rp.permission_id
                  WHERE rp.role_id = :rid',
                ['rid' => $roleId],
            ),
            'code',
        );

        Database::transaction(function () use ($roleId, $input, $context): void {
            $this->replaceRolePermissions($roleId, $input);
            $this->assertRestaurantKeepsAnAdmin($context);
        });

        Audit::log(
            $context,
            'users',
            'role_permissions_changed',
            $roleId,
            field: 'permissions',
            oldValue: implode(',', $before),
            newValue: implode(',', array_map('strval', $input)),
            reason: (string) $role['code'],
        );

        return $this->roleById($context, $roleId);
    }

    /** @return array<string,mixed> */
    public function destroyRole(Request $request, AuthContext $context): array
    {
        $roleId = $request->intParam('id');
        $role = self::requireScoped('roles', $roleId, $context->restaurantId, 'Role not found');

        if ((int) $role['is_system'] === 1) {
            throw ApiException::conflict('Built-in roles cannot be deleted');
        }

        $assigned = (int) Database::scalar(
            'SELECT COUNT(*) FROM user_roles WHERE role_id = :rid',
            ['rid' => $roleId],
        );
        if ($assigned > 0) {
            throw ApiException::conflict(
                sprintf('Move the %d user(s) on this role first', $assigned),
            );
        }

        Database::run(
            'DELETE FROM roles WHERE id = :id AND restaurant_id = :rid',
            ['id' => $roleId, 'rid' => $context->restaurantId],
        );

        Audit::log($context, 'users', 'role_deleted', $roleId, oldValue: (string) $role['code']);

        return ['deleted' => true, 'id' => $roleId];
    }

    /** @return array<string,mixed> */
    public function destroy(Request $request, AuthContext $context): array
    {
        $id = $request->intParam('id');

        if ($id === $context->userId) {
            throw ApiException::unprocessable('You cannot delete your own account');
        }

        $user = self::requireScoped('users', $id, $context->restaurantId, 'User not found');

        // Deactivate instead of deleting: orders reference the waiter, and the
        // audit trail must keep naming who did what.
        Database::transaction(function () use ($id, $context): void {
            Database::updateScoped('users', ['is_active' => 0], $id, $context->restaurantId);
            Database::run(
                'UPDATE api_tokens SET revoked_at = NOW() WHERE user_id = :uid AND revoked_at IS NULL',
                ['uid' => $id],
            );

            $this->assertRestaurantKeepsAnAdmin($context);
        });

        Audit::log($context, 'users', 'user_deactivated', $id, oldValue: (string) $user['name']);

        return ['deactivated' => true, 'id' => $id];
    }

    // ============================================================ helpers

    /**
     * Call inside a transaction — the lockout guard that follows a permission
     * change must be able to roll the change back.
     *
     * @param array<int|string,mixed> $codes
     */
    private function replaceRolePermissions(int $roleId, array $codes): void
    {
        $lookup = array_column(
            Database::select('SELECT id, code FROM permissions'),
            'id',
            'code',
        );

        Database::run('DELETE FROM role_permissions WHERE role_id = :rid', ['rid' => $roleId]);

        foreach ($codes as $code) {
            $permissionId = $lookup[(string) $code] ?? null;
            if ($permissionId !== null) {
                Database::insert('role_permissions', [
                    'role_id'       => $roleId,
                    'permission_id' => (int) $permissionId,
                ]);
            }
        }
    }

    /**
     * A restaurant must always keep at least one active user who can still
     * manage users. Without this, one careless permission edit locks everyone
     * out of their own account administration with no way back in.
     */
    private function assertRestaurantKeepsAnAdmin(AuthContext $context): void
    {
        $survivors = Database::select(
            'SELECT u.id FROM users u WHERE u.restaurant_id = :rid AND u.is_active = 1',
            ['rid' => $context->restaurantId],
        );

        foreach ($survivors as $row) {
            if (in_array('users.edit', Auth::permissionsFor((int) $row['id']), true)) {
                return;
            }
        }

        throw ApiException::conflict(
            'This would leave the restaurant with nobody able to manage users',
        );
    }

    /** @return array<string,mixed> */
    private function roleById(AuthContext $context, int $roleId): array
    {
        $row = self::requireScoped('roles', $roleId, $context->restaurantId, 'Role not found');

        return [
            'id'          => (int) $row['id'],
            'code'        => (string) $row['code'],
            'name'        => (string) $row['name'],
            'is_system'   => (bool) $row['is_system'],
            'user_count'  => (int) Database::scalar(
                'SELECT COUNT(*) FROM user_roles WHERE role_id = :rid',
                ['rid' => $roleId],
            ),
            'permissions' => array_column(
                Database::select(
                    'SELECT p.code FROM role_permissions rp
                       JOIN permissions p ON p.id = rp.permission_id
                      WHERE rp.role_id = :rid',
                    ['rid' => $roleId],
                ),
                'code',
            ),
        ];
    }
}
