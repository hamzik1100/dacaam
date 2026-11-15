<?php

declare(strict_types=1);

use DacaamAdmin\Controllers\InvoiceController;
use DacaamAdmin\Controllers\RestaurantController;
use DacaamAdmin\Core\Csrf;
use DacaamAdmin\Core\Response;

use function DacaamAdmin\Core\dateTime;
use function DacaamAdmin\Core\e;
use function DacaamAdmin\Core\money;
use function DacaamAdmin\Core\shortDate;

/** @var array $restaurant @var ?array $subscription @var array $stats */
/** @var array $staff @var array $payments @var array $history @var array $backups */
/** @var array $today @var array $recent_orders @var array $debtors */
/** @var ?array $plan @var array $usage @var array $plans @var array<string,bool> $can */
$id = (int) $restaurant['id'];
$status = (string) $restaurant['status'];
$archived = $status === 'archived';
$daysLeft = $subscription !== null ? (int) $subscription['days_left'] : null;

// "3 of 5", or just "3" when the plan does not limit it.
$used = static function (int $count, int $limit): string {
    return $limit === 0 ? $count . ' (no limit)' : $count . ' of ' . $limit;
};

// The plans a picker offers: everything on sale, plus the current one even if
// it has since been retired — otherwise saving would silently move them off it.
$pickable = array_values(array_filter(
    $plans,
    static fn (array $p): bool => (int) $p['is_active'] === 1
        || ($subscription !== null && $p['code'] === $subscription['plan']),
));
$planOptions = static function (string $current) use ($pickable): string {
    $html = '';
    foreach ($pickable as $p) {
        $html .= sprintf(
            '<option value="%s"%s>%s%s</option>',
            e($p['code']),
            $p['code'] === $current ? ' selected' : '',
            e($p['name']),
            (float) $p['price'] > 0 ? ' — ' . e(money($p['price'])) . '/month' : '',
        );
    }

    return $html;
};
?>
<div class="page-head">
  <div>
    <h1><?= e($restaurant['logo_emoji']) ?> <?= e($restaurant['name']) ?></h1>
    <div class="page-sub">
      <span class="mono"><?= e($restaurant['slug']) ?></span>
      · <span class="chip chip-<?= e($status) ?>"><?= e($status) ?></span>
      <?php if ($restaurant['phone'] !== ''): ?>· <?= e($restaurant['phone']) ?><?php endif; ?>
    </div>
  </div>
  <a class="btn" href="<?= e(Response::url('/restaurants')) ?>">← All restaurants</a>
</div>

<?php if ($archived): ?>
  <div class="notice" style="margin-bottom:16px">
    Archived <?= e(dateTime($restaurant['archived_at'] ?? '')) ?>. Nobody can sign in,
    and it is left out of the working lists and renewal reminders. Every record
    is still here — restore it below to bring them back.
  </div>
<?php endif; ?>

<div class="grid grid-4">
  <div class="card">
    <div class="kpi-label">Lifetime sales</div>
    <div class="kpi-value"><?= money($stats['sales'] ?? 0) ?></div>
  </div>
  <div class="card">
    <div class="kpi-label">Orders</div>
    <div class="kpi-value"><?= (int) ($stats['orders'] ?? 0) ?></div>
  </div>
  <div class="card">
    <div class="kpi-label">Menu items</div>
    <div class="kpi-value"><?= (int) ($stats['items'] ?? 0) ?></div>
  </div>
  <div class="card">
    <div class="kpi-label">Active staff</div>
    <div class="kpi-value"><?= (int) ($stats['staff'] ?? 0) ?></div>
  </div>
</div>

<div class="grid grid-2" style="margin-top:16px">
  <div class="card">
    <div class="card-head"><h2>Details</h2></div>
    <?php if ($can['manage']): ?>
      <form method="post" action="<?= e(Response::url('/restaurants/' . $id)) ?>">
        <?= Csrf::field() ?>
        <div class="form-row">
          <div class="field">
            <label for="name">Name</label>
            <input id="name" name="name" required value="<?= e($restaurant['name']) ?>">
          </div>
          <div class="field">
            <label for="slug">Restaurant code</label>
            <input id="slug" name="slug" required value="<?= e($restaurant['slug']) ?>"
                   style="text-transform:uppercase">
            <div class="hint">Changing this changes how staff sign in.</div>
          </div>
        </div>
        <div class="form-row">
          <div class="field">
            <label for="phone">Phone</label>
            <input id="phone" name="phone" value="<?= e($restaurant['phone']) ?>">
          </div>
          <div class="field">
            <label for="logo_emoji">Icon</label>
            <input id="logo_emoji" name="logo_emoji" maxlength="8"
                   value="<?= e($restaurant['logo_emoji']) ?>">
          </div>
        </div>
        <div class="field">
          <label for="address">Address</label>
          <input id="address" name="address" value="<?= e($restaurant['address']) ?>">
        </div>
        <button class="btn btn-primary">Save changes</button>
      </form>
    <?php else: ?>
      <div class="stat-row"><span class="muted">Name</span><strong><?= e($restaurant['name']) ?></strong></div>
      <div class="stat-row"><span class="muted">Code</span><span class="mono"><?= e($restaurant['slug']) ?></span></div>
      <div class="stat-row"><span class="muted">Phone</span><span><?= e($restaurant['phone'] ?: '—') ?></span></div>
      <div class="stat-row"><span class="muted">Address</span><span><?= e($restaurant['address'] ?: '—') ?></span></div>
    <?php endif; ?>

    <?php if ($can['manage'] && !$archived): ?>
      <hr>

      <h3>Access</h3>
      <p class="muted">
        Suspending revokes every live token immediately. Nothing is deleted —
        orders, menu and balances stay exactly as they are, and reactivating
        restores access unchanged.
      </p>
      <div class="actions">
        <?php foreach (['active' => 'Activate', 'trial' => 'Move to trial', 'suspended' => 'Suspend'] as $value => $label): ?>
          <?php if ($status !== $value): ?>
            <form method="post" action="<?= e(Response::url('/restaurants/' . $id . '/status')) ?>">
              <?= Csrf::field() ?>
              <input type="hidden" name="status" value="<?= $value ?>">
              <button class="btn <?= $value === 'suspended' ? 'btn-danger' : '' ?>">
                <?= $label ?>
              </button>
            </form>
          <?php endif; ?>
        <?php endforeach; ?>
      </div>
    <?php endif; ?>
  </div>

  <div class="card">
    <div class="card-head"><h2>Subscription</h2></div>
    <?php if ($subscription === null): ?>
      <div class="empty">No subscription record.</div>
    <?php else: ?>
      <div class="stat-row">
        <span class="muted">Plan</span>
        <strong>
          <?= e($plan['name'] ?? $subscription['plan']) ?>
          <?php if ($plan !== null && (float) $plan['price'] > 0): ?>
            <span class="muted" style="font-weight:400">· <?= money($plan['price']) ?>/month</span>
          <?php endif; ?>
        </strong>
      </div>
      <div class="stat-row">
        <span class="muted">Staff in use</span>
        <span><?= e($used($usage['users'], (int) ($plan['max_users'] ?? 0))) ?></span>
      </div>
      <div class="stat-row">
        <span class="muted">Tables in use</span>
        <span><?= e($used($usage['tables'], (int) ($plan['max_tables'] ?? 0))) ?></span>
      </div>
      <div class="stat-row">
        <span class="muted">Status</span>
        <span class="chip chip-<?= e($subscription['status']) ?>"><?= e($subscription['status']) ?></span>
      </div>
      <div class="stat-row">
        <span class="muted">Started</span>
        <span><?= shortDate($subscription['starts_on']) ?></span>
      </div>
      <div class="stat-row">
        <span class="muted">Ends</span>
        <span>
          <?= shortDate($subscription['ends_on']) ?>
          <?php if ($daysLeft !== null): ?>
            <span class="chip <?= $daysLeft < 0 ? 'chip-expired' : ($daysLeft <= 7 ? 'chip-suspended' : 'chip-active') ?>">
              <?= $daysLeft < 0 ? abs($daysLeft) . 'd overdue' : $daysLeft . 'd left' ?>
            </span>
          <?php endif; ?>
        </span>
      </div>

      <?php if ($can['billing'] && !$archived): ?>
        <hr>

        <h3>Renew</h3>
        <form method="post" action="<?= e(Response::url('/subscriptions/' . $subscription['id'] . '/renew')) ?>">
          <?= Csrf::field() ?>
          <div class="form-row">
            <div class="field">
              <label for="renew_plan">Plan</label>
              <select id="renew_plan" name="plan"><?= $planOptions((string) $subscription['plan']) ?></select>
            </div>
            <div class="field">
              <label for="months">Months</label>
              <input id="months" name="months" type="number" min="1" max="36" value="12">
            </div>
          </div>
          <div class="form-row">
            <div class="field">
              <label for="renew_amount">Amount paid</label>
              <input id="renew_amount" name="amount" type="number" min="0" step="1000"
                     value="<?= e((string) (int) $subscription['amount']) ?>">
              <?php if ($plan !== null && (float) $plan['price'] > 0): ?>
                <div class="hint">
                  <?= e($plan['name']) ?> is <?= money($plan['price']) ?>/month —
                  <?= money((float) $plan['price'] * 12) ?> for 12 months.
                </div>
              <?php endif; ?>
            </div>
            <div class="field">
              <label for="method">Method</label>
              <select id="method" name="method">
                <option value="bank">Bank</option>
                <option value="zaad">ZAAD</option>
                <option value="edahab">eDahab</option>
                <option value="cash">Cash</option>
              </select>
            </div>
          </div>
          <div class="field">
            <label for="reference">Reference</label>
            <input id="reference" name="reference" placeholder="Transaction id">
          </div>
          <div class="hint" style="margin-bottom:12px">
            A lapsed subscription renews from today, not from the expired date.
            Every payment gets a numbered invoice.
          </div>
          <button class="btn btn-primary">Renew &amp; record payment</button>
        </form>

        <hr>

        <h3>Adjust</h3>
        <form method="post" action="<?= e(Response::url('/subscriptions/' . $subscription['id'])) ?>">
          <?= Csrf::field() ?>
          <div class="form-row">
            <div class="field">
              <label for="plan">Plan</label>
              <select id="plan" name="plan"><?= $planOptions((string) $subscription['plan']) ?></select>
            </div>
            <div class="field">
              <label for="sub_status">Status</label>
              <select id="sub_status" name="status">
                <?php foreach (['active', 'trial', 'expired', 'suspended'] as $s): ?>
                  <option value="<?= $s ?>" <?= $subscription['status'] === $s ? 'selected' : '' ?>>
                    <?= ucfirst($s) ?>
                  </option>
                <?php endforeach; ?>
              </select>
            </div>
          </div>
          <div class="form-row">
            <div class="field">
              <label for="ends_on">Ends on</label>
              <input id="ends_on" name="ends_on" type="date"
                     value="<?= e((string) $subscription['ends_on']) ?>">
            </div>
            <div class="field">
              <label for="sub_amount">Plan amount</label>
              <input id="sub_amount" name="amount" type="number" min="0" step="1000"
                     value="<?= e((string) (int) $subscription['amount']) ?>">
            </div>
          </div>
          <button class="btn">Save subscription</button>
        </form>
      <?php endif; ?>
    <?php endif; ?>
  </div>
</div>

<div class="card" style="margin-top:16px">
  <div class="card-head">
    <h2>Staff</h2>
    <span class="muted"><?= count($staff) ?> account(s)</span>
  </div>
  <?php if ($staff === []): ?>
    <div class="empty">No users.</div>
  <?php else: ?>
    <div class="table-wrap">
      <table>
        <thead>
          <tr>
            <th>Name</th><th>Phone</th><th>Role</th><th>Last sign-in</th>
            <?php if ($can['manage']): ?><th>Reset password</th><?php endif; ?>
          </tr>
        </thead>
        <tbody>
        <?php foreach ($staff as $u): ?>
          <tr>
            <td>
              <strong><?= e($u['name']) ?></strong>
              <?php if ((int) $u['is_active'] !== 1): ?>
                <span class="chip chip-expired">inactive</span>
              <?php endif; ?>
            </td>
            <td class="mono"><?= e($u['phone']) ?></td>
            <td><?= e($u['role']) ?></td>
            <td><?= $u['last_login_at'] !== null ? dateTime($u['last_login_at']) : '—' ?></td>
            <?php if ($can['manage']): ?>
              <td>
                <form method="post"
                      action="<?= e(Response::url('/restaurants/' . $id . '/reset-password')) ?>"
                      style="display:flex;gap:8px">
                  <?= Csrf::field() ?>
                  <input type="hidden" name="user_id" value="<?= (int) $u['id'] ?>">
                  <input name="password" minlength="6" required placeholder="New password"
                         style="max-width:180px">
                  <button class="btn btn-sm">Reset</button>
                </form>
              </td>
            <?php endif; ?>
          </tr>
        <?php endforeach; ?>
        </tbody>
      </table>
    </div>
    <?php if ($can['manage']): ?>
      <div class="hint" style="margin-top:10px">
        A reset ends every session for that user and forces a change on next sign-in.
      </div>
    <?php endif; ?>
  <?php endif; ?>
</div>

<div class="grid grid-2" style="margin-top:16px">
  <div class="card">
    <div class="card-head"><h2>Payments</h2></div>
    <?php if ($payments === []): ?>
      <div class="empty">No payments recorded.</div>
    <?php else: ?>
      <div class="table-wrap">
        <table>
          <thead>
            <tr>
              <th>Invoice</th><th>Date</th><th>Method</th><th>Reference</th>
              <th class="num">Amount</th><th></th>
            </tr>
          </thead>
          <tbody>
          <?php foreach ($payments as $p): ?>
            <tr>
              <td>
                <a class="mono" href="<?= e(Response::url('/invoices/' . $p['id'])) ?>">
                  <?= e(InvoiceController::number($p)) ?>
                </a>
              </td>
              <td><?= shortDate($p['paid_on']) ?></td>
              <td><?= e($p['method']) ?></td>
              <td class="muted"><?= e($p['reference'] ?? '') ?></td>
              <td class="num"><?= money($p['amount']) ?></td>
              <td class="num">
                <?php if ($can['billing']): ?>
                  <form method="post" action="<?= e(Response::url('/invoices/' . $p['id'] . '/email')) ?>">
                    <?= Csrf::field() ?>
                    <button class="btn btn-sm">Email</button>
                  </form>
                <?php endif; ?>
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
      <h2>What they are seeing</h2>
      <span class="chip">read-only</span>
    </div>

    <div class="grid grid-2" style="gap:.75rem">
      <div class="stack">
        <span class="muted">Sales today</span>
        <strong><?= money((float) ($today['sales'] ?? 0)) ?></strong>
      </div>
      <div class="stack">
        <span class="muted">Orders today</span>
        <strong><?= (int) ($today['orders'] ?? 0) ?><?php
          if ((int) ($today['cancelled'] ?? 0) > 0): ?>
          <span class="muted"> · <?= (int) $today['cancelled'] ?> cancelled</span>
        <?php endif; ?></strong>
      </div>
    </div>

    <?php if ((float) ($today['unpaid'] ?? 0) > 0): ?>
      <p class="muted" style="margin-bottom:0">
        <?= money((float) $today['unpaid']) ?> of today's orders are not fully
        paid.
      </p>
    <?php endif; ?>

    <h3 style="margin:1.25rem 0 .5rem;font-size:14px">Recent orders</h3>
    <?php if ($recent_orders === []): ?>
      <div class="empty">No orders yet.</div>
    <?php else: ?>
      <div class="table-wrap">
      <table class="table">
        <thead><tr><th>#</th><th>Type</th><th>Who</th><th>Total</th><th>State</th><th>When</th></tr></thead>
        <tbody>
          <?php foreach ($recent_orders as $o): ?>
            <tr>
              <td class="mono">#<?= (int) $o['order_number'] ?></td>
              <td><?= e(str_replace('_', ' ', (string) $o['order_type'])) ?></td>
              <td>
                <?= e((string) ($o['customer_name'] ?: $o['waiter_name'])) ?>
              </td>
              <td><?= money((float) $o['total']) ?></td>
              <td>
                <span class="chip <?= $o['status'] === 'cancelled' ? 'chip-expired' : 'chip-active' ?>">
                  <?= e((string) $o['status']) ?>
                </span>
                <?php if ((string) $o['payment_status'] !== 'paid' && $o['status'] !== 'cancelled'): ?>
                  <span class="chip chip-expired"><?= e((string) $o['payment_status']) ?></span>
                <?php endif; ?>
              </td>
              <td class="muted"><?= dateTime($o['created_at']) ?></td>
            </tr>
          <?php endforeach; ?>
        </tbody>
      </table>
      </div>
    <?php endif; ?>

    <?php if ($debtors !== []): ?>
      <h3 style="margin:1.25rem 0 .5rem;font-size:14px">Their customers owe</h3>
      <table class="table">
        <tbody>
          <?php foreach ($debtors as $d): ?>
            <tr>
              <td><?= e((string) $d['name']) ?>
                <span class="muted"><?= e((string) $d['phone']) ?></span>
              </td>
              <td style="text-align:right"><?= money((float) $d['balance_owed']) ?></td>
            </tr>
          <?php endforeach; ?>
        </tbody>
      </table>
    <?php endif; ?>
  </div>

  <?php if ($can['backups']): ?>
  <div class="card">
    <div class="card-head"><h2>Backups</h2></div>

    <p class="muted" style="margin-top:0">
      This restaurant's own data — menu, staff, orders, customers, ledger.
      Separate from the nightly whole-database backup, and restoring one touches
      nothing belonging to any other restaurant.
    </p>

    <form method="post" action="<?= e(Response::url('/restaurants/' . $restaurant['id'] . '/backup')) ?>">
      <?= Csrf::field() ?>
      <button type="submit" class="btn btn-primary">Back up this restaurant</button>
    </form>

    <?php if ($backups === []): ?>
      <div class="empty" style="margin-top:1rem">No backups for this restaurant yet.</div>
    <?php else: ?>
      <table class="table" style="margin-top:1rem">
        <thead><tr><th>File</th><th>Size</th><th>Taken</th><th></th></tr></thead>
        <tbody>
          <?php foreach ($backups as $b): ?>
            <tr>
              <td style="font-size:12px"><?= e($b['name']) ?></td>
              <td><?= e($b['size'] > 1048576
                  ? number_format($b['size'] / 1048576, 1) . ' MB'
                  : number_format($b['size'] / 1024) . ' KB') ?></td>
              <td class="muted"><?= e(dateTime(date('Y-m-d H:i:s', $b['at']))) ?></td>
              <td>
                <form method="post"
                      action="<?= e(Response::url('/restaurants/' . $restaurant['id'] . '/restore')) ?>"
                      onsubmit="return confirm('Restore this restaurant from the backup? Everything it has now is replaced.')">
                  <?= Csrf::field() ?>
                  <input type="hidden" name="file" value="<?= e($b['name']) ?>">
                  <input type="text" name="confirm" required
                         placeholder="<?= e((string) $restaurant['slug']) ?>"
                         style="width:110px;display:inline-block;margin:0 6px 0 0">
                  <button type="submit" class="btn">Restore</button>
                </form>
              </td>
            </tr>
          <?php endforeach; ?>
        </tbody>
      </table>

      <p class="muted" style="margin-top:.75rem">
        Restoring replaces everything this restaurant has now. A copy of the
        present state is saved first, automatically — so a restore can itself be
        undone.
      </p>
    <?php endif; ?>
  </div>
  <?php endif; ?>

  <?php if ($can['export'] || $can['archive']): ?>
  <div class="card">
    <div class="card-head"><h2>Their data</h2></div>

    <?php if ($can['export']): ?>
      <p class="muted" style="margin-top:0">
        Their own records as spreadsheets — for their accountant, or to take
        with them if they leave. Each download is written to the platform audit.
      </p>
      <div class="actions">
        <?php foreach (RestaurantController::exportable() as $dataset => $label): ?>
          <a class="btn btn-sm"
             href="<?= e(Response::url('/restaurants/' . $id . '/export/' . $dataset)) ?>">
            <?= e($label) ?> CSV
          </a>
        <?php endforeach; ?>
      </div>
    <?php endif; ?>

    <?php if ($can['archive']): ?>
      <?php if ($can['export']): ?><hr><?php endif; ?>

      <?php if ($archived): ?>
        <h3>Restore from the archive</h3>
        <p class="muted">
          Comes back suspended, so that switching them on is its own decision.
        </p>
        <form method="post" action="<?= e(Response::url('/restaurants/' . $id . '/unarchive')) ?>">
          <?= Csrf::field() ?>
          <button class="btn btn-primary">Restore</button>
        </form>
      <?php else: ?>
        <h3>Archive</h3>
        <p class="muted">
          For a restaurant that has left. Everyone is signed out, it drops out of
          the working lists and reminders, and nothing is deleted — it can be
          restored later exactly as it was.
        </p>
        <form method="post" action="<?= e(Response::url('/restaurants/' . $id . '/archive')) ?>"
              style="display:flex;gap:8px;flex-wrap:wrap">
          <?= Csrf::field() ?>
          <input name="confirm" required autocomplete="off"
                 placeholder="Type <?= e($restaurant['slug']) ?> to confirm"
                 style="max-width:240px">
          <button class="btn btn-danger">Archive restaurant</button>
        </form>
      <?php endif; ?>
    <?php endif; ?>
  </div>
  <?php endif; ?>

  <div class="card">
    <div class="card-head"><h2>Platform history</h2></div>
    <?php if ($history === []): ?>
      <div class="empty">Nothing recorded for this restaurant.</div>
    <?php else: ?>
      <?php foreach ($history as $h): ?>
        <div style="display:flex;justify-content:space-between;gap:12px;padding:6px 0">
          <div class="stack">
            <span><strong><?= e(str_replace('_', ' ', (string) $h['action'])) ?></strong></span>
            <?php if ((string) $h['detail'] !== ''): ?>
              <span class="muted"><?= e($h['detail']) ?></span>
            <?php endif; ?>
          </div>
          <span class="muted" style="white-space:nowrap"><?= dateTime($h['created_at']) ?></span>
        </div>
      <?php endforeach; ?>
    <?php endif; ?>
  </div>
</div>
