<?php

declare(strict_types=1);

use DacaamAdmin\Core\Csrf;
use DacaamAdmin\Core\Response;

use function DacaamAdmin\Core\e;

/**
 * @var bool         $on
 * @var bool         $pending
 * @var string       $secret
 * @var string       $uri
 * @var ?array       $codes
 * @var int          $codes_left
 */
?>
<div class="page-head">
  <div>
    <h1>Security</h1>
    <div class="page-sub">
      This account can reach every restaurant on the platform.
    </div>
  </div>
  <span class="chip <?= $on ? 'chip-active' : 'chip-expired' ?>">
    <?= $on ? 'two-factor on' : 'password only' ?>
  </span>
</div>

<?php if ($codes !== null): ?>
  <div class="card" style="margin-bottom:1.25rem;border-color:var(--success)">
    <div class="card-head"><h2>Your recovery codes</h2></div>

    <p class="muted" style="margin-top:0">
      Shown once. Write them down now — they are stored hashed and cannot be
      read back, only replaced. Each one works a single time.
    </p>

    <div class="grid grid-4" style="gap:8px;margin:1rem 0">
      <?php foreach ($codes as $code): ?>
        <code style="
          display:block;padding:10px;text-align:center;
          background:var(--muted);border-radius:var(--radius-sm);
          font-size:15px;letter-spacing:1px
        "><?= e($code) ?></code>
      <?php endforeach; ?>
    </div>

    <div class="notice">
      A lost phone with no codes, on the only active administrator account,
      locks the platform out of itself — and the only way back is somebody with
      database access. That is the situation these prevent.
    </div>
  </div>
<?php endif; ?>

<div class="grid grid-2">
  <div class="card">
    <div class="card-head"><h2>Two-factor</h2></div>

    <?php if ($on): ?>
      <p class="muted" style="margin-top:0">
        Signing in asks for a code after the password. Recovery codes left:
        <strong><?= (int) $codes_left ?></strong>.
      </p>

      <?php if ($codes_left <= 2): ?>
        <div class="notice" style="margin-bottom:1rem">
          Nearly out. Generate a new set before the last one is spent.
        </div>
      <?php endif; ?>

      <form method="post" action="<?= e(Response::url('/security/recovery-codes')) ?>"
            style="margin-bottom:1rem">
        <?= Csrf::field() ?>
        <button class="btn">New recovery codes</button>
      </form>

      <form method="post" action="<?= e(Response::url('/security/2fa/disable')) ?>"
            onsubmit="return confirm('Turn two-factor off for this account?')">
        <?= Csrf::field() ?>
        <div class="field">
          <label for="password">Your password</label>
          <input id="password" name="password" type="password"
                 autocomplete="current-password" required>
          <div class="hint">
            Asked for because a borrowed session should not be enough to take
            the lock off.
          </div>
        </div>
        <button class="btn btn-danger">Turn two-factor off</button>
      </form>

    <?php elseif ($pending): ?>
      <p class="muted" style="margin-top:0">
        Scan this with Google Authenticator, Authy, or any TOTP app, then type
        what it shows.
      </p>

      <div class="field">
        <label>Setup key</label>
        <code style="
          display:block;padding:12px;background:var(--muted);
          border-radius:var(--radius-sm);word-break:break-all;font-size:14px
        "><?= e($secret) ?></code>
        <div class="hint">
          Type this in by hand if the app cannot scan. The full link is
          <span style="word-break:break-all"><?= e($uri) ?></span>
        </div>
      </div>

      <form method="post" action="<?= e(Response::url('/security/2fa/confirm')) ?>">
        <?= Csrf::field() ?>
        <div class="field">
          <label for="code">Code from the app</label>
          <input id="code" name="code" type="text" inputmode="numeric"
                 autocomplete="one-time-code" required placeholder="000000"
                 style="letter-spacing:4px">
        </div>
        <button class="btn btn-primary">Turn it on</button>
      </form>

      <p class="muted" style="font-size:12px;margin-top:1rem">
        Nothing changes about signing in until this code is accepted. A setup
        that was typed in wrong cannot lock you out.
      </p>

    <?php else: ?>
      <p class="muted" style="margin-top:0">
        Right now this account is a password and nothing else — while the staff
        inside the restaurants can already turn on a second factor. It is the
        most valuable credential on the platform and the least protected.
      </p>

      <form method="post" action="<?= e(Response::url('/security/2fa/setup')) ?>">
        <?= Csrf::field() ?>
        <button class="btn btn-primary">Set up two-factor</button>
      </form>
    <?php endif; ?>
  </div>

  <div class="card">
    <div class="card-head"><h2>Password</h2></div>

    <form method="post" action="<?= e(Response::url('/password')) ?>">
      <?= Csrf::field() ?>
      <div class="field">
        <label for="current_password">Current password</label>
        <input id="current_password" name="current_password" type="password"
               autocomplete="current-password" required>
      </div>
      <div class="field">
        <label for="new_password">New password</label>
        <input id="new_password" name="new_password" type="password"
               autocomplete="new-password" required>
      </div>
      <div class="field">
        <label for="confirm_password">Again</label>
        <input id="confirm_password" name="confirm_password" type="password"
               autocomplete="new-password" required>
      </div>
      <button class="btn btn-primary">Change password</button>
    </form>
  </div>
</div>
