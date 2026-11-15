<?php

declare(strict_types=1);

use DacaamAdmin\Core\Csrf;
use DacaamAdmin\Core\Response;

use function DacaamAdmin\Core\dateTime;
use function DacaamAdmin\Core\e;

/** @var array $files @var ?int $hours @var int $total @var string $command */

// One number decides the colour of this page: how long ago the newest backup
// was written, because that is how much work is lost if the disk goes now.
$state = $hours === null ? 'none' : ($hours > 48 ? 'stale' : 'fresh');

$size = static fn (int $b): string => $b > 1048576
    ? number_format($b / 1048576, 1) . ' MB'
    : number_format($b / 1024) . ' KB';
?>
<div class="page-head">
  <div>
    <h1>Backups</h1>
    <div class="page-sub">
      The database — every order, every debt, every customer ledger.
    </div>
  </div>
  <span class="chip <?= $state === 'fresh' ? 'chip-active' : 'chip-expired' ?>">
    <?= $state === 'none'
      ? 'no backup'
      : ($state === 'stale' ? 'stale' : 'up to date') ?>
  </span>
</div>

<div class="grid grid-2">
  <div class="card">
    <div class="card-head"><h2>Where things stand</h2></div>

    <?php if ($hours === null): ?>
      <p style="margin-top:0">
        <strong>There is no backup.</strong>
        If the server is lost right now, everything is lost with it.
      </p>
    <?php elseif ($state === 'stale'): ?>
      <p style="margin-top:0">
        The newest backup is <strong><?= (int) $hours ?> hours</strong> old.
        Anything entered since then is not saved anywhere else — the nightly
        job may have stopped.
      </p>
    <?php else: ?>
      <p style="margin-top:0">
        Newest backup is <strong><?= (int) $hours ?> hour<?= $hours === 1 ? '' : 's' ?></strong>
        old. <?= count($files) ?> kept, <?= e($size($total)) ?> in total.
      </p>
    <?php endif; ?>

    <form method="post" action="<?= e(Response::url('/backups')) ?>">
      <?= Csrf::field() ?>
      <button type="submit" class="btn btn-primary">Back up now</button>
    </form>

    <p class="muted" style="margin-top:1.25rem">
      To run this every night, add one cron job in hPanel — the same script:
    </p>
    <pre class="muted" style="white-space:pre-wrap;font-size:12px"><?= e($command) ?></pre>
    <p class="muted">
      Files are kept outside anything the web serves, and the last 14 are
      retained. Restoring is done over SSH, deliberately — there is no download
      button here on purpose, because that file is the whole business.
    </p>
  </div>

  <div class="card">
    <div class="card-head"><h2>Kept</h2></div>

    <?php if ($files === []): ?>
      <p class="muted">Nothing yet.</p>
    <?php else: ?>
      <table class="table">
        <thead><tr><th>File</th><th>Size</th><th>Taken</th></tr></thead>
        <tbody>
          <?php foreach ($files as $f): ?>
            <tr>
              <td><?= e($f['name']) ?></td>
              <td><?= e($size($f['size'])) ?></td>
              <td class="muted"><?= e(dateTime(date('Y-m-d H:i:s', $f['at']))) ?></td>
            </tr>
          <?php endforeach; ?>
        </tbody>
      </table>
    <?php endif; ?>
  </div>
</div>
