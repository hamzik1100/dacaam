<?php

declare(strict_types=1);

use DacaamAdmin\Core\Access;
use DacaamAdmin\Core\Csrf;
use DacaamAdmin\Core\Response;

use function DacaamAdmin\Core\e;

/** @var string $title @var string $content @var array $admin @var ?array $flash @var string $nav */
$nav ??= '';
// The last column is the ability the page needs (Access); null is every role.
// A link that only ever answers 403 is not worth showing.
$items = array_filter(
    [
        ['dashboard',     '/',              '◈', 'Dashboard',      null],
        ['restaurants',   '/restaurants',   '🏪', 'Restaurants',    null],
        ['subscriptions', '/subscriptions', '◷', 'Subscriptions',  null],
        ['plans',         '/plans',         '◆', 'Plans',          null],
        ['notifications', '/notifications', '✉', 'Notifications',  'notifications'],
        ['reports',       '/reports',       '▤', 'Global reports', null],
        ['audit',         '/audit',         '⧗', 'Platform audit', 'audit'],
        ['tills',         '/tills',         '▦', 'Tills',          'operations'],
        ['health',        '/health',        '◉', 'Health',         'operations'],
        ['backups',       '/backups',       '⛁', 'Backups',        'backups'],
        ['admins',        '/admins',        '☗', 'Administrators', 'admins'],
        ['security',      '/security',      '⚿', 'Security',       null],
        ['settings',      '/settings',      '⚙', 'Settings',       'settings'],
    ],
    static fn (array $item): bool => $item[4] === null || Access::allows($admin ?? null, $item[4]),
);
?>
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title><?= e($title) ?> · DACAAM Platform</title>
<link rel="stylesheet" href="<?= e(Response::url('/assets/app.css')) ?>">
</head>
<body>
<div class="shell">
  <aside class="sidebar">
    <div class="brand">
      <div class="brand-mark">🍔</div>
      <div>
        <div class="brand-name">DACAAM</div>
        <div class="brand-sub">Platform</div>
      </div>
    </div>

    <?php foreach ($items as [$key, $href, $icon, $label, $ability]): ?>
      <a class="nav-link <?= $nav === $key ? 'active' : '' ?>"
         href="<?= e(Response::url($href)) ?>">
        <span class="nav-icon"><?= $icon ?></span><span class="nav-label"><?= e($label) ?></span>
      </a>
    <?php endforeach; ?>

    <div class="sidebar-foot">
      <div class="who"><?= e($admin['name'] ?? '') ?></div>
      <div class="who-sub"><?= e($admin['email'] ?? '') ?></div>
      <?php if ($admin !== null): ?>
        <div class="who-sub"><?= e(Access::ROLES[Access::role($admin)]) ?></div>
      <?php endif; ?>
      <form method="post" action="<?= e(Response::url('/logout')) ?>">
        <?= Csrf::field() ?>
        <button class="btn btn-sm">Sign out</button>
      </form>
    </div>
  </aside>

  <main class="main">
    <?php if ($flash !== null): ?>
      <div class="flash flash-<?= e($flash['type']) ?>"><?= e($flash['message']) ?></div>
    <?php endif; ?>
    <?= $content ?>
  </main>
</div>
</body>
</html>
