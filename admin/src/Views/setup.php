<?php

declare(strict_types=1);

use DacaamAdmin\Core\Csrf;
use DacaamAdmin\Core\Response;

use function DacaamAdmin\Core\e;

/** @var ?array $flash @var int $min */
?>
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Set up · DACAAM Platform</title>
<link rel="stylesheet" href="<?= e(Response::url('/assets/app.css')) ?>">
</head>
<body>
<div class="login-wrap">
  <div class="login-card">
    <div class="login-brand">
      <div class="brand-mark">🍔</div>
      <h1>DACAAM</h1>
      <div class="muted">First-run setup</div>
    </div>

    <?php if ($flash !== null): ?>
      <div class="flash flash-<?= e($flash['type']) ?>"><?= e($flash['message']) ?></div>
    <?php endif; ?>

    <form class="card" method="post" action="<?= e(Response::url('/setup')) ?>">
      <?= Csrf::field() ?>

      <p class="muted" style="margin-top:0">
        There is no platform administrator yet. This page creates the first one
        and then closes for good.
      </p>

      <div class="field">
        <label for="name">Your name</label>
        <input id="name" name="name" required autofocus placeholder="Axmed Xasan">
      </div>

      <div class="field">
        <label for="email">Email</label>
        <input id="email" name="email" type="email" required
               autocomplete="username" placeholder="you@yourdomain.com">
        <div class="hint">You sign in with this. It is not sent anywhere.</div>
      </div>

      <div class="field">
        <label for="password">Password</label>
        <input id="password" name="password" type="password" required
               minlength="<?= (int) $min ?>" autocomplete="new-password">
        <div class="hint">
          At least <?= (int) $min ?> characters. This account can reach every
          restaurant on the platform — give it a password you use nowhere else.
        </div>
      </div>

      <div class="field">
        <label for="confirm_password">Repeat password</label>
        <input id="confirm_password" name="confirm_password" type="password"
               required minlength="<?= (int) $min ?>" autocomplete="new-password">
      </div>

      <button class="btn btn-primary" style="width:100%">Create administrator</button>
    </form>

    <p class="muted" style="text-align:center;margin-top:18px">
      Restaurant staff sign in from the app, not here.
    </p>
  </div>
</div>
</body>
</html>
