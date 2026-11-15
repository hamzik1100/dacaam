<?php

declare(strict_types=1);

use DacaamAdmin\Core\Csrf;
use DacaamAdmin\Core\Response;

use function DacaamAdmin\Core\dateTime;
use function DacaamAdmin\Core\e;

/** @var array $smtp @var array $system @var array $admins @var array $app @var array $issuer */
$s = static fn (string $key, string $default = ''): string => e($smtp[$key] ?? $default);
$configured = ($smtp['smtp_host'] ?? '') !== '' && ($smtp['smtp_from_email'] ?? '') !== '';
?>
<div class="page-head">
  <div>
    <h1>Settings</h1>
    <div class="page-sub">Platform-wide configuration. Restaurants keep their own settings.</div>
  </div>
</div>

<div class="grid grid-2">
  <div class="card">
    <div class="card-head">
      <h2>Mail (SMTP)</h2>
      <span class="chip <?= $configured ? 'chip-active' : 'chip-expired' ?>">
        <?= $configured ? 'configured' : 'not configured' ?>
      </span>
    </div>
    <p class="muted" style="margin-top:0">
      Used for password-reset codes. Without it the app still works — staff
      just cannot reset their own password.
    </p>

    <form method="post" action="<?= e(Response::url('/settings/smtp')) ?>">
      <?= Csrf::field() ?>
      <div class="form-row">
        <div class="field">
          <label for="host">Host</label>
          <input id="host" name="host" value="<?= $s('smtp_host') ?>" placeholder="smtp.gmail.com">
        </div>
        <div class="field">
          <label for="port">Port</label>
          <input id="port" name="port" type="number" value="<?= $s('smtp_port', '587') ?>">
        </div>
      </div>
      <div class="form-row">
        <div class="field">
          <label for="encryption">Encryption</label>
          <select id="encryption" name="encryption">
            <?php foreach (['tls' => 'STARTTLS', 'ssl' => 'SSL', 'none' => 'None'] as $value => $label): ?>
              <option value="<?= $value ?>" <?= ($smtp['smtp_encryption'] ?? 'tls') === $value ? 'selected' : '' ?>>
                <?= $label ?>
              </option>
            <?php endforeach; ?>
          </select>
        </div>
        <div class="field">
          <label for="username">Username</label>
          <input id="username" name="username" value="<?= $s('smtp_username') ?>" autocomplete="off">
        </div>
      </div>
      <div class="field">
        <label for="password">Password</label>
        <input id="password" name="password" type="password" autocomplete="new-password"
               placeholder="<?= ($smtp['smtp_password'] ?? '') !== '' ? 'Unchanged' : 'Not set' ?>">
        <div class="hint">Leave blank to keep the stored password.</div>
      </div>
      <div class="form-row">
        <div class="field">
          <label for="from_email">From address</label>
          <input id="from_email" name="from_email" type="email" value="<?= $s('smtp_from_email') ?>">
        </div>
        <div class="field">
          <label for="from_name">From name</label>
          <input id="from_name" name="from_name" value="<?= $s('smtp_from_name', 'DACAAM') ?>">
        </div>
      </div>
      <button class="btn btn-primary">Save mail settings</button>
    </form>

    <hr>

    <h3>Send a test</h3>
    <form method="post" action="<?= e(Response::url('/settings/smtp/test')) ?>"
          style="display:flex;gap:10px;flex-wrap:wrap">
      <?= Csrf::field() ?>
      <input name="to" type="email" required placeholder="you@example.com"
             style="flex:1;min-width:200px">
      <button class="btn">Send test</button>
    </form>
  </div>

  <div class="card">
    <div class="card-head"><h2>Platform administrators</h2></div>
    <div class="table-wrap">
      <table>
        <thead>
          <tr><th>Name</th><th>Email</th><th>Last sign-in</th><th></th></tr>
        </thead>
        <tbody>
        <?php foreach ($admins as $a): ?>
          <tr>
            <td><strong><?= e($a['name']) ?></strong></td>
            <td class="mono"><?= e($a['email']) ?></td>
            <td><?= $a['last_login_at'] !== null ? dateTime($a['last_login_at']) : '—' ?></td>
            <td>
              <span class="chip <?= (int) $a['is_active'] === 1 ? 'chip-active' : 'chip-expired' ?>">
                <?= (int) $a['is_active'] === 1 ? 'active' : 'disabled' ?>
              </span>
            </td>
          </tr>
        <?php endforeach; ?>
        </tbody>
      </table>
    </div>

    <hr>

    <div class="card-head"><h2>System values</h2></div>
    <?php if ($system === []): ?>
      <div class="empty">No system settings stored.</div>
    <?php else: ?>
      <div class="table-wrap">
        <table>
          <thead><tr><th>Key</th><th>Value</th></tr></thead>
          <tbody>
          <?php foreach ($system as $row): ?>
            <tr>
              <td class="mono"><?= e($row['key_name']) ?></td>
              <td class="muted"><?= e((string) ($row['value'] ?? '')) ?></td>
            </tr>
          <?php endforeach; ?>
          </tbody>
        </table>
      </div>
    <?php endif; ?>
  </div>
</div>

<div class="grid grid-2" style="margin-top:16px">
  <div class="card">
    <div class="card-head">
      <h2>Mobile app version</h2>
      <span class="chip <?= $app['min_version'] !== '' ? 'chip-active' : 'chip-muted' ?>">
        <?= $app['min_version'] !== '' ? 'minimum ' . e($app['min_version']) : 'no minimum' ?>
      </span>
    </div>
    <p class="muted" style="margin-top:0">
      The app checks this when it starts. Below the <strong>minimum</strong> it
      stops and shows the download link; below the <strong>latest</strong> it only
      mentions that an update exists. Leave both empty to ask for nothing.
    </p>
    <form method="post" action="<?= e(Response::url('/settings/app-version')) ?>">
      <?= Csrf::field() ?>
      <div class="form-row">
        <div class="field">
          <label for="min_version">Minimum version</label>
          <input id="min_version" name="min_version" placeholder="1.1.0"
                 value="<?= e($app['min_version']) ?>">
        </div>
        <div class="field">
          <label for="latest_version">Latest version</label>
          <input id="latest_version" name="latest_version" placeholder="1.1.0"
                 value="<?= e($app['latest_version']) ?>">
        </div>
      </div>
      <div class="field">
        <label for="download_url">Download link (APK)</label>
        <input id="download_url" name="download_url" type="url"
               placeholder="https://dhuuh.shop/DACAAM.apk"
               value="<?= e($app['download_url']) ?>">
        <div class="hint">Required before a minimum can be set — otherwise old phones have nowhere to go.</div>
      </div>
      <div class="field">
        <label for="message">Message shown with the update</label>
        <input id="message" name="message" maxlength="300"
               placeholder="Nooc cusub ayaa diyaar ah — fadlan cusboonaysii."
               value="<?= e($app['message']) ?>">
      </div>
      <button class="btn btn-primary">Save app version</button>
    </form>
    <p class="hint" style="margin-top:12px">
      Phones running an APK from before this feature do not check — hand them
      the new one once, and every update after that is announced here.
    </p>
  </div>

  <div class="card">
    <div class="card-head"><h2>Invoice details</h2></div>
    <p class="muted" style="margin-top:0">Who the subscription invoices say they are from.</p>
    <form method="post" action="<?= e(Response::url('/settings/invoice')) ?>">
      <?= Csrf::field() ?>
      <div class="field">
        <label for="business_name">Business name</label>
        <input id="business_name" name="business_name" maxlength="255"
               value="<?= e($issuer['invoice_business_name']) ?>">
      </div>
      <div class="field">
        <label for="business_address">Address</label>
        <input id="business_address" name="business_address" maxlength="255"
               value="<?= e($issuer['invoice_business_address']) ?>">
      </div>
      <div class="form-row">
        <div class="field">
          <label for="business_phone">Phone</label>
          <input id="business_phone" name="business_phone" maxlength="255"
                 value="<?= e($issuer['invoice_business_phone']) ?>">
        </div>
        <div class="field">
          <label for="business_email">Email</label>
          <input id="business_email" name="business_email" type="email" maxlength="255"
                 value="<?= e($issuer['invoice_business_email']) ?>">
        </div>
      </div>
      <div class="field">
        <label for="footer">Footer line</label>
        <input id="footer" name="footer" maxlength="255" value="<?= e($issuer['invoice_footer']) ?>">
      </div>
      <button class="btn btn-primary">Save invoice details</button>
    </form>
  </div>
</div>
