<?php

declare(strict_types=1);

use DacaamAdmin\Core\Response;

use function DacaamAdmin\Core\e;
use function DacaamAdmin\Core\money;
use function DacaamAdmin\Core\shortDate;

/**
 * A page of its own rather than inside the dashboard layout: it is meant to be
 * printed or saved as PDF, and a sidebar on the printout is noise. The
 * dashboard ships no JavaScript, so there is no print button — Ctrl+P does it,
 * and the print styles below leave only the invoice on the paper.
 *
 * @var array  $payment
 * @var array  $restaurant
 * @var ?array $subscription
 * @var string $number
 * @var array  $issuer
 */
$plan = (string) ($payment['plan'] ?? '') !== ''
    ? (string) $payment['plan']
    : (string) ($subscription['plan'] ?? '');
$methods = ['cash' => 'Cash', 'zaad' => 'ZAAD', 'edahab' => 'eDahab', 'bank' => 'Bank transfer'];
?>
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Invoice <?= e($number) ?> · <?= e($restaurant['name']) ?></title>
<style>
  :root { --text: #0F172A; --sub: #64748B; --line: #E2E8F0; --accent: #F97316; }
  * { box-sizing: border-box; }
  body {
    margin: 0; background: #F1F5F9; color: var(--text);
    font: 14px/1.5 system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
  }
  .bar {
    max-width: 780px; margin: 24px auto 0; padding: 0 16px;
    display: flex; justify-content: space-between; align-items: center; gap: 12px;
    color: var(--sub); font-size: 13px;
  }
  .bar a { color: var(--accent); text-decoration: none; font-weight: 600; }
  .sheet {
    max-width: 780px; margin: 12px auto 40px; background: #fff; padding: 48px;
    border-radius: 16px; box-shadow: 0 8px 18px -6px rgba(15, 23, 42, .08);
  }
  .top { display: flex; justify-content: space-between; gap: 24px; flex-wrap: wrap; }
  .issuer-name { font-size: 22px; font-weight: 800; color: var(--accent); }
  .muted { color: var(--sub); }
  .mono { font-family: ui-monospace, SFMono-Regular, Consolas, monospace; }
  h1 { margin: 0; font-size: 28px; letter-spacing: .04em; text-align: right; }
  .paid {
    display: inline-block; margin-top: 6px; padding: 2px 12px; border-radius: 999px;
    background: #D1FAE5; color: #065F46; font-weight: 700; font-size: 12px; letter-spacing: .08em;
  }
  .meta { text-align: right; }
  .billed { margin: 36px 0 24px; }
  .label { font-size: 11px; text-transform: uppercase; letter-spacing: .08em; color: var(--sub); }
  table { width: 100%; border-collapse: collapse; margin-top: 8px; }
  th, td { padding: 12px 8px; border-bottom: 1px solid var(--line); text-align: left; vertical-align: top; }
  th { font-size: 11px; text-transform: uppercase; letter-spacing: .08em; color: var(--sub); }
  .num { text-align: right; white-space: nowrap; }
  .total td { border-bottom: 0; font-size: 18px; font-weight: 800; }
  .foot { margin-top: 36px; padding-top: 16px; border-top: 1px solid var(--line); }
  @media (max-width: 640px) {
    .sheet { padding: 24px 16px; border-radius: 0; }
    h1, .meta { text-align: left; }
  }
  @media print {
    body { background: #fff; }
    .bar { display: none; }
    .sheet { box-shadow: none; margin: 0; max-width: none; padding: 0; }
  }
</style>
</head>
<body>
<div class="bar">
  <a href="<?= e(Response::url('/restaurants/' . $restaurant['id'])) ?>">← <?= e($restaurant['name']) ?></a>
  <span>Press Ctrl+P to print or save as PDF</span>
</div>

<div class="sheet">
  <div class="top">
    <div>
      <div class="issuer-name"><?= e($issuer['invoice_business_name']) ?></div>
      <?php foreach (['invoice_business_address', 'invoice_business_phone', 'invoice_business_email'] as $k): ?>
        <?php if ($issuer[$k] !== ''): ?>
          <div class="muted"><?= e($issuer[$k]) ?></div>
        <?php endif; ?>
      <?php endforeach; ?>
    </div>
    <div class="meta">
      <h1>INVOICE</h1>
      <div class="mono"><strong><?= e($number) ?></strong></div>
      <div class="muted">Date: <?= shortDate($payment['paid_on']) ?></div>
      <div class="paid">PAID</div>
    </div>
  </div>

  <div class="billed">
    <div class="label">Billed to</div>
    <div><strong><?= e($restaurant['name']) ?></strong> <span class="muted">(<?= e($restaurant['slug']) ?>)</span></div>
    <?php if ((string) $restaurant['address'] !== ''): ?>
      <div class="muted"><?= e($restaurant['address']) ?></div>
    <?php endif; ?>
    <?php if ((string) $restaurant['phone'] !== ''): ?>
      <div class="muted"><?= e($restaurant['phone']) ?></div>
    <?php endif; ?>
  </div>

  <table>
    <thead>
      <tr><th>Description</th><th>Period</th><th class="num">Amount</th></tr>
    </thead>
    <tbody>
      <tr>
        <td>
          DACAAM subscription<?= $plan !== '' ? ' — ' . e(ucfirst($plan)) . ' plan' : '' ?>
          <?php if ($payment['months'] !== null): ?>
            <div class="muted"><?= (int) $payment['months'] ?> month(s)</div>
          <?php endif; ?>
        </td>
        <td>
          <?php if ($payment['period_start'] !== null && $payment['period_end'] !== null): ?>
            <?= shortDate($payment['period_start']) ?> – <?= shortDate($payment['period_end']) ?>
          <?php else: ?>
            <span class="muted">—</span>
          <?php endif; ?>
        </td>
        <td class="num"><?= money($payment['amount']) ?></td>
      </tr>
      <tr class="total">
        <td colspan="2">Total paid</td>
        <td class="num"><?= money($payment['amount']) ?></td>
      </tr>
    </tbody>
  </table>

  <p class="muted" style="margin-top:20px">
    Paid by <?= e($methods[(string) $payment['method']] ?? (string) $payment['method']) ?>
    <?php if ((string) $payment['reference'] !== ''): ?>
      — reference <strong><?= e($payment['reference']) ?></strong>
    <?php endif; ?>
  </p>

  <div class="foot muted"><?= e($issuer['invoice_footer']) ?></div>
</div>
</body>
</html>
