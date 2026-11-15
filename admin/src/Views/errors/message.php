<?php

declare(strict_types=1);

use DacaamAdmin\Core\Response;

use function DacaamAdmin\Core\e;

/** @var string $heading @var string $message */
?>
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title><?= e($heading) ?> · DACAAM Platform</title>
<link rel="stylesheet" href="<?= e(Response::url('/assets/app.css')) ?>">
</head>
<body>
<div class="login-wrap">
  <div class="login-card" style="text-align:center">
    <div class="brand-mark" style="margin:0 auto 16px">🍔</div>
    <h1 style="margin:0 0 6px"><?= e($heading) ?></h1>
    <p class="muted" style="font-size:14px"><?= e($message) ?></p>
    <a class="btn btn-primary" href="<?= e(Response::url('/')) ?>">Back to the dashboard</a>
  </div>
</div>
</body>
</html>
