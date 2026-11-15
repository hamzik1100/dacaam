<?php

declare(strict_types=1);

use function DacaamAdmin\Core\dateTime;
use function DacaamAdmin\Core\e;

/** @var array $entries @var array $counts @var ?int $freshest @var string $log @var array $database @var array $email */

/**
 * How long ago, in words.
 *
 * The number of hours is the whole point of this page: an error last seen six
 * hours ago has been fixed or has stopped, and an error last seen four minutes
 * ago is happening to somebody right now.
 */
$ago = static function (?int $hours): string {
    if ($hours === null) {
        return 'unknown';
    }

    if ($hours < 1) {
        return 'just now';
    }

    if ($hours < 24) {
        return $hours . 'h ago';
    }

    return (int) floor($hours / 24) . 'd ago';
};

// Anything within the hour is treated as live. Below that it is history, and
// the page should not be red about it.
$live = $freshest !== null && $freshest < 1;
?>
<div class="page-head">
  <div>
    <h1>Health</h1>
    <div class="page-sub">
      What the API has been complaining about, and how big the database is.
    </div>
  </div>
  <span class="chip <?= $entries === [] || !$live ? 'chip-active' : 'chip-expired' ?>">
    <?= $entries === []
      ? 'quiet'
      : ($live ? count($entries) . ' recent' : 'quiet · ' . $ago($freshest)) ?>
  </span>
</div>

<?php if ($entries !== [] && !$live): ?>
  <div class="notice" style="margin-bottom:1.25rem">
    Nothing new for <?= e($ago($freshest)) ?>. Everything below already
    happened and stopped — a list of past faults, not current ones. It stays
    here so a fault that comes back is recognisable as one that came back.
  </div>
<?php endif; ?>

<div class="grid grid-2">
  <div class="card">
    <div class="card-head"><h2>Most frequent</h2></div>

    <?php if ($counts === []): ?>
      <div class="empty">
        <?= $log === ''
          ? 'No error log found on this host.'
          : 'Nothing in the log worth showing.' ?>
      </div>
      <?php if ($log !== ''): ?>
        <p class="muted" style="font-size:12px"><?= e($log) ?></p>
      <?php endif; ?>
    <?php else: ?>
      <p class="muted" style="margin-top:0">
        Grouped by shape, so the same fault five hundred times counts once and
        does not bury the others.
      </p>
      <table class="table">
        <thead><tr><th>Error</th><th class="num">Seen</th><th>Last seen</th></tr></thead>
        <tbody>
          <?php foreach ($counts as $c): ?>
            <tr>
              <td style="font-size:12px"><?= e(mb_substr($c['message'], 0, 180)) ?></td>
              <td class="num"><?= (int) $c['count'] ?></td>
              <td class="muted" style="white-space:nowrap;font-size:12px"><?= e($ago($c['age'])) ?></td>
            </tr>
          <?php endforeach; ?>
        </tbody>
      </table>
    <?php endif; ?>
  </div>

  <div class="card">
    <div class="card-head"><h2>Database</h2></div>
    <table class="table">
      <tbody>
        <tr><td>Size</td><td style="text-align:right"><?= number_format((float) $database['size'], 1) ?> MB</td></tr>
        <tr><td>Tables</td><td style="text-align:right"><?= (int) $database['tables'] ?></td></tr>
        <tr><td>Orders</td><td style="text-align:right"><?= number_format((int) $database['orders']) ?></td></tr>
        <tr><td>Audit rows</td><td style="text-align:right"><?= number_format((int) $database['audit']) ?></td></tr>
      </tbody>
    </table>
    <p class="muted">
      Audit rows only ever grow. They are the record of who changed what, so
      they are not pruned — but they are the first thing to watch if the
      database starts getting large.
    </p>
  </div>
</div>

<?php if (!empty($email['ready'])): ?>
  <div class="card" style="margin-top:1.25rem">
    <div class="card-head">
      <h2>Alert email</h2>
      <span class="chip <?= ($email['stuck'] ?? 0) > 0 ? 'chip-expired' : 'chip-active' ?>">
        <?= ($email['stuck'] ?? 0) > 0
          ? (int) $email['stuck'] . ' never sent'
          : 'delivering' ?>
      </span>
    </div>

    <p class="muted" style="margin-top:0">
      Owners are told when an order is voided, a balance is adjusted by hand, or
      staff are added. Nobody is waiting on these, so when they stop going out
      the only symptom is silence — which is why the numbers are here.
    </p>

    <table class="table">
      <tbody>
        <tr><td>Waiting to send</td><td style="text-align:right"><?= (int) ($email['pending'] ?? 0) ?></td></tr>
        <tr><td>Sent today</td><td style="text-align:right"><?= (int) ($email['sent_today'] ?? 0) ?></td></tr>
        <tr>
          <td>Gave up on</td>
          <td style="text-align:right"><?= (int) ($email['stuck'] ?? 0) ?></td>
        </tr>
        <tr>
          <td>Last one out</td>
          <td style="text-align:right">
            <?= $email['last_sent'] === null ? 'never' : e(dateTime((string) $email['last_sent'])) ?>
          </td>
        </tr>
      </tbody>
    </table>

    <?php if (($email['failures'] ?? []) !== []): ?>
      <p class="muted" style="margin-top:1rem;margin-bottom:.5rem">
        What the mail server said:
      </p>
      <table class="table">
        <thead><tr><th>Restaurant</th><th>To</th><th class="num">Tries</th><th>Error</th></tr></thead>
        <tbody>
          <?php foreach ($email['failures'] as $f): ?>
            <tr>
              <td><?= e((string) ($f['slug'] ?? '-')) ?></td>
              <td style="font-size:12px"><?= e((string) $f['to_email']) ?></td>
              <td class="num"><?= (int) $f['attempts'] ?></td>
              <td style="font-size:12px"><?= e(mb_substr((string) $f['last_error'], 0, 90)) ?></td>
            </tr>
          <?php endforeach; ?>
        </tbody>
      </table>
    <?php endif; ?>

    <?php if ((int) ($email['pending'] ?? 0) > 20): ?>
      <div class="notice" style="margin-top:1rem">
        More than twenty are queued. That usually means the cron that drains the
        outbox is not running — the API sends one per request as a fallback, but
        that only keeps up while somebody is using the tills.
      </div>
    <?php endif; ?>
  </div>
<?php endif; ?>
<?php if ($entries !== []): ?>
  <div class="card" style="margin-top:1.25rem">
    <div class="card-head"><h2>Latest</h2></div>
    <table class="table">
      <thead><tr><th>When</th><th>Message</th></tr></thead>
      <tbody>
        <?php foreach (array_slice($entries, 0, 50) as $x): ?>
          <tr>
            <td class="muted" style="white-space:nowrap;font-size:12px"><?= e($x['at']) ?></td>
            <td style="font-size:12px"><?= e(mb_substr($x['message'], 0, 300)) ?></td>
          </tr>
        <?php endforeach; ?>
      </tbody>
    </table>
  </div>
<?php endif; ?>
