<?php
/**
 * SCAS - live session board. Answers proposal problem 3 directly:
 * "headteachers have no real-time view of which classes are currently
 * unstaffed".
 *
 * This page reads the ledger directly rather than the materialised summary:
 * a one-hour-old aggregate is useless for an alert about a classroom that is
 * empty right now.
 */
declare(strict_types=1);

$db = Database::get();

$rows = $db->all(
    'SELECT * FROM v_live_session_board ORDER BY start_time, room_name',
    [],
    'board: live sessions'
);

$counts = ['Present' => 0, 'Late' => 0, 'No Scan' => 0, 'On Leave' => 0, 'Absent' => 0, 'Excused' => 0];
$running = 0;
foreach ($rows as $r) {
    $state = $r['attendance_state'];
    if (isset($counts[$state])) { $counts[$state]++; }
    if ($r['session_state'] === 'In Progress') { $running++; }
}

$pageTitle = 'Live board';
$pageDesc  = 'Every session scheduled today and its current check-in state. Refreshes every 60 seconds.';
$pageActions = '<a class="btn secondary" href="' . e(url('board')) . '">Refresh now</a>'
             . '<a class="btn" href="' . e(url('qrcodes')) . '">Session codes</a>';

require __DIR__ . '/../includes/header.php';
?>
<meta http-equiv="refresh" content="60">

<div class="grid grid-4" style="margin-bottom:20px">
  <div class="tile"><div class="label">Scheduled today</div>
    <div class="value"><?= count($rows) ?></div><div class="foot"><?= $running ?> in progress</div></div>
  <div class="tile ok"><div class="label">Present</div>
    <div class="value"><?= $counts['Present'] ?></div><div class="foot">checked in on time</div></div>
  <div class="tile warn"><div class="label">Late</div>
    <div class="value"><?= $counts['Late'] ?></div><div class="foot">after the grace period</div></div>
  <div class="tile bad"><div class="label">No check-in</div>
    <div class="value"><?= $counts['No Scan'] ?></div>
    <div class="foot"><?= $counts['On Leave'] ?> on approved leave</div></div>
</div>

<div class="card">
  <h2><?= date('l, j F Y') ?> <span class="sub">as at <?= date('H:i') ?></span></h2>
  <?php if (!$rows): ?>
    <div class="empty"><strong>Nothing scheduled today</strong>
      No active sessions run on <?= date('l') ?> in the current term.</div>
  <?php else: ?>
  <div class="table-scroll">
    <table class="data">
      <thead><tr>
        <th>Slot</th><th>Teacher</th><th>Subject</th><th>Class</th><th>Room</th>
        <th>Session</th><th>Code</th><th>Attendance</th><th>Scanned at</th>
      </tr></thead>
      <tbody>
      <?php foreach ($rows as $r):
          $alert = ($r['session_state'] === 'In Progress' && $r['attendance_state'] === 'No Scan'); ?>
        <tr<?= $alert ? ' style="background:var(--bad-bg)"' : '' ?>>
          <td><?= fmtTime($r['start_time']) ?><br><span class="sub"><?= fmtTime($r['end_time']) ?></span></td>
          <td><strong><?= e($r['teacher_name']) ?></strong><br><span class="sub"><?= e($r['staff_number']) ?></span></td>
          <td><?= e($r['subject']) ?></td>
          <td><?= e($r['class_group']) ?></td>
          <td><?= e($r['room_name']) ?></td>
          <td><span class="badge <?= $r['session_state'] === 'In Progress' ? 'info' : 'muted' ?>"><?= e($r['session_state']) ?></span></td>
          <td><span class="badge <?= $r['qr_state'] === 'VALID' ? 'ok' : 'muted' ?>"><?= e($r['qr_state']) ?></span></td>
          <td>
            <span class="badge <?= statusClass($r['attendance_state']) ?>"><?= e($r['attendance_state']) ?></span>
            <?php if ((int) $r['minutes_late'] > 0): ?><br><span class="sub"><?= (int) $r['minutes_late'] ?> min late</span><?php endif; ?>
          </td>
          <td><?= $r['scan_datetime'] ? fmtTime(substr($r['scan_datetime'], 11)) : '-' ?></td>
        </tr>
      <?php endforeach; ?>
      </tbody>
    </table>
  </div>
  <?php endif; ?>
</div>

<div class="note">
  Sessions with no check-in are only resolved into <em>Absent</em> or
  <em>Excused</em> at 23:30, when the scheduled event
  <code class="inline">ev_mark_daily_absentees</code> closes the day. Until
  then they show as <em>No Scan</em>, because a teacher who has not yet
  arrived is not the same as a teacher who never came.
</div>

<?php require __DIR__ . '/../includes/footer.php'; ?>
