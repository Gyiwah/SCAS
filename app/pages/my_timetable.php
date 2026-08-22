<?php
/** SCAS - a teacher's weekly schedule for the current term. */
declare(strict_types=1);

$db = Database::get();

$rows = $db->all(
    'SELECT * FROM v_my_timetable
     ORDER BY FIELD(day_of_week, "Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday"),
              start_time',
    [],
    'my_timetable'
);

$byDay = [];
foreach ($rows as $r) {
    $byDay[$r['day_of_week']][] = $r;
}
$days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

$pageTitle   = 'My timetable';
$pageDesc    = $rows ? ($rows[0]['term_name'] . ' - ' . $rows[0]['school_name']) : 'Current term';
$pageActions = '<button class="btn secondary" onclick="window.print()">Print</button>';

require __DIR__ . '/../includes/header.php';
?>

<?php if (!$rows): ?>
  <div class="card"><div class="empty">
    <strong>No sessions assigned</strong>
    You have no active sessions in the current term.
  </div></div>
<?php else: ?>
<div class="grid grid-2">
<?php foreach ($days as $day):
    if (empty($byDay[$day])) { continue; }
    $isToday = ($day === date('l')); ?>
  <div class="card">
    <h2><?= e($day) ?>
      <span class="sub">
        <?= count($byDay[$day]) ?> session<?= count($byDay[$day]) === 1 ? '' : 's' ?><?= $isToday ? ' &middot; today' : '' ?>
      </span>
    </h2>
    <div class="table-scroll">
      <table class="data">
        <thead><tr><th>Time</th><th>Subject</th><th>Class</th><th>Room</th><th class="num">Min</th></tr></thead>
        <tbody>
        <?php foreach ($byDay[$day] as $s): ?>
          <tr>
            <td><?= fmtTime($s['start_time']) ?><br><span class="sub"><?= fmtTime($s['end_time']) ?></span></td>
            <td><strong><?= e($s['subject']) ?></strong></td>
            <td><?= e($s['class_group']) ?></td>
            <td><?= e($s['room_name']) ?><br><span class="sub"><?= e($s['building']) ?></span></td>
            <td class="num"><?= (int) $s['duration_minutes'] ?></td>
          </tr>
        <?php endforeach; ?>
        </tbody>
      </table>
    </div>
  </div>
<?php endforeach; ?>
</div>
<?php endif; ?>

<?php require __DIR__ . '/../includes/footer.php'; ?>
