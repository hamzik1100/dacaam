<?php

declare(strict_types=1);

namespace DacaamAdmin\Controllers;

use Dacaam\Core\Database;
use DacaamAdmin\Core\View;

final class DashboardController
{
    public function index(): void
    {
        $counts = Database::selectOne(
            'SELECT
                SUM(status <> "archived") AS total,
                SUM(status = "active")    AS active,
                SUM(status = "trial")     AS trial,
                SUM(status = "suspended") AS suspended
               FROM restaurants',
        ) ?? [];

        // Subscription revenue is what was actually received, not what was
        // invoiced — an unpaid renewal is not income.
        $revenue = Database::selectOne(
            'SELECT
                COALESCE(SUM(amount), 0) AS lifetime,
                COALESCE(SUM(CASE WHEN paid_on >= DATE_SUB(CURDATE(), INTERVAL 30 DAY)
                                  THEN amount END), 0) AS last_30
               FROM subscription_payments',
        ) ?? [];

        // Platform-wide trading volume across every tenant, for the month.
        $gmv = (float) Database::scalar(
            'SELECT COALESCE(SUM(total), 0) FROM orders
              WHERE status <> "cancelled"
                AND created_at >= DATE_SUB(NOW(), INTERVAL 30 DAY)',
        );

        $expiring = Database::select(
            'SELECT s.*, r.name, r.slug,
                    DATEDIFF(s.ends_on, CURDATE()) AS days_left
               FROM subscriptions s
               JOIN restaurants r ON r.id = s.restaurant_id
              WHERE s.status IN ("active", "trial")
                AND r.status <> "archived"
                AND s.ends_on <= DATE_ADD(CURDATE(), INTERVAL 30 DAY)
              ORDER BY s.ends_on ASC
              LIMIT 10',
        );

        $busiest = Database::select(
            'SELECT r.id, r.name, r.slug, r.status,
                    COUNT(o.id) AS orders,
                    COALESCE(SUM(o.total), 0) AS sales
               FROM restaurants r
          LEFT JOIN orders o ON o.restaurant_id = r.id
                            AND o.status <> "cancelled"
                            AND o.created_at >= DATE_SUB(NOW(), INTERVAL 30 DAY)
              GROUP BY r.id, r.name, r.slug, r.status
              ORDER BY sales DESC
              LIMIT 8',
        );

        $recent = Database::select(
            'SELECT * FROM platform_audit_logs ORDER BY created_at DESC LIMIT 8',
        );

        View::page('dashboard', [
            // The renewal pipeline. Subscriptions already knew when each one
            // ends; what was missing was the working list — who to chase this
            // week, and what it is worth. With notifications in place this is
            // now one screen: see who is expiring, message them, see who paid.
            'renewals' => Database::select(
                'SELECT r.id, r.name, r.slug, s.plan, s.status AS sub_status,
                        s.ends_on, s.amount,
                        DATEDIFF(s.ends_on, CURDATE()) AS days_left
                   FROM subscriptions s
                   JOIN restaurants r ON r.id = s.restaurant_id
                  WHERE s.ends_on IS NOT NULL
                    AND r.status <> "archived"
                    AND DATEDIFF(s.ends_on, CURDATE()) <= 14
                  ORDER BY s.ends_on ASC
                  LIMIT 20',
            ),
            'at_risk' => (float) Database::scalar(
                'SELECT COALESCE(SUM(s.amount), 0)
                   FROM subscriptions s
                   JOIN restaurants r ON r.id = s.restaurant_id
                  WHERE s.ends_on IS NOT NULL
                    AND r.status <> "archived"
                    AND DATEDIFF(s.ends_on, CURDATE()) <= 14',
            ),
            'title'     => 'Dashboard',
            'nav'       => 'dashboard',
            'counts'    => $counts,
            'revenue'   => $revenue,
            'gmv'       => $gmv,
            'expiring'  => $expiring,
            'busiest'   => $busiest,
            'recent'    => $recent,
        ]);
    }
}
