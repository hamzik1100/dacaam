<?php

declare(strict_types=1);

use DacaamAdmin\Core\Response;

use function DacaamAdmin\Core\dateTime;
use function DacaamAdmin\Core\e;
use function DacaamAdmin\Core\money;

/**
 * @var bool  $ready
 * @var array $restaurants
 * @var array $recent
 * @var array $people
 * @var array $totals
 * @var int   $days
 */

/** Short is red, over is amber — they are different problems. */
$tone = static function (float $variance): string {
    if (abs($variance) < 0.01) {
        return 'chip-active';
    }

    return $variance < 0 ? 'chip-expired' : 'chip-trial';
};
?>
<div class="page-head">
  <div>
    <h1>Tills</h1>
    <div class="page-sub">
      What the drawers actually held, against what the system said they should.
    </div>
  </div>
  <?php if ($ready): ?>
    <span class="chip <?= ($totals['short'] ?? 0) > 0 ? 'chip-expired' : 'chip-active' ?>">
      <?= (int) ($totals['short'] ?? 0) ?> short in <?= (int) $days ?> days
    </span>
  <?php endif; ?>
</div>

<?php if (!$ready): ?>
  <div class="card">
    <div class="empty">
      No till counts yet — the shift migration has not run on this database.
    </div>
  </div>
<?php else: ?>

  <div class="notice" style="margin-bottom:1.25rem">
    A short till is usually a float that was never counted properly, or change
    given out of the wrong drawer. It is worth asking about, not worth accusing
    over — one evening tells you nothing. The same name against the same sign,
    week after week, is the thing to look at.
  </div>

  <div class="grid grid-4">
    <div class="card">
      <div class="kpi-label">Closes counted</div>
      <div class="kpi-value"><?= number_format((int) $totals['shifts']) ?></div>
      <div class="kpi-foot">last <?= (int) $days ?> days</div>
    </div>
    <div class="card">
      <div class="kpi-label">Came up short</div>
      <div class="kpi-value" style="color:var(--danger)"><?= number_format((int) $totals['short']) ?></div>
    </div>
    <div class="card">
      <div class="kpi-label">Came up over</div>
      <div class="kpi-value"><?= number_format((int) $totals['over']) ?></div>
      <div class="kpi-foot">also a mistake, just a kinder one</div>
    </div>
    <div class="card">
      <div class="kpi-label">Net across the platform</div>
      <div class="kpi-value" style="color:<?= (float) $totals['net'] < 0 ? 'var(--danger)' : 'inherit' ?>">
        <?= e(money((float) $totals['net'])) ?>
      </div>
    </div>
  </div>

  <div class="card" style="margin-top:1.25rem">
    <div class="card-head"><h2>By restaurant</h2></div>

    <?php if ($restaurants === []): ?>
      <div class="empty">No till has been closed in the last <?= (int) $days ?> days.</div>
    <?php else: ?>
      <div class="table-wrap">
        <table class="table">
          <thead>
            <tr>
              <th>Restaurant</th>
              <th class="num">Closes</th>
              <th class="num">Short</th>
              <th class="num">Shortfall</th>
              <th class="num">Net</th>
              <th class="num">Off-shift orders</th>
              <th>Last close</th>
            </tr>
          </thead>
          <tbody>
            <?php foreach ($restaurants as $r): ?>
              <tr>
                <td>
                  <a href="<?= e(Response::url('/restaurants/' . $r['id'])) ?>">
                    <?= e((string) $r['name']) ?>
                  </a>
                  <div class="muted" style="font-size:12px"><?= e((string) $r['slug']) ?></div>
                </td>
                <td class="num"><?= (int) $r['closes'] ?></td>
                <td class="num">
                  <?php if ((int) $r['short_count'] > 0): ?>
                    <span class="chip chip-expired"><?= (int) $r['short_count'] ?></span>
                  <?php else: ?>
                    <span class="muted">—</span>
                  <?php endif; ?>
                </td>
                <td class="num" style="color:var(--danger)">
                  <?= (float) $r['shortfall'] < -0.01 ? e(money((float) $r['shortfall'])) : '—' ?>
                </td>
                <td class="num"><?= e(money((float) $r['net'])) ?></td>
                <td class="num">
                  <?= (int) $r['outside'] > 0
                    ? '<span class="chip chip-trial">' . (int) $r['outside'] . '</span>'
                    : '<span class="muted">—</span>' ?>
                </td>
                <td class="muted" style="white-space:nowrap;font-size:12px">
                  <?= e(dateTime((string) $r['last_close'])) ?>
                </td>
              </tr>
            <?php endforeach; ?>
          </tbody>
        </table>
      </div>

      <p class="muted" style="margin-top:.75rem">
        Off-shift orders were taken while no till was open. The app does not
        refuse them — a POS that stops taking money because somebody missed a
        button is worse than a hole in a report — but they sit outside every
        count, so a restaurant with a lot of them is not really being counted.
      </p>
    <?php endif; ?>
  </div>

  <?php if ($people !== []): ?>
    <div class="card" style="margin-top:1.25rem">
      <div class="card-head"><h2>By whoever counted</h2></div>

      <p class="muted" style="margin-top:0">
        Three closes or more. A till is a place; the variance belongs to the
        person who was standing at it, and this is the only view where a habit
        can show itself.
      </p>

      <table class="table">
        <thead>
          <tr><th>Person</th><th>Restaurant</th><th class="num">Closes</th><th class="num">Short</th><th class="num">Net</th></tr>
        </thead>
        <tbody>
          <?php foreach ($people as $p): ?>
            <tr>
              <td><?= e((string) $p['name']) ?></td>
              <td class="muted"><?= e((string) $p['slug']) ?></td>
              <td class="num"><?= (int) $p['closes'] ?></td>
              <td class="num"><?= (int) $p['short_count'] ?></td>
              <td class="num">
                <span class="chip <?= $tone((float) $p['net']) ?>">
                  <?= e(money((float) $p['net'])) ?>
                </span>
              </td>
            </tr>
          <?php endforeach; ?>
        </tbody>
      </table>
    </div>
  <?php endif; ?>

  <div class="card" style="margin-top:1.25rem">
    <div class="card-head"><h2>Closes that did not balance</h2></div>

    <?php if ($recent === []): ?>
      <div class="empty">Every till has balanced. That is the right answer.</div>
    <?php else: ?>
      <div class="table-wrap">
        <table class="table">
          <thead>
            <tr>
              <th>When</th><th>Restaurant</th><th>Counted by</th>
              <th class="num">Expected</th><th class="num">Counted</th>
              <th class="num">Difference</th><th>Reason given</th>
            </tr>
          </thead>
          <tbody>
            <?php foreach ($recent as $s): ?>
              <tr>
                <td class="muted" style="white-space:nowrap;font-size:12px">
                  <?= e(dateTime((string) $s['closed_at'])) ?>
                </td>
                <td><?= e((string) $s['slug']) ?></td>
                <td><?= e((string) ($s['closed_by'] ?? '—')) ?></td>
                <td class="num"><?= e(money((float) $s['expected_close'])) ?></td>
                <td class="num"><?= e(money((float) $s['counted_close'])) ?></td>
                <td class="num">
                  <span class="chip <?= $tone((float) $s['variance']) ?>">
                    <?= e(money((float) $s['variance'])) ?>
                  </span>
                </td>
                <td style="font-size:12px">
                  <?= ($s['close_reason'] ?? '') === ''
                    ? '<span class="muted">within tolerance</span>'
                    : e((string) $s['close_reason']) ?>
                </td>
              </tr>
            <?php endforeach; ?>
          </tbody>
        </table>
      </div>
    <?php endif; ?>
  </div>

<?php endif; ?>
