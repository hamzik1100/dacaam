<?php

declare(strict_types=1);

use DacaamAdmin\Core\Csrf;
use DacaamAdmin\Core\Response;

use function DacaamAdmin\Core\dateTime;
use function DacaamAdmin\Core\e;

/** @var array $sent @var array $restaurants @var array $staff @var bool $configured @var int $devices */

// Staff grouped by restaurant, so choosing a shop can narrow the person list
// without a second request.
$byRestaurant = [];
foreach ($staff as $member) {
    $byRestaurant[(int) $member['restaurant_id']][] = [
        'id'   => (int) $member['id'],
        'name' => (string) $member['name'],
    ];
}
?>
<div class="page-head">
  <div>
    <h1>Notifications</h1>
    <div class="page-sub">
      Messages to the restaurants running DACAAM. Everyone, one shop, or one person.
    </div>
  </div>
  <span class="chip <?= $configured ? 'chip-active' : 'chip-expired' ?>">
    <?= $configured ? 'push ready' : 'push not configured' ?>
  </span>
</div>

<div class="grid grid-2">
  <div class="card">
    <div class="card-head"><h2>Send a message</h2></div>

    <?php if (!$configured): ?>
      <p class="muted" style="margin-top:0">
        The Firebase key is missing, so nothing will arrive on a closed handset.
        Messages are still saved and appear when somebody opens the app.
      </p>
    <?php else: ?>
      <p class="muted" style="margin-top:0">
        <?= (int) $devices ?> handset<?= $devices === 1 ? '' : 's' ?> registered.
      </p>
    <?php endif; ?>

    <form method="post" action="<?= e(Response::url('/notifications')) ?>">
      <?= Csrf::field() ?>

      <label>Restaurant</label>
      <select name="restaurant_id" id="restaurant">
        <option value="">Everyone — all restaurants</option>
        <?php foreach ($restaurants as $r): ?>
          <option value="<?= (int) $r['id'] ?>"><?= e((string) $r['name']) ?></option>
        <?php endforeach; ?>
      </select>

      <label>Person</label>
      <select name="user_id" id="person">
        <option value="">Everyone in the restaurant</option>
      </select>

      <label>Kind</label>
      <select name="kind">
        <option value="info">Information</option>
        <option value="warning">Warning</option>
        <option value="urgent">Urgent</option>
      </select>

      <label>Title</label>
      <input type="text" name="title" maxlength="150" required
             placeholder="Lacag bixinta bisha">

      <label>Message</label>
      <textarea name="body" rows="4" maxlength="1000" required
                placeholder="Fadlan lacagta bisha bixi ka hor 25-ka."></textarea>

      <button type="submit" class="btn btn-primary" style="margin-top:1rem">Send</button>
    </form>
  </div>

  <div class="card">
    <div class="card-head"><h2>Sent</h2></div>

    <?php if ($sent === []): ?>
      <p class="muted">Nothing sent yet.</p>
    <?php else: ?>
      <table class="table">
        <thead>
          <tr><th>Message</th><th>To</th><th>Read</th><th>When</th></tr>
        </thead>
        <tbody>
          <?php foreach ($sent as $n): ?>
            <tr>
              <td>
                <strong><?= e((string) $n['title']) ?></strong>
                <div class="muted"><?= e((string) $n['body']) ?></div>
              </td>
              <td>
                <?php if ($n['user_name'] !== null): ?>
                  <?= e((string) $n['user_name']) ?>
                <?php elseif ($n['restaurant_name'] !== null): ?>
                  <?= e((string) $n['restaurant_name']) ?>
                <?php else: ?>
                  <span class="muted">Everyone</span>
                <?php endif; ?>
              </td>
              <td><?= (int) $n['reads'] ?></td>
              <td class="muted"><?= e(dateTime($n['created_at'])) ?></td>
            </tr>
          <?php endforeach; ?>
        </tbody>
      </table>
    <?php endif; ?>
  </div>
</div>

<script>
  // Choosing a restaurant narrows the person list. Held inline rather than
  // fetched, because the whole staff list is a few hundred names at most and a
  // request per keystroke is worse than the bytes.
  const staffByRestaurant = <?= json_encode($byRestaurant, JSON_THROW_ON_ERROR) ?>;

  document.getElementById('restaurant').addEventListener('change', function () {
    const person = document.getElementById('person');
    const members = staffByRestaurant[this.value] || [];

    person.innerHTML = '<option value="">Everyone in the restaurant</option>';

    for (const member of members) {
      const option = document.createElement('option');
      option.value = member.id;
      option.textContent = member.name;
      person.appendChild(option);
    }
  });
</script>
