<?php
/**
 * SCAS - security monitoring.
 * Sign-in telemetry, lockouts, refused privilege escalations and blocked
 * QR-code replays, all recorded by the database rather than by this page.
 */
declare(strict_types=1);

$db = Database::get();

if ($_SERVER['REQUEST_METHOD'] === 'POST' && strParam('action', '', 20) === 'unlock') {
    try {
        $db->callProc('sp_unlock_account', [intParam('user_id'), Auth::userId()]);
        Flash::add('success', 'Account unlocked.');
    } catch (DatabaseException $ex) {
        Flash::add('danger', $ex->getMessage());
    }
    header('Location: ' . url('security'));
    exit;
}

$hours = intParam('hours', 24, 1, 720);
$type  = strParam('type', '', 30);

$sql  = 'SELECT event_id, event_type, username_attempted, user_id, ip_address,
                detail, severity, occurred_at
         FROM security_event
         WHERE occurred_at >= NOW() - INTERVAL ? HOUR';
$args = [$hours];
if ($type !== '') { $sql .= ' AND event_type = ?'; $args[] = $type; }
$sql .= ' ORDER BY occurred_at DESC LIMIT 300';

$events = $db->all($sql, $args, 'security: events');

$summary = $db->all(
    'SELECT event_type, severity, COUNT(*) AS occurrences, MAX(occurred_at) AS latest
     FROM security_event WHERE occurred_at >= NOW() - INTERVAL ? HOUR
     GROUP BY event_type, severity ORDER BY occurrences DESC',
    [$hours],
    'security: summary'
);

$dashboard = $db->all(
    'SELECT * FROM v_security_dashboard ORDER BY failed_24h DESC, username LIMIT 40',
    [],
    'security: dashboard'
);

$locked = $db->all(
    'SELECT user_id, full_name, username, locked_until, failed_login_attempts
     FROM app_user WHERE locked_until IS NOT NULL AND locked_until > NOW()
     ORDER BY locked_until DESC',
    [],
    'security: locked accounts'
);

$critical = 0;
foreach ($summary as $s) {
    if ($s['severity'] === 'CRITICAL') { $critical += (int) $s['occurrences']; }
}

$pageTitle = 'Security';
$pageDesc  = 'Authentication and authorisation telemetry for the last ' . $hours . ' hours.';

require __DIR__ . '/../includes/header.php';
?>

<div class="grid grid-4" style="margin-bottom:20px">
  <div class="tile"><div class="label">Events recorded</div>
    <div class="value"><?= count($events) ?></div><div class="foot">last <?= $hours ?>h, capped at 300</div></div>
  <div class="tile <?= $critical > 0 ? 'bad' : 'ok' ?>"><div class="label">Critical events</div>
    <div class="value"><?= $critical ?></div><div class="foot">lockouts and refused escalations</div></div>
  <div class="tile <?= count($locked) > 0 ? 'warn' : 'ok' ?>"><div class="label">Locked accounts</div>
    <div class="value"><?= count($locked) ?></div><div class="foot">currently unable to sign in</div></div>
  <div class="tile"><div class="label">Lockout policy</div>
    <div class="value"><?= e((string) $db->scalar("SELECT fn_get_setting('security.max_failed_logins')")) ?></div>
    <div class="foot">failures, then
      <?= e((string) $db->scalar("SELECT fn_get_setting('security.lockout_minutes')")) ?> minutes locked</div></div>
</div>

<?php if ($locked): ?>
<div class="card">
  <h2 style="color:var(--bad)">Locked accounts</h2>
  <div class="table-scroll">
    <table class="data">
      <thead><tr><th>Name</th><th>Username</th><th>Failed attempts</th><th>Locked until</th><th class="no-print"></th></tr></thead>
      <tbody>
      <?php foreach ($locked as $l): ?>
        <tr>
          <td><strong><?= e($l['full_name']) ?></strong></td>
          <td class="mono"><?= e($l['username']) ?></td>
          <td><?= (int) $l['failed_login_attempts'] ?></td>
          <td><?= fmtDateTime($l['locked_until']) ?></td>
          <td class="no-print">
            <form method="post" style="display:inline">
              <?= Auth::csrfField() ?>
              <input type="hidden" name="action" value="unlock">
              <input type="hidden" name="user_id" value="<?= (int) $l['user_id'] ?>">
              <button class="btn small" type="submit">Unlock</button>
            </form>
          </td>
        </tr>
      <?php endforeach; ?>
      </tbody>
    </table>
  </div>
</div>
<?php endif; ?>

<div class="grid grid-2">
  <div class="card">
    <h2>Event summary</h2>
    <?php if (!$summary): ?><div class="empty">No events in this window.</div><?php else: ?>
    <div class="table-scroll">
      <table class="data">
        <thead><tr><th>Event</th><th>Severity</th><th class="num">Count</th><th>Latest</th></tr></thead>
        <tbody>
        <?php foreach ($summary as $s): ?>
          <tr>
            <td class="mono"><?= e($s['event_type']) ?></td>
            <td><span class="badge <?= match ($s['severity']) {
                'CRITICAL' => 'bad', 'WARNING' => 'warn', default => 'muted' } ?>">
              <?= e($s['severity']) ?></span></td>
            <td class="num"><?= (int) $s['occurrences'] ?></td>
            <td><span class="sub"><?= fmtDateTime($s['latest']) ?></span></td>
          </tr>
        <?php endforeach; ?>
        </tbody>
      </table>
    </div>
    <?php endif; ?>
  </div>

  <div class="card">
    <h2>Accounts by sign-in activity <span class="sub">last 24 hours</span></h2>
    <?php if (!$dashboard): ?><div class="empty">No sign-in activity.</div><?php else: ?>
    <div class="table-scroll">
      <table class="data">
        <thead><tr><th>Username</th><th>Name</th><th class="num">Failed</th><th class="num">Success</th><th>State</th></tr></thead>
        <tbody>
        <?php foreach ($dashboard as $d): ?>
          <tr>
            <td class="mono"><?= e($d['username']) ?></td>
            <td><?= e($d['full_name'] ?? '<unknown account>') ?></td>
            <td class="num"><?= (int) $d['failed_24h'] ?: '' ?></td>
            <td class="num"><?= (int) $d['success_24h'] ?: '' ?></td>
            <td><span class="badge <?= $d['account_state'] === 'LOCKED' ? 'bad' : 'ok' ?>">
              <?= e($d['account_state'] ?? 'OPEN') ?></span></td>
          </tr>
        <?php endforeach; ?>
        </tbody>
      </table>
    </div>
    <?php endif; ?>
  </div>
</div>

<div class="card">
  <form method="get" class="filters no-print">
    <input type="hidden" name="page" value="security">
    <div class="field"><label for="hours">Window (hours)</label>
      <input type="number" id="hours" name="hours" value="<?= $hours ?>" min="1" max="720"></div>
    <div class="field"><label for="type">Event type</label>
      <select id="type" name="type">
        <option value="">All</option>
        <?php foreach (['LOGIN_SUCCESS','LOGIN_FAILED','ACCOUNT_LOCKED','ACCOUNT_UNLOCKED',
                        'PASSWORD_CHANGED','PRIVILEGE_DENIED','QR_REPLAY_BLOCKED',
                        'QR_EXPIRED_BLOCKED','USER_CREATED','USER_DEACTIVATED'] as $t): ?>
          <option value="<?= $t ?>" <?= $type === $t ? 'selected' : '' ?>><?= $t ?></option>
        <?php endforeach; ?>
      </select></div>
    <button class="btn secondary" type="submit">Apply</button>
  </form>

  <?php if (!$events): ?>
    <div class="empty"><strong>No events</strong>Nothing was recorded in this window.</div>
  <?php else: ?>
  <div class="table-scroll">
    <table class="data">
      <thead><tr><th>When</th><th>Event</th><th>Username</th><th>IP</th><th>Detail</th><th>Severity</th></tr></thead>
      <tbody>
      <?php foreach ($events as $ev): ?>
        <tr>
          <td style="white-space:nowrap"><?= fmtDateTime($ev['occurred_at']) ?></td>
          <td class="mono"><?= e($ev['event_type']) ?></td>
          <td class="mono"><?= e($ev['username_attempted'] ?? '-') ?></td>
          <td class="mono"><?= e($ev['ip_address'] ?? '-') ?></td>
          <td><?= e($ev['detail']) ?></td>
          <td><span class="badge <?= match ($ev['severity']) {
              'CRITICAL' => 'bad', 'WARNING' => 'warn', default => 'muted' } ?>">
            <?= e($ev['severity']) ?></span></td>
        </tr>
      <?php endforeach; ?>
      </tbody>
    </table>
  </div>
  <?php endif; ?>
</div>

<?php require __DIR__ . '/../includes/footer.php'; ?>
