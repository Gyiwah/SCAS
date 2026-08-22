<?php
/** SCAS - in-app notifications raised by procedures and triggers. */
declare(strict_types=1);

$db = Database::get();

if ($_SERVER['REQUEST_METHOD'] === 'POST' && strParam('action', '', 20) === 'mark_read') {
    // This is the single narrow column-level UPDATE the application account
    // holds anywhere in the schema: GRANT UPDATE (is_read) ON notification.
    $db->exec('UPDATE notification SET is_read = 1 WHERE user_id = ?', [Auth::userId()]);
    Flash::add('success', 'All notifications marked as read.');
    header('Location: ' . url('notifications'));
    exit;
}

$rows = $db->all(
    'SELECT notification_id, title, message, notif_type, is_read, created_at
     FROM notification WHERE user_id = ? ORDER BY created_at DESC LIMIT 100',
    [Auth::userId()],
    'notifications'
);

$pageTitle = 'Notifications';
$pageDesc  = 'Raised automatically when your attendance is recorded or your leave is actioned.';

require __DIR__ . '/../includes/header.php';
?>
<div class="card">
  <h2>Recent <span class="sub"><?= count($rows) ?> shown</span></h2>
  <?php if (!$rows): ?>
    <div class="empty"><strong>Nothing yet</strong>Notifications appear here as they are raised.</div>
  <?php else: ?>
  <div class="card-body no-print">
    <form method="post">
      <?= Auth::csrfField() ?>
      <input type="hidden" name="action" value="mark_read">
      <button class="btn secondary small" type="submit">Mark all as read</button>
    </form>
  </div>
  <div class="table-scroll">
    <table class="data">
      <thead><tr><th>When</th><th>Title</th><th>Message</th><th>Type</th></tr></thead>
      <tbody>
      <?php foreach ($rows as $n): ?>
        <tr<?= $n['is_read'] ? '' : ' style="font-weight:600"' ?>>
          <td><?= fmtDateTime($n['created_at']) ?></td>
          <td><?= e($n['title']) ?></td>
          <td><?= e($n['message']) ?></td>
          <td><span class="badge <?= match ($n['notif_type']) {
                'SUCCESS' => 'ok', 'WARNING' => 'warn', 'ALERT' => 'bad', default => 'info' } ?>">
            <?= e($n['notif_type']) ?></span></td>
        </tr>
      <?php endforeach; ?>
      </tbody>
    </table>
  </div>
  <?php endif; ?>
</div>
<?php require __DIR__ . '/../includes/footer.php'; ?>
