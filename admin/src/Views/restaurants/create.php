<?php

declare(strict_types=1);

use DacaamAdmin\Core\Csrf;
use DacaamAdmin\Core\Response;

use function DacaamAdmin\Core\e;
use function DacaamAdmin\Core\money;

/** @var array $old @var array $plans */
$v = static fn (string $key, string $default = ''): string => e($old[$key] ?? $default);
$chosen = (string) ($old['plan'] ?? 'trial');
?>
<div class="page-head">
  <div>
    <h1>New restaurant</h1>
    <div class="page-sub">
      Creates the tenant, its admin user, the built-in roles, default settings,
      accounts and starter categories — all or nothing.
    </div>
  </div>
  <a class="btn" href="<?= e(Response::url('/restaurants')) ?>">Cancel</a>
</div>

<form method="post" action="<?= e(Response::url('/restaurants')) ?>">
  <?= Csrf::field() ?>

  <div class="card">
    <div class="card-head"><h2>Restaurant</h2></div>

    <div class="form-row">
      <div class="field">
        <label for="name">Name</label>
        <input id="name" name="name" required value="<?= $v('name') ?>"
               placeholder="Hamze Restaurant">
      </div>
      <div class="field">
        <label for="slug">Restaurant code</label>
        <input id="slug" name="slug" required value="<?= $v('slug') ?>"
               placeholder="HAMZE" style="text-transform:uppercase">
        <div class="hint">Staff type this to sign in. Letters and numbers only.</div>
      </div>
    </div>

    <div class="form-row">
      <div class="field">
        <label for="phone">Phone</label>
        <input id="phone" name="phone" value="<?= $v('phone') ?>" placeholder="063 4567890">
      </div>
      <div class="field">
        <label for="logo_emoji">Icon</label>
        <input id="logo_emoji" name="logo_emoji" value="<?= $v('logo_emoji', '🍽️') ?>" maxlength="8">
      </div>
    </div>

    <div class="field">
      <label for="address">Address</label>
      <input id="address" name="address" value="<?= $v('address') ?>"
             placeholder="Jigjiga Yar, Hargeysa">
    </div>
  </div>

  <div class="card">
    <div class="card-head"><h2>Subscription</h2></div>

    <div class="form-row">
      <div class="field">
        <label for="status">Status</label>
        <select id="status" name="status">
          <option value="trial">Trial</option>
          <option value="active">Active</option>
        </select>
      </div>
      <div class="field">
        <label for="plan">Plan</label>
        <select id="plan" name="plan">
          <?php foreach ($plans as $p): ?>
            <option value="<?= e($p['code']) ?>" <?= $chosen === $p['code'] ? 'selected' : '' ?>>
              <?= e($p['name']) ?><?= (float) $p['price'] > 0 ? ' — ' . e(money($p['price'])) . '/month' : '' ?>
            </option>
          <?php endforeach; ?>
        </select>
        <div class="hint">Plans and their limits are set on the Plans page.</div>
      </div>
    </div>

    <div class="form-row">
      <div class="field">
        <label for="subscription_days">Length (days)</label>
        <input id="subscription_days" name="subscription_days" type="number"
               min="1" max="1095" value="<?= $v('subscription_days', '30') ?>">
      </div>
      <div class="field">
        <label for="amount">Amount (SLSH)</label>
        <input id="amount" name="amount" type="number" min="0" step="1000"
               value="<?= $v('amount', '0') ?>">
        <div class="hint">Recorded on the subscription. Payments are logged on renewal.</div>
      </div>
    </div>
  </div>

  <div class="card">
    <div class="card-head"><h2>Restaurant admin</h2></div>
    <p class="muted" style="margin-top:0">
      This person signs in first and creates the rest of the staff. They will be
      asked to change this password on first use.
    </p>

    <div class="form-row">
      <div class="field">
        <label for="admin_name">Name</label>
        <input id="admin_name" name="admin_name" required value="<?= $v('admin_name') ?>"
               placeholder="Axmed Xasan">
      </div>
      <div class="field">
        <label for="admin_phone">Phone</label>
        <input id="admin_phone" name="admin_phone" required value="<?= $v('admin_phone') ?>"
               placeholder="063 4567890">
      </div>
    </div>

    <div class="form-row">
      <div class="field">
        <label for="admin_email">Email <span class="muted">(optional)</span></label>
        <input id="admin_email" name="admin_email" type="email" value="<?= $v('admin_email') ?>">
        <div class="hint">Only used for password reset. No email means no self-service reset.</div>
      </div>
      <div class="field">
        <label for="admin_password">Temporary password</label>
        <input id="admin_password" name="admin_password" required minlength="6"
               placeholder="At least 6 characters">
      </div>
    </div>
  </div>

  <div class="actions">
    <button class="btn btn-primary">Create restaurant</button>
    <a class="btn" href="<?= e(Response::url('/restaurants')) ?>">Cancel</a>
  </div>
</form>
