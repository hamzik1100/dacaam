<?php

declare(strict_types=1);

use DacaamAdmin\Core\Response;

use function DacaamAdmin\Core\dateTime;
use function DacaamAdmin\Core\e;

/** @var array $entries @var array $actions @var string $action */
?>
<div class="page-head">
  <div>
    <h1>Platform audit</h1>
    <div class="page-sub">
      Everything a platform administrator did, in order. Entries are written,
      never edited or removed.
    </div>
  </div>
</div>

<div class="card">
  <form method="get" action="<?= e(Response::url('/audit')) ?>"
        style="display:flex;gap:12px;flex-wrap:wrap;margin-bottom:18px">
    <select name="action" style="min-width:220px;width:auto">
      <option value="">All actions</option>
      <?php foreach ($actions as $a): ?>
        <option value="<?= e($a) ?>" <?= $action === $a ? 'selected' : '' ?>>
          <?= e(str_replace('_', ' ', (string) $a)) ?>
        </option>
      <?php endforeach; ?>
    </select>
    <button class="btn">Filter</button>
    <?php if ($action !== ''): ?>
      <a class="btn" href="<?= e(Response::url('/audit')) ?>">Clear</a>
    <?php endif; ?>
  </form>

  <?php if ($entries === []): ?>
    <div class="empty">No entries.</div>
  <?php else: ?>
    <div class="table-wrap">
      <table>
        <thead>
          <tr>
            <th>When</th><th>Action</th><th>Restaurant</th>
            <th>Detail</th><th>By</th><th>IP</th>
          </tr>
        </thead>
        <tbody>
        <?php foreach ($entries as $entry): ?>
          <tr>
            <td style="white-space:nowrap"><?= dateTime($entry['created_at']) ?></td>
            <td><strong><?= e(str_replace('_', ' ', (string) $entry['action'])) ?></strong></td>
            <td>
              <?php if ($entry['restaurant_id'] !== null): ?>
                <a href="<?= e(Response::url('/restaurants/' . $entry['restaurant_id'])) ?>">
                  <?= e($entry['restaurant_name'] ?? '#' . $entry['restaurant_id']) ?>
                </a>
              <?php else: ?>
                <span class="muted">platform</span>
              <?php endif; ?>
            </td>
            <td class="muted"><?= e((string) ($entry['detail'] ?? '')) ?></td>
            <td><?= e((string) ($entry['admin_name'] ?? '—')) ?></td>
            <td class="mono muted"><?= e((string) ($entry['ip'] ?? '')) ?></td>
          </tr>
        <?php endforeach; ?>
        </tbody>
      </table>
    </div>
    <div class="hint" style="margin-top:10px">
      Showing the most recent <?= count($entries) ?> entries.
    </div>
  <?php endif; ?>
</div>
