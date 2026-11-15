<?php

declare(strict_types=1);

use DacaamAdmin\Core\Response;

use function DacaamAdmin\Core\dateTime;
use function DacaamAdmin\Core\e;
use function DacaamAdmin\Core\money;
use function DacaamAdmin\Core\shortDate;

/** @var array $counts @var array $revenue @var float $gmv */
/** @var array $expiring @var array $busiest @var array $recent */
$maxSales = 0.0;
foreach ($busiest as $r) {
    $maxSales = max($maxSales, (float) $r['sales']);
}
?>
<div class="page-head">
  <div>
    <h1>Dashboard</h1>
    <div class="page-sub">Every restaurant on the platform, at a glance.</div>
  </div>
  <a class="btn btn-primary" href="<?= e(Response::url('/restaurants/new')) ?>">
    + New restaurant
  </a>
</div>

<div class="grid grid-4">
  <div class="card">
    <div class="kpi-label">Total restaurants</div>
    <div class="kpi-value"><?= (int) ($counts['total'] ?? 0) ?></div>
    <div class="kpi-foot">
      <span class="chip chip-active"><?= (int) ($counts['active'] ?? 0) ?> active</span>
    </div>
  </div>
  <div class="card">
    <div class="kpi-label">On trial</div>
    <div class="kpi-value"><?= (int) ($counts['trial'] ?? 0) ?></div>
    <div class="kpi-foot">Converting these is the growth number.</div>
  </div>
  <div class="card">
    <div class="kpi-label">Suspended</div>
    <div class="kpi-value"><?= (int) ($counts['suspended'] ?? 0) ?></div>
    <div class="kpi-foot">Data retained, access paused.</div>
  </div>
  <div class="card">
    <div class="kpi-label">Subscription revenue</div>
    <div class="kpi-value"><?= money($revenue['lifetime'] ?? 0) ?></div>
    <div class="kpi-foot"><?= money($revenue['last_30'] ?? 0) ?> in the last 30 days</div>
  </div>
</div>

<div class="grid grid-2" style="margin-top:16px">
  <div class="card">
    <div class="card-head">
      <h2>Busiest restaurants</h2>
      <span class="muted">last 30 days</span>
    </div>
    <?php if ($busiest === []): ?>
      <div class="empty">No restaurants yet.</div>
    <?php else: ?>
      <?php foreach ($busiest as $r): ?>
        <div style="margin-bottom:14px">
          <div style="display:flex;justify-content:space-between;gap:12px;margin-bottom:5px">
            <a href="<?= e(Response::url('/restaurants/' . $r['id'])) ?>">
              <strong><?= e($r['name']) ?></strong>
            </a>
            <span class="num"><?= money($r['sales']) ?></span>
          </div>
          <div class="bar">
            <span style="width:<?= $maxSales > 0 ? round(((float) $r['sales'] / $maxSales) * 100) : 0 ?>%"></span>
          </div>
          <div class="muted" style="margin-top:4px">
            <?= (int) $r['orders'] ?> orders · <?= e($r['slug']) ?>
          </div>
        </div>
      <?php endforeach; ?>
    <?php endif; ?>
  </div>

  <div class="card">
    <div class="card-head">
      <h2>Renewals due</h2>
      <a href="<?= e(Response::url('/subscriptions?status=expiring')) ?>">View all</a>
    </div>
    <?php if ($expiring === []): ?>
      <div class="empty">Nothing expiring in the next 30 days.</div>
    <?php else: ?>
      <div class="table-wrap">
        <table>
          <thead>
            <tr><th>Restaurant</th><th>Plan</th><th>Ends</th><th class="num">Days</th></tr>
          </thead>
          <tbody>
          <?php foreach ($expiring as $s): ?>
            <tr>
              <td>
                <a href="<?= e(Response::url('/restaurants/' . $s['restaurant_id'])) ?>">
                  <?= e($s['name']) ?>
                </a>
                <div class="muted"><?= e($s['slug']) ?></div>
              </td>
              <td><span class="chip chip-<?= e($s['status']) ?>"><?= e($s['plan']) ?></span></td>
              <td><?= shortDate($s['ends_on']) ?></td>
              <td class="num">
                <?php $days = (int) $s['days_left']; ?>
                <span class="chip <?= $days <= 7 ? 'chip-suspended' : 'chip-trial' ?>">
                  <?= $days < 0 ? 'overdue' : $days . 'd' ?>
                </span>
              </td>
            </tr>
          <?php endforeach; ?>
          </tbody>
        </table>
      </div>
    <?php endif; ?>
  </div>
</div>

<div class="grid grid-2" style="margin-top:16px">
  <div class="card">
    <div class="card-head">
      <h2>Platform volume</h2>
      <span class="muted">last 30 days</span>
    </div>
    <div class="kpi-value"><?= money($gmv) ?></div>
    <div class="kpi-foot">
      Total trading across every tenant. This is what the restaurants sold,
      not what the platform earned.
    </div>
  </div>

  <div class="card">
    <div class="card-head">
      <h2>Recent platform activity</h2>
      <a href="<?= e(Response::url('/audit')) ?>">Full log</a>
    </div>
    <?php if ($recent === []): ?>
      <div class="empty">Nothing recorded yet.</div>
    <?php else: ?>
      <?php foreach ($recent as $entry): ?>
        <div style="display:flex;justify-content:space-between;gap:12px;padding:6px 0">
          <div class="stack">
            <span><strong><?= e(str_replace('_', ' ', (string) $entry['action'])) ?></strong></span>
            <span class="muted"><?= e($entry['admin_name']) ?><?= $entry['detail'] !== '' ? ' · ' . e($entry['detail']) : '' ?></span>
          </div>
          <span class="muted" style="white-space:nowrap"><?= dateTime($entry['created_at']) ?></span>
        </div>
      <?php endforeach; ?>
    <?php endif; ?>
  </div>
</div>

<div class="card" style="margin-top:1.25rem">
  <div class="card-head">
    <h2>Renewals — next 14 days</h2>
    <?php if ($at_risk > 0): ?>
      <span class="chip chip-expired">
        <?= money($at_risk) ?> at risk
      </span>
    <?php endif; ?>
  </div>

  <?php if ($renewals === []): ?>
    <div class="empty">Nothing expiring in the next fortnight.</div>
  <?php else: ?>
    <p class="muted" style="margin-top:0">
      Expired subscriptions keep every record and turn the app read-only, so a
      shop that lapses loses nothing by renewing late — but it also stops
      taking orders, which is the conversation to have before the date, not
      after it.
    </p>
    <table class="table">
      <thead>
        <tr><th>Restaurant</th><th>Plan</th><th>Ends</th><th>Amount</th><th></th></tr>
      </thead>
      <tbody>
        <?php foreach ($renewals as $x): ?>
          <?php $left = (int) $x['days_left']; ?>
          <tr>
            <td>
              <a href="<?= e(Response::url('/restaurants/' . $x['id'])) ?>">
                <?= e((string) $x['name']) ?>
              </a>
              <div class="muted mono"><?= e((string) $x['slug']) ?></div>
            </td>
            <td><?= e((string) ($x['plan'] ?? '—')) ?></td>
            <td>
              <?= e(shortDate($x['ends_on'])) ?>
              <div class="muted">
                <?= $left < 0
                  ? abs($left) . ' days ago'
                  : ($left === 0 ? 'today' : "in $left days") ?>
              </div>
            </td>
            <td><?= money((float) $x['amount']) ?></td>
            <td>
              <span class="chip <?= $left < 0 ? 'chip-expired' : 'chip-active' ?>">
                <?= $left < 0 ? 'expired' : e((string) $x['sub_status']) ?>
              </span>
            </td>
          </tr>
        <?php endforeach; ?>
      </tbody>
    </table>
    <p class="muted">
      <a href="<?= e(Response::url('/notifications')) ?>">Send them a message →</a>
    </p>
  <?php endif; ?>
</div>