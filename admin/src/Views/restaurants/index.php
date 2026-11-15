<?php

declare(strict_types=1);

use DacaamAdmin\Core\Access;
use DacaamAdmin\Core\Response;

use function DacaamAdmin\Core\e;
use function DacaamAdmin\Core\money;
use function DacaamAdmin\Core\shortDate;

/** @var array $restaurants @var string $search @var string $status */
// The export carries whatever the list is showing, filters included.
$csv = '/restaurants?' . http_build_query(array_filter([
    'q' => $search, 'status' => $status, 'format' => 'csv',
], static fn (string $v): bool => $v !== ''));
?>
<div class="page-head">
  <div>
    <h1>Restaurants</h1>
    <div class="page-sub">
      <?= count($restaurants) ?> tenant(s)<?= $status === 'archived' ? ' in the archive' : '' ?>
    </div>
  </div>
  <div class="actions">
    <a class="btn" href="<?= e(Response::url($csv)) ?>">Export CSV</a>
    <?php if (Access::can('restaurants.manage')): ?>
      <a class="btn btn-primary" href="<?= e(Response::url('/restaurants/new')) ?>">
        + New restaurant
      </a>
    <?php endif; ?>
  </div>
</div>

<div class="card">
  <form method="get" action="<?= e(Response::url('/restaurants')) ?>"
        style="display:flex;gap:12px;flex-wrap:wrap;margin-bottom:18px">
    <input name="q" value="<?= e($search) ?>" placeholder="Search name, code or phone"
           style="flex:1;min-width:220px">
    <select name="status" style="width:auto">
      <option value="">All working</option>
      <?php foreach (['active', 'trial', 'suspended', 'archived'] as $s): ?>
        <option value="<?= $s ?>" <?= $status === $s ? 'selected' : '' ?>>
          <?= ucfirst($s) ?>
        </option>
      <?php endforeach; ?>
    </select>
    <button class="btn">Filter</button>
  </form>

  <?php if ($restaurants === []): ?>
    <div class="empty">
      No restaurants match. <a href="<?= e(Response::url('/restaurants')) ?>">Clear filters</a>
    </div>
  <?php else: ?>
    <div class="table-wrap">
      <table>
        <thead>
          <tr>
            <th>Restaurant</th><th>Code</th><th>Status</th><th>Plan</th>
            <th>Renews</th><th class="num">Staff</th><th class="num">Orders</th>
            <th>Activity</th>
          </tr>
        </thead>
        <tbody>
        <?php foreach ($restaurants as $r): ?>
          <tr>
            <td>
              <a href="<?= e(Response::url('/restaurants/' . $r['id'])) ?>">
                <strong><?= e($r['logo_emoji']) ?> <?= e($r['name']) ?></strong>
              </a>
              <div class="muted"><?= e($r['phone']) ?></div>
            </td>
            <td><span class="mono"><?= e($r['slug']) ?></span></td>
            <td><span class="chip chip-<?= e($r['status']) ?>"><?= e($r['status']) ?></span></td>
            <td><?= e($r['plan'] ?? '—') ?></td>
            <td>
              <?= $r['ends_on'] !== null ? shortDate($r['ends_on']) : '—' ?>
              <?php if ($r['days_left'] !== null && (int) $r['days_left'] < 0): ?>
                <div><span class="chip chip-expired">overdue</span></div>
              <?php endif; ?>
            </td>
            <td class="num"><?= (int) $r['staff'] ?></td>
            <td class="num"><?= (int) $r['orders'] ?></td>
            <td>
              <?php
                // Silence is the signal. A restaurant with no order for a
                // fortnight has effectively stopped using the product, and
                // saying so here is the difference between noticing now and
                // noticing at renewal.
                $last = $r['last_order_at'] ?? null;
                $days = $last === null ? null : (int) floor((time() - strtotime((string) $last)) / 86400);
                $week = (int) ($r['orders_week'] ?? 0);
                $prev = (int) ($r['orders_prev_week'] ?? 0);
              ?>
              <?php if ($days === null): ?>
                <span class="chip chip-expired">never ordered</span>
              <?php elseif ($days >= 14): ?>
                <span class="chip chip-expired">quiet <?= $days ?>d</span>
              <?php else: ?>
                <div class="stack">
                  <span><?= $week ?> this week</span>
                  <span class="muted">
                    <?php if ($prev === 0 && $week > 0): ?>
                      new activity
                    <?php elseif ($prev > 0): ?>
                      <?= $week >= $prev ? '▲' : '▼' ?>
                      <?= abs((int) round((($week - $prev) / $prev) * 100)) ?>% vs last
                    <?php else: ?>
                      quiet
                    <?php endif; ?>
                  </span>
                </div>
              <?php endif; ?>
            </td>
          </tr>
        <?php endforeach; ?>
        </tbody>
      </table>
    </div>
  <?php endif; ?>
</div>
