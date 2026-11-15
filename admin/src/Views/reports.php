<?php

declare(strict_types=1);

use DacaamAdmin\Core\Response;

use function DacaamAdmin\Core\e;
use function DacaamAdmin\Core\money;
use function DacaamAdmin\Core\shortDate;

/** @var int $days @var array $totals @var array $daily */
/** @var array $byRestaurant @var array $growth */
$peak = 0.0;
foreach ($daily as $d) {
    $peak = max($peak, (float) $d['total']);
}
$topSales = 0.0;
foreach ($byRestaurant as $r) {
    $topSales = max($topSales, (float) $r['sales']);
}
$ranges = [7 => '7 days', 30 => '30 days', 90 => '90 days', 365 => '12 months'];
?>
<div class="page-head">
  <div>
    <h1>Global reports</h1>
    <div class="page-sub">Trading across every tenant, last <?= $days ?> days.</div>
  </div>
  <div class="actions">
    <div class="tabs">
      <?php foreach ($ranges as $value => $label): ?>
        <a class="tab <?= $days === $value ? 'active' : '' ?>"
           href="<?= e(Response::url('/reports?days=' . $value)) ?>"><?= $label ?></a>
      <?php endforeach; ?>
    </div>
    <a class="btn" href="<?= e(Response::url('/reports?days=' . $days . '&format=csv')) ?>">Export CSV</a>
  </div>
</div>

<div class="grid grid-3">
  <div class="card">
    <div class="kpi-label">Platform volume</div>
    <div class="kpi-value"><?= money($totals['sales'] ?? 0) ?></div>
  </div>
  <div class="card">
    <div class="kpi-label">Orders</div>
    <div class="kpi-value"><?= number_format((float) ($totals['orders'] ?? 0)) ?></div>
  </div>
  <div class="card">
    <div class="kpi-label">Average order</div>
    <div class="kpi-value"><?= money($totals['avg_order'] ?? 0) ?></div>
  </div>
</div>

<div class="card" style="margin-top:16px">
  <div class="card-head">
    <h2>Daily volume</h2>
    <span class="muted">peak <?= money($peak) ?></span>
  </div>
  <?php if ($daily === []): ?>
    <div class="empty">No orders in this window.</div>
  <?php else: ?>
    <div class="chart">
      <?php foreach ($daily as $d): ?>
        <div class="chart-col" title="<?= e(shortDate($d['d'])) ?> · <?= e(money($d['total'])) ?>">
          <div class="chart-bar"
               style="height:<?= $peak > 0 ? max(2, round(((float) $d['total'] / $peak) * 100)) : 2 ?>%"></div>
        </div>
      <?php endforeach; ?>
    </div>
    <div class="chart-axis">
      <span><?= shortDate($daily[0]['d']) ?></span>
      <span><?= shortDate($daily[count($daily) - 1]['d']) ?></span>
    </div>
  <?php endif; ?>
</div>

<div class="grid grid-2" style="margin-top:16px">
  <div class="card">
    <div class="card-head"><h2>By restaurant</h2></div>
    <?php if ($byRestaurant === []): ?>
      <div class="empty">No restaurants yet.</div>
    <?php else: ?>
      <div class="table-wrap">
        <table>
          <thead>
            <tr><th>Restaurant</th><th>Status</th><th class="num">Orders</th><th class="num">Sales</th><th>Share</th></tr>
          </thead>
          <tbody>
          <?php foreach ($byRestaurant as $r): ?>
            <tr>
              <td>
                <a href="<?= e(Response::url('/restaurants/' . $r['id'])) ?>">
                  <strong><?= e($r['name']) ?></strong>
                </a>
                <div class="muted mono"><?= e($r['slug']) ?></div>
              </td>
              <td><span class="chip chip-<?= e($r['status']) ?>"><?= e($r['status']) ?></span></td>
              <td class="num"><?= (int) $r['orders'] ?></td>
              <td class="num"><?= money($r['sales']) ?></td>
              <td style="min-width:110px">
                <div class="bar">
                  <span style="width:<?= $topSales > 0 ? round(((float) $r['sales'] / $topSales) * 100) : 0 ?>%"></span>
                </div>
              </td>
            </tr>
          <?php endforeach; ?>
          </tbody>
        </table>
      </div>
    <?php endif; ?>
  </div>

  <div class="card">
    <div class="card-head">
      <h2>Restaurants added</h2>
      <span class="muted">by month</span>
    </div>
    <?php if ($growth === []): ?>
      <div class="empty">Nothing yet.</div>
    <?php else: ?>
      <?php
      $topAdded = 0;
      foreach ($growth as $g) {
          $topAdded = max($topAdded, (int) $g['added']);
      }
      ?>
      <?php foreach ($growth as $g): ?>
        <div style="margin-bottom:12px">
          <div style="display:flex;justify-content:space-between;margin-bottom:5px">
            <span><?= e($g['month']) ?></span>
            <span class="num"><?= (int) $g['added'] ?></span>
          </div>
          <div class="bar">
            <span style="width:<?= $topAdded > 0 ? round(((int) $g['added'] / $topAdded) * 100) : 0 ?>%"></span>
          </div>
        </div>
      <?php endforeach; ?>
    <?php endif; ?>
  </div>
</div>
