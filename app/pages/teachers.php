<?php
/**
 * SCAS - staff directory.
 *
 * Reads v_my_school_teachers. That view resolves the caller's school from the
 * connection's session variables, so a headteacher signed in at Winneba
 * cannot see Accra Academy's staff - not by changing a URL, and not by
 * editing this file.
 *
 * Note the phone column: v_teacher_directory exposes fn_mask_phone(), so what
 * arrives here is already 024****456. The full number never leaves the
 * database.
 */
declare(strict_types=1);

$db     = Database::get();
$search = strParam('q', '', 60);
$dept   = strParam('dept', '', 60);
$from   = dateParam('from', date('Y-m-01'));
$to     = dateParam('to', date('Y-m-d'));

$sql = 'SELECT teacher_id, staff_number, full_name, department, qualification,
               date_employed, employment_status, email, phone_masked,
               school_name, years_of_service, is_active
        FROM v_my_school_teachers WHERE 1 = 1';
$args = [];

if ($search !== '') {
    $sql   .= ' AND (full_name LIKE ? OR staff_number LIKE ?)';
    $args[] = '%' . $search . '%';
    $args[] = '%' . $search . '%';
}
if ($dept !== '') {
    $sql   .= ' AND department = ?';
    $args[] = $dept;
}
$sql .= ' ORDER BY full_name';

$teachers = $db->all($sql, $args, 'teachers: directory');

// Attendance figures for the same period, keyed by teacher.
$stats = [];
foreach ($db->all(
    'SELECT teacher_id,
            SUM(present_count) AS present_count,
            SUM(late_count)    AS late_count,
            SUM(absent_count)  AS absent_count,
            SUM(sessions_recorded) AS sessions
     FROM v_monthly_attendance_summary
     WHERE (session_year * 100 + session_month) BETWEEN ? AND ?
     GROUP BY teacher_id',
    [(int) (date('Ym', strtotime($from))), (int) (date('Ym', strtotime($to)))],
    'teachers: period stats'
) as $s) {
    $stats[(int) $s['teacher_id']] = $s;
}

$departments = $db->all(
    'SELECT DISTINCT department FROM v_my_school_teachers ORDER BY department',
    [],
    'teachers: departments'
);

$pageTitle   = 'Staff directory';
$pageDesc    = 'Teaching staff visible to your account, with attendance for the selected period.';
$pageActions = '<button class="btn secondary" onclick="window.print()">Print</button>';

require __DIR__ . '/../includes/header.php';
?>

<div class="card">
  <form method="get" class="filters no-print">
    <input type="hidden" name="page" value="teachers">
    <div class="field">
      <label for="q">Search</label>
      <input type="text" id="q" name="q" value="<?= e($search) ?>" placeholder="name or staff number">
    </div>
    <div class="field">
      <label for="dept">Department</label>
      <select id="dept" name="dept">
        <option value="">All departments</option>
        <?php foreach ($departments as $d): ?>
          <option value="<?= e($d['department']) ?>" <?= $dept === $d['department'] ? 'selected' : '' ?>>
            <?= e($d['department']) ?>
          </option>
        <?php endforeach; ?>
      </select>
    </div>
    <div class="field"><label for="from">From</label><input type="date" id="from" name="from" value="<?= e($from) ?>"></div>
    <div class="field"><label for="to">To</label><input type="date" id="to" name="to" value="<?= e($to) ?>"></div>
    <button class="btn secondary" type="submit">Apply</button>
  </form>

  <?php if (!$teachers): ?>
    <div class="empty"><strong>No staff match</strong>Try clearing the filters.</div>
  <?php else: ?>
  <div class="table-scroll">
    <table class="data">
      <thead><tr>
        <th>Name</th><th>Staff number</th><th>Department</th><th>Qualification</th>
        <th>Employed</th><th>Status</th><th>Contact</th>
        <th class="num">Present</th><th class="num">Late</th><th class="num">Absent</th><th>Rate</th>
      </tr></thead>
      <tbody>
      <?php foreach ($teachers as $t):
          $s        = $stats[(int) $t['teacher_id']] ?? null;
          $sessions = $s ? (int) $s['sessions'] : 0;
          $rate     = $sessions > 0
                      ? round(((int) $s['present_count'] + (int) $s['late_count']) * 100 / $sessions, 1)
                      : null; ?>
        <tr>
          <td><strong><?= e($t['full_name']) ?></strong>
            <?php if (!$t['is_active']): ?><br><span class="badge muted">inactive</span><?php endif; ?>
          </td>
          <td class="mono"><?= e($t['staff_number']) ?></td>
          <td><?= e($t['department']) ?></td>
          <td><span class="sub"><?= e($t['qualification']) ?></span></td>
          <td><?= fmtDate($t['date_employed'], 'M Y') ?><br>
              <span class="sub"><?= (int) $t['years_of_service'] ?> yrs</span></td>
          <td><span class="badge <?= $t['employment_status'] === 'Active' ? 'ok' : 'muted' ?>">
              <?= e($t['employment_status']) ?></span></td>
          <td><span class="sub"><?= e($t['email']) ?><br><?= e($t['phone_masked']) ?></span></td>
          <td class="num"><?= $s ? (int) $s['present_count'] : '-' ?></td>
          <td class="num"><?= $s ? (int) $s['late_count'] : '-' ?></td>
          <td class="num"><?= $s ? (int) $s['absent_count'] : '-' ?></td>
          <td><span class="badge <?= rateClass($rate) ?>"><?= $rate === null ? '-' : $rate . '%' ?></span></td>
        </tr>
      <?php endforeach; ?>
      </tbody>
    </table>
  </div>
  <?php endif; ?>
</div>

<div class="note">
  Telephone numbers are masked by <code class="inline">fn_mask_phone()</code>
  inside the view. The application never receives the full number, so it
  cannot leak one through this page, an export, or an error message.
</div>

<?php require __DIR__ . '/../includes/footer.php'; ?>
