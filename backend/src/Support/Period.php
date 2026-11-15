<?php

declare(strict_types=1);

namespace Dacaam\Support;

use DateTimeImmutable;

/**
 * Resolves the report range presets into concrete datetime bounds, and the
 * matching previous period used for the percentage deltas on every KPI.
 */
final class Period
{
    public function __construct(
        public readonly string $key,
        public readonly DateTimeImmutable $from,
        public readonly DateTimeImmutable $to,
        public readonly DateTimeImmutable $previousFrom,
        public readonly DateTimeImmutable $previousTo,
    ) {
    }

    public static function resolve(string $range, ?string $from = null, ?string $to = null): self
    {
        $now = new DateTimeImmutable();
        $startOfToday = $now->setTime(0, 0);
        $endOfToday = $now->setTime(23, 59, 59);

        [$start, $end] = match ($range) {
            'today'       => [$startOfToday, $endOfToday],
            'yesterday'   => [
                $startOfToday->modify('-1 day'),
                $startOfToday->modify('-1 second'),
            ],
            'this_week'   => [
                $startOfToday->modify('monday this week'),
                $endOfToday,
            ],
            '30_days'     => [$startOfToday->modify('-29 days'), $endOfToday],
            'this_month'  => [$now->modify('first day of this month')->setTime(0, 0), $endOfToday],
            'last_month'  => [
                $now->modify('first day of last month')->setTime(0, 0),
                $now->modify('last day of last month')->setTime(23, 59, 59),
            ],
            'this_year'   => [$now->setDate((int) $now->format('Y'), 1, 1)->setTime(0, 0), $endOfToday],
            'custom'      => [
                new DateTimeImmutable($from ?: '-6 days'),
                (new DateTimeImmutable($to ?: 'now'))->setTime(23, 59, 59),
            ],
            default       => [$startOfToday->modify('-6 days'), $endOfToday], // 7_days
        };

        // The comparison window is the same length immediately before the
        // selected one, so "+18.6%" always means like-for-like.
        $lengthSeconds = max(1, $end->getTimestamp() - $start->getTimestamp());
        $previousEnd = $start->modify('-1 second');
        $previousStart = $previousEnd->modify(sprintf('-%d seconds', $lengthSeconds));

        return new self(
            key: $range,
            from: $start,
            to: $end,
            previousFrom: $previousStart,
            previousTo: $previousEnd,
        );
    }

    public function fromSql(): string
    {
        return $this->from->format('Y-m-d H:i:s');
    }

    public function toSql(): string
    {
        return $this->to->format('Y-m-d H:i:s');
    }

    public function previousFromSql(): string
    {
        return $this->previousFrom->format('Y-m-d H:i:s');
    }

    public function previousToSql(): string
    {
        return $this->previousTo->format('Y-m-d H:i:s');
    }

    public function days(): int
    {
        return max(1, (int) $this->from->diff($this->to)->days + 1);
    }

    public static function delta(float $current, float $previous): float
    {
        if ($previous <= 0.0) {
            return $current > 0.0 ? 100.0 : 0.0;
        }

        return round((($current - $previous) / $previous) * 100, 1);
    }
}
