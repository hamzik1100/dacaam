<?php

declare(strict_types=1);

namespace DacaamAdmin\Controllers;

use Dacaam\Core\Database;
use Dacaam\Support\Plans;
use DacaamAdmin\Core\Access;
use DacaamAdmin\Core\Flash;
use DacaamAdmin\Core\PlatformAudit;
use DacaamAdmin\Core\Refused;
use DacaamAdmin\Core\Response;
use DacaamAdmin\Core\View;

/**
 * What the platform sells.
 *
 * A plan used to be whatever was typed into the subscription form, which is
 * how the same plan ended up spelled three ways with no price behind any of
 * them. Now it is a row: a code the subscriptions point at, a monthly price,
 * and two limits the API enforces when a restaurant adds staff or tables.
 *
 * Plans are retired, never deleted — subscriptions that were sold one keep
 * pointing at it, and an invoice must still be able to say what it was for.
 */
final class PlanController
{
    public function index(): void
    {
        View::page('plans', [
            'title'  => 'Plans',
            'nav'    => 'plans',
            'plans'  => Database::select(
                'SELECT p.*,
                        (SELECT COUNT(*) FROM subscriptions s
                           JOIN restaurants r ON r.id = s.restaurant_id
                          WHERE s.plan = p.code AND r.status <> "archived") AS restaurants
                   FROM plans p
                  ORDER BY p.sort_order ASC, p.id ASC',
            ),
            'manage' => Access::can('plans.manage'),
        ]);
    }

    public function store(): void
    {
        $code = strtolower(trim((string) ($_POST['code'] ?? '')));

        if (preg_match('/^[a-z0-9][a-z0-9_-]{1,31}$/', $code) !== 1) {
            throw new Refused('The code is 2–32 lowercase letters, numbers, - or _');
        }
        if (Plans::find($code) !== null) {
            throw new Refused("A plan with the code $code already exists");
        }

        $fields = self::fields();

        $id = Database::insert('plans', ['code' => $code] + $fields + [
            'sort_order' => (int) Database::scalar('SELECT COALESCE(MAX(sort_order), 0) + 10 FROM plans'),
        ]);

        PlatformAudit::log('plan_created', detail: sprintf('%s (#%d)', $code, $id));
        Flash::success(sprintf('Plan %s added.', $fields['name']));
        Response::redirect('/plans');
    }

    /** @param array<string,string> $params */
    public function update(array $params): void
    {
        $id = (int) $params['id'];
        $plan = Database::selectOne('SELECT * FROM plans WHERE id = :id', ['id' => $id]);

        if ($plan === null) {
            Response::notFound();
        }

        // The code is not editable: every subscription sold on this plan holds
        // it, and renaming it here would orphan them all.
        $fields = self::fields() + ['is_active' => ($_POST['is_active'] ?? '') === '1' ? 1 : 0];

        Database::run(
            'UPDATE plans
                SET name = :name, price = :price, max_users = :max_users,
                    max_tables = :max_tables, description = :description,
                    is_active = :is_active
              WHERE id = :id',
            $fields + ['id' => $id],
        );

        PlatformAudit::log(
            'plan_updated',
            detail: sprintf(
                '%s: %s/month, %s users, %s tables%s',
                $plan['code'],
                number_format((float) $fields['price'], 0),
                $fields['max_users'] === 0 ? 'unlimited' : (string) $fields['max_users'],
                $fields['max_tables'] === 0 ? 'unlimited' : (string) $fields['max_tables'],
                $fields['is_active'] === 1 ? '' : ', retired',
            ),
        );

        Flash::success(sprintf('Plan %s saved.', $fields['name']));
        Response::redirect('/plans');
    }

    /** @return array{name:string,price:float,max_users:int,max_tables:int,description:string} */
    private static function fields(): array
    {
        $name = trim((string) ($_POST['name'] ?? ''));
        if ($name === '' || mb_strlen($name) > 100) {
            throw new Refused('Give the plan a name (up to 100 characters)');
        }

        $price = (float) ($_POST['price'] ?? 0);
        if ($price < 0) {
            throw new Refused('The price cannot be negative');
        }

        $limit = static function (string $key): int {
            $value = (int) ($_POST[$key] ?? 0);
            if ($value < 0 || $value > 10000) {
                throw new Refused('Limits are between 0 (unlimited) and 10000');
            }

            return $value;
        };

        return [
            'name'        => $name,
            'price'       => $price,
            'max_users'   => $limit('max_users'),
            'max_tables'  => $limit('max_tables'),
            'description' => mb_substr(trim((string) ($_POST['description'] ?? '')), 0, 255),
        ];
    }
}
