<?php
/**
 * SCAS - session code issue and display.
 *
 * The QR image is rendered from the token by QrCode (pure PHP, inline SVG).
 * The token itself is generated inside sp_generate_qr_code, never here: the
 * application must not be able to choose or predict a code value.
 */
declare(strict_types=1);

$db   = Database::get();
$date = dateParam('date', date('Y-m-d'));

// ---- actions -------------------------------------------------------------
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $action = strParam('action', '', 20);

    try {
        if ($action === 'generate') {
            $out = $db->callProc(
                'sp_generate_qr_code',
                [intParam('timetable_id'), $date, intParam('validity', 30, 1, 600), Auth::userId()],
                ['qr_code_id', 'code_value']
            );
            Flash::add('success', 'Session code issued.');
        } elseif ($action === 'generate_all') {
            $targets = $db->all(
                'SELECT vt.timetable_id
                 FROM v_active_timetable vt
                 LEFT JOIN qr_code q ON q.timetable_id = vt.timetable_id AND q.session_date = ?
                 WHERE vt.day_of_week = DAYNAME(?) AND q.qr_code_id IS NULL',
                [$date, $date]
            );
            $made = 0; $failed = 0;
            foreach ($targets as $t) {
                try {
                    $db->callProc(
                        'sp_generate_qr_code',
                        [(int) $t['timetable_id'], $date, intParam('validity', 60, 1, 600), Auth::userId()],
                        ['qr_code_id', 'code_value']
                    );
                    $made++;
                } catch (Throwable) {
                    $failed++;
                }
            }
            Flash::add($made ? 'success' : 'warning',
                "Issued {$made} code(s)" . ($failed ? ", {$failed} could not be issued." : '.'));
        } elseif ($action === 'revoke') {
            $db->callProc('sp_revoke_qr_code',
                [intParam('qr_code_id'), strParam('reason', 'Revoked by administrator', 100), Auth::userId()]);
            Flash::add('success', 'Code revoked. It can no longer be scanned.');
        }
    } catch (DatabaseException $e) {
        Flash::add('danger', $e->getMessage());
    }

    header('Location: ' . url('qrcodes', ['date' => $date]));
    exit;
}

// ---- data ----------------------------------------------------------------
$sessions = $db->all(
    "SELECT vt.timetable_id, vt.subject, vt.class_group, vt.room_name,
            vt.teacher_name, vt.start_time, vt.end_time,
            q.qr_code_id, q.code_value, q.expiry_datetime, q.generated_datetime,
            q.is_revoked, q.revoked_reason, q.scan_count, q.max_scans,
            CASE WHEN q.qr_code_id IS NULL THEN 'Not issued'
                 ELSE fn_qr_status(q.code_value) END AS code_state,
            a.status AS attendance_status
     FROM v_active_timetable vt
     LEFT JOIN qr_code q
            ON q.timetable_id = vt.timetable_id AND q.session_date = ?
     LEFT JOIN attendance a
            ON a.timetable_id = vt.timetable_id AND a.session_date = ?
           AND a.teacher_id = vt.teacher_id
     WHERE vt.day_of_week = DAYNAME(?)
     ORDER BY vt.start_time, vt.room_name",
    [$date, $date, $date],
    'qrcodes: sessions for date'
);

$isHoliday = (int) $db->scalar(
    'SELECT fn_is_holiday(?, ?)',
    [Auth::schoolId(), $date]
);

$focus = intParam('show', 0);

$pageTitle = 'Session codes';
$pageDesc  = 'Issue the QR code a teacher scans to check in. Codes are single-use and expire.';
$pageActions = '<a class="btn secondary" href="' . e(url('board')) . '">Live board</a>';

require __DIR__ . '/../includes/header.php';
?>

<div class="card no-print">
  <form method="get" class="filters">
    <input type="hidden" name="page" value="qrcodes">
    <div class="field">
      <label for="date">Session date</label>
      <input type="date" id="date" name="date" value="<?= e($date) ?>">
    </div>
    <button class="btn secondary" type="submit">Show</button>
  </form>

  <?php if ($isHoliday): ?>
    <div class="card-body">
      <div class="alert warning">
        <strong><?= fmtDate($date) ?> is a holiday</strong>
        No codes can be issued: the database refuses to create a session code on a holiday.
      </div>
    </div>
  <?php else: ?>
    <div class="card-body">
      <form method="post" style="display:flex;gap:12px;align-items:flex-end;flex-wrap:wrap">
        <?= Auth::csrfField() ?>
        <input type="hidden" name="action" value="generate_all">
        <input type="hidden" name="date" value="<?= e($date) ?>">
        <div class="field" style="margin:0;max-width:190px">
          <label for="validity">Validity (minutes)</label>
          <input type="number" id="validity" name="validity" value="60" min="1" max="600">
        </div>
        <button class="btn" type="submit">Issue codes for every session on <?= e(fmtDate($date, 'D j M')) ?></button>
      </form>
    </div>
  <?php endif; ?>
</div>

<?php if (!$sessions): ?>
  <div class="card"><div class="empty">
    <strong>No sessions scheduled</strong>
    Nothing runs on <?= e(fmtDate($date, 'l, j F Y')) ?>.
  </div></div>
<?php else: ?>

<div class="card">
  <h2>Sessions on <?= e(fmtDate($date, 'l, j F Y')) ?> <span class="sub"><?= count($sessions) ?> scheduled</span></h2>
  <div class="table-scroll">
    <table class="data">
      <thead><tr>
        <th>Time</th><th>Teacher</th><th>Subject</th><th>Room</th>
        <th>Code</th><th>Expires</th><th>Attendance</th><th class="no-print"></th>
      </tr></thead>
      <tbody>
      <?php foreach ($sessions as $s):
          $state = $s['code_state'];
          $cls = match ($state) {
              'VALID'       => 'ok',
              'Not issued'  => 'muted',
              'EXHAUSTED'   => 'info',
              'REVOKED'     => 'bad',
              'EXPIRED'     => 'warn',
              default       => 'muted',
          }; ?>
        <tr>
          <td><?= fmtTime($s['start_time']) ?><br><span class="sub"><?= fmtTime($s['end_time']) ?></span></td>
          <td><?= e($s['teacher_name']) ?></td>
          <td><strong><?= e($s['subject']) ?></strong><br><span class="sub"><?= e($s['class_group']) ?></span></td>
          <td><?= e($s['room_name']) ?></td>
          <td><span class="badge <?= $cls ?>"><?= e($state) ?></span></td>
          <td><?= $s['expiry_datetime'] ? fmtDateTime($s['expiry_datetime']) : '-' ?></td>
          <td>
            <?php if ($s['attendance_status']): ?>
              <span class="badge <?= statusClass($s['attendance_status']) ?>"><?= e($s['attendance_status']) ?></span>
            <?php else: ?>
              <span class="badge muted">none</span>
            <?php endif; ?>
          </td>
          <td class="no-print" style="white-space:nowrap">
            <?php if (!$s['qr_code_id'] && !$isHoliday): ?>
              <form method="post" style="display:inline">
                <?= Auth::csrfField() ?>
                <input type="hidden" name="action" value="generate">
                <input type="hidden" name="timetable_id" value="<?= (int) $s['timetable_id'] ?>">
                <input type="hidden" name="date" value="<?= e($date) ?>">
                <input type="hidden" name="validity" value="60">
                <button class="btn small" type="submit">Issue</button>
              </form>
            <?php else: ?>
              <a class="btn small secondary" href="<?= e(url('qrcodes', ['date' => $date, 'show' => (int) $s['qr_code_id']])) ?>">Display</a>
              <?php if ($state === 'VALID'): ?>
                <form method="post" style="display:inline"
                      onsubmit="return confirm('Revoke this code? It cannot be scanned afterwards.')">
                  <?= Auth::csrfField() ?>
                  <input type="hidden" name="action" value="revoke">
                  <input type="hidden" name="qr_code_id" value="<?= (int) $s['qr_code_id'] ?>">
                  <input type="hidden" name="date" value="<?= e($date) ?>">
                  <button class="btn small danger" type="submit">Revoke</button>
                </form>
              <?php endif; ?>
            <?php endif; ?>
          </td>
        </tr>
      <?php endforeach; ?>
      </tbody>
    </table>
  </div>
</div>

<?php
// A single code blown up for projection or printing.
if ($focus > 0) {
    $one = null;
    foreach ($sessions as $s) {
        if ((int) $s['qr_code_id'] === $focus) { $one = $s; break; }
    }
    if ($one && $one['code_value']):
?>
<div class="card">
  <h2>Display code <span class="sub">project this, or print and pin it up in the classroom</span></h2>
  <div class="card-body qr-print">
    <h3 style="margin:0 0 2px"><?= e($one['subject']) ?> &middot; <?= e($one['class_group']) ?></h3>
    <div class="sub" style="margin-bottom:14px">
      <?= e($one['teacher_name']) ?> &middot; <?= e($one['room_name']) ?> &middot;
      <?= fmtTime($one['start_time']) ?>&ndash;<?= fmtTime($one['end_time']) ?> &middot;
      <?= fmtDate($date, 'l j F Y') ?>
    </div>
    <?= QrCode::svg($one['code_value'], 9, 4, '#111827', '#ffffff',
                    'Session code for ' . $one['subject']) ?>
    <div class="qr-token"><?= e($one['code_value']) ?></div>
    <p class="sub" style="margin-top:12px">
      Valid until <strong><?= fmtDateTime($one['expiry_datetime']) ?></strong>
      &middot; used <?= (int) $one['scan_count'] ?> of <?= (int) $one['max_scans'] ?> times
    </p>
    <p class="no-print"><button class="btn secondary" onclick="window.print()">Print this code</button></p>
  </div>
</div>
<?php endif; } ?>

<?php endif; ?>

<?php require __DIR__ . '/../includes/footer.php'; ?>
