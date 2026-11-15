<?php

declare(strict_types=1);

use DacaamAdmin\Core\Csrf;
use DacaamAdmin\Core\Response;

use function DacaamAdmin\Core\e;
use function DacaamAdmin\Core\money;

/** @var array $plans @var bool $manage */
$limit = static fn (int $n): string => $n === 0 ? 'Unlimited' : (string) $n;
?>
<div class="page-head">
  <div>
    <h1>Plans</h1>
    <div class="page-sub">
      What restaurants can be sold. The limits are enforced by the app when
      staff or tables are added — existing ones are never switched off.
    </div>
  </div>
</div>

<div class="card">
  <div class="card-head">
    <h2>Plans</h2>
    <span class="muted"><?= count($plans) ?> plan(s)</span>
  </div>

  <?php if ($plans === []): ?>
    <div class="empty">No plans yet.</div>
  <?php else: ?>
    <div class="table-wrap">
      <table>
        <thead>
          <tr>
            <th>Plan</th><th class="num">Price / month</th><th class="num">Staff</th>
            <th class="num">Tables</th><th class="num">Restaurants</th><th>State</th>
          </tr>
        </thead>
        <tbody>
        <?php foreach ($plans as $p): ?>
          <tr<?= (int) $p['is_active'] === 1 ? '' : ' style="opacity:.6"' ?>>
            <td>
              <strong><?= e($p['name']) ?></strong>
              <div class="muted mono"><?= e($p['code']) ?></div>
              <?php if ((string) $p['description'] !== ''): ?>
                <div class="muted" style="font-size:12px"><?= e($p['description']) ?></div>
              <?php endif; ?>
            </td>
            <td class="num">
              <?php if ((float) $p['price'] > 0): ?>
                <?= money($p['price']) ?>
              <?php else: ?>
                <span class="muted"><?= $p['code'] === 'trial' ? 'free' : 'not set' ?></span>
              <?php endif; ?>
            </td>
            <td class="num"><?= e($limit((int) $p['max_users'])) ?></td>
            <td class="num"><?= e($limit((int) $p['max_tables'])) ?></td>
            <td class="num"><?= (int) $p['restaurants'] ?></td>
            <td>
              <span class="chip <?= (int) $p['is_active'] === 1 ? 'chip-active' : 'chip-muted' ?>">
                <?= (int) $p['is_active'] === 1 ? 'on sale' : 'retired' ?>
              </span>
            </td>
          </tr>
        <?php endforeach; ?>
        </tbody>
      </table>
    </div>
  <?php endif; ?>

  <p class="muted" style="margin-top:.75rem">
    Retired, never deleted: a restaurant already on a plan keeps it, and its
    invoices still say what it paid for. A retired plan just stops being
    offered.
  </p>
</div>

<?php if ($manage): ?>
  <div class="grid grid-2" style="margin-top:16px">
    <?php foreach ($plans as $p): ?>
      <div class="card">
        <div class="card-head">
          <h2><?= e($p['name']) ?></h2>
          <span class="muted mono"><?= e($p['code']) ?></span>
        </div>
        <form method="post" action="<?= e(Response::url('/plans/' . $p['id'])) ?>">
          <?= Csrf::field() ?>
          <div class="form-row">
            <div class="field">
              <label for="name-<?= (int) $p['id'] ?>">Name</label>
              <input id="name-<?= (int) $p['id'] ?>" name="name" required maxlength="100"
                     value="<?= e($p['name']) ?>">
            </div>
            <div class="field">
              <label for="price-<?= (int) $p['id'] ?>">Price per month (SLSH)</label>
              <input id="price-<?= (int) $p['id'] ?>" name="price" type="number" min="0" step="1000"
                     value="<?= e((string) (int) $p['price']) ?>">
            </div>
          </div>
          <div class="form-row">
            <div class="field">
              <label for="users-<?= (int) $p['id'] ?>">Max active staff</label>
              <input id="users-<?= (int) $p['id'] ?>" name="max_users" type="number" min="0" max="10000"
                     value="<?= (int) $p['max_users'] ?>">
              <div class="hint">0 = unlimited</div>
            </div>
            <div class="field">
              <label for="tables-<?= (int) $p['id'] ?>">Max active tables</label>
              <input id="tables-<?= (int) $p['id'] ?>" name="max_tables" type="number" min="0" max="10000"
                     value="<?= (int) $p['max_tables'] ?>">
              <div class="hint">0 = unlimited</div>
            </div>
          </div>
          <div class="field">
            <label for="desc-<?= (int) $p['id'] ?>">Description</label>
            <input id="desc-<?= (int) $p['id'] ?>" name="description" maxlength="255"
                   value="<?= e($p['description']) ?>">
          </div>
          <div class="field">
            <label for="active-<?= (int) $p['id'] ?>">State</label>
            <select id="active-<?= (int) $p['id'] ?>" name="is_active">
              <option value="1" <?= (int) $p['is_active'] === 1 ? 'selected' : '' ?>>On sale</option>
              <option value="0" <?= (int) $p['is_active'] === 1 ? '' : 'selected' ?>>Retired</option>
            </select>
          </div>
          <button class="btn">Save plan</button>
        </form>
      </div>
    <?php endforeach; ?>

    <div class="card">
      <div class="card-head"><h2>Add a plan</h2></div>
      <form method="post" action="<?= e(Response::url('/plans')) ?>">
        <?= Csrf::field() ?>
        <div class="form-row">
          <div class="field">
            <label for="new-code">Code</label>
            <input id="new-code" name="code" required maxlength="32" placeholder="premium"
                   pattern="[a-z0-9][a-z0-9_\-]{1,31}">
            <div class="hint">Lowercase, fixed once created — subscriptions point at it.</div>
          </div>
          <div class="field">
            <label for="new-name">Name</label>
            <input id="new-name" name="name" required maxlength="100" placeholder="Premium">
          </div>
        </div>
        <div class="form-row">
          <div class="field">
            <label for="new-price">Price per month (SLSH)</label>
            <input id="new-price" name="price" type="number" min="0" step="1000" value="0">
          </div>
          <div class="field">
            <label for="new-desc">Description</label>
            <input id="new-desc" name="description" maxlength="255">
          </div>
        </div>
        <div class="form-row">
          <div class="field">
            <label for="new-users">Max active staff</label>
            <input id="new-users" name="max_users" type="number" min="0" max="10000" value="0">
          </div>
          <div class="field">
            <label for="new-tables">Max active tables</label>
            <input id="new-tables" name="max_tables" type="number" min="0" max="10000" value="0">
          </div>
        </div>
        <button class="btn btn-primary">Add plan</button>
      </form>
    </div>
  </div>
<?php endif; ?>
