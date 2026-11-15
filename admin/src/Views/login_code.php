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

    <form class="card" method="post" action="<?= e(Response::url('/login/code')) ?>">
      <?= Csrf::field() ?>

      <p class="muted" style="margin-top:0">
        The password was right. Open your authenticator and type the six digits
        it is showing.
      </p>

      <div class="field">
        <label for="code">Code</label>
        <input id="code" name="code" type="text"
               inputmode="numeric" autocomplete="one-time-code"
               required autofocus placeholder="000000"
               style="letter-spacing:6px;font-size:20px;text-align:center">
      </div>

      <button class="btn btn-primary" style="width:100%">Continue</button>
    </form>

    <p class="muted" style="text-align:center;margin-top:18px;font-size:12px">
      Lost the phone? One of your recovery codes goes in the same box. Each one
      works once.
    </p>

    <p style="text-align:center;margin-top:10px">
      <a href="<?= e(Response::url('/login')) ?>" class="muted" style="font-size:12px">
        Start again
      </a>
    </p>
  </div>
</div>
</body>
</html>
