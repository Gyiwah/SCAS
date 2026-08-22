<?php
/**
 * SCAS - database administration console.
 *
 * This page exists so the advanced DBMS work can be inspected from inside the
 * application instead of only from the mysql client: query plans, index
 * cardinalities, integrity rules, live locks, the recovery position and the
 * temporal history of configuration.
 *
 * The EXPLAIN runner accepts only a single SELECT. It runs EXPLAIN, never the
 * statement itself, and it runs as scas_app - the same least-privileged
 * account as the rest of the application, so it cannot reach anything the
 * application could not already reach.
 */
declare(strict_types=1);

$db  = Database::get();
$tab = strParam('tab', 'overview', 20);

$tabs = [
    'overview'     => 'Overview',
    'plans'        => 'Query plans',
    'indexes'      => 'Indexes',
    'integrity'    => 'Integrity',
    'transactions' => 'Transactions',
    'recovery'     => 'Recovery',
    'performance'  => 'Slow queries',
];
if (!isset($tabs[$tab])) {
    $tab = 'overview';
}

// ---- actions -------------------------------------------------------------
$explainRows = [];
$explainError = '';
$userSql = '';
$demoOutput = [];

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $action = strParam('action', '', 30);

    if ($action === 'explain') {
        $userSql = trim((string) ($_POST['sql'] ?? ''));
        $tab = 'plans';

        // Only a single SELECT. Rejecting anything else keeps this a
        // diagnostic tool rather than a general SQL console.
        if (!preg_match('/^\s*(SELECT|WITH)\b/i', $userSql)) {
            $explainError = 'Only SELECT (or WITH ... SELECT) statements can be explained here.';
        } elseif (str_contains($userSql, ';')) {
            $explainError = 'Remove the semicolon: only one statement at a time.';
        } else {
            try {
                $explainRows = $db->explain($userSql);
            } catch (Throwable $ex) {
                $explainError = $ex->getMessage();
            }
        }
    } elseif ($action === 'demo_savepoint') {
        $tab = 'transactions';
        try { $demoOutput = $db->callProcRows('sp_demo_savepoint'); }
        catch (Throwable $ex) { Flash::add('danger', $ex->getMessage()); }
    } elseif ($action === 'demo_consistency') {
        $tab = 'transactions';
        try { $demoOutput = $db->callProcRows('sp_demo_consistency'); }
        catch (Throwable $ex) { Flash::add('danger', $ex->getMessage()); }
    } elseif ($action === 'restore_setting') {
        try {
            $db->callProc('sp_restore_setting_as_of',
                [strParam('setting_key', '', 60), strParam('as_of', '', 30)]);
            Flash::add('success', 'Setting restored from the temporal history.');
        } catch (DatabaseException $ex) {
            Flash::add('danger', $ex->getMessage());
        }
        header('Location: ' . url('dba', ['tab' => 'recovery']));
        exit;
    }
}

$pageTitle = 'DBA console';
$pageDesc  = 'Query plans, indexes, integrity, transactions and recovery, inspected through the least-privileged application account.';

require __DIR__ . '/../includes/header.php';
?>

<div class="card no-print">
  <div style="display:flex;flex-wrap:wrap;gap:2px;padding:0 8px">
    <?php foreach ($tabs as $key => $label): ?>
      <a href="<?= e(url('dba', ['tab' => $key])) ?>"
         style="padding:12px 14px;font-size:14px;border-bottom:3px solid <?= $tab === $key ? 'var(--brand)' : 'transparent' ?>;
                color:<?= $tab === $key ? 'var(--brand)' : 'var(--text-muted)' ?>;font-weight:<?= $tab === $key ? '600' : '400' ?>">
        <?= e($label) ?>
      </a>
    <?php endforeach; ?>
  </div>
</div>

<?php if ($tab === 'overview'):
    $objects = $db->all(
        "SELECT 'tables' AS object_type, COUNT(*) AS count FROM information_schema.TABLES
          WHERE TABLE_SCHEMA = 'scas_db' AND TABLE_TYPE <> 'VIEW'
         UNION ALL SELECT 'views',      COUNT(*) FROM information_schema.VIEWS    WHERE TABLE_SCHEMA = 'scas_db'
         UNION ALL SELECT 'procedures', COUNT(*) FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA = 'scas_db' AND ROUTINE_TYPE = 'PROCEDURE'
         UNION ALL SELECT 'functions',  COUNT(*) FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA = 'scas_db' AND ROUTINE_TYPE = 'FUNCTION'
         UNION ALL SELECT 'triggers',   COUNT(*) FROM information_schema.TRIGGERS WHERE TRIGGER_SCHEMA = 'scas_db'
         UNION ALL SELECT 'events',     COUNT(*) FROM information_schema.EVENTS   WHERE EVENT_SCHEMA = 'scas_db'
         UNION ALL SELECT 'indexes',    COUNT(DISTINCT TABLE_NAME, INDEX_NAME) FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = 'scas_db'
         UNION ALL SELECT 'foreign keys', COUNT(*) FROM information_schema.TABLE_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = 'scas_db' AND CONSTRAINT_TYPE = 'FOREIGN KEY'
         UNION ALL SELECT 'check constraints', COUNT(*) FROM information_schema.CHECK_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = 'scas_db'",
        [], 'dba: object inventory');

    $sizes = $db->all(
        "SELECT TABLE_NAME, ENGINE, TABLE_ROWS,
                ROUND((DATA_LENGTH) / 1024, 1)  AS data_kb,
                ROUND((INDEX_LENGTH) / 1024, 1) AS index_kb,
                TABLE_COLLATION
         FROM information_schema.TABLES
         WHERE TABLE_SCHEMA = 'scas_db' AND TABLE_TYPE <> 'VIEW'
         ORDER BY (DATA_LENGTH + INDEX_LENGTH) DESC",
        [], 'dba: table sizes');

    $settings = $db->one(
        'SELECT @@version AS version, @@innodb_flush_log_at_trx_commit AS flush_log,
                @@innodb_doublewrite AS doublewrite, @@tx_isolation AS isolation,
                @@log_bin AS binlog, @@event_scheduler AS scheduler,
                @@innodb_buffer_pool_size / 1024 / 1024 AS buffer_pool_mb,
                @@use_stat_tables AS stat_tables, @@histogram_size AS histogram_size',
        [], 'dba: server settings');
?>
  <div class="grid grid-4" style="margin-bottom:20px">
    <?php foreach (array_slice($objects, 0, 4) as $o): ?>
      <div class="tile"><div class="label"><?= e($o['object_type']) ?></div>
        <div class="value"><?= (int) $o['count'] ?></div></div>
    <?php endforeach; ?>
  </div>
  <div class="grid grid-4" style="margin-bottom:20px">
    <?php foreach (array_slice($objects, 4) as $o): ?>
      <div class="tile"><div class="label"><?= e($o['object_type']) ?></div>
        <div class="value"><?= (int) $o['count'] ?></div></div>
    <?php endforeach; ?>
  </div>

  <div class="card">
    <h2>Server configuration <span class="sub">the settings that decide durability</span></h2>
    <div class="table-scroll">
      <table class="data">
        <tbody>
          <tr><th>MariaDB version</th><td class="mono"><?= e((string) $settings['version']) ?></td>
              <td><span class="sub">the engine this database was designed against</span></td></tr>
          <tr><th>innodb_flush_log_at_trx_commit</th>
              <td class="mono"><?= (int) $settings['flush_log'] ?></td>
              <td><span class="badge <?= (int) $settings['flush_log'] === 1 ? 'ok' : 'warn' ?>">
                  <?= (int) $settings['flush_log'] === 1 ? 'fully durable' : 'may lose committed work' ?></span>
                  <span class="sub"> 1 means the redo log is fsynced at every COMMIT</span></td></tr>
          <tr><th>innodb_doublewrite</th><td class="mono"><?= (int) $settings['doublewrite'] ?></td>
              <td><span class="badge <?= (int) $settings['doublewrite'] === 1 ? 'ok' : 'warn' ?>">
                  <?= (int) $settings['doublewrite'] === 1 ? 'torn pages protected' : 'unprotected' ?></span></td></tr>
          <tr><th>Default isolation level</th><td class="mono"><?= e((string) $settings['isolation']) ?></td>
              <td><span class="sub">what sp_record_attendance runs under</span></td></tr>
          <tr><th>Binary logging</th><td class="mono"><?= $settings['binlog'] ? 'ON' : 'OFF' ?></td>
              <td><span class="badge <?= $settings['binlog'] ? 'ok' : 'warn' ?>">
                  <?= $settings['binlog'] ? 'point-in-time recovery available' : 'recovery granularity is the last backup' ?></span>
                  <?php if (!$settings['binlog']): ?>
                    <span class="sub"> enable log_bin in my.ini - see docs/RECOVERY.md</span>
                  <?php endif; ?></td></tr>
          <tr><th>Event scheduler</th><td class="mono"><?= e((string) $settings['scheduler']) ?></td>
              <td><span class="badge <?= $settings['scheduler'] === 'ON' ? 'ok' : 'bad' ?>">
                  <?= $settings['scheduler'] === 'ON' ? 'nightly jobs will run' : 'the daily close will NOT run' ?></span></td></tr>
          <tr><th>InnoDB buffer pool</th><td class="mono"><?= number_format((float) $settings['buffer_pool_mb'], 0) ?> MB</td>
              <td><span class="sub">working set held in memory</span></td></tr>
          <tr><th>Optimiser statistics</th><td class="mono"><?= e((string) $settings['stat_tables']) ?></td>
              <td><span class="sub">histogram size <?= (int) $settings['histogram_size'] ?></span></td></tr>
        </tbody>
      </table>
    </div>
  </div>

  <div class="card">
    <h2>Storage <span class="sub">rows are InnoDB estimates, not exact counts</span></h2>
    <div class="table-scroll">
      <table class="data">
        <thead><tr><th>Table</th><th>Engine</th><th class="num">Rows</th>
        <th class="num">Data (KB)</th><th class="num">Index (KB)</th><th>Collation</th></tr></thead>
        <tbody>
        <?php foreach ($sizes as $s): ?>
          <tr>
            <td class="mono"><?= e($s['TABLE_NAME']) ?></td>
            <td><?= e($s['ENGINE']) ?></td>
            <td class="num"><?= number_format((int) $s['TABLE_ROWS']) ?></td>
            <td class="num"><?= number_format((float) $s['data_kb'], 1) ?></td>
            <td class="num"><?= number_format((float) $s['index_kb'], 1) ?></td>
            <td><span class="sub"><?= e($s['TABLE_COLLATION']) ?></span></td>
          </tr>
        <?php endforeach; ?>
        </tbody>
      </table>
    </div>
  </div>

<?php elseif ($tab === 'plans'):
    $samples = [
        'Scan validation (the hot path)' =>
            "SELECT qr_code_id, timetable_id, expiry_datetime, is_revoked, scan_count, max_scans\n"
          . "FROM qr_code WHERE code_value = 'abc123abc123abc123abc123abc12345'",
        'Sargable: a date range on the bare column' =>
            "SELECT COUNT(*) FROM attendance\nWHERE session_date >= '2026-07-01' AND session_date < '2026-08-01'",
        'NOT sargable: a function wrapped around the column' =>
            "SELECT COUNT(*) FROM attendance\nWHERE YEAR(session_date) = 2026 AND MONTH(session_date) = 7",
        'Covering index (every column read is in the index)' =>
            "SELECT status, COUNT(*), SUM(minutes_late) FROM attendance\n"
          . "WHERE teacher_id = 1 AND session_date BETWEEN '2026-05-04' AND '2026-08-18'\nGROUP BY status",
        'Monthly report join' =>
            "SELECT teacher_name, present_count, absent_count, attendance_rate\n"
          . "FROM v_monthly_attendance_summary WHERE session_year = 2026 AND session_month = 8",
    ];
?>
  <div class="card">
    <h2>EXPLAIN runner</h2>
    <div class="card-body">
      <form method="post">
        <?= Auth::csrfField() ?>
        <input type="hidden" name="action" value="explain">
        <div class="field">
          <label for="sql">A single SELECT statement <span class="hint">&mdash; it is explained, not executed</span></label>
          <textarea id="sql" name="sql" style="font-family:var(--mono);min-height:120px"
                    placeholder="SELECT ..."><?= e($userSql) ?></textarea>
        </div>
        <button class="btn" type="submit">Explain</button>
      </form>

      <?php if ($explainError !== ''): ?>
        <div class="alert danger" style="margin-top:14px"><?= e($explainError) ?></div>
      <?php endif; ?>

      <?php if ($explainRows): ?>
        <h3 style="margin:20px 0 8px;font-size:15px">Execution plan</h3>
        <div class="table-scroll">
          <table class="data">
            <thead><tr><?php foreach (array_keys($explainRows[0]) as $col): ?>
              <th><?= e($col) ?></th><?php endforeach; ?></tr></thead>
            <tbody>
            <?php foreach ($explainRows as $row): ?>
              <tr><?php foreach ($row as $col => $val): ?>
                <td class="<?= $col === 'rows' ? 'num' : 'mono' ?>">
                  <?php if ($col === 'type'): ?>
                    <span class="badge <?= in_array($val, ['const','eq_ref','ref'], true) ? 'ok'
                        : ($val === 'range' ? 'good' : ($val === 'ALL' ? 'bad' : 'warn')) ?>"><?= ev($val) ?></span>
                  <?php else: ?>
                    <?= ev($val) ?>
                  <?php endif; ?>
                </td>
              <?php endforeach; ?></tr>
            <?php endforeach; ?>
            </tbody>
          </table>
        </div>
        <div class="note">
          <strong>Reading this:</strong>
          <code class="inline">type</code> is the access method &mdash;
          <code class="inline">const</code> and <code class="inline">eq_ref</code> are single-row lookups,
          <code class="inline">ref</code> and <code class="inline">range</code> use an index,
          and <code class="inline">ALL</code> is a full table scan.
          <code class="inline">key</code> names the index actually chosen, and
          <code class="inline">rows</code> is how many the optimiser expects to examine.
          <code class="inline">Using index</code> in Extra means the query was answered
          from the index alone, without touching the table.
        </div>
      <?php endif; ?>
    </div>
  </div>

  <div class="card">
    <h2>Workload samples <span class="sub">click to load, then explain</span></h2>
    <div class="card-body">
      <?php foreach ($samples as $label => $sql): ?>
        <div style="margin-bottom:14px">
          <form method="post">
            <?= Auth::csrfField() ?>
            <input type="hidden" name="action" value="explain">
            <input type="hidden" name="sql" value="<?= e($sql) ?>">
            <div style="display:flex;justify-content:space-between;align-items:center;gap:12px;margin-bottom:6px">
              <strong style="font-size:14px"><?= e($label) ?></strong>
              <button class="btn small secondary" type="submit">Explain this</button>
            </div>
            <pre class="sql"><?= e($sql) ?></pre>
          </form>
        </div>
      <?php endforeach; ?>
    </div>
  </div>

<?php elseif ($tab === 'indexes'):
    $indexes   = $db->all('SELECT * FROM v_index_inventory', [], 'dba: index inventory');
    $redundant = $db->all('SELECT * FROM v_redundant_indexes', [], 'dba: redundant indexes');
?>
  <div class="card">
    <h2>Redundant index check</h2>
    <?php if (!$redundant): ?>
      <div class="empty"><strong>No redundant indexes</strong>
        No non-unique index is a left-prefix of another. Every index earns its write cost.</div>
    <?php else: ?>
    <div class="table-scroll">
      <table class="data">
        <thead><tr><th>Table</th><th>Redundant index</th><th>Covered by</th><th>Its columns</th><th>Covering columns</th></tr></thead>
        <tbody>
        <?php foreach ($redundant as $r): ?>
          <tr>
            <td class="mono"><?= e($r['TABLE_NAME']) ?></td>
            <td class="mono"><?= e($r['redundant_index']) ?></td>
            <td class="mono"><?= e($r['covered_by']) ?></td>
            <td class="mono"><?= e($r['redundant_columns']) ?></td>
            <td class="mono"><?= e($r['covering_columns']) ?></td>
          </tr>
        <?php endforeach; ?>
        </tbody>
      </table>
    </div>
    <?php endif; ?>
  </div>

  <div class="card">
    <h2>Index inventory <span class="sub"><?= count($indexes) ?> indexes; cardinality drives the optimiser</span></h2>
    <div class="table-scroll">
      <table class="data">
        <thead><tr><th>Table</th><th>Index</th><th>Unique</th><th>Columns</th><th class="num">Cardinality</th><th>Type</th></tr></thead>
        <tbody>
        <?php foreach ($indexes as $i): ?>
          <tr>
            <td class="mono"><?= e($i['TABLE_NAME']) ?></td>
            <td class="mono"><?= e($i['INDEX_NAME']) ?></td>
            <td><?= (int) $i['NON_UNIQUE'] === 0 ? '<span class="badge ok">unique</span>' : '' ?></td>
            <td class="mono"><?= e($i['index_columns']) ?></td>
            <td class="num"><?= number_format((int) $i['cardinality']) ?></td>
            <td><span class="sub"><?= e($i['INDEX_TYPE']) ?></span></td>
          </tr>
        <?php endforeach; ?>
        </tbody>
      </table>
    </div>
  </div>

<?php elseif ($tab === 'integrity'):
    $checks = $db->callProcRows('sp_run_integrity_check');
    $failed = 0;
    foreach ($checks as $c) { $failed += (int) $c['violations']; }
?>
  <div class="card">
    <h2>Integrity sweep
      <span class="sub">every rule should report zero</span>
    </h2>
    <?php if ($failed === 0): ?>
      <div class="card-body"><div class="alert success">
        <strong>All rules satisfied</strong>
        The ledger is internally consistent: no forged sessions, no orphans, and no
        approved leave still counted as absenteeism.
      </div></div>
    <?php else: ?>
      <div class="card-body"><div class="alert danger">
        <strong><?= $failed ?> violation(s) found</strong>
        These indicate data that was written around the application layer.
      </div></div>
    <?php endif; ?>
    <div class="table-scroll">
      <table class="data">
        <thead><tr><th>Rule</th><th class="num">Violations</th><th>Result</th></tr></thead>
        <tbody>
        <?php foreach ($checks as $c): ?>
          <tr>
            <td><?= e($c['check_name']) ?></td>
            <td class="num"><?= (int) $c['violations'] ?></td>
            <td><span class="badge <?= (int) $c['violations'] === 0 ? 'ok' : 'bad' ?>">
              <?= (int) $c['violations'] === 0 ? 'PASS' : 'FAIL' ?></span></td>
          </tr>
        <?php endforeach; ?>
        </tbody>
      </table>
    </div>
  </div>

<?php elseif ($tab === 'transactions'):
    $locks = $db->callProcRows('sp_show_locks');
?>
  <div class="card">
    <h2>Run a transaction demonstration</h2>
    <div class="card-body">
      <div class="grid grid-2">
        <div>
          <p><strong>Atomicity and SAVEPOINT.</strong> Inserts two rows, takes a savepoint,
             inserts a third, rolls back to the savepoint and commits. The third insert
             must vanish while the first two survive.</p>
          <form method="post">
            <?= Auth::csrfField() ?>
            <input type="hidden" name="action" value="demo_savepoint">
            <button class="btn" type="submit">Run the savepoint demonstration</button>
          </form>
        </div>
        <div>
          <p><strong>Consistency.</strong> Runs a transaction whose second statement
             violates a CHECK constraint. The whole transaction must be discarded, including
             the first, valid statement.</p>
          <form method="post">
            <?= Auth::csrfField() ?>
            <input type="hidden" name="action" value="demo_consistency">
            <button class="btn" type="submit">Run the consistency demonstration</button>
          </form>
        </div>
      </div>

      <?php if ($demoOutput): ?>
        <h3 style="margin:20px 0 8px;font-size:15px">Result</h3>
        <div class="table-scroll">
          <table class="data">
            <thead><tr><?php foreach (array_keys($demoOutput[0]) as $col): ?>
              <th><?= e($col) ?></th><?php endforeach; ?></tr></thead>
            <tbody>
            <?php foreach ($demoOutput as $row): ?>
              <tr><?php foreach ($row as $col => $val): ?>
                <td<?= $col === 'result' ? '' : ' class="num"' ?>>
                  <?php if ($col === 'result'): ?>
                    <span class="badge <?= str_starts_with((string) $val, 'PASS') ? 'ok' : 'bad' ?>"><?= ev($val) ?></span>
                  <?php else: ?><?= ev($val) ?><?php endif; ?>
                </td>
              <?php endforeach; ?></tr>
            <?php endforeach; ?>
            </tbody>
          </table>
        </div>
      <?php endif; ?>
    </div>
  </div>

  <div class="card">
    <h2>Open transactions and lock waits <span class="sub">the first thing to check on a lock timeout</span></h2>
    <?php if (!$locks): ?>
      <div class="empty"><strong>Nothing is blocked</strong>
        No transaction is currently waiting on another.</div>
    <?php else: ?>
    <div class="table-scroll">
      <table class="data">
        <thead><tr><?php foreach (array_keys($locks[0]) as $col): ?>
          <th><?= e($col) ?></th><?php endforeach; ?></tr></thead>
        <tbody>
        <?php foreach ($locks as $row): ?>
          <tr><?php foreach ($row as $val): ?><td class="mono"><?= ev($val) ?></td><?php endforeach; ?></tr>
        <?php endforeach; ?>
        </tbody>
      </table>
    </div>
    <?php endif; ?>
  </div>

  <div class="note">
    The dirty-read, non-repeatable-read, lost-update and deadlock demonstrations
    genuinely need two concurrent connections, so they cannot run from a single web
    request. They are written out as paired SESSION A / SESSION B scripts in
    <code class="inline">database/08_transactions_recovery.sql</code>, Part 5.
  </div>

<?php elseif ($tab === 'recovery'):
    $recovery = $db->callProcRows('sp_recovery_report');
    $settings = $db->all('SELECT setting_key, setting_value, data_type, description, updated_by
                          FROM system_setting ORDER BY setting_key', [], 'dba: settings');
?>
  <div class="card">
    <h2>Backup register</h2>
    <?php if (!$recovery): ?>
      <div class="card-body"><div class="alert warning">
        <strong>No backup has ever been recorded</strong>
        Run <code class="inline">tools\backup.bat</code>. A database with no tested
        restore has no recovery plan, only a hope.
      </div></div>
    <?php else: ?>
    <div class="table-scroll">
      <table class="data">
        <thead><tr><?php foreach (array_keys($recovery[0]) as $col): ?>
          <th><?= e($col) ?></th><?php endforeach; ?></tr></thead>
        <tbody>
        <?php foreach ($recovery as $row): ?>
          <tr><?php foreach ($row as $col => $val): ?>
            <td class="<?= is_numeric($val) ? 'num' : 'mono' ?>">
              <?php if ($col === 'status'): ?>
                <span class="badge <?= $val === 'SUCCESS' ? 'ok' : ($val === 'FAILED' ? 'bad' : 'warn') ?>"><?= ev($val) ?></span>
              <?php else: ?><?= ev($val) ?><?php endif; ?>
            </td>
          <?php endforeach; ?></tr>
        <?php endforeach; ?>
        </tbody>
      </table>
    </div>
    <?php endif; ?>
  </div>

  <div class="card">
    <h2>Configuration <span class="sub">system_setting is a temporal table: every past value is retained</span></h2>
    <div class="table-scroll">
      <table class="data">
        <thead><tr><th>Key</th><th>Value</th><th>Type</th><th>Description</th><th>Last changed by</th></tr></thead>
        <tbody>
        <?php foreach ($settings as $s): ?>
          <tr>
            <td class="mono"><?= e($s['setting_key']) ?></td>
            <td><strong><?= e($s['setting_value']) ?></strong></td>
            <td><span class="sub"><?= e($s['data_type']) ?></span></td>
            <td><span class="sub"><?= e($s['description']) ?></span></td>
            <td><span class="sub"><?= e($s['updated_by'] ?? 'never changed') ?></span></td>
          </tr>
        <?php endforeach; ?>
        </tbody>
      </table>
    </div>
    <div class="card-body">
      <form method="post" style="display:flex;gap:12px;align-items:flex-end;flex-wrap:wrap">
        <?= Auth::csrfField() ?>
        <input type="hidden" name="action" value="restore_setting">
        <div class="field" style="margin:0;min-width:230px">
          <label for="setting_key">Restore setting</label>
          <select id="setting_key" name="setting_key">
            <?php foreach ($settings as $s): ?>
              <option value="<?= e($s['setting_key']) ?>"><?= e($s['setting_key']) ?></option>
            <?php endforeach; ?>
          </select>
        </div>
        <div class="field" style="margin:0;min-width:210px">
          <label for="as_of">to its value at</label>
          <input type="text" id="as_of" name="as_of" placeholder="YYYY-MM-DD HH:MM:SS"
                 value="<?= e(date('Y-m-d H:i:s', strtotime('-1 hour'))) ?>">
        </div>
        <button class="btn secondary" type="submit">Restore from history</button>
      </form>
      <div class="note">
        This is point-in-time recovery without a backup file. MariaDB keeps every
        previous version of a system-versioned row, so
        <code class="inline">SELECT ... FOR SYSTEM_TIME AS OF</code> can read the
        configuration exactly as it stood at any past moment, and put it back.
      </div>
    </div>
  </div>

<?php elseif ($tab === 'performance'):
    $slow = $db->all(
        'SELECT log_id, query_label, exec_ms, rows_returned, executed_by, executed_at,
                LEFT(sql_text, 400) AS sql_text
         FROM query_performance_log ORDER BY executed_at DESC LIMIT 100',
        [], 'dba: slow query log');
    $worst = $db->all(
        'SELECT query_label, COUNT(*) AS occurrences,
                ROUND(AVG(exec_ms), 1) AS avg_ms, ROUND(MAX(exec_ms), 1) AS max_ms
         FROM query_performance_log GROUP BY query_label ORDER BY avg_ms DESC LIMIT 20',
        [], 'dba: slow query summary');
?>
  <div class="card">
    <h2>Slowest labels <span class="sub">statements over <?= SLOW_QUERY_MS ?> ms are logged by the data-access layer</span></h2>
    <?php if (!$worst): ?>
      <div class="empty"><strong>Nothing logged</strong>
        No statement has exceeded <?= SLOW_QUERY_MS ?> ms. On this dataset every
        indexed query completes well inside that budget.</div>
    <?php else: ?>
    <div class="table-scroll">
      <table class="data">
        <thead><tr><th>Label</th><th class="num">Times</th><th class="num">Average ms</th><th class="num">Worst ms</th></tr></thead>
        <tbody>
        <?php foreach ($worst as $w): ?>
          <tr>
            <td><?= e($w['query_label']) ?></td>
            <td class="num"><?= (int) $w['occurrences'] ?></td>
            <td class="num"><?= e((string) $w['avg_ms']) ?></td>
            <td class="num"><?= e((string) $w['max_ms']) ?></td>
          </tr>
        <?php endforeach; ?>
        </tbody>
      </table>
    </div>
    <?php endif; ?>
  </div>

  <?php if ($slow): ?>
  <div class="card">
    <h2>Recent entries</h2>
    <div class="table-scroll">
      <table class="data">
        <thead><tr><th>When</th><th>Label</th><th class="num">ms</th><th>Statement</th><th>Account</th></tr></thead>
        <tbody>
        <?php foreach ($slow as $s): ?>
          <tr>
            <td style="white-space:nowrap"><?= fmtDateTime($s['executed_at']) ?></td>
            <td><?= e($s['query_label']) ?></td>
            <td class="num"><?= e((string) $s['exec_ms']) ?></td>
            <td class="mono" style="max-width:520px;word-break:break-word"><?= e($s['sql_text']) ?></td>
            <td><span class="sub"><?= e($s['executed_by']) ?></span></td>
          </tr>
        <?php endforeach; ?>
        </tbody>
      </table>
    </div>
  </div>
  <?php endif; ?>

<?php endif; ?>

<?php require __DIR__ . '/../includes/footer.php'; ?>
