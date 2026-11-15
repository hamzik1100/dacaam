<?php

declare(strict_types=1);

namespace DacaamAdmin\Controllers;

use Dacaam\Core\Database;
use Dacaam\Support\Plans;
use Dacaam\Support\RenewalReminders;
use DacaamAdmin\Core\Csv;
use DacaamAdmin\Core\Flash;
use DacaamAdmin\Core\PlatformAudit;
use DacaamAdmin\Core\Refused;
use DacaamAdmin\Core\Response;
use DacaamAdmin\Core\View;
use RuntimeException;

/**
 * Subscription lifecycle.
 *
 * An expired subscription restricts operations but never destroys data — the
 * restaurant keeps every order, every menu item and every balance, and renewal
 * restores access unchanged. That rule is what makes lapsing safe for them and
 * therefore workable for us.
 */
final class SubscriptionController
{
    public function index(): void
    {
        $filter = (string) ($_GET['status'] ?? '');

        $where = ['1 = 1'];
        $bind = [];

        if (in_array($filter, ['active', 'trial', 'expired', 'suspended'], true)) {
            $where[] = 's.status = :status';
            $bind['status'] = $filter;
        } elseif ($filter === 'expiring') {
            $where[] = 's.status IN ("active","trial")
                       AND s.ends_on <= DATE_ADD(CURDATE(), INTERVAL 30 DAY)';
        }

        $subscriptions = Database::select(
            'SELECT s.*, r.name, r.slug, r.status AS restaurant_status,
                    DATEDIFF(s.ends_on, CURDATE()) AS days_left,
                    (SELECT COALESCE(SUM(p.amount), 0) FROM subscription_payments p
                      WHERE p.subscription_id = s.id) AS paid
               FROM subscriptions s
               JOIN restaurants r ON r.id = s.restaurant_id
              WHERE ' . implode(' AND ', $where) . '
              ORDER BY s.ends_on ASC',
            $bind,
        );

        if (($_GET['format'] ?? '') === 'csv') {
            PlatformAudit::log('csv_exported', detail: 'subscriptions' . ($filter !== '' ? " ($filter)" : ''));

            Csv::download(
                Csv::filename('subscriptions' . ($filter !== '' ? "-$filter" : '')),
                ['Restaurant', 'Code', 'Plan', 'Status', 'Starts', 'Ends', 'Days left', 'Plan amount', 'Paid to date'],
                array_map(static fn (array $s): array => [
                    $s['name'], $s['slug'], $s['plan'], $s['status'], $s['starts_on'],
                    $s['ends_on'], $s['days_left'], $s['amount'], $s['paid'],
                ], $subscriptions),
            );
        }

        $totals = Database::selectOne(
            'SELECT
                COALESCE(SUM(amount), 0) AS lifetime,
                COALESCE(SUM(CASE WHEN paid_on >= DATE_FORMAT(CURDATE(), "%Y-%m-01")
                                  THEN amount END), 0) AS this_month
               FROM subscription_payments',
        ) ?? [];

        View::page('subscriptions/index', [
            'title'         => 'Subscriptions',
            'nav'           => 'subscriptions',
            'subscriptions' => $subscriptions,
            'totals'        => $totals,
            'filter'        => $filter,
            // Who is about to be told, and who already was. The daily cron
            // does the sending; the button on the page does the same for a
            // host without one.
            'due'           => RenewalReminders::due(),
            'reminders'     => Database::select(
                'SELECT m.*, r.name, r.slug
                   FROM subscription_reminders m
                   JOIN restaurants r ON r.id = m.restaurant_id
                  ORDER BY m.created_at DESC, m.id DESC
                  LIMIT 15',
            ),
        ]);
    }

    /** Sends every renewal reminder that is due now. */
    public function sendReminders(): void
    {
        $result = RenewalReminders::send();

        PlatformAudit::log(
            'renewal_reminders_sent',
            detail: $result['sent'] === [] ? 'none due' : implode(', ', $result['sent']),
        );

        Flash::success(
            $result['restaurants'] === 0
                ? 'Nothing due — every reminder that applies today has already gone out.'
                : sprintf(
                    'Reminded %d restaurant(s): %d admin(s) notified, %d push, %d email(s) queued.',
                    $result['restaurants'],
                    $result['notified'],
                    $result['pushed'],
                    $result['emailed'],
                ),
        );
        Response::redirect('/subscriptions');
    }

    /** @param array<string,string> $params */
    public function update(array $params): void
    {
        $id = (int) $params['id'];
        $subscription = self::find($id);

        $plan = self::plan((string) ($_POST['plan'] ?? $subscription['plan']), (string) $subscription['plan']);
        $status = (string) ($_POST['status'] ?? 'active');
        $endsOn = (string) ($_POST['ends_on'] ?? '');
        $amount = (float) ($_POST['amount'] ?? 0);

        if (!in_array($status, ['active', 'trial', 'expired', 'suspended'], true)) {
            throw new Refused('Unknown subscription status');
        }
        if (strtotime($endsOn) === false) {
            throw new Refused('End date is not valid');
        }

        Database::transaction(static function () use ($id, $subscription, $plan, $status, $endsOn, $amount): void {
            Database::run(
                'UPDATE subscriptions
                    SET plan = :plan, status = :status, ends_on = :ends, amount = :amount
                  WHERE id = :id',
                [
                    'plan'   => $plan,
                    'status' => $status,
                    'ends'   => date('Y-m-d', (int) strtotime($endsOn)),
                    'amount' => $amount,
                    'id'     => $id,
                ],
            );

            // The restaurant's own status follows the subscription: those two
            // disagreeing is how a suspended tenant ends up still trading.
            $restaurantStatus = match ($status) {
                'trial'     => 'trial',
                'active'    => 'active',
                default     => 'suspended',
            };

            Database::run(
                'UPDATE restaurants SET status = :status WHERE id = :id',
                ['status' => $restaurantStatus, 'id' => $subscription['restaurant_id']],
            );

            if ($restaurantStatus === 'suspended') {
                Database::run(
                    'UPDATE api_tokens SET revoked_at = NOW()
                      WHERE restaurant_id = :id AND revoked_at IS NULL',
                    ['id' => $subscription['restaurant_id']],
                );
            }
        });

        PlatformAudit::log(
            'subscription_updated',
            restaurantId: (int) $subscription['restaurant_id'],
            detail: sprintf('%s → %s, ends %s', $subscription['status'], $status, $endsOn),
        );

        Flash::success('Subscription updated.');
        Response::redirect('/restaurants/' . $subscription['restaurant_id']);
    }

    /** @param array<string,string> $params */
    public function renew(array $params): void
    {
        $id = (int) $params['id'];
        $subscription = self::find($id);

        $months = max(1, min(36, (int) ($_POST['months'] ?? 12)));
        $amount = (float) ($_POST['amount'] ?? 0);
        $method = (string) ($_POST['method'] ?? 'bank');
        $reference = trim((string) ($_POST['reference'] ?? ''));
        // Renewal is when a restaurant most often moves up a plan.
        $plan = self::plan((string) ($_POST['plan'] ?? $subscription['plan']), (string) $subscription['plan']);

        if (!in_array($method, ['cash', 'zaad', 'edahab', 'bank'], true)) {
            throw new Refused('Unknown payment method');
        }

        $paymentId = Database::transaction(static function () use ($id, $subscription, $months, $amount, $method, $reference, $plan): ?int {
            // Renewing an already-expired subscription starts from today, not
            // from the lapsed end date — otherwise a restaurant that renews
            // three months late pays for time it could not use.
            $lapsed = strtotime((string) $subscription['ends_on']) < time();
            $from = $lapsed ? 'CURDATE()' : '`ends_on`';

            Database::run(
                "UPDATE subscriptions
                    SET ends_on = DATE_ADD($from, INTERVAL :months MONTH),
                        status = 'active',
                        plan = :plan,
                        amount = :amount
                  WHERE id = :id",
                ['months' => $months, 'plan' => $plan, 'amount' => $amount, 'id' => $id],
            );

            Database::run(
                'UPDATE restaurants SET status = "active" WHERE id = :id',
                ['id' => $subscription['restaurant_id']],
            );

            if ($amount <= 0) {
                return null;
            }

            // What the money bought, fixed at the moment it was paid, so the
            // invoice still says so after the next renewal moves the dates.
            return Database::insert('subscription_payments', [
                'subscription_id' => $id,
                'restaurant_id'   => (int) $subscription['restaurant_id'],
                'amount'          => $amount,
                'method'          => $method,
                'reference'       => $reference,
                'paid_on'         => date('Y-m-d'),
                'recorded_by'     => $_SESSION['super_admin_id'] ?? null,
                'plan'            => $plan,
                'months'          => $months,
                'period_start'    => $lapsed
                    ? date('Y-m-d')
                    : date('Y-m-d', (int) strtotime($subscription['ends_on'] . ' +1 day')),
                'period_end'      => (string) Database::scalar(
                    'SELECT ends_on FROM subscriptions WHERE id = :id',
                    ['id' => $id],
                ),
            ]);
        });

        PlatformAudit::log(
            'subscription_renewed',
            restaurantId: (int) $subscription['restaurant_id'],
            detail: sprintf('%s, %d month(s), %s', $plan, $months, number_format($amount, 0)),
        );

        Flash::success(
            $paymentId === null
                ? 'Subscription renewed. No payment was recorded.'
                : sprintf('Subscription renewed and payment recorded — invoice %s.', InvoiceController::number([
                    'id'      => $paymentId,
                    'paid_on' => date('Y-m-d'),
                ])),
        );
        Response::redirect('/restaurants/' . $subscription['restaurant_id']);
    }

    /**
     * A plan code that exists.
     *
     * The current plan is accepted even when it has since been retired, so
     * saving an unrelated change does not force a restaurant off it.
     */
    private static function plan(string $code, string $current): string
    {
        $code = strtolower(trim($code));
        $plan = Plans::find($code);

        if ($plan === null || ((int) $plan['is_active'] !== 1 && $code !== strtolower($current))) {
            throw new Refused('Choose a plan from the list');
        }

        return $code;
    }

    /** @return array<string,mixed> */
    private static function find(int $id): array
    {
        $row = Database::selectOne(
            'SELECT s.*, r.status AS restaurant_status
               FROM subscriptions s
               JOIN restaurants r ON r.id = s.restaurant_id
              WHERE s.id = :id LIMIT 1',
            ['id' => $id],
        );

        if ($row === null) {
            Response::notFound();
        }

        // Renewing would quietly reactivate a restaurant that has left.
        if ($row['restaurant_status'] === 'archived') {
            throw new Refused('This restaurant is archived. Restore it from the archive first.');
        }

        return $row;
    }
}
