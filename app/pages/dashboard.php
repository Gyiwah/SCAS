<?php
/** SCAS - dashboard. What it shows depends on who is looking. */
declare(strict_types=1);

$db   = Database::get();
$priv = Auth::privilege();
$today = date('Y-m-d');

$pageTitle = 'Dashboard';
$pageDesc  = date('l, j F Y');

// ---------------------------------------------------------------------------
// Teacher view
// ---------------------------------------------------------------------------
$mySessions = [];
$myStats    = null;
if (Auth::isTeacher()) {
    $mySessions = $db->all(
        "SELECT vt.timetable_id, vt.subject, vt.class_group, vt.room_name,
                vt.start_time, vt.end_time,
                a.status, a.scan_datetime, a.minutes_late,
                q.qr_code_id,
                CASE WHEN CURTIME() < vt.start_time THEN 'Upcoming'
                     WHEN CURTIME() BETWEEN vt.start_time AND vt.end_time THEN 'In Progress'
                     ELSE 'Ended' END AS session_state
         FROM v_my_timetable vt
         LEFT JOIN qr_code q
                ON q.timetable_id = vt.timetable_id AND q.session_date = ?
         LEFT JOIN attendance a
                ON a.timetable_id = vt.timetable_id AND a.session_date = ?
               AND a.teacher_id = vt.teacher_id
         WHERE vt.day_of_week = DAYNAME(?)
         ORDER BY vt.start_time",
        [$today, $today, $today],
        'dashboard: my sessions today'
    );

    $myStats = $db->one(
        "SELECT COUNT(*) AS sessions,
                SUM(status = 'Present') AS present_count,
                SUM(status = 'Late')    AS late_count,
                SUM(status = 'Absent')  AS absent_count,
                SUM(status = 'Excused') AS excused_count,
                fn_attendance_rate(?, ?, ?) AS rate
         FROM v_my_attendance
         WHERE session_date BETWEEN ? AND ?",
        [Auth::teacherId(), date('Y-m-01'), $today, date('Y-m-01'), $today],
        'dashboard: my month'
    );
}

// ---------------------------------------------------------------------------
// Headteacher and above
// ---------------------------------------------------------------------------
$schoolToday = null;
$unstaffed   = [];
$pendingLeave = 0;
$trend        = [];
$worst        = [];

if ($priv >= PRIV_HEADTEACHER) {
    $schoolToday = $db->one(
        "SELECT COUNT(*) AS sessions,
                SUM(attendance_state = 'Present')  AS present_count,
                SUM(attendance_state = 'Late')     AS late_count,
                SUM(attendance_state = 'No Scan')  AS no_scan,
                SUM(attendance_state = 'On Leave') AS on_leave,
                SUM(session_state = 'In Progress') AS running_now
         FROM v_live_session_board",
        [],
        'dashboard: school today'
    );

    $unstaffed = $db->all(
        'SELECT teacher_name, subject, room_name, class_group, start_time, end_time,
                minutes_into_session
         FROM v_unstaffed_now ORDER BY minutes_into_session DESC',
        [],
        'dashboard: unstaffed now'
    );

    $pendingLeave = (int) $db->scalar('SELECT COUNT(*) FROM v_leave_pending', [], 'dashboard: pending leave');

    $trend = $db->all(
        'SELECT session_date, sessions_recorded, absences, lateness, absence_pct
         FROM v_absence_trend
         WHERE session_date >= ? ORDER BY session_date DESC LIMIT 14',
        [date('Y-m-d', strtotime('-21 days'))],
        'dashboard: absence trend'
    );

    $worst = $db->all(
        "SELECT teacher_name, department, absent_count, late_count, attendance_rate
         FROM v_monthly_attendance_summary
         WHERE session_year = ? AND session_month = ?
         ORDER BY attendance_rate ASC, absent_count DESC LIMIT 6",
        [(int) date('Y'), (int) date('n')],
        'dashboard: attention list'
    );
}

require __DIR__ . '/../includes/header.php';
?>

<?php if (Auth::isTeacher()): ?>
  <div class="grid grid-4" style="margin-bottom:20px">
    <div class="tile">
      <div class="label">Sessions today</div>
      <div class="value"><?= count($mySessions) ?></div>
      <div class="foot"><?= date('l') ?></div>
    </div>
    <div class="tile <?= rateClass($myStats['rate'] !== null ? (float) $myStats['rate'] : null) ?>">
      <div class="label">My rate this month</div>
      <div class="value"><?= $myStats && $myStats['rate'] !== null ? number_format((float) $myStats['rate'], 1) . '%' : '-' ?></div>
      <div class="foot"><?= (int) ($myStats['sessions'] ?? 0) ?> sessions recorded</div>
    </div>
    <div class="tile warn">
      <div class="label">Late this month</div>
      <div class="value"><?= (int) ($myStats['late_count'] ?? 0) ?></div>
      <div class="foot">arrivals after the grace period</div>
    </div>
    <div class="tile bad">
      <div class="label">Absent this month</div>
      <div class="value"><?= (int) ($myStats['absent_count'] ?? 0) ?></div>
      <div class="foot"><?= (int) ($myStats['excused_count'] ?? 0) ?> excused by approved leave</div>
    </div>
  </div>

  <div class="card">
    <h2>My sessions today <span class="sub">check in from the session that is running</span></h2>
    <?php if (!$mySessions): ?>
      <div class="empty"><strong>Nothing scheduled today</strong>You have no sessions on <?= date('l') ?>.</div>
    <?php else: ?>
    <div class="table-scroll">
      <table class="data">
        <thead><tr>
          <th>Time</th><th>Subject</th><th>Class</th><th>Room</th>
          <th>Session</th><th>Attendance</th><th></th>
        </tr></thead>
        <tbody>
        <?php foreach ($mySessions as $s): ?>
          <tr>
            <td><?= fmtTime($s['start_time']) ?> &ndash; <?= fmtTime($s['end_time']) ?></td>
            <td><strong><?= e($s['subject']) ?></strong></td>
            <td><?= e($s['class_group']) ?></td>
            <td><?= e($s['room_name']) ?></td>
            <td><span class="badge <?= $s['session_state'] === 'In Progress' ? 'info' : 'muted' ?>"><?= e($s['session_state']) ?></span></td>
            <td>
              <?php if ($s['status']): ?>
                <span class="badge <?= statusClass($s['status']) ?>"><?= e($s['status']) ?></span>
                <?php if ((int) $s['minutes_late'] > 0): ?>
                  <span class="sub"><?= (int) $s['minutes_late'] ?> min late</span>
                <?php endif; ?>
              <?php else: ?>
                <span class="badge muted">Not checked in</span>
              <?php endif; ?>
            </td>
            <td>
              <?php if (!$s['status'] && $s['qr_code_id']): ?>
                <a class="btn small" href="<?= e(url('checkin')) ?>">Check in</a>
              <?php endif; ?>
            </td>
          </tr>
        <?php endforeach; ?>
        </tbody>
      </table>
    </div>
    <?php endif; ?>
  </div>
<?php endif; ?>

<?php if ($priv >= PRIV_HEADTEACHER): ?>
  <div class="grid grid-4" style="margin-bottom:20px">
    <div class="tile">
      <div class="label">Sessions scheduled today</div>
      <div class="value"><?= (int) ($schoolToday['sessions'] ?? 0) ?></div>
      <div class="foot"><?= (int) ($schoolToday['running_now'] ?? 0) ?> running right now</div>
    </div>
    <div class="tile ok">
      <div class="label">Checked in</div>
      <div class="value"><?= (int) ($schoolToday['present_count'] ?? 0) + (int) ($schoolToday['late_count'] ?? 0) ?></div>
      <div class="foot"><?= (int) ($schoolToday['late_count'] ?? 0) ?> of them late</div>
    </div>
    <div class="tile <?= count($unstaffed) > 0 ? 'bad' : 'ok' ?>">
      <div class="label">Unstaffed right now</div>
      <div class="value"><?= count($unstaffed) ?></div>
      <div class="foot">running with no check-in</div>
    </div>
    <div class="tile <?= $pendingLeave > 0 ? 'warn' : '' ?>">
      <div class="label">Leave awaiting you</div>
      <div class="value"><?= $pendingLeave ?></div>
      <div class="foot"><a href="<?= e(url('approvals')) ?>">Open the queue</a></div>
    </div>
  </div>

  <?php if ($unstaffed): ?>
  <div class="card">
    <h2 style="color:var(--bad)">Classes running with no teacher checked in</h2>
    <div class="table-scroll">
      <table class="data">
        <thead><tr><th>Teacher</th><th>Subject</th><th>Class</th><th>Room</th><th>Slot</th><th class="num">Minutes in</th></tr></thead>
        <tbody>
        <?php foreach ($unstaffed as $u): ?>
          <tr>
            <td><strong><?= e($u['teacher_name']) ?></strong></td>
            <td><?= e($u['subject']) ?></td>
            <td><?= e($u['class_group']) ?></td>
            <td><?= e($u['room_name']) ?></td>
            <td><?= fmtTime($u['start_time']) ?> &ndash; <?= fmtTime($u['end_time']) ?></td>
            <td class="num"><span class="badge bad"><?= (int) $u['minutes_into_session'] ?></span></td>
          </tr>
        <?php endforeach; ?>
        </tbody>
      </table>
    </div>
  </div>
  <?php endif; ?>

  <div class="grid grid-2">
    <div class="card">
      <h2>Absence trend <span class="sub">last 14 recorded days</span></h2>
      <?php if (!$trend): ?>
        <div class="empty">No attendance recorded yet.</div>
      <?php else: ?>
      <div class="table-scroll">
        <table class="data">
          <thead><tr><th>Date</th><th class="num">Sessions</th><th class="num">Absent</th><th class="num">Late</th><th>Absence rate</th></tr></thead>
          <tbody>
          <?php foreach ($trend as $t):
              $pct = (float) $t['absence_pct'];
              $cls = $pct >= 20 ? 'bad' : ($pct >= 10 ? 'warn' : 'ok'); ?>
            <tr>
              <td><?= fmtDate($t['session_date'], 'D, d M') ?></td>
              <td class="num"><?= (int) $t['sessions_recorded'] ?></td>
              <td class="num"><?= (int) $t['absences'] ?></td>
              <td class="num"><?= (int) $t['lateness'] ?></td>
              <td>
                <div style="display:flex;align-items:center;gap:8px">
                  <div class="bar <?= $cls ?>" style="flex:1"><span style="width:<?= min(100, $pct * 3) ?>%"></span></div>
                  <span style="min-width:46px;text-align:right"><?= number_format($pct, 1) ?>%</span>
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
      <h2>Needing attention <span class="sub"><?= date('F Y') ?></span></h2>
      <?php if (!$worst): ?>
        <div class="empty">No data for this month yet.</div>
      <?php else: ?>
      <div class="table-scroll">
        <table class="data">
          <thead><tr><th>Teacher</th><th>Department</th><th class="num">Absent</th><th class="num">Late</th><th class="num">Rate</th></tr></thead>
          <tbody>
          <?php foreach ($worst as $w): ?>
            <tr>
              <td><?= e($w['teacher_name']) ?></td>
              <td><?= e($w['department']) ?></td>
              <td class="num"><?= (int) $w['absent_count'] ?></td>
              <td class="num"><?= (int) $w['late_count'] ?></td>
              <td class="num">
                <span class="badge <?= rateClass($w['attendance_rate'] === null ? null : (float) $w['attendance_rate']) ?>">
                  <?= $w['attendance_rate'] === null ? '-' : number_format((float) $w['attendance_rate'], 1) . '%' ?>
                </span>
              </td>
            </tr>
          <?php endforeach; ?>
          </tbody>
        </table>
      </div>
      <?php endif; ?>
    </div>
  </div>
<?php endif; ?>

<?php if (!Auth::isTeacher() && $priv < PRIV_HEADTEACHER): ?>
  <div class="card"><div class="empty">
    <strong>Nothing to show</strong>
    Your account has no teacher record and no school-wide privileges.
  </div></div>
<?php endif; ?>

<?php require __DIR__ . '/../includes/footer.php'; ?>
