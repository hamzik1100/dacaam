<?php

declare(strict_types=1);

use Dacaam\Support\RenewalReminders;
use DacaamAdmin\Core\Access;
use DacaamAdmin\Core\Csrf;
use DacaamAdmin\Core\Response;

use function DacaamAdmin\Core\dateTime;
use function DacaamAdmin\Core\e;
use function DacaamAdmin\Core\money;
use function DacaamAdmin\Core\shortDate;

/** @var array $subscriptions @var array $totals @var string $filter */
/** @var array $due @var array $reminders */
$tabs = [
    ''          => 'All',
    'expiring'  => 'Expiring soon',
    'active'    => 'Active',
    'trial'     => 'Trial',
    'expired'   => 'Expired',
    'suspended' => 'Suspended',
];
?>
<div class="page-head">
  <div>
    <h1>Subscriptions</h1>
    <div class="page-sub">
      Lapsing restricts access. It never deletes anything — renewal restores
      the restaurant exactly as it was.
    </div>
  </div>
  <a class="btn"
     href="<?= e(Response::url('/subscriptions?' . http_build_query(array_filter(['status' => $filter, 'format' => 'csv'])))) ?>">
    Export CSV
  </a>
</div>

<div class="grid grid-2">
  <div class="card">
    <div class="kpi-label">Collected this month</div>
    <div class="kpi-value"><?= money($totals['this_month'] ?? 0) ?></div>
  </div>
  <div class="card">
    <div class="kpi-label">Collected lifetime</div>
    <div class="kpi-value"><?= money($totals['lifetime'] ?? 0) ?></div>
  </div>
</div>

<div class="card" style="margin-top:16px">
  <div class="tabs">
    <?php foreach ($tabs as $value => $label): ?>
      <a class="tab <?= $filter === $value ? 'active' : '' ?>"
         href="<?= e(Response::url('/subscriptions' . ($value === '' ? '' : '?status=' . $value))) ?>">
        <?= $label ?>
      </a>
    <?php endforeach; ?>
  </div>

  <?php if ($subscriptions === []): ?>
    <div class="empty">No subscriptions in this view.</div>
  <?php else: ?>
    <div class="table-wrap">
      <table>
        <thead>
          <tr>
            <th>Restaurant</th><th>Plan</th><th>Status</th>
            <th>Ends</th><th class="num">Days left</th>
            <th class="num">Plan amount</th><th class="num">Paid to date</th><th></th>
          </tr>
        </thead>
        <tbody>
        <?php foreach ($subscriptions as $s): ?>
          <?php $days = (int) $s['days_left']; ?>
          <tr>
            <td>
              <a href="<?= e(Response::url('/restaurants/' . $s['restaurant_id'])) ?>">
                <strong><?= e($s['name']) ?></strong>
              </a>
              <div class="muted mono"><?= e($s['slug']) ?></div>
            </td>
            <td><?= e($s['plan']) ?></td>
            <td><span class="chip chip-<?= e($s['status']) ?>"><?= e($s['status']) ?></span></td>
            <td><?= shortDate($s['ends_on']) ?></td>
            <td class="num">
              <span class="chip <?= $days < 0 ? 'chip-expired' : ($days <= 7 ? 'chip-suspended' : 'chip-active') ?>">
                <?= $days < 0 ? abs($days) . 'd over' : $days . 'd' ?>
              </span>
            </td>
            <td class="num"><?= money($s['amount']) ?></td>
            <td class="num"><?= money($s['paid']) ?></td>
            <td class="num">
              <a class="btn btn-sm"
                 href="<?= e(Response::url('/restaurants/' . $s['restaurant_id'])) ?>">
                Manage
              </a>
            </td>
          </tr>
        <?php endforeach; ?>
        </tbody>
      </table>
    </div>
  <?php endif; ?>
</div>

<div class="card" style="margin-top:16px">
  <div class="card-head">
    <h2>Renewal reminders</h2>
    <span class="muted">7 days before · 1 day before · once after it ends</span>
  </div>
  <p class="muted" style="margin-top:0">
    Each restaurant's admins get an in-app notification, a push and an email,
    in Somali. The daily cron sends them; this button does the same now.
    Nothing is ever sent twice.
  </p>

  <?php if ($due === []): ?>
    <div class="empty">Nothing due right now.</div>
  <?php else: ?>
    <div class="table-wrap">
      <table>
        <thead><tr><th>Restaurant</th><th>Ends</th><th>Reminder</th></tr></thead>
        <tbody>
        <?php foreach ($due as $d): ?>
          <tr>
            <td>
              <a href="<?= e(Response::url('/restaurants/' . $d['restaurant_id'])) ?>"><?= e($d['name']) ?></a>
              <span class="muted mono"><?= e($d['slug']) ?></span>
            </td>
            <td><?= shortDate($d['ends_on']) ?></td>
            <td><span class="chip chip-suspended"><?= e(RenewalReminders::stageLabel((int) $d['stage'])) ?></span></td>
          </tr>
        <?php endforeach; ?>
        </tbody>
      </table>
    </div>
  <?php endif; ?>

  <?php if (Access::can('billing')): ?>
    <form method="post" action="<?= e(Response::url('/subscriptions/reminders')) ?>" style="margin-top:12px">
      <?= Csrf::field() ?>
      <button class="btn btn-primary" <?= $due === [] ? 'disabled' : '' ?>>
        Send <?= count($due) ?> due reminder(s) now
      </button>
    </form>
  <?php endif; ?>

  <?php if ($reminders !== []): ?>
    <h3 style="margin:1.25rem 0 .5rem;font-size:14px">Recently sent</h3>
    <div class="table-wrap">
      <table>
        <thead>
          <tr><th>Restaurant</th><th>Reminder</th><th>For end date</th><th class="num">Push</th><th class="num">Email</th><th>Sent</th></tr>
        </thead>
        <tbody>
        <?php foreach ($reminders as $m): ?>
          <tr>
            <td><?= e($m['name']) ?> <span class="muted mono"><?= e($m['slug']) ?></span></td>
            <td><?= e(RenewalReminders::stageLabel((int) $m['stage'])) ?></td>
            <td><?= shortDate($m['ends_on']) ?></td>
            <td class="num"><?= (int) $m['pushed'] ?></td>
            <td class="num"><?= (int) $m['emailed'] ?></td>
            <td class="muted"><?= dateTime($m['created_at']) ?></td>
          </tr>
        <?php endforeach; ?>
        </tbody>
      </table>
    </div>
  <?php endif; ?>
</div>
