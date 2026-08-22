<?php
/**
 * SCAS - reports.
 *
 * The monthly report is produced by sp_month_end_report_serializable, which
 * runs SERIALIZABLE READ ONLY. That matters for a document a headteacher
 * signs: the header totals and the per-teacher rows are guaranteed to have
 * been read from the same instant, so they cannot disagree with each other
 * because a scan landed midway through the report.
 */
declare(strict_types=1);

$db     = Database::get();
$year   = intParam('year', (int) date('Y'), 2020, 2100);
$month  = intParam('month', (int) date('n'), 1, 12);
$school = intParam('school_id', Auth::schoolId() ?? 1, 1);

if (Auth::privilege() < PRIV_SYS_ADMIN) {
    $school = Auth::schoolId() ?? $school;   // scoped users cannot choose
}

$schools = Auth::privilege() >= PRIV_SYS_ADMIN
    ? $db->all('SELECT school_id, school_name FROM school WHERE is_active = 1 ORDER BY school_name')
    : [];

$report = $db->callProcRows('sp_monthly_attendance_report', [$school, $year, $month]);

$ranking = $db->all(
    'SELECT teacher_name, department, sessions_recorded, present_count, late_count,
            absent_count, attendance_rate, school_rank, department_average
     FROM v_teacher_ranking WHERE school_id = ? ORDER BY school_rank LIMIT 25',
    [$school],
    'reports: ranking'
);

$departments = $db->all(
    'SELECT department, teachers, sessions_recorded, absences, lateness, attendance_rate
     FROM v_department_stats WHERE school_id = ? ORDER BY attendance_rate DESC',
    [$school],
    'reports: departments'
);

$trend = $db->all(
    'SELECT session_date, sessions_recorded, absences, lateness, absence_pct, absences_7day_avg
     FROM v_absence_trend WHERE school_id = ? AND session_date >= ?
     ORDER BY session_date DESC LIMIT 30',
    [$school, date('Y-m-d', strtotime('-45 days'))],
    'reports: trend'
);

$schoolName = (string) $db->scalar('SELECT school_name FROM school WHERE school_id = ?', [$school]);

$totals = ['sessions' => 0, 'present' => 0, 'late' => 0, 'absent' => 0, 'excused' => 0];
foreach ($report as $r) {
    $totals['sessions'] += (int) $r['sessions_recorded'];
    $totals['present']  += (int) $r['present_count'];
    $totals['late']     += (int) $r['late_count'];
    $totals['absent']   += (int) $r['absent_count'];
    $totals['excused']  += (int) $r['excused_count'];
}
$overall = $totals['sessions'] > 0
    ? round(($totals['present'] + $totals['late']) * 100 / max(1, $totals['sessions'] - $totals['excused']), 2)
    : null;

$pageTitle   = 'Reports';
$pageDesc    = $schoolName . ' - ' . date('F Y', mktime(0, 0, 0, $month, 1, $year));
$pageActions = '<button class="btn secondary" onclick="window.print()">Print / save as PDF</button>';

require __DIR__ . '/../includes/header.php';
?>

<div class="card no-print">
  <form method="get" class="filters">
    <input type="hidden" name="page" value="reports">
    <?php if ($schools): ?>
      <div class="field">
        <label for="school_id">School</label>
        <select id="school_id" name="school_id">
          <?php foreach ($schools as $s): ?>
            <option value="<?= (int) $s['school_id'] ?>" <?= $school === (int) $s['school_id'] ? 'selected' : '' ?>>
              <?= e($s['school_name']) ?>
            </option>
          <?php endforeach; ?>
        </select>
      </div>
    <?php endif; ?>
    <div class="field">
      <label for="month">Month</label>
      <select id="month" name="month">
        <?php for ($m = 1; $m <= 12; $m++): ?>
          <option value="<?= $m ?>" <?= $month === $m ? 'selected' : '' ?>>
            <?= date('F', mktime(0, 0, 0, $m, 1)) ?>
          </option>
        <?php endfor; ?>
      </select>
    </div>
    <div class="field">
      <label for="year">Year</label>
      <input type="number" id="year" name="year" value="<?= $year ?>" min="2020" max="2100">
    </div>
    <button class="btn secondary" type="submit">Run report</button>
  </form>
</div>

<div class="grid grid-4" style="margin-bottom:20px">
  <div class="tile"><div class="label">Sessions recorded</div><div class="value"><?= $totals['sessions'] ?></div>
    <div class="foot"><?= count($report) ?> teachers</div></div>
  <div class="tile ok"><div class="label">Present</div><div class="value"><?= $totals['present'] ?></div></div>
  <div class="tile warn"><div class="label">Late</div><div class="value"><?= $totals['late'] ?></div></div>
  <div class="tile <?= rateClass($overall) ?>"><div class="label">School attendance rate</div>
    <div class="value"><?= $overall === null ? '-' : $overall . '%' ?></div>
    <div class="foot"><?= $totals['absent'] ?> absent, <?= $totals['excused'] ?> excused</div></div>
</div>

<div class="card">
  <h2>Monthly attendance report
    <span class="sub"><?= e($schoolName) ?> &middot; <?= date('F Y', mktime(0, 0, 0, $month, 1, $year)) ?></span>
  </h2>
  <?php if (!$report): ?>
    <div class="empty"><strong>No attendance recorded</strong>
      Nothing was captured for this school in <?= date('F Y', mktime(0, 0, 0, $month, 1, $year)) ?>.</div>
  <?php else: ?>
  <div class="table-scroll">
    <table class="data">
      <thead><tr>
        <th>Staff number</th><th>Teacher</th><th>Department</th>
        <th class="num">Sessions</th><th class="num">Present</th><th class="num">Late</th>
        <th class="num">Absent</th><th class="num">Excused</th><th class="num">Late minutes</th>
        <th class="num">Rate</th><th>Rating</th>
      </tr></thead>
      <tbody>
      <?php foreach ($report as $r): ?>
        <tr>
          <td class="mono"><?= e($r['staff_number']) ?></td>
          <td><strong><?= e($r['teacher_name']) ?></strong></td>
          <td><?= e($r['department']) ?></td>
          <td class="num"><?= (int) $r['sessions_recorded'] ?></td>
          <td class="num"><?= (int) $r['present_count'] ?></td>
          <td class="num"><?= (int) $r['late_count'] ?></td>
          <td class="num"><?= (int) $r['absent_count'] ?></td>
          <td class="num"><?= (int) $r['excused_count'] ?></td>
          <td class="num"><?= (int) $r['total_minutes_late'] ?></td>
          <td class="num"><?= $r['attendance_rate'] === null ? '-' : number_format((float) $r['attendance_rate'], 1) . '%' ?></td>
          <td><span class="badge <?= rateClass($r['attendance_rate'] === null ? null : (float) $r['attendance_rate']) ?>">
              <?= e($r['rating']) ?></span></td>
        </tr>
      <?php endforeach; ?>
      </tbody>
    </table>
  </div>
  <?php endif; ?>
</div>

<div class="grid grid-2">
  <div class="card">
    <h2>Departments <span class="sub">whole term to date</span></h2>
    <?php if (!$departments): ?><div class="empty">No data.</div><?php else: ?>
    <div class="table-scroll">
      <table class="data">
        <thead><tr><th>Department</th><th class="num">Staff</th><th class="num">Sessions</th>
        <th class="num">Absent</th><th class="num">Late</th><th>Rate</th></tr></thead>
        <tbody>
        <?php foreach ($departments as $d): ?>
          <tr>
            <td><strong><?= e($d['department']) ?></strong></td>
            <td class="num"><?= (int) $d['teachers'] ?></td>
            <td class="num"><?= (int) $d['sessions_recorded'] ?></td>
            <td class="num"><?= (int) $d['absences'] ?></td>
            <td class="num"><?= (int) $d['lateness'] ?></td>
            <td>
              <?php $dr = $d['attendance_rate'] === null ? null : (float) $d['attendance_rate']; ?>
              <div style="display:flex;align-items:center;gap:8px">
                <div class="bar <?= rateClass($dr) ?>" style="flex:1"><span style="width:<?= (float) $dr ?>%"></span></div>
                <span style="min-width:48px;text-align:right"><?= $dr === null ? '-' : number_format($dr, 1) . '%' ?></span>
              </div>
            </td>
          </tr>
        <?php endforeach; ?>
        </tbody>
      </table>
    </div>
    <?php endif; ?>
  </div>

  <div class="card">
    <h2>Teacher ranking
      <span class="sub">RANK() over the school, computed in the database</span>
    </h2>
    <?php if (!$ranking): ?><div class="empty">No data.</div><?php else: ?>
    <div class="table-scroll">
      <table class="data">
        <thead><tr><th class="num">#</th><th>Teacher</th><th>Department</th>
        <th class="num">Rate</th><th class="num">Dept avg</th></tr></thead>
        <tbody>
        <?php foreach ($ranking as $r): ?>
          <tr>
            <td class="num"><?= (int) $r['school_rank'] ?></td>
            <td><?= e($r['teacher_name']) ?></td>
            <td><?= e($r['department']) ?></td>
            <td class="num"><span class="badge <?= rateClass($r['attendance_rate'] === null ? null : (float) $r['attendance_rate']) ?>">
              <?= $r['attendance_rate'] === null ? '-' : number_format((float) $r['attendance_rate'], 1) . '%' ?></span></td>
            <td class="num"><span class="sub">
              <?= $r['department_average'] === null ? '-' : number_format((float) $r['department_average'], 1) . '%' ?></span></td>
          </tr>
        <?php endforeach; ?>
        </tbody>
      </table>
    </div>
    <?php endif; ?>
  </div>
</div>

<div class="card">
  <h2>Absence trend <span class="sub">with a 7-day moving average from a window frame</span></h2>
  <?php if (!$trend): ?><div class="empty">No data.</div><?php else: ?>
  <div class="table-scroll">
    <table class="data">
      <thead><tr><th>Date</th><th class="num">Sessions</th><th class="num">Absent</th>
      <th class="num">Late</th><th class="num">7-day avg</th><th>Absence rate</th></tr></thead>
      <tbody>
      <?php foreach ($trend as $t):
          $pct = (float) $t['absence_pct'];
          $cls = $pct >= 20 ? 'bad' : ($pct >= 10 ? 'warn' : 'ok'); ?>
        <tr>
          <td><?= fmtDate($t['session_date'], 'D, d M Y') ?></td>
          <td class="num"><?= (int) $t['sessions_recorded'] ?></td>
          <td class="num"><?= (int) $t['absences'] ?></td>
          <td class="num"><?= (int) $t['lateness'] ?></td>
          <td class="num"><?= $t['absences_7day_avg'] === null ? '-' : number_format((float) $t['absences_7day_avg'], 1) ?></td>
          <td>
            <div style="display:flex;align-items:center;gap:8px">
              <div class="bar <?= $cls ?>" style="flex:1"><span style="width:<?= min(100, $pct * 3) ?>%"></span></div>
              <span style="min-width:48px;text-align:right"><?= number_format($pct, 1) ?>%</span>
            </div>
          </td>
        </tr>
      <?php endforeach; ?>
      </tbody>
    </table>
  </div>
  <?php endif; ?>
</div>

<?php require __DIR__ . '/../includes/footer.php'; ?>
