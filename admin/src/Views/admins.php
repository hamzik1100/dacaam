<?php

declare(strict_types=1);

use DacaamAdmin\Core\Access;
use DacaamAdmin\Core\Csrf;
use DacaamAdmin\Core\Response;

use function DacaamAdmin\Core\dateTime;
use function DacaamAdmin\Core\e;

/**
 * @var array $admins
 * @var array $me
 * @var int   $active
 * @var int   $owners
 */
?>
<div class="page-head">
  <div>
    <h1>Administrators</h1>
    <div class="page-sub">
      Who can run the platform. Each of these can reach every restaurant.
    </div>
  </div>
  <span class="chip <?= $active > 1 ? 'chip-active' : 'chip-trial' ?>">
    <?= (int) $active ?> active
  </span>
</div>

<?php if ($active === 1): ?>
  <div class="notice" style="margin-bottom:1.25rem">
    One active administrator. If that account is lost — a forgotten password, a
    lost phone, somebody leaving — there is nobody else who can let you back in.
    A second one is the cheapest insurance on this page.
  </div>
<?php endif; ?>

<div class="card">
  <div class="card-head"><h2>People</h2></div>

  <div class="table-wrap">
    <table class="table">
      <thead>
        <tr>
          <th>Name</th><th>Email</th><th>Role</th><th>Two-factor</th>
          <th>Last signed in</th><th>Added by</th><th></th>
        </tr>
      </thead>
      <tbody>
        <?php foreach ($admins as $a): ?>
          <tr<?= (int) $a['is_active'] === 1 ? '' : ' style="opacity:.55"' ?>>
            <td>
              <?= e((string) $a['name']) ?>
              <?php if ((int) $a['id'] === (int) $me['id']): ?>
                <span class="chip chip-info" style="margin-left:6px">you</span>
              <?php endif; ?>
              <?php if ((int) $a['is_active'] !== 1): ?>
                <div class="muted" style="font-size:12px">
                  disabled <?= e(dateTime((string) $a['disabled_at'])) ?>
                </div>
              <?php endif; ?>
            </td>
            <td class="muted" style="font-size:13px"><?= e((string) $a['email']) ?></td>
            <td>
              <?php
              // Not your own, and not the last active owner's — the two ways a
              // role change could leave nobody able to manage this page.
              $roleLocked = (int) $a['id'] === (int) $me['id']
                  || ($a['role'] === 'owner' && (int) $a['is_active'] === 1 && $owners <= 1);
              ?>
              <?php if ($roleLocked): ?>
                <span class="chip <?= $a['role'] === 'owner' ? 'chip-info' : 'chip-muted' ?>">
                  <?= e(Access::ROLES[$a['role']] ?? $a['role']) ?>
                </span>
              <?php else: ?>
                <form method="post" action="<?= e(Response::url('/admins/' . $a['id'] . '/role')) ?>"
                      style="display:flex;gap:6px">
                  <?= Csrf::field() ?>
                  <select name="role" style="width:auto;padding:4px 8px">
                    <?php foreach (Access::ROLES as $value => $label): ?>
                      <option value="<?= e($value) ?>" <?= $a['role'] === $value ? 'selected' : '' ?>>
                        <?= e($label) ?>
                      </option>
                    <?php endforeach; ?>
                  </select>
                  <button class="btn btn-sm">Set</button>
                </form>
              <?php endif; ?>
            </td>
            <td>
              <?php if ($a['two_factor_confirmed_at'] !== null): ?>
                <span class="chip chip-active">on</span>
                <?php if ((int) $a['codes_left'] <= 2): ?>
                  <div class="muted" style="font-size:11px">
                    <?= (int) $a['codes_left'] ?> codes left
                  </div>
                <?php endif; ?>
              <?php else: ?>
                <span class="chip chip-expired">off</span>
              <?php endif; ?>
            </td>
            <td class="muted" style="white-space:nowrap;font-size:12px">
              <?= $a['last_login_at'] === null
                ? 'never' : e(dateTime((string) $a['last_login_at'])) ?>
            </td>
            <td class="muted" style="font-size:12px">
              <?= ($a['invited_by'] ?? '') === ''
                ? 'first-run setup' : e((string) $a['invited_by']) ?>
            </td>
            <td>
              <?php
              // Two ways to lock the platform out of itself, both closed: you
              // cannot switch yourself off, and the last one standing stays on.
              $blocked = (int) $a['id'] === (int) $me['id']
                  || ((int) $a['is_active'] === 1 && $active <= 1)
                  || ($a['role'] === 'owner' && (int) $a['is_active'] === 1 && $owners <= 1);
              ?>
              <?php if ($blocked): ?>
                <span class="muted" style="font-size:12px">—</span>
              <?php else: ?>
                <form method="post"
                      action="<?= e(Response::url('/admins/' . $a['id'] . '/active')) ?>"
                      onsubmit="return confirm('<?= (int) $a['is_active'] === 1
                          ? 'Disable ' . e((string) $a['name']) . '?'
                          : 'Let ' . e((string) $a['name']) . ' sign in again?' ?>')">
                  <?= Csrf::field() ?>
                  <input type="hidden" name="active"
                         value="<?= (int) $a['is_active'] === 1 ? '0' : '1' ?>">
                  <button class="btn btn-sm <?= (int) $a['is_active'] === 1 ? 'btn-danger' : '' ?>">
                    <?= (int) $a['is_active'] === 1 ? 'Disable' : 'Enable' ?>
                  </button>
                </form>
              <?php endif; ?>
            </td>
          </tr>
        <?php endforeach; ?>
      </tbody>
    </table>
  </div>

  <p class="muted" style="margin-top:.75rem">
    Disabled, never deleted. Half the platform history points at these rows, and
    a trail that says "administrator 3" with nothing behind it cannot be read.
  </p>
</div>

<div class="card" style="margin-top:1.25rem">
  <div class="card-head"><h2>Add an administrator</h2></div>

  <form method="post" action="<?= e(Response::url('/admins')) ?>">
    <?= Csrf::field() ?>

    <div class="form-row">
      <div class="field">
        <label for="name">Name</label>
        <input id="name" name="name" type="text" required>
      </div>
      <div class="field">
        <label for="email">Email</label>
        <input id="email" name="email" type="email" required>
      </div>
    </div>

    <div class="field">
      <label for="role">Role</label>
      <select id="role" name="role">
        <option value="support" selected>Support — restaurants, staff passwords, backups, messages</option>
        <option value="billing">Billing — renewals, payments, invoices, reminders</option>
        <option value="owner">Owner — everything, including administrators and settings</option>
      </select>
      <div class="hint">Everyone can read every page they can open. Roles decide who can act.</div>
    </div>

    <div class="field">
      <label for="password">Temporary password</label>
      <input id="password" name="password" type="text" required autocomplete="off">
      <div class="hint">
        At least 10 characters. Hand it over in person and have them change it —
        a working password sent by email sits in a mailbox neither of you
        controls.
      </div>
    </div>

    <button class="btn btn-primary">Add</button>
  </form>
</div>
