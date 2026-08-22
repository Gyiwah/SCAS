<?php
/**
 * SCAS - timetable administration.
 *
 * Clash prevention is not implemented in this page. Two sessions that start
 * at exactly the same minute are refused by the UNIQUE keys; two that merely
 * overlap are refused by trg_timetable_bi. Either way the database raises the
 * message and the page just shows it, so the rule holds for phpMyAdmin too.
 */
declare(strict_types=1);

$db = Database::get();

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $action = strParam('action', '', 20);
    try {
        if ($action === 'create') {
            $db->callProc('sp_create_timetable_session', [
                intParam('teacher_id'),
                intParam('classroom_id'),
                intParam('term_id'),
                strParam('subject', '', 60),
                strParam('class_group', '', 30),
                strParam('day_of_week', 'Monday', 10),
                strParam('start_time', '07:30', 8),
                strParam('end_time', '08:40', 8),
                Auth::userId(),
            ], ['timetable_id']);
            Flash::add('success', 'Session added to the timetable.');
        } elseif ($action === 'toggle') {
            $db->callProc('sp_set_timetable_active',
                [intParam('timetable_id'), intParam('active', 0, 0, 1), Auth::userId()]);
            Flash::add('success', 'Session updated.');
        }
    } catch (DatabaseException $ex) {
        Flash::add('danger', $ex->getMessage());
    }
    header('Location: ' . url('timetable'));
    exit;
}

$scoped = Auth::privilege() < PRIV_SYS_ADMIN;

$rows = $db->all(
    'SELECT tt.timetable_id, tt.subject, tt.class_group, tt.day_of_week,
            tt.start_time, tt.end_time, tt.duration_minutes, tt.is_active,
            u.full_name AS teacher_name, t.staff_number, t.department,
            c.room_name, c.school_id, s.school_name, at.term_name
     FROM timetable tt
     JOIN teacher       t  ON t.teacher_id   = tt.teacher_id
     JOIN app_user      u  ON u.user_id      = t.user_id
     JOIN classroom     c  ON c.classroom_id = tt.classroom_id
     JOIN school        s  ON s.school_id    = c.school_id
     JOIN academic_term at ON at.term_id     = tt.term_id
     WHERE at.is_current = 1 AND (? = 0 OR c.school_id = ?)
     ORDER BY FIELD(tt.day_of_week, "Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday"),
              tt.start_time, c.room_name',
    [$scoped ? 1 : 0, Auth::schoolId()],
    'timetable: current term'
);

$teachers = $db->all(
    'SELECT teacher_id, full_name, staff_number, department
     FROM v_my_school_teachers WHERE is_active = 1 ORDER BY full_name',
    [],
    'timetable: teacher options'
);
$classrooms = $db->all(
    'SELECT classroom_id, room_name, building, school_id FROM classroom
     WHERE is_active = 1 AND (? = 0 OR school_id = ?) ORDER BY room_name',
    [$scoped ? 1 : 0, Auth::schoolId()]
);
$terms = $db->all(
    'SELECT term_id, term_name, school_id FROM academic_term
     WHERE is_current = 1 AND (? = 0 OR school_id = ?)',
    [$scoped ? 1 : 0, Auth::schoolId()]
);

$conflicts = $db->callProcRows('sp_detect_timetable_conflicts', [$terms[0]['term_id'] ?? null]);

$periods = [
    '07:30-08:40' => 'Period 1  07:30 - 08:40',
    '08:40-09:50' => 'Period 2  08:40 - 09:50',
    '10:10-11:20' => 'Period 3  10:10 - 11:20',
    '11:20-12:30' => 'Period 4  11:20 - 12:30',
    '13:10-14:20' => 'Period 5  13:10 - 14:20',
];

$pageTitle = 'Timetable';
$pageDesc  = 'Sessions in the current term. A session is retired rather than deleted, because attendance records point at it.';

require __DIR__ . '/../includes/header.php';
?>

<?php if ($conflicts): ?>
  <div class="alert danger">
    <strong><?= count($conflicts) ?> scheduling conflict(s) detected</strong>
    sp_detect_timetable_conflicts found overlapping sessions. These predate the
    clash triggers or were introduced by a direct database edit.
  </div>
  <div class="card">
    <h2>Conflicts</h2>
    <div class="table-scroll">
      <table class="data">
        <thead><tr><th>Type</th><th>Who / where</th><th>Day</th><th>Session A</th><th>Session B</th></tr></thead>
        <tbody>
        <?php foreach ($conflicts as $c): ?>
          <tr>
            <td><span class="badge bad"><?= e($c['conflict_type']) ?></span></td>
            <td><?= e($c['teacher_name']) ?></td>
            <td><?= e($c['day_of_week']) ?></td>
            <td>#<?= (int) $c['session_a'] ?>: <?= fmtTime($c['a_start']) ?>&ndash;<?= fmtTime($c['a_end']) ?></td>
            <td>#<?= (int) $c['session_b'] ?>: <?= fmtTime($c['b_start']) ?>&ndash;<?= fmtTime($c['b_end']) ?></td>
          </tr>
        <?php endforeach; ?>
        </tbody>
      </table>
    </div>
  </div>
<?php endif; ?>

<div class="card">
  <h2>Add a session</h2>
  <div class="card-body">
    <form method="post" id="ttform">
      <?= Auth::csrfField() ?>
      <input type="hidden" name="action" value="create">
      <input type="hidden" name="start_time" id="start_time">
      <input type="hidden" name="end_time"   id="end_time">
      <div class="form-row">
        <div class="field"><label for="teacher_id">Teacher</label>
          <select id="teacher_id" name="teacher_id" required>
            <?php foreach ($teachers as $t): ?>
              <option value="<?= (int) $t['teacher_id'] ?>">
                <?= e($t['full_name']) ?> &mdash; <?= e($t['department']) ?>
              </option>
            <?php endforeach; ?>
          </select></div>
        <div class="field"><label for="classroom_id">Classroom</label>
          <select id="classroom_id" name="classroom_id" required>
            <?php foreach ($classrooms as $c): ?>
              <option value="<?= (int) $c['classroom_id'] ?>"><?= e($c['room_name']) ?></option>
            <?php endforeach; ?>
          </select></div>
        <div class="field"><label for="term_id">Term</label>
          <select id="term_id" name="term_id" required>
            <?php foreach ($terms as $t): ?>
              <option value="<?= (int) $t['term_id'] ?>"><?= e($t['term_name']) ?></option>
            <?php endforeach; ?>
          </select></div>
        <div class="field"><label for="subject">Subject</label>
          <input type="text" id="subject" name="subject" required maxlength="60"></div>
        <div class="field"><label for="class_group">Class group</label>
          <input type="text" id="class_group" name="class_group" maxlength="30" placeholder="SHS 2 Science A"></div>
        <div class="field"><label for="day_of_week">Day</label>
          <select id="day_of_week" name="day_of_week" required>
            <?php foreach (['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday'] as $d): ?>
              <option value="<?= e($d) ?>"><?= e($d) ?></option>
            <?php endforeach; ?>
          </select></div>
        <div class="field"><label for="period">Period</label>
          <select id="period" name="period" required>
            <?php foreach ($periods as $val => $label): ?>
              <option value="<?= e($val) ?>"><?= e($label) ?></option>
            <?php endforeach; ?>
          </select></div>
      </div>
      <button class="btn" type="submit">Add session</button>
    </form>
  </div>
</div>

<div class="card">
  <h2>Current term <span class="sub"><?= count($rows) ?> sessions</span></h2>
  <div class="table-scroll">
    <table class="data">
      <thead><tr>
        <th>Day</th><th>Time</th><th>Teacher</th><th>Subject</th><th>Class</th>
        <th>Room</th><th class="num">Min</th><th>State</th><th class="no-print"></th>
      </tr></thead>
      <tbody>
      <?php foreach ($rows as $r): ?>
        <tr<?= $r['is_active'] ? '' : ' style="opacity:.55"' ?>>
          <td><?= e($r['day_of_week']) ?></td>
          <td><?= fmtTime($r['start_time']) ?><br><span class="sub"><?= fmtTime($r['end_time']) ?></span></td>
          <td><?= e($r['teacher_name']) ?><br><span class="sub"><?= e($r['department']) ?></span></td>
          <td><strong><?= e($r['subject']) ?></strong></td>
          <td><?= e($r['class_group']) ?></td>
          <td><?= e($r['room_name']) ?></td>
          <td class="num"><?= (int) $r['duration_minutes'] ?></td>
          <td><span class="badge <?= $r['is_active'] ? 'ok' : 'muted' ?>"><?= $r['is_active'] ? 'active' : 'retired' ?></span></td>
          <td class="no-print">
            <form method="post" style="display:inline">
              <?= Auth::csrfField() ?>
              <input type="hidden" name="action" value="toggle">
              <input type="hidden" name="timetable_id" value="<?= (int) $r['timetable_id'] ?>">
              <input type="hidden" name="active" value="<?= $r['is_active'] ? 0 : 1 ?>">
              <button class="btn small secondary" type="submit"><?= $r['is_active'] ? 'Retire' : 'Restore' ?></button>
            </form>
          </td>
        </tr>
      <?php endforeach; ?>
      </tbody>
    </table>
  </div>
</div>

<script>
/* Split the chosen period into the two TIME values the procedure expects. */
document.getElementById('ttform').addEventListener('submit', function () {
    var parts = document.getElementById('period').value.split('-');
    document.getElementById('start_time').value = parts[0] + ':00';
    document.getElementById('end_time').value   = parts[1] + ':00';
});
</script>

<?php require __DIR__ . '/../includes/footer.php'; ?>
