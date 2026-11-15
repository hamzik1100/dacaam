<?php

declare(strict_types=1);

namespace Dacaam\Controllers;

use Dacaam\Core\Audit;
use Dacaam\Core\AuthContext;
use Dacaam\Core\Database;
use Dacaam\Core\Request;
use Dacaam\Core\Response;
use Dacaam\Repositories\Repository;
use Dacaam\Support\Period;
use Dacaam\Support\Presenter;
use Dacaam\Support\Pricing;

/**
 * Analytics.
 *
 * Cancelled orders and drafts are excluded from every revenue figure — they
 * are counted separately in Order Analytics but must never inflate sales.
 */
final class ReportController extends Repository
{
    private const REVENUE_SCOPE = "o.status <> 'cancelled'";

    /**
     * Extra WHERE clauses from the report filter sheet.
     *
     * Built once and reused by every section so the KPI row, the charts and
     * the breakdowns can never disagree about what is being reported on.
     *
     * @param  array<string,mixed> $bind
     * @return string
     */
    private function filters(Request $request, array &$bind): string
    {
        $clauses = [];

        if (($waiter = $request->queryString('waiter')) !== '') {
            $clauses[] = 'o.waiter_name = :f_waiter';
            $bind['f_waiter'] = $waiter;
        }
        if (($type = $request->queryString('order_type')) !== '') {
            $clauses[] = 'o.order_type = :f_type';
            $bind['f_type'] = $type;
        }
        if (($tableId = $request->queryInt('table_id')) !== null) {
            $clauses[] = 'o.table_id = :f_table';
            $bind['f_table'] = $tableId;
        }
        if (($method = $request->queryString('payment_method')) !== '') {
            $clauses[] = 'EXISTS (SELECT 1 FROM order_payments p
                                   WHERE p.order_id = o.id AND p.method = :f_method)';
            $bind['f_method'] = $method;
        }
        if (($categoryId = $request->queryInt('category_id')) !== null) {
            $clauses[] = 'EXISTS (SELECT 1 FROM order_items oi2
                                    JOIN menu_items m2 ON m2.id = oi2.menu_item_id
                                   WHERE oi2.order_id = o.id AND m2.category_id = :f_category)';
            $bind['f_category'] = $categoryId;
        }

        return $clauses === [] ? '' : ' AND ' . implode(' AND ', $clauses);
    }

    /** @return array<string,mixed> */
    public function summary(Request $request, AuthContext $context): array
    {
        $period = Period::resolve(
            $request->queryString('range', '7_days'),
            $request->queryString('from'),
            $request->queryString('to'),
        );

        $bind = [];
        $filter = $this->filters($request, $bind);

        $current = $this->totals(
            $context->restaurantId,
            $period->fromSql(),
            $period->toSql(),
            $filter,
            $bind,
        );
        $previous = $this->totals(
            $context->restaurantId,
            $period->previousFromSql(),
            $period->previousToSql(),
            $filter,
            $bind,
        );

        $profit = Pricing::round($current['sales'] - $current['expenses']);
        $previousProfit = Pricing::round($previous['sales'] - $previous['expenses']);

        return [
            'range' => $period->key,
            'from'  => $period->from->format('Y-m-d'),
            'to'    => $period->to->format('Y-m-d'),

            'sales'    => $this->kpi($current['sales'], $previous['sales']),
            'orders'   => $this->kpi($current['orders'], $previous['orders']),
            'expenses' => $this->kpi($current['expenses'], $previous['expenses']),
            'profit'   => $this->kpi($profit, $previousProfit),

            'gross_sales'    => Pricing::round($current['sales'] + $current['discounts']),
            'discounts'      => $current['discounts'],
            'tax'            => $current['tax'],
            'packaging'      => $current['packaging'],
            'avg_order_value' => $current['orders'] > 0
                ? Pricing::round($current['sales'] / $current['orders'])
                : 0.0,

            'completed_orders' => $current['completed'],
            'cancelled_orders' => $current['cancelled'],
            'dine_in_orders'   => $current['dine_in'],
            'takeaway_orders'  => $current['takeaway'],
            'draft_orders'     => $this->draftCount($context->restaurantId, $period),

            'daily'       => $this->daily($context->restaurantId, $period, $filter, $bind),
            'hourly'      => $this->hourly($context->restaurantId, $period, $filter, $bind),
            'by_category' => $this->byCategory($context->restaurantId, $period, $filter, $bind),
            'by_payment'  => $this->byPayment($context->restaurantId, $period, $filter, $bind),
            'by_waiter'   => $this->byWaiter($context->restaurantId, $period, $filter, $bind),
            'by_table'    => $this->byTable($context->restaurantId, $period, $filter, $bind),
            'top_items'   => $this->items($context->restaurantId, $period, 'DESC', 5, $filter, $bind),
            'low_items'   => $this->items($context->restaurantId, $period, 'ASC', 5, $filter, $bind),

            // Everything above this line is accrual: a credit sale counts the
            // moment the food leaves the kitchen. Everything below is cash that
            // actually moved. Shown together because either one alone misleads
            // — the first inflates a month of unpaid credit into takings, the
            // second hides a month of genuine trade.
            'cash' => $this->cash($context->restaurantId, $period),

            // What the restaurant is owed, and what it holds that is not its
            // own. Neither is a period figure: they are the position right now.
            'receivables'    => $this->receivables($context->restaurantId),

            // Money owed on orders that no ledger is carrying. Without this
            // the books did not add up: an order edited after payment, or one
            // part-settled at the counter, left `sales` above `cash` with
            // nothing in `receivables` to explain the difference — a sum the
            // restaurant is owed by nobody it can name.
            'unpaid_orders'  => $this->unpaidOrders($context->restaurantId),
            'deposits_held'  => $this->depositsHeld($context->restaurantId),

            'top_customers'  => $this->topCustomers($context->restaurantId, $period),
            'top_debtors'    => $this->topDebtors($context->restaurantId),
        ];
    }

    /**
     * Money that actually moved in the period, from the account ledger.
     *
     * Deliberately not derived from orders. An order tells you what was sold;
     * only the account transactions tell you what was collected, and with
     * credit in play those are different numbers.
     *
     * @return array<string,float>
     */
    private function cash(int $restaurantId, Period $period): array
    {
        $row = Database::selectOne(
            'SELECT
                COALESCE(SUM(CASE WHEN t.kind = "money_in"  THEN t.amount END), 0) AS money_in,
                COALESCE(SUM(CASE WHEN t.kind = "money_out" THEN t.amount END), 0) AS money_out,
                COALESCE(SUM(CASE WHEN t.source_type = "customer" AND t.kind = "money_in"
                                  THEN t.amount END), 0)                           AS from_customers
               FROM account_transactions t
              WHERE t.restaurant_id = :rid
                AND t.created_at BETWEEN :from AND :to
                -- A transfer moves money between the restaurant\'s own
                -- accounts and earns nothing. Both legs must go: excluding only
                -- kind = transfer left the receiving side, written as money_in,
                -- looking like a sale — so moving cash to the bank inflated the
                -- day by the amount moved, which is the easiest books-cooking
                -- there is.
                AND t.kind <> "transfer"
                AND t.source_type <> "transfer"',
            [
                'rid'  => $restaurantId,
                'from' => $period->from->format('Y-m-d H:i:s'),
                'to'   => $period->to->format('Y-m-d H:i:s'),
            ],
        ) ?? [];

        $in = Pricing::round((float) ($row['money_in'] ?? 0));
        $out = Pricing::round((float) ($row['money_out'] ?? 0));

        return [
            'money_in'       => $in,
            'money_out'      => $out,
            'net'            => Pricing::round($in - $out),
            // How much of today's cash was old debt being settled rather than
            // new trade. Without this the two are indistinguishable.
            'from_customers' => Pricing::round((float) ($row['from_customers'] ?? 0)),
        ];
    }

    /**
     * Outstanding on orders, excluding whatever a customer ledger already
     * carries.
     *
     * The subtraction is the point. A credit sale is owed twice over on paper —
     * once as an unpaid order and once as a charge on the customer — and adding
     * both to the same report would double it. What is left after taking the
     * ledger out is the part nobody has been made responsible for: a walk-in
     * who paid half, or an order that grew after it was settled.
     */
    private function unpaidOrders(int $restaurantId): float
    {
        return Pricing::round((float) Database::scalar(
            'SELECT COALESCE(SUM(GREATEST(owing, 0)), 0) FROM (
                SELECT o.total
                     - COALESCE((SELECT SUM(p.amount) FROM order_payments p
                                  WHERE p.order_id = o.id
                                    AND p.restaurant_id = o.restaurant_id), 0)
                     - COALESCE((SELECT SUM(l.amount) FROM customer_ledger l
                                  WHERE l.source_type = "order"
                                    AND l.source_id = o.id
                                    AND l.restaurant_id = o.restaurant_id), 0)
                       AS owing
                  FROM orders o
                 WHERE o.restaurant_id = :rid
                   AND o.status <> "cancelled"
            ) AS t',
            ['rid' => $restaurantId],
        ));
    }
    private function receivables(int $restaurantId): float
    {
        return Pricing::round((float) Database::scalar(
            'SELECT COALESCE(SUM(balance_owed), 0) FROM customers
              WHERE restaurant_id = :rid AND balance_owed > 0',
            ['rid' => $restaurantId],
        ));
    }

    /**
     * Customer money the restaurant is holding. A liability, not income: it has
     * been paid for food that has not been served.
     */
    private function depositsHeld(int $restaurantId): float
    {
        return Pricing::round(-(float) Database::scalar(
            'SELECT COALESCE(SUM(balance_owed), 0) FROM customers
              WHERE restaurant_id = :rid AND balance_owed < 0',
            ['rid' => $restaurantId],
        ));
    }

    /**
     * Measured on orders, not repayments.
     *
     * A customer clearing three months of debt today moves a great deal of
     * cash and has bought nothing; ranking on payments would put them top and
     * bury the person who actually eats here every day.
     *
     * @return list<array<string,mixed>>
     */
    private function topCustomers(int $restaurantId, Period $period): array
    {
        $rows = Database::select(
            'SELECT c.id, c.name, c.balance_owed,
                    COUNT(o.id) AS orders, COALESCE(SUM(o.total), 0) AS spent
               FROM customers c
               JOIN orders o ON o.customer_id = c.id AND o.status <> "cancelled"
              WHERE c.restaurant_id = :rid
                AND o.created_at BETWEEN :from AND :to
              GROUP BY c.id, c.name, c.balance_owed
              ORDER BY spent DESC
              LIMIT 10',
            [
                'rid'  => $restaurantId,
                'from' => $period->from->format('Y-m-d H:i:s'),
                'to'   => $period->to->format('Y-m-d H:i:s'),
            ],
        );

        return array_map(
            static fn (array $r): array => [
                'id'           => (int) $r['id'],
                'name'         => (string) $r['name'],
                'orders'       => (int) $r['orders'],
                'spent'        => Pricing::round((float) $r['spent']),
                'balance_owed' => Pricing::round((float) $r['balance_owed']),
            ],
            $rows,
        );
    }

    /**
     * Who owes the most, right now. Not period-scoped: a debt from March is
     * still a debt in August, and a list that forgot it would be worse than
     * useless.
     *
     * @return list<array<string,mixed>>
     */
    private function topDebtors(int $restaurantId): array
    {
        $rows = Database::select(
            'SELECT c.id, c.name, c.phone, c.balance_owed, c.credit_limit,
                    (SELECT MAX(l.created_at) FROM customer_ledger l
                      WHERE l.customer_id = c.id AND l.kind = "payment") AS last_paid
               FROM customers c
              WHERE c.restaurant_id = :rid AND c.balance_owed > 0
              ORDER BY c.balance_owed DESC
              LIMIT 10',
            ['rid' => $restaurantId],
        );

        return array_map(
            static fn (array $r): array => [
                'id'           => (int) $r['id'],
                'name'         => (string) $r['name'],
                'phone'        => (string) ($r['phone'] ?? ''),
                'balance_owed' => Pricing::round((float) $r['balance_owed']),
                'credit_limit' => Pricing::round((float) $r['credit_limit']),
                // Null when they have never paid anything, which is the row a
                // manager most wants to see.
                'last_paid'    => $r['last_paid'] === null
                    ? null
                    : Presenter::iso($r['last_paid']),
            ],
            $rows,
        );
    }

    /**
     * CSV export of the selected period.
     *
     * Emitted as a download rather than JSON: the point of Export is a file
     * somebody opens in a spreadsheet, and re-encoding JSON on the client
     * would just be the same table twice.
     */
    public function export(Request $request, AuthContext $context): never
    {
        $period = Period::resolve(
            $request->queryString('range', '7_days'),
            $request->queryString('from'),
            $request->queryString('to'),
        );

        $bind = [];
        $filter = $this->filters($request, $bind);
        $type = $request->queryString('type', 'orders');

        $rows = match ($type) {
            'items' => $this->exportItems($context->restaurantId, $period, $filter, $bind),
            'expenses' => $this->exportExpenses($context->restaurantId, $period),
            default => $this->exportOrders($context->restaurantId, $period, $filter, $bind),
        };

        Audit::log(
            $context,
            'reports',
            'report_exported',
            null,
            field: 'type',
            newValue: $type,
            reason: $period->from->format('Y-m-d') . ' → ' . $period->to->format('Y-m-d'),
        );

        $filename = sprintf(
            'dacaam-%s-%s-%s.csv',
            $type,
            $period->from->format('Ymd'),
            $period->to->format('Ymd'),
        );

        header('Content-Type: text/csv; charset=utf-8');
        header('Content-Disposition: attachment; filename="' . $filename . '"');
        Response::securityHeaders();
        Response::cors();

        $out = fopen('php://output', 'wb');
        // A BOM makes Excel open UTF-8 correctly; without it Somali names come
        // out mangled, which is exactly the audience for these files.
        fwrite($out, "\xEF\xBB\xBF");
        foreach ($rows as $row) {
            fputcsv($out, $row);
        }
        fclose($out);

        exit;
    }

    /** @return list<list<string|float|int>> */
    private function exportOrders(int $restaurantId, Period $period, string $filter, array $bind): array
    {
        $rows = Database::select(
            'SELECT o.order_number, o.created_at, o.order_type, o.status,
                    o.waiter_name, o.customer_name, o.guests,
                    CASE WHEN t.name <> "" THEN t.name
                         ELSE CONCAT("Table ", LPAD(t.table_number, 2, "0")) END AS table_label,
                    o.subtotal, o.discount, o.tax_amount, o.packaging_fee, o.total,
                    (SELECT GROUP_CONCAT(p.method) FROM order_payments p
                      WHERE p.order_id = o.id) AS methods
               FROM orders o
          LEFT JOIN `tables` t ON t.id = o.table_id
              WHERE o.restaurant_id = :rid
                AND o.created_at BETWEEN :from AND :to' . $filter . '
              ORDER BY o.created_at ASC',
            $bind + ['rid' => $restaurantId, 'from' => $period->fromSql(), 'to' => $period->toSql()],
        );

        $out = [[
            'Order', 'Date', 'Type', 'Status', 'Waiter', 'Customer', 'Guests',
            'Table', 'Subtotal', 'Discount', 'Tax', 'Packaging', 'Total', 'Payment',
        ]];

        foreach ($rows as $r) {
            $out[] = [
                '#' . $r['order_number'],
                (string) $r['created_at'],
                (string) $r['order_type'],
                (string) $r['status'],
                (string) $r['waiter_name'],
                (string) $r['customer_name'],
                (int) $r['guests'],
                (string) ($r['table_label'] ?? ''),
                (float) $r['subtotal'],
                (float) $r['discount'],
                (float) $r['tax_amount'],
                (float) $r['packaging_fee'],
                (float) $r['total'],
                (string) ($r['methods'] ?? ''),
            ];
        }

        return $out;
    }

    /** @return list<list<string|float|int>> */
    private function exportItems(int $restaurantId, Period $period, string $filter, array $bind): array
    {
        $rows = Database::select(
            'SELECT oi.item_name, c.name AS category, SUM(oi.quantity) AS qty,
                    AVG(oi.unit_price) AS avg_price, SUM(oi.line_total) AS revenue
               FROM order_items oi
               JOIN orders o     ON o.id = oi.order_id
          LEFT JOIN menu_items m ON m.id = oi.menu_item_id
          LEFT JOIN categories c ON c.id = m.category_id
              WHERE o.restaurant_id = :rid
                AND ' . self::REVENUE_SCOPE . '
                AND o.created_at BETWEEN :from AND :to' . $filter . '
              GROUP BY oi.item_name, c.name
              ORDER BY revenue DESC',
            $bind + ['rid' => $restaurantId, 'from' => $period->fromSql(), 'to' => $period->toSql()],
        );

        $out = [['Item', 'Category', 'Quantity', 'Avg Price', 'Revenue']];
        foreach ($rows as $r) {
            $out[] = [
                (string) $r['item_name'],
                (string) ($r['category'] ?? ''),
                (int) $r['qty'],
                round((float) $r['avg_price'], 2),
                (float) $r['revenue'],
            ];
        }

        return $out;
    }

    /** @return list<list<string|float|int>> */
    private function exportExpenses(int $restaurantId, Period $period): array
    {
        $rows = Database::select(
            'SELECT e.expense_date, e.name, e.kind, e.method, e.amount,
                    c.name AS category, u.name AS created_by
               FROM expenses e
          LEFT JOIN expense_categories c ON c.id = e.expense_category_id
          LEFT JOIN users u              ON u.id = e.created_by
              WHERE e.restaurant_id = :rid AND e.expense_date BETWEEN :from AND :to
                AND e.cancelled_at IS NULL
              ORDER BY e.expense_date ASC',
            [
                'rid'  => $restaurantId,
                'from' => $period->from->format('Y-m-d'),
                'to'   => $period->to->format('Y-m-d'),
            ],
        );

        $out = [['Date', 'Name', 'Category', 'Kind', 'Method', 'Amount', 'Recorded By']];
        foreach ($rows as $r) {
            $out[] = [
                (string) $r['expense_date'],
                (string) $r['name'],
                (string) ($r['category'] ?? ''),
                (string) $r['kind'],
                (string) $r['method'],
                (float) $r['amount'],
                (string) ($r['created_by'] ?? ''),
            ];
        }

        return $out;
    }

    /** @return array<string,mixed> */
    public function dashboard(Request $request, AuthContext $context): array
    {
        $today = Period::resolve('today');
        $current = $this->totals($context->restaurantId, $today->fromSql(), $today->toSql());
        $yesterday = $this->totals(
            $context->restaurantId,
            $today->previousFromSql(),
            $today->previousToSql(),
        );

        $profit = Pricing::round($current['sales'] - $current['expenses']);
        $previousProfit = Pricing::round($yesterday['sales'] - $yesterday['expenses']);

        $week = Period::resolve('this_week');

        return [
            'date'     => $today->from->format('Y-m-d'),
            'sales'    => $this->kpi($current['sales'], $yesterday['sales']),
            'orders'   => $this->kpi($current['orders'], $yesterday['orders']),
            'expenses' => $this->kpi($current['expenses'], $yesterday['expenses']),
            'profit'   => $this->kpi($profit, $previousProfit),
            'weekly'   => $this->weekly($context->restaurantId, $week),
            'previous_weekly' => $this->weekly(
                $context->restaurantId,
                Period::resolve('custom',
                    $week->from->modify('-7 days')->format('Y-m-d'),
                    $week->from->modify('-1 day')->format('Y-m-d'),
                ),
            ),
            'top_items' => $this->items($context->restaurantId, $today, 'DESC', 5),
        ];
    }

    // ------------------------------------------------------------ pieces

    /** @return array<string,float|int> */
    private function totals(
        int $restaurantId,
        string $from,
        string $to,
        string $filter = '',
        array $bind = [],
    ): array {
        $row = Database::selectOne(
            'SELECT
                COALESCE(SUM(CASE WHEN o.status <> "cancelled" THEN o.total END), 0)         AS sales,
                COALESCE(SUM(CASE WHEN o.status <> "cancelled" THEN o.discount END), 0)      AS discounts,
                COALESCE(SUM(CASE WHEN o.status <> "cancelled" THEN o.tax_amount END), 0)    AS tax,
                COALESCE(SUM(CASE WHEN o.status <> "cancelled" THEN o.packaging_fee END), 0) AS packaging,
                COALESCE(SUM(CASE WHEN o.status <> "cancelled" THEN 1 ELSE 0 END), 0)        AS orders,
                COALESCE(SUM(CASE WHEN o.status = "completed" THEN 1 ELSE 0 END), 0)         AS completed,
                COALESCE(SUM(CASE WHEN o.status = "cancelled" THEN 1 ELSE 0 END), 0)         AS cancelled,
                COALESCE(SUM(CASE WHEN o.order_type = "dine_in"  AND o.status <> "cancelled" THEN 1 ELSE 0 END), 0) AS dine_in,
                COALESCE(SUM(CASE WHEN o.order_type = "takeaway" AND o.status <> "cancelled" THEN 1 ELSE 0 END), 0) AS takeaway
              FROM orders o
             WHERE o.restaurant_id = :rid AND o.created_at BETWEEN :from AND :to' . $filter,
            $bind + ['rid' => $restaurantId, 'from' => $from, 'to' => $to],
        ) ?? [];

        // Expenses are restaurant-wide; an order-shaped filter (a waiter, a
        // table) cannot narrow them, so a filtered report shows unfiltered
        // spend rather than silently inventing an attribution that does not
        // exist in the data.
        $expenses = $filter !== '' ? 0.0 : (float) Database::scalar(
            // Cancelled spend is not spend. Leaving it in here would
            // understate profit by money that went back to the till.
            'SELECT COALESCE(SUM(amount), 0) FROM expenses
              WHERE restaurant_id = :rid AND expense_date BETWEEN :from AND :to
                AND cancelled_at IS NULL',
            [
                'rid'  => $restaurantId,
                'from' => substr($from, 0, 10),
                'to'   => substr($to, 0, 10),
            ],
        );

        return [
            'sales'     => (float) ($row['sales'] ?? 0),
            'discounts' => (float) ($row['discounts'] ?? 0),
            'tax'       => (float) ($row['tax'] ?? 0),
            'packaging' => (float) ($row['packaging'] ?? 0),
            'orders'    => (int) ($row['orders'] ?? 0),
            'completed' => (int) ($row['completed'] ?? 0),
            'cancelled' => (int) ($row['cancelled'] ?? 0),
            'dine_in'   => (int) ($row['dine_in'] ?? 0),
            'takeaway'  => (int) ($row['takeaway'] ?? 0),
            'expenses'  => $expenses,
        ];
    }

    /** @return array{value:float,delta_percent:float} */
    private function kpi(float|int $current, float|int $previous): array
    {
        return [
            'value'         => (float) $current,
            'delta_percent' => Period::delta((float) $current, (float) $previous),
        ];
    }

    /** @return list<array{label:string,value:float,date:string}> */
    private function daily(int $restaurantId, Period $period, string $filter = "", array $bind = []): array
    {
        $rows = Database::select(
            'SELECT DATE(o.created_at) AS d, COALESCE(SUM(o.total), 0) AS total
               FROM orders o
              WHERE o.restaurant_id = :rid
                AND ' . self::REVENUE_SCOPE . '
                AND o.created_at BETWEEN :from AND :to' . $filter . '
              GROUP BY DATE(o.created_at)
              ORDER BY d ASC',
            $bind + ['rid' => $restaurantId, 'from' => $period->fromSql(), 'to' => $period->toSql()],
        );

        $byDate = [];
        foreach ($rows as $row) {
            $byDate[(string) $row['d']] = (float) $row['total'];
        }

        // Zero-fill: a day with no sales is a data point, not a gap. Charts
        // that skip empty days misrepresent a quiet Tuesday as a busy one.
        $out = [];
        $cursor = $period->from->setTime(0, 0);
        while ($cursor <= $period->to) {
            $key = $cursor->format('Y-m-d');
            $out[] = [
                'label' => $cursor->format('j'),
                'value' => $byDate[$key] ?? 0.0,
                'date'  => $key,
            ];
            $cursor = $cursor->modify('+1 day');
        }

        return $out;
    }

    /** @return list<array{label:string,value:float,date:string}> */
    private function weekly(int $restaurantId, Period $period, string $filter = "", array $bind = []): array
    {
        return $this->daily($restaurantId, $period);
    }

    /** @return list<array{label:string,value:float}> */
    private function hourly(int $restaurantId, Period $period, string $filter = "", array $bind = []): array
    {
        $rows = Database::select(
            'SELECT HOUR(o.created_at) AS h, COALESCE(SUM(o.total), 0) AS total
               FROM orders o
              WHERE o.restaurant_id = :rid
                AND ' . self::REVENUE_SCOPE . '
                AND o.created_at BETWEEN :from AND :to' . $filter . '
              GROUP BY HOUR(o.created_at)
              ORDER BY h ASC',
            $bind + ['rid' => $restaurantId, 'from' => $period->fromSql(), 'to' => $period->toSql()],
        );

        $byHour = [];
        foreach ($rows as $row) {
            $byHour[(int) $row['h']] = (float) $row['total'];
        }

        // Service hours, not midnight-to-midnight: a flat 00:00–07:00 stretch
        // squashes the shape of the trading day.
        $out = [];
        for ($hour = 8; $hour <= 22; $hour++) {
            $out[] = [
                'label' => sprintf('%02d:00', $hour),
                'value' => $byHour[$hour] ?? 0.0,
            ];
        }

        return $out;
    }

    /** @return list<array{label:string,value:float,count:int,color:string}> */
    private function byCategory(int $restaurantId, Period $period, string $filter = "", array $bind = []): array
    {
        $rows = Database::select(
            'SELECT c.name AS label, c.color, COALESCE(SUM(oi.line_total), 0) AS value,
                    COALESCE(SUM(oi.quantity), 0) AS qty
               FROM order_items oi
               JOIN orders o     ON o.id = oi.order_id
               JOIN menu_items m ON m.id = oi.menu_item_id
               JOIN categories c ON c.id = m.category_id
              WHERE o.restaurant_id = :rid
                AND ' . self::REVENUE_SCOPE . '
                AND o.created_at BETWEEN :from AND :to' . $filter . '
              GROUP BY c.id, c.name, c.color
              ORDER BY value DESC',
            $bind + ['rid' => $restaurantId, 'from' => $period->fromSql(), 'to' => $period->toSql()],
        );

        return array_map(
            static fn (array $r): array => [
                'label' => (string) $r['label'],
                'value' => (float) $r['value'],
                'count' => (int) $r['qty'],
                'color' => (string) $r['color'],
            ],
            $rows,
        );
    }

    /** @return list<array{label:string,value:float,count:int}> */
    private function byPayment(int $restaurantId, Period $period, string $filter = "", array $bind = []): array
    {
        $rows = Database::select(
            'SELECT p.method AS label, COALESCE(SUM(p.amount), 0) AS value, COUNT(*) AS cnt
               FROM order_payments p
               JOIN orders o ON o.id = p.order_id
              WHERE p.restaurant_id = :rid
                AND ' . self::REVENUE_SCOPE . '
                AND p.created_at BETWEEN :from AND :to' . $filter . '
              GROUP BY p.method
              ORDER BY value DESC',
            $bind + ['rid' => $restaurantId, 'from' => $period->fromSql(), 'to' => $period->toSql()],
        );

        return array_map(
            static fn (array $r): array => [
                'label' => (string) $r['label'],
                'value' => (float) $r['value'],
                'count' => (int) $r['cnt'],
            ],
            $rows,
        );
    }

    /** @return list<array{label:string,value:float,count:int}> */
    private function byWaiter(int $restaurantId, Period $period, string $filter = "", array $bind = []): array
    {
        $rows = Database::select(
            'SELECT o.waiter_name AS label, COALESCE(SUM(o.total), 0) AS value, COUNT(*) AS cnt
               FROM orders o
              WHERE o.restaurant_id = :rid
                AND ' . self::REVENUE_SCOPE . '
                AND o.waiter_name <> ""
                AND o.created_at BETWEEN :from AND :to' . $filter . '
              GROUP BY o.waiter_name
              ORDER BY value DESC
              LIMIT 10',
            $bind + ['rid' => $restaurantId, 'from' => $period->fromSql(), 'to' => $period->toSql()],
        );

        return array_map(
            static fn (array $r): array => [
                'label' => (string) $r['label'],
                'value' => (float) $r['value'],
                'count' => (int) $r['cnt'],
            ],
            $rows,
        );
    }

    /** @return list<array<string,mixed>> */
    private function items(int $restaurantId, Period $period, string $direction, int $limit = 5, string $filter = "", array $bind = []): array
    {
        $direction = $direction === 'ASC' ? 'ASC' : 'DESC';

        $rows = Database::select(
            "SELECT oi.menu_item_id, oi.item_name, oi.emoji,
                    SUM(oi.quantity) AS qty, SUM(oi.line_total) AS revenue
               FROM order_items oi
               JOIN orders o ON o.id = oi.order_id
              WHERE o.restaurant_id = :rid
                AND " . self::REVENUE_SCOPE . "
                AND o.created_at BETWEEN :from AND :to" . $filter . "
              GROUP BY oi.menu_item_id, oi.item_name, oi.emoji
              ORDER BY qty $direction
              LIMIT " . max(1, min($limit, 50)),
            $bind + ['rid' => $restaurantId, 'from' => $period->fromSql(), 'to' => $period->toSql()],
        );

        return array_map(
            static fn (array $r): array => [
                'menu_item_id' => $r['menu_item_id'] === null ? null : (int) $r['menu_item_id'],
                'name'         => (string) $r['item_name'],
                'emoji'        => (string) $r['emoji'],
                'quantity'     => (int) $r['qty'],
                'revenue'      => (float) $r['revenue'],
            ],
            $rows,
        );
    }

    /**
     * Revenue per table. Takeaway has no table, so it is grouped separately
     * rather than dropped — otherwise the numbers here would not add up to
     * total sales and nobody could tell why.
     *
     * @return list<array{label:string,value:float,count:int}>
     */
    private function byTable(
        int $restaurantId,
        Period $period,
        string $filter = '',
        array $bind = [],
    ): array {
        $rows = Database::select(
            'SELECT CASE
                      WHEN o.table_id IS NULL THEN "Takeaway"
                      WHEN t.name <> "" THEN t.name
                      ELSE CONCAT("Table ", LPAD(t.table_number, 2, "0"))
                    END AS label,
                    COALESCE(SUM(o.total), 0) AS value, COUNT(*) AS cnt
               FROM orders o
          LEFT JOIN `tables` t ON t.id = o.table_id
              WHERE o.restaurant_id = :rid
                AND ' . self::REVENUE_SCOPE . '
                AND o.created_at BETWEEN :from AND :to' . $filter . '
              GROUP BY label
              ORDER BY value DESC
              LIMIT 15',
            $bind + ['rid' => $restaurantId, 'from' => $period->fromSql(), 'to' => $period->toSql()],
        );

        return array_map(
            static fn (array $r): array => [
                'label' => (string) $r['label'],
                'value' => (float) $r['value'],
                'count' => (int) $r['cnt'],
            ],
            $rows,
        );
    }

    private function draftCount(int $restaurantId, Period $period): int
    {
        return (int) Database::scalar(
            'SELECT COUNT(*) FROM draft_orders
              WHERE restaurant_id = :rid AND created_at BETWEEN :from AND :to',
            ['rid' => $restaurantId, 'from' => $period->fromSql(), 'to' => $period->toSql()],
        );
    }
}
