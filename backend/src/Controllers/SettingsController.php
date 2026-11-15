<?php

declare(strict_types=1);

namespace Dacaam\Controllers;

use Dacaam\Core\Audit;
use Dacaam\Core\AuthContext;
use Dacaam\Core\Database;
use Dacaam\Core\Request;
use Dacaam\Core\Validator;
use Dacaam\Repositories\Repository;
use Dacaam\Support\Presenter;

final class SettingsController extends Repository
{
    /** @return array<string,mixed> */
    public function show(Request $request, AuthContext $context): array
    {
        return [
            'restaurant' => Presenter::restaurant(
                Database::selectOne(
                    'SELECT * FROM restaurants WHERE id = :id',
                    ['id' => $context->restaurantId],
                ) ?? [],
            ),
            'settings' => Presenter::settings(self::settings($context->restaurantId)),
        ];
    }

    /** @return array<string,mixed> */
    public function update(Request $request, AuthContext $context): array
    {
        $before = self::settings($context->restaurantId);

        $data = Validator::check($request->all(), [
            'language'                  => 'nullable|string|in:so,en',
            'theme_mode'                => 'nullable|string|in:light,dark,system',
            'currency_prefix'           => 'nullable|string|max:12',
            'tax_rate'                  => 'nullable|numeric|min:0|max:100',
            'tax_enabled'               => 'nullable|bool',
            'packaging_fee_enabled'     => 'nullable|bool',
            'packaging_fee'             => 'nullable|numeric|min:0',
            'require_table_for_dine_in' => 'nullable|bool',
            'guest_count_enabled'       => 'nullable|bool',
            // Where the alerts go, and how loud each group is. An owner
            // who does not read email at the till can point this at an
            // address they actually watch.
            'alert_email'               => 'nullable|string|email|max:190',
            'alerts_money'              => 'nullable|string|in:off,digest,instant',
            'alerts_security'           => 'nullable|string|in:off,digest,instant',
            'alerts_orders'             => 'nullable|string|in:off,digest,instant',
            'alerts_menu'               => 'nullable|string|in:off,digest,instant',
        ]);

        $update = [];
        foreach ([
            'language', 'theme_mode', 'currency_prefix', 'tax_rate', 'packaging_fee',
            'alert_email', 'alerts_money', 'alerts_security', 'alerts_orders', 'alerts_menu',
        ] as $field) {
            if (array_key_exists($field, $data) && $data[$field] !== null) {
                $update[$field] = $data[$field];
            }
        }
        foreach ([
            'tax_enabled',
            'packaging_fee_enabled',
            'require_table_for_dine_in',
            'guest_count_enabled',
        ] as $flag) {
            if (array_key_exists($flag, $data) && $data[$flag] !== null) {
                $update[$flag] = $data[$flag] ? 1 : 0;
            }
        }

        if ($update !== []) {
            $assignments = implode(
                ', ',
                array_map(static fn (string $c): string => "`$c` = :$c", array_keys($update)),
            );

            Database::run(
                "UPDATE restaurant_settings SET $assignments WHERE restaurant_id = :rid",
                $update + ['rid' => $context->restaurantId],
            );

            // Pricing settings change what customers are charged, so each one
            // is audited individually with its before and after value.
            // Alerts caches these for the life of a request. Changing them
            // and then auditing the change would otherwise be judged against
            // the values from before the change.
            \Dacaam\Support\Alerts::forget();

            Audit::diff(
                $context,
                module: 'settings',
                action: 'settings_updated',
                recordId: $context->restaurantId,
                before: $before,
                after: $update,
                fields: array_keys($update),
            );
        }

        return $this->show($request, $context);
    }

    /** @return array<string,mixed> */
    public function updateRestaurant(Request $request, AuthContext $context): array
    {
        $before = Database::selectOne(
            'SELECT * FROM restaurants WHERE id = :id',
            ['id' => $context->restaurantId],
        ) ?? [];

        $data = Validator::check($request->all(), [
            'name'    => 'nullable|string|min:1|max:150',
            'phone'   => 'nullable|string|max:32',
            'address' => 'nullable|string|max:255',
            'is_open' => 'nullable|bool',
        ]);

        $update = [];
        foreach (['name', 'phone', 'address'] as $field) {
            if (array_key_exists($field, $data) && $data[$field] !== null) {
                $update[$field] = $data[$field];
            }
        }
        if (array_key_exists('is_open', $data) && $data['is_open'] !== null) {
            $update['is_open'] = $data['is_open'] ? 1 : 0;
        }

        if ($update !== []) {
            $assignments = implode(
                ', ',
                array_map(static fn (string $c): string => "`$c` = :$c", array_keys($update)),
            );

            Database::run(
                "UPDATE restaurants SET $assignments WHERE id = :rid",
                $update + ['rid' => $context->restaurantId],
            );

            Audit::diff(
                $context,
                'settings',
                'restaurant_updated',
                $context->restaurantId,
                $before,
                $update,
                array_keys($update),
            );
        }

        return $this->show($request, $context);
    }
}
