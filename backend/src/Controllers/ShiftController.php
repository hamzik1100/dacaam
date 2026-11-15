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
use Dacaam\Support\Presenter;
use Dacaam\Support\Pricing;
use Dacaam\Support\Shifts;
use PDOException;

/**
 * Counting the drawer against what the system says.
 *
 * Every other control in this system watches actions that were recorded — who
 * edited an order, who adjusted a balance, who voided an expense. The theft
 * that defeats all of them is the sale that was never entered at all: there is
 * no row to audit, no total that looks wrong, nothing to alert on.
 *
 * Counting the cash is the one control that catches it, because the money in
 * the drawer is not something the software can be talked out of. A till that is
 * short by twenty thousand five evenings running is not a rounding problem, and
 * without a count nobody would ever have a reason to look.
 *
 * The expected figure is derived from `account_transactions` rather than
 * recomputed from orders. One source of truth means the shift and the Accounts
 * screen agree by construction; two calculations drift, and then nobody can say
 * which of them is right.
 */
final class ShiftController extends Repository
{
    /**
     * What is open on a till right now.
     *
     * Deliberately without the expected total. Whoever is about to count the
     * drawer must not be able to read the number they are supposed to arrive
     * at independently — see `shifts.view` versus `shifts.manage`.
     *
     * @return array<string,mixed>
     */
    public function current(Request $request, AuthContext $context): array
    {
        $accountId = $request->queryString('account_id') !== ''
            ? (int) $request->queryString('account_id')
            : self::defaultTill($context->restaurantId);

        if ($accountId === 0) {
            return ['shift' => null, 'account_id' => null];
        }

        $shift = Database::selectOne(
            'SELECT s.*, u.name AS opened_by_name
               FROM shifts s
          LEFT JOIN users u ON u.id = s.opened_by
              WHERE s.restaurant_id = :rid AND s.account_id = :aid AND s.closed_at IS NULL
              LIMIT 1',
            ['rid' => $context->restaurantId, 'aid' => $accountId],
        );

        return [
            'account_id' => $accountId,
            'shift'      => $shift === null ? null : Presenter::shift($shift, blind: true),
            // What the drawer held when it was last closed. Not the expected
            // total — this is what the previous person counted, which the next
            // one needs in order to know what they are starting from.
            'last_close' => self::lastClose($context->restaurantId, $accountId),
            // Every account the closing screen has to ask about, by name and
            // without a balance. The list is needed to build the form; the
            // balances are the answer, and handing those over would turn the
            // count into a transcription.
            'accounts'   => self::countable($context->restaurantId, $shift),
            // What went out of the tills today. The cashier paid these, so it
            // is not news to them — but it is why the drawer holds less than
            // the day's sales, and a close that does not show it invites a
            // panicked recount of money that was legitimately spent.
            'expenses'   => self::todaysExpenses($context->restaurantId, $shift),
        ];
    }

    /**
     * Opens a till for the day.
     *
     * @return array<string,mixed>
     */
    public function open(Request $request, AuthContext $context): array
    {
        $data = Validator::check($request->all(), [
            'account_id'    => 'nullable|int',
            'opening_float' => 'required|numeric|min:0|max:1000000000',
            'notes'         => 'nullable|string|max:500',
        ]);

        $accountId = isset($data['account_id']) && (int) $data['account_id'] > 0
            ? (int) $data['account_id']
            : self::defaultTill($context->restaurantId);

        if ($accountId === 0) {
            throw ApiException::validation(['account_id' => 'No cash account to open']);
        }

        $account = self::requireScoped('accounts', $accountId, $context->restaurantId, 'Account not found');

        // The shift is opened against the cash drawer because that is the
        // physical thing somebody unlocks. Every other account is counted at
        // close alongside it — a Zaad balance can be read off the phone, so it
        // can be checked, and a payment recorded as Zaad that never arrived is
        // exactly the hole that leaving it unchecked keeps open.
        if ((string) $account['method'] !== 'cash') {
            throw ApiException::validation([
                'account_id' => 'A shift opens against the cash drawer. The other accounts are counted when it closes.',
            ]);
        }

        $float = Pricing::round((float) $data['opening_float']);
        $previous = self::lastClose($context->restaurantId, $accountId);

        try {
            $id = Database::transaction(function () use ($context, $accountId, $float, $previous, $data): int {
                $id = Database::insert('shifts', [
                    'restaurant_id'  => $context->restaurantId,
                    'account_id'     => $accountId,
                    'opened_by'      => $context->userId,
                    'opening_float'  => $float,
                    'previous_close' => $previous,
                    // Money that goes missing between a close and the next open
                    // was lost while nobody was there. That is a different
                    // question from a till being short during a shift, and
                    // folding the two together hides both.
                    'overnight_diff' => $previous === null
                        ? null
                        : Pricing::round($float - $previous),
                    'notes'          => (string) ($data['notes'] ?? ''),
                    'open_marker'    => $accountId,
                ]);

                Audit::log(
                    $context,
                    'shifts',
                    'shift_opened',
                    $id,
                    field: 'opening_float',
                    oldValue: $previous === null ? null : (string) $previous,
                    newValue: (string) $float,
                );

                Shifts::forget();

                return $id;
            });
        } catch (PDOException $e) {
            // The unique index on open_marker is what enforces one open shift
            // per till, so two people opening at the same moment cannot both
            // succeed. Turning the constraint into a sentence is friendlier
            // than letting a 500 out.
            if (str_starts_with((string) $e->getCode(), '23')) {
                throw ApiException::conflict('This till already has an open shift');
            }

            throw $e;
        }

        return self::find($context->restaurantId, $id, blind: true);
    }

    /**
     * Counts the drawer and closes the till.
     *
     * The expected total is not returned anywhere before this point, so the
     * number that arrives here is a count rather than a copy.
     *
     * @return array<string,mixed>
     */
    public function close(Request $request, AuthContext $context): array
    {
        $id = $request->intParam('id');

        $data = Validator::check($request->all(), [
            // One figure per account, not one for the till. Cash short by
            // twenty thousand while Zaad is over by twenty thousand nets to
            // nothing and is two separate problems; a single total would have
            // hidden both.
            'counts' => 'required|array|min:1',
            'reason' => 'nullable|string|max:255',
            'notes'  => 'nullable|string|max:500',
        ]);

        // The rows inside are checked here rather than through dotted rules:
        // the validator does not walk into arrays, and a rule it silently
        // ignores is worse than no rule — it reads as protection that is not
        // there. Money is being recorded, so every figure is checked by hand.
        $checked = [];

        foreach ((array) $data['counts'] as $entry) {
            if (!is_array($entry)
                || !isset($entry['account_id'], $entry['counted'])
                || !is_numeric($entry['account_id'])
                || !is_numeric($entry['counted'])
            ) {
                throw ApiException::validation([
                    'counts' => 'Each account needs an id and a counted amount',
                ]);
            }

            $amount = (float) $entry['counted'];

            if ($amount < 0 || $amount > 1000000000) {
                throw ApiException::validation([
                    'counts' => 'A counted amount is out of range',
                ]);
            }

            $checked[] = [
                'account_id' => (int) $entry['account_id'],
                'counted'    => $amount,
            ];
        }

        $data['counts'] = $checked;

        $reason = trim((string) ($data['reason'] ?? ''));

        /** @var list<array{account_id:int,counted:float}> $counts */
        $counts = $data['counts'];

        $result = Database::transaction(function () use ($context, $id, $counts, $reason, $data): array {
            // Locked and re-read rather than trusting a copy fetched earlier:
            // two taps on a slow connection arrive as two requests, and the
            // second would post a second set of variance adjustments against a
            // till that had already been settled.
            $shift = Database::selectOne(
                'SELECT * FROM shifts WHERE id = :id AND restaurant_id = :rid FOR UPDATE',
                ['id' => $id, 'rid' => $context->restaurantId],
            );

            if ($shift === null) {
                throw ApiException::notFound('Shift not found');
            }

            if ($shift['closed_at'] !== null) {
                throw ApiException::conflict('This shift is already closed');
            }

            $countable = self::countable($context->restaurantId);
            $byId = [];
            foreach ($countable as $account) {
                $byId[(int) $account['id']] = $account;
            }

            $given = [];
            foreach ($counts as $entry) {
                $accountId = (int) $entry['account_id'];

                if (!isset($byId[$accountId])) {
                    throw ApiException::validation([
                        'counts' => 'That account does not belong to this restaurant',
                    ]);
                }

                $given[$accountId] = Pricing::round((float) $entry['counted']);
            }

            // Every account, or none. A close that quietly skipped the Zaad
            // balance would report a balanced till while a hole sat in the one
            // account nobody was asked about.
            $missing = array_diff(array_keys($byId), array_keys($given));

            if ($missing !== []) {
                $names = array_map(
                    static fn (int $aid): string => (string) $byId[$aid]['name'],
                    array_values($missing),
                );

                throw ApiException::validation([
                    'counts' => 'Count every account before closing: ' . implode(', ', $names),
                ]);
            }

            $tolerance = self::tolerance($context->restaurantId);
            $lines = [];
            $totalExpected = 0.0;
            $totalCounted = 0.0;
            $worst = 0.0;

            foreach ($given as $accountId => $counted) {
                $expected = self::expectedFor($context->restaurantId, $shift, $accountId);
                $variance = Pricing::round($counted - $expected);

                $lines[] = [
                    'account_id' => $accountId,
                    'name'       => (string) $byId[$accountId]['name'],
                    'method'     => (string) $byId[$accountId]['method'],
                    'expected'   => $expected,
                    'counted'    => $counted,
                    'variance'   => $variance,
                ];

                $totalExpected += $expected;
                $totalCounted += $counted;

                if (abs($variance) > abs($worst)) {
                    $worst = $variance;
                }
            }

            // Judged per account, not on the total. Two errors that cancel out
            // are still two errors, and a net of zero must not buy silence.
            if (abs($worst) > $tolerance && $reason === '') {
                throw ApiException::validation([
                    'reason' => sprintf(
                        'One account is %s %s. Say what happened.',
                        number_format(abs($worst), 0),
                        $worst < 0 ? 'short' : 'over',
                    ),
                ]);
            }

            $totalExpected = Pricing::round($totalExpected);
            $totalCounted = Pricing::round($totalCounted);
            $totalVariance = Pricing::round($totalCounted - $totalExpected);

            Database::run(
                'UPDATE shifts
                    SET closed_by = :uid, closed_at = NOW(),
                        expected_close = :expected, counted_close = :counted,
                        variance = :variance, close_reason = :reason,
                        orders_outside = 0,
                        notes = CONCAT(notes, :notes),
                        open_marker = NULL
                  WHERE id = :id AND restaurant_id = :rid',
                [
                    'uid'      => $context->userId,
                    'expected' => $totalExpected,
                    'counted'  => $totalCounted,
                    'variance' => $totalVariance,
                    'reason'   => $reason === '' ? null : $reason,
                    'notes'    => isset($data['notes']) && $data['notes'] !== ''
                        ? "\n" . (string) $data['notes']
                        : '',
                    'id'       => $id,
                    'rid'      => $context->restaurantId,
                ],
            );

            foreach ($lines as $line) {
                Database::insert('shift_counts', [
                    'shift_id'   => $id,
                    'account_id' => $line['account_id'],
                    'expected'   => $line['expected'],
                    'counted'    => $line['counted'],
                    'variance'   => $line['variance'],
                ]);

                // Each balance is made to match its own count, through a
                // visible ledger entry with a name on it.
                //
                // Leaving them alone would be tidier for one evening and wrong
                // for every one after: tomorrow's expected totals would start
                // from figures nobody has held, and the error would compound
                // until the numbers meant nothing at all.
                if (abs($line['variance']) > 0.001) {
                    self::postVariance(
                        $context,
                        $line['account_id'],
                        $id,
                        $line['variance'],
                        $reason,
                    );
                }
            }

            Audit::log(
                $context,
                'shifts',
                'shift_closed',
                $id,
                field: 'variance',
                oldValue: (string) $totalExpected,
                newValue: (string) $totalCounted,
                reason: $reason === '' ? null : $reason,
            );

            // A second, separate row when something did not balance.
            //
            // Every till closes every evening, and the alerting hangs off the
            // audit trail — so if the close itself were the alerted action the
            // owner would get one email a night, almost all of them saying
            // nothing happened, and the one that mattered would arrive into a
            // folder they had already learned to skip.
            if (abs($worst) > $tolerance) {
                Audit::log(
                    $context,
                    'shifts',
                    'shift_variance',
                    $id,
                    field: $worst < 0 ? 'gaabis' : 'dheeraad',
                    oldValue: (string) $totalExpected,
                    newValue: (string) $totalCounted,
                    reason: $reason === '' ? null : $reason,
                );
            }

            Shifts::forget();

            return [
                'expected' => $totalExpected,
                'counted'  => $totalCounted,
                'variance' => $totalVariance,
                'accounts' => $lines,
            ];
        });

        // Revealed only now, with the count already committed.
        return self::find($context->restaurantId, $id, blind: false) + [
            'revealed' => $result,
        ];
    }

    /**
     * A mid-shift look at where the till stands, without closing it.
     *
     * The manager's view — `shifts.view`, not `shifts.manage` — because it
     * carries the expected total and handing that to the person about to count
     * turns the count into a transcription.
     *
     * @return array<string,mixed>
     */
    public function peek(Request $request, AuthContext $context): array
    {
        $id = $request->intParam('id');
        $shift = self::requireScoped('shifts', $id, $context->restaurantId, 'Shift not found');

        $expected = $shift['closed_at'] === null
            ? self::expected($context->restaurantId, $shift)
            : (float) $shift['expected_close'];

        // Names for the two ends of the shift. The list query joins these; a
        // single row read straight from the table does not, and a detail screen
        // showing a blank where the person's name belongs is the one thing it
        // exists to say.
        $shift['opened_by_name'] = Database::scalar(
            'SELECT name FROM users WHERE id = :id',
            ['id' => $shift['opened_by']],
        ) ?: '';

        $shift['closed_by_name'] = $shift['closed_by'] === null ? '' : (Database::scalar(
            'SELECT name FROM users WHERE id = :id',
            ['id' => $shift['closed_by']],
        ) ?: '');

        $shift['account_name'] = Database::scalar(
            'SELECT name FROM accounts WHERE id = :id',
            ['id' => $shift['account_id']],
        ) ?: '';

        return [
            'shift'     => Presenter::shift($shift, blind: false),
            'expected'  => $expected,
            // Per account, once it is closed. A single total for the whole till
            // would net a short drawer against an over one and report a clean
            // night, which is the thing this breakdown exists to prevent.
            'accounts'  => $shift['closed_at'] === null ? [] : self::countsFor($id),
            'expenses'  => self::todaysExpenses($context->restaurantId, $shift),
            'movements' => self::movements($context->restaurantId, $shift),
        ];
    }

    /**
     * Shift history.
     *
     * The list is the point, not any single row: one short evening is a
     * Tuesday, and the same person short on eleven of them is a pattern that
     * only shows up next to the others.
     *
     * @return list<array<string,mixed>>
     */
    public function index(Request $request, AuthContext $context): array
    {
        $limit = min(200, max(1, (int) ($request->queryString('limit') ?: 60)));

        $rows = Database::select(
            'SELECT s.*, o.name AS opened_by_name, c.name AS closed_by_name,
                    a.name AS account_name
               FROM shifts s
          LEFT JOIN users o ON o.id = s.opened_by
          LEFT JOIN users c ON c.id = s.closed_by
          LEFT JOIN accounts a ON a.id = s.account_id
              WHERE s.restaurant_id = :rid
              ORDER BY s.opened_at DESC
              LIMIT ' . $limit,
            ['rid' => $context->restaurantId],
        );

        return array_map(
            static fn (array $row): array => Presenter::shift($row, blind: false),
            $rows,
        );
    }

    // ------------------------------------------------------------- helpers

    /**
     * float + money in − money out, over the shift's own rows.
     *
     * Rows are matched by `shift_id` where it was stamped and by time where it
     * was not, so a database that predates the column still reports honestly
     * rather than showing every till as empty.
     */
    private static function expected(int $restaurantId, array $shift): float
    {
        return self::expectedFor($restaurantId, $shift, (int) $shift['account_id']);
    }

    /**
     * What one account should hold right now.
     *
     * The opening float belongs to the drawer the shift was opened against;
     * every other account starts the shift wherever the last close left it,
     * which the ledger already reflects.
     */
    private static function expectedFor(int $restaurantId, array $shift, int $accountId): float
    {
        $row = Database::selectOne(
            'SELECT
                COALESCE(SUM(CASE WHEN kind IN ("money_in") THEN amount ELSE 0 END), 0) AS money_in,
                COALESCE(SUM(CASE WHEN kind IN ("money_out") THEN amount ELSE 0 END), 0) AS money_out,
                COALESCE(SUM(CASE WHEN kind = "transfer" AND account_id = :aid2 THEN amount ELSE 0 END), 0) AS sent,
                COALESCE(SUM(CASE WHEN kind = "transfer" AND to_account_id = :aid3 THEN amount ELSE 0 END), 0) AS received,
                COALESCE(SUM(CASE WHEN kind = "adjustment" THEN amount ELSE 0 END), 0) AS adjusted
               FROM account_transactions
              WHERE restaurant_id = :rid
                AND (account_id = :aid OR to_account_id = :aid4)
                AND created_at >= :opened
                AND (shift_id IS NULL OR shift_id = :sid)',
            [
                'rid'    => $restaurantId,
                'aid'    => $accountId,
                'aid2'   => $accountId,
                'aid3'   => $accountId,
                'aid4'   => $accountId,
                'opened' => $shift['opened_at'],
                'sid'    => $shift['id'],
            ],
        ) ?? [];

        $float = (int) $shift['account_id'] === $accountId
            ? (float) $shift['opening_float']
            : 0.0;

        $expected = $float
            + (float) ($row['money_in'] ?? 0)
            - (float) ($row['money_out'] ?? 0)
            - (float) ($row['sent'] ?? 0)
            + (float) ($row['received'] ?? 0)
            + (float) ($row['adjusted'] ?? 0);

        return Pricing::round($expected);
    }

    /** @return list<array<string,mixed>> */
    private static function movements(int $restaurantId, array $shift): array
    {
        return Database::select(
            'SELECT kind, description, amount, created_at
               FROM account_transactions
              WHERE restaurant_id = :rid AND account_id = :aid
                AND created_at >= :opened
                AND (:closed IS NULL OR created_at <= :closed2)
              ORDER BY id DESC LIMIT 100',
            [
                'rid'     => $restaurantId,
                'aid'     => $shift['account_id'],
                'opened'  => $shift['opened_at'],
                'closed'  => $shift['closed_at'],
                'closed2' => $shift['closed_at'],
            ],
        );
    }

    /**
     * Orders taken while no shift was open.
     *
     * Not blocked — a till that refuses money because of a missed button is
     * worse than a hole in a report — but counted, so the hole is visible to
     * whoever reads the close.
     */
    private static function ordersOutside(int $restaurantId, array $shift): int
    {
        return (int) Database::scalar(
            'SELECT COUNT(*) FROM orders
              WHERE restaurant_id = :rid
                AND shift_id IS NULL
                AND status <> "cancelled"
                AND created_at >= :opened',
            ['rid' => $restaurantId, 'opened' => $shift['opened_at']],
        );
    }

    /** The variance, as a visible ledger row rather than a silent correction. */
    private static function postVariance(
        AuthContext $context,
        int $accountId,
        int $shiftId,
        float $variance,
        string $reason,
    ): void {
        $account = Database::selectOne(
            'SELECT balance FROM accounts WHERE id = :id AND restaurant_id = :rid FOR UPDATE',
            ['id' => $accountId, 'rid' => $context->restaurantId],
        );

        if ($account === null) {
            return;
        }

        $balance = Pricing::round((float) $account['balance'] + $variance);

        Database::run(
            'UPDATE accounts SET balance = :b WHERE id = :id AND restaurant_id = :rid',
            ['b' => $balance, 'id' => $accountId, 'rid' => $context->restaurantId],
        );

        Database::insert('account_transactions', [
            'restaurant_id' => $context->restaurantId,
            'account_id'    => $accountId,
            'kind'          => 'adjustment',
            'amount'        => $variance,
            'balance_after' => $balance,
            'description'   => sprintf(
                'Xidhitaanka shifka — %s%s',
                $variance < 0 ? 'gaabis' : 'dheeraad',
                $reason === '' ? '' : ': ' . $reason,
            ),
            'source_type'   => 'shift',
            'source_id'     => $shiftId,
            'created_by'    => $context->userId,
            'shift_id'      => $shiftId,
        ]);
    }

    /**
     * Every account the close has to ask about.
     *
     * Names and methods only — never balances. The list builds the form; the
     * balances are the answer, and a screen that has them will show them.
     *
     * @return list<array<string,mixed>>
     */
    private static function countable(int $restaurantId, ?array $shift = null): array
    {
        $accounts = Database::select(
            'SELECT id, name, method FROM accounts
              WHERE restaurant_id = :rid AND is_active = 1
              ORDER BY method = "cash" DESC, id ASC',
            ['rid' => $restaurantId],
        );

        if ($shift === null) {
            return $accounts;
        }

        // What came in on each account since the till opened, cash included.
        //
        // Cash was withheld at first, on the reasoning that somebody who knows
        // the takings can work out the closing total and type that instead of
        // counting. The owner overruled it, and the argument holds: the figure
        // is a demand, not a hint. Whatever the system says came in is money the
        // cashier is expected to be holding, and showing it does not create a
        // shortfall that was not already there.
        //
        // What it does buy is the part that was missing. A drawer that comes up
        // short has to be investigated before the shift closes — a missed
        // expense, a payment rung up wrong, a recount — and somebody given only
        // an empty box has nowhere to start. These are the numbers they check
        // against.
        //
        // The closing total itself is still not sent. Whoever counts writes
        // their own figure first; these say where to look when it does not
        // match, not what to write.
        foreach ($accounts as $i => $account) {
            $accounts[$i]['received'] = (float) Database::scalar(
                'SELECT COALESCE(SUM(amount), 0) FROM account_transactions
                  WHERE restaurant_id = :rid AND account_id = :aid
                    AND kind = "money_in" AND created_at >= :since',
                [
                    'rid'   => $restaurantId,
                    'aid'   => $account['id'],
                    'since' => $shift['opened_at'],
                ],
            );

            // And what went back out of it, so the two sides are both on screen
            // rather than one of them being a surprise.
            $accounts[$i]['paid_out'] = (float) Database::scalar(
                'SELECT COALESCE(SUM(amount), 0) FROM account_transactions
                  WHERE restaurant_id = :rid AND account_id = :aid
                    AND kind = "money_out" AND created_at >= :since',
                [
                    'rid'   => $restaurantId,
                    'aid'   => $account['id'],
                    'since' => $shift['opened_at'],
                ],
            );
        }

        return $accounts;
    }

    /**
     * What left the tills today.
     *
     * Shown on the closing screen because it is why the drawer holds less than
     * the day's sales. The cashier paid these themselves, so it tells them
     * nothing they did not already know — and without it a close turns into a
     * panicked recount of money that was legitimately spent.
     *
     * @param  array<string,mixed>|null $shift
     * @return array<string,mixed>
     */
    private static function todaysExpenses(int $restaurantId, ?array $shift): array
    {
        $since = $shift === null ? date('Y-m-d 00:00:00') : (string) $shift['opened_at'];

        // Bounded at both ends once the shift is closed. Without the upper
        // bound, opening last Tuesday from the history would list this
        // morning's spending as though it had happened that night.
        $until = $shift === null ? null : ($shift['closed_at'] ?? null);

        $rows = Database::select(
            'SELECT e.name, e.amount, e.method, e.created_at
               FROM expenses e
              WHERE e.restaurant_id = :rid
                AND e.cancelled_at IS NULL
                AND e.created_at >= :since
                AND (:until IS NULL OR e.created_at <= :until2)
              ORDER BY e.id DESC LIMIT 50',
            ['rid' => $restaurantId, 'since' => $since, 'until' => $until, 'until2' => $until],
        );

        return [
            'items' => $rows,
            'total' => (float) Database::scalar(
                'SELECT COALESCE(SUM(amount), 0) FROM expenses
                  WHERE restaurant_id = :rid AND cancelled_at IS NULL
                    AND created_at >= :since
                    AND (:until IS NULL OR created_at <= :until2)',
                ['rid' => $restaurantId, 'since' => $since, 'until' => $until, 'until2' => $until],
            ),
        ];
    }

    /** What the previous close said was left in the drawer. */
    private static function lastClose(int $restaurantId, int $accountId): ?float
    {
        $value = Database::scalar(
            'SELECT counted_close FROM shifts
              WHERE restaurant_id = :rid AND account_id = :aid AND closed_at IS NOT NULL
              ORDER BY closed_at DESC LIMIT 1',
            ['rid' => $restaurantId, 'aid' => $accountId],
        );

        return $value === null ? null : (float) $value;
    }

    private static function tolerance(int $restaurantId): float
    {
        $value = Database::scalar(
            'SELECT variance_tolerance FROM restaurant_settings WHERE restaurant_id = :rid',
            ['rid' => $restaurantId],
        );

        return $value === null ? 1000.0 : (float) $value;
    }

    /** The restaurant's cash drawer — the only account there is anything to count. */
    private static function defaultTill(int $restaurantId): int
    {
        return (int) (Database::scalar(
            'SELECT id FROM accounts
              WHERE restaurant_id = :rid AND method = "cash" AND is_active = 1
              ORDER BY id ASC LIMIT 1',
            ['rid' => $restaurantId],
        ) ?? 0);
    }

    /**
     * The per-account figures for a closed shift.
     *
     * @return list<array<string,mixed>>
     */
    private static function countsFor(int $id): array
    {
        return Database::select(
            'SELECT c.account_id, c.expected, c.counted, c.variance,
                    a.name, a.method
               FROM shift_counts c
          LEFT JOIN accounts a ON a.id = c.account_id
              WHERE c.shift_id = :id
              ORDER BY a.method = "cash" DESC, c.id ASC',
            ['id' => $id],
        );
    }

    /** @return array<string,mixed> */
    private static function find(int $restaurantId, int $id, bool $blind): array
    {
        $row = Database::selectOne(
            'SELECT s.*, o.name AS opened_by_name, c.name AS closed_by_name,
                    a.name AS account_name
               FROM shifts s
          LEFT JOIN users o ON o.id = s.opened_by
          LEFT JOIN users c ON c.id = s.closed_by
          LEFT JOIN accounts a ON a.id = s.account_id
              WHERE s.id = :id AND s.restaurant_id = :rid',
            ['id' => $id, 'rid' => $restaurantId],
        );

        if ($row === null) {
            return [];
        }

        $out = Presenter::shift($row, blind: $blind);

        if ($row['closed_at'] !== null) {
            $out['accounts'] = self::countsFor($id);
        }

        return $out;
    }
}
