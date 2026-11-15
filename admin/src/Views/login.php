<?php

declare(strict_types=1);

use DacaamAdmin\Core\Csrf;
use DacaamAdmin\Core\Response;

use function DacaamAdmin\Core\e;

/** @var ?array $flash */
?>
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Sign in · DACAAM Platform</title>
<link rel="stylesheet" href="<?= e(Response::url('/assets/app.css')) ?>">
</head>
<body>
<div class="login-wrap">
  <div class="login-card">
    <div class="login-brand">
      <div class="brand-mark">🍔</div>
      <h1>DACAAM</h1>
      <div class="muted">Platform administration</div>
    </div>

    <?php if ($flash !== null): ?>
      <div class="flash flash-<?= e($flash['type']) ?>"><?= e($flash['message']) ?></div>
    <?php endif; ?>

    <form class="card" method="post" action="<?= e(Response::url('/login')) ?>">
      <?= Csrf::field() ?>
      <div class="field">
        <label for="email">Email</label>
        <input id="email" name="email" type="email" autocomplete="username"
               required autofocus placeholder="super@dacaam.test">
      </div>
      <div class="field">
        <label for="password">Password</label>
        <input id="password" name="password" type="password"
               autocomplete="current-password" required placeholder="••••••••">
      </div>
      <button class="btn btn-primary" style="width:100%">Sign in</button>
    </form>

    <p class="muted" style="text-align:center;margin-top:18px">
      This is the platform dashboard. Restaurant staff sign in from the app.
    </p>
  </div>
</div>
</body>
</html>
