<?php
/**
 * SCAS - audit trail viewer.
 *
 * The trail is written by triggers, so it captures every writer, not only
 * this application. There is deliberately no way to edit or delete an entry
 * from here: the application account holds no INSERT, UPDATE or DELETE on
 * audit_log at all, and neither does the auditor role.
 */
declare(strict_types=1);

$db = Database::get();

$table  = strParam('table', '', 64);
$action = strParam('action_type', '', 10);
$from   = dateParam('from', date('Y-m-d', strtotime('-7 days')));
$to     = dateParam('to', date('Y-m-d'));
$record = strParam('record', '', 40);

$sql  = 'SELECT audit_id, changed_at, table_name, record_id, action,
                changed_by_name, db_user, client_host, old_values, new_values
         FROM v_audit_trail
         WHERE changed_at >= ? AND changed_at < ? + INTERVAL 1 DAY';
$args = [$from, $to];

if ($table !== '')  { $sql .= ' AND table_name = ?'; $args[] = $table; }
if ($action !== '') { $sql .= ' AND action = ?';     $args[] = $action; }
if ($record !== '') { $sql .= ' AND record_id = ?';  $args[] = $record; }

$sql .= ' ORDER BY changed_at DESC LIMIT 300';

$rows = $db->all($sql, $args, 'audit: trail');

$byTable = $db->all(
    'SELECT table_name, action, COUNT(*) AS entries
     FROM audit_log
     WHERE changed_at >= ? AND changed_at < ? + INTERVAL 1 DAY
     GROUP BY table_name, action ORDER BY entries DESC',
    [$from, $to],
    'audit: summary'
);

$tables = $db->all('SELECT DISTINCT table_name FROM audit_log ORDER BY table_name');

$pageTitle = 'Audit trail';
$pageDesc  = 'Who changed what, and when. Written by database triggers, so connecting outside this application does not avoid it.';

require __DIR__ . '/../includes/header.php';
?>

<div class="card">
  <form method="get" class="filters no-print">
    <input type="hidden" name="page" value="audit">
    <div class="field"><label for="table">Table</label>
      <select id="table" name="table">
        <option value="">All tables</option>
        <?php foreach ($tables as $t): ?>
          <option value="<?= e($t['table_name']) ?>" <?= $table === $t['table_name'] ? 'selected' : '' ?>>
            <?= e($t['table_name']) ?></option>
        <?php endforeach; ?>
      </select></div>
    <div class="field"><label for="action_type">Action</label>
      <select id="action_type" name="action_type">
        <option value="">All</option>
        <?php foreach (['INSERT','UPDATE','DELETE'] as $a): ?>
          <option value="<?= $a ?>" <?= $action === $a ? 'selected' : '' ?>><?= $a ?></option>
        <?php endforeach; ?>
      </select></div>
    <div class="field"><label for="record">Record id</label>
      <input type="text" id="record" name="record" value="<?= e($record) ?>" maxlength="40" placeholder="any"></div>
    <div class="field"><label for="from">From</label><input type="date" id="from" name="from" value="<?= e($from) ?>"></div>
    <div class="field"><label for="to">To</label><input type="date" id="to" name="to" value="<?= e($to) ?>"></div>
    <button class="btn secondary" type="submit">Apply</button>
  </form>
</div>

<div class="card">
  <h2>Activity by table <span class="sub"><?= e(fmtDate($from)) ?> to <?= e(fmtDate($to)) ?></span></h2>
  <?php if (!$byTable): ?>
    <div class="empty">No audit entries in this range.</div>
  <?php else: ?>
  <div class="table-scroll">
    <table class="data">
      <thead><tr><th>Table</th><th>Action</th><th class="num">Entries</th></tr></thead>
      <tbody>
      <?php foreach ($byTable as $b): ?>
        <tr>
          <td class="mono"><?= e($b['table_name']) ?></td>
          <td><span class="badge <?= match ($b['action']) {
              'INSERT' => 'ok', 'UPDATE' => 'warn', 'DELETE' => 'bad', default => 'muted' } ?>">
            <?= e($b['action']) ?></span></td>
          <td class="num"><?= (int) $b['entries'] ?></td>
        </tr>
      <?php endforeach; ?>
      </tbody>
    </table>
  </div>
  <?php endif; ?>
</div>

<div class="card">
  <h2>Entries <span class="sub">newest first, most recent 300</span></h2>
  <?php if (!$rows): ?>
    <div class="empty"><strong>Nothing recorded</strong>No changes match these filters.</div>
  <?php else: ?>
  <div class="table-scroll">
    <table class="data">
      <thead><tr>
        <th>When</th><th>Table</th><th>Record</th><th>Action</th>
        <th>Changed by</th><th>DB account</th><th>Before</th><th>After</th>
      </tr></thead>
      <tbody>
      <?php foreach ($rows as $r): ?>
        <tr>
          <td style="white-space:nowrap"><?= fmtDateTime($r['changed_at']) ?></td>
          <td class="mono"><?= e($r['table_name']) ?></td>
          <td class="mono"><?= e($r['record_id']) ?></td>
          <td><span class="badge <?= match ($r['action']) {
              'INSERT' => 'ok', 'UPDATE' => 'warn', 'DELETE' => 'bad', default => 'muted' } ?>">
            <?= e($r['action']) ?></span></td>
          <td><?= e($r['changed_by_name']) ?></td>
          <td><span class="sub"><?= e($r['db_user']) ?></span></td>
          <td class="mono" style="max-width:260px;word-break:break-all"><?= e($r['old_values']) ?></td>
          <td class="mono" style="max-width:260px;word-break:break-all"><?= e($r['new_values']) ?></td>
        </tr>
      <?php endforeach; ?>
      </tbody>
    </table>
  </div>
  <?php endif; ?>
</div>

<div class="note">
  Password hashes are never written to this trail. A change of password is
  recorded as <code class="inline">"password_changed": true</code> and the
  value itself as <code class="inline">[redacted]</code>, so the audit table
  cannot become a second, less-protected credential store.
</div>

<?php require __DIR__ . '/../includes/footer.php'; ?>
