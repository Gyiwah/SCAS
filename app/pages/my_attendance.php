<?php
/**
 * SCAS - a teacher's own attendance history.
 * Reads v_my_attendance, which is filtered inside the database to the
 * signed-in user. The page cannot widen that scope even if it tried.
 */
declare(strict_types=1);

$db   = Database::get();
$from = dateParam('from', date('Y-m-01'));
$to   = dateParam('to', date('Y-m-d'));

$rows = $db->all(
    'SELECT session_date, subject, class_group, room_name, start_time,
            status, minutes_late, scan_datetime, remarks
     FROM v_my_attendance
     WHERE session_date BETWEEN ? AND ?
     ORDER BY session_date DESC, start_time DESC',
    [$from, $to],
    'my_attendance: history'
);

$sum = $db->one(
    "SELECT COUNT(*) AS sessions,
            SUM(status='Present') AS present_count,
            SUM(status='Late')    AS late_count,
            SUM(status='Absent')  AS absent_count,
            SUM(status='Excused') AS excused_count,
            SUM(minutes_late)     AS total_late_minutes,
            fn_attendance_rate(?, ?, ?) AS rate
     FROM v_my_attendance WHERE session_date BETWEEN ? AND ?",
    [Auth::teacherId(), $from, $to, $from, $to],
    'my_attendance: summary'
);

$pageTitle   = 'My attendance';
$pageDesc    = 'Your own record. An attendance row cannot be edited or deleted once written, by you or by anyone else.';
$pageActions = '<button class="btn secondary" onclick="window.print()">Print</button>';

require __DIR__ . '/../includes/header.php';
?>

<div class="grid grid-4" style="margin-bottom:20px">
  <div class="tile <?= rateClass($sum['rate'] === null ? null : (float) $sum['rate']) ?>">
    <div class="label">Attendance rate</div>
    <div class="value"><?= $sum['rate'] === null ? '-' : number_format((float) $sum['rate'], 1) . '%' ?></div>
    <div class="foot"><?= (int) $sum['sessions'] ?> sessions in range</div>
  </div>
  <div class="tile ok">
    <div class="label">Present</div>
    <div class="value"><?= (int) $sum['present_count'] ?></div>
  </div>
  <div class="tile warn">
    <div class="label">Late</div>
    <div class="value"><?= (int) $sum['late_count'] ?></div>
    <div class="foot"><?= (int) $sum['total_late_minutes'] ?> minutes in total</div>
  </div>
  <div class="tile bad">
    <div class="label">Absent</div>
    <div class="value"><?= (int) $sum['absent_count'] ?></div>
    <div class="foot"><?= (int) $sum['excused_count'] ?> excused by approved leave</div>
  </div>
</div>

<div class="card">
  <form method="get" class="filters no-print">
    <input type="hidden" name="page" value="my_attendance">
    <div class="field"><label for="from">From</label><input type="date" id="from" name="from" value="<?= e($from) ?>"></div>
    <div class="field"><label for="to">To</label><input type="date" id="to" name="to" value="<?= e($to) ?>"></div>
    <button class="btn secondary" type="submit">Apply</button>
  </form>

  <?php if (!$rows): ?>
    <div class="empty"><strong>No records in this range</strong>Try widening the dates.</div>
  <?php else: ?>
  <div class="table-scroll">
    <table class="data">
      <thead><tr>
        <th>Date</th><th>Subject</th><th>Class</th><th>Room</th><th>Bell</th>
        <th>Checked in</th><th>Status</th><th class="num">Late (min)</th><th>Note</th>
      </tr></thead>
      <tbody>
      <?php foreach ($rows as $r): ?>
        <tr>
          <td><?= fmtDate($r['session_date'], 'D, d M Y') ?></td>
          <td><strong><?= e($r['subject']) ?></strong></td>
          <td><?= e($r['class_group']) ?></td>
          <td><?= e($r['room_name']) ?></td>
          <td><?= fmtTime($r['start_time']) ?></td>
          <td><?= in_array($r['status'], ['Present', 'Late'], true)
                  ? fmtTime(substr((string) $r['scan_datetime'], 11)) : '-' ?></td>
          <td><span class="badge <?= statusClass($r['status']) ?>"><?= e($r['status']) ?></span></td>
          <td class="num"><?= (int) $r['minutes_late'] ?: '' ?></td>
          <td><span class="sub"><?= e($r['remarks']) ?></span></td>
        </tr>
      <?php endforeach; ?>
      </tbody>
    </table>
  </div>
  <?php endif; ?>
</div>

<?php require __DIR__ . '/../includes/footer.php'; ?>
