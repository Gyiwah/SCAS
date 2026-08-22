<?php
/**
 * SCAS - teacher check-in.
 *
 * The page collects a code and hands it to sp_record_attendance. It performs
 * NO validation of its own beyond basic shape: whether the code is live, is
 * for this teacher, and whether the arrival counts as Present or Late is
 * decided entirely inside the database, so the answer is the same however the
 * scan arrives.
 */
declare(strict_types=1);

$db     = Database::get();
$result = null;

// A code may arrive by form post, or in the query string when the teacher's
// phone camera opens the encoded value as a link.
$submitted = strParam('code', '', 64);

if ($_SERVER['REQUEST_METHOD'] === 'POST' && $submitted !== '') {
    $out = $db->callProc(
        'sp_record_attendance',
        [Auth::userId(), $submitted, Auth::clientIp(),
         mb_substr($_SERVER['HTTP_USER_AGENT'] ?? 'unknown', 0, 120)],
        ['result', 'message', 'attendance_id', 'status']
    );
    $result = $out;
}

$today    = date('Y-m-d');
$sessions = $db->all(
    "SELECT vt.timetable_id, vt.subject, vt.class_group, vt.room_name,
            vt.start_time, vt.end_time,
            a.status, a.minutes_late, a.scan_datetime,
            q.qr_code_id, q.expiry_datetime,
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
    'checkin: my sessions'
);

$pageTitle = 'Check in';
$pageDesc  = 'Scan the code displayed in your classroom, or type it in if the camera is unavailable.';

require __DIR__ . '/../includes/header.php';
?>

<div class="checkin-shell">

  <?php if ($result !== null): ?>
    <?php $ok = ($result['result'] ?? '') === 'OK'; ?>
    <div class="card">
      <div class="scan-result <?= $ok ? 'ok' : 'bad' ?>">
        <div class="icon"><?= $ok ? '&#10004;' : '&#10008;' ?></div>
        <h3>
          <?php if ($ok): ?>
            Marked <?= e($result['status'] ?? '') ?>
          <?php else: ?>
            Not recorded
          <?php endif; ?>
        </h3>
        <p><?= e($result['message'] ?? 'No response from the database.') ?></p>
      </div>
    </div>
  <?php endif; ?>

  <div class="card">
    <h2>Enter your session code</h2>
    <div class="card-body">
      <form method="post" id="checkin-form">
        <?= Auth::csrfField() ?>
        <div class="field">
          <label for="code">Session code
            <span class="hint">&mdash; 32 characters, shown under the QR code</span></label>
          <input type="text" id="code" name="code" class="code-input" required
                 maxlength="64" autocomplete="off" autocapitalize="off" spellcheck="false"
                 placeholder="paste or scan">
        </div>
        <button class="btn" type="submit" style="width:100%">Check in</button>
      </form>

      <div id="scan-area" style="margin-top:16px; display:none">
        <button class="btn secondary" type="button" id="scan-btn" style="width:100%">
          Use the camera to scan
        </button>
        <video id="scan-video" playsinline muted
               style="display:none;width:100%;margin-top:12px;border-radius:8px;background:#000"></video>
        <div id="scan-status" class="note" style="display:none"></div>
      </div>

      <div class="note">
        A code is valid only for your own session, only on the day it was
        issued, and only until it expires. Scanning a colleague's code is
        refused by the database and recorded as a security event.
      </div>
    </div>
  </div>

  <div class="card">
    <h2>Your sessions today <span class="sub"><?= date('l, j F') ?></span></h2>
    <?php if (!$sessions): ?>
      <div class="empty"><strong>Nothing scheduled</strong>You have no sessions today.</div>
    <?php else: ?>
    <div class="table-scroll">
      <table class="data">
        <thead><tr><th>Time</th><th>Subject</th><th>Room</th><th>Session</th><th>Status</th></tr></thead>
        <tbody>
        <?php foreach ($sessions as $s): ?>
          <tr>
            <td><?= fmtTime($s['start_time']) ?></td>
            <td><strong><?= e($s['subject']) ?></strong><br><span class="sub"><?= e($s['class_group']) ?></span></td>
            <td><?= e($s['room_name']) ?></td>
            <td><span class="badge <?= $s['session_state'] === 'In Progress' ? 'info' : 'muted' ?>"><?= e($s['session_state']) ?></span></td>
            <td>
              <?php if ($s['status']): ?>
                <span class="badge <?= statusClass($s['status']) ?>"><?= e($s['status']) ?></span>
                <?php if ((int) $s['minutes_late'] > 0): ?><br><span class="sub"><?= (int) $s['minutes_late'] ?> min late</span><?php endif; ?>
              <?php elseif (!$s['qr_code_id']): ?>
                <span class="badge muted">No code issued</span>
              <?php else: ?>
                <span class="badge warn">Awaiting check-in</span>
              <?php endif; ?>
            </td>
          </tr>
        <?php endforeach; ?>
        </tbody>
      </table>
    </div>
    <?php endif; ?>
  </div>
</div>

<script>
/* Camera scanning uses the browser's built-in BarcodeDetector where it
   exists (Chrome and Edge on Android and Windows). There is deliberately no
   JavaScript QR library bundled: the manual code box below always works, so
   an unsupported browser degrades to typing 32 characters rather than to a
   broken page. */
(function () {
    var area   = document.getElementById('scan-area');
    var btn    = document.getElementById('scan-btn');
    var video  = document.getElementById('scan-video');
    var status = document.getElementById('scan-status');
    var input  = document.getElementById('code');
    var form   = document.getElementById('checkin-form');

    if (!('BarcodeDetector' in window) || !navigator.mediaDevices) {
        return;                                  // manual entry only
    }
    area.style.display = 'block';

    var stream = null, detector = null, timer = null;

    function stop() {
        if (timer)  { clearInterval(timer); timer = null; }
        if (stream) { stream.getTracks().forEach(function (t) { t.stop(); }); stream = null; }
        video.style.display = 'none';
    }

    btn.addEventListener('click', function () {
        status.style.display = 'block';
        status.textContent = 'Starting the camera...';

        navigator.mediaDevices.getUserMedia({ video: { facingMode: 'environment' } })
            .then(function (s) {
                stream = s;
                video.srcObject = s;
                video.style.display = 'block';
                return video.play();
            })
            .then(function () {
                detector = new BarcodeDetector({ formats: ['qr_code'] });
                status.textContent = 'Point the camera at the code on the board.';
                timer = setInterval(function () {
                    detector.detect(video).then(function (codes) {
                        if (codes && codes.length) {
                            input.value = codes[0].rawValue.trim();
                            status.textContent = 'Code captured. Submitting...';
                            stop();
                            form.submit();
                        }
                    }).catch(function () { /* a frame that cannot be decoded is normal */ });
                }, 350);
            })
            .catch(function (err) {
                status.textContent = 'The camera is unavailable (' + err.name +
                                     '). Please type the code instead.';
            });
    });

    window.addEventListener('pagehide', stop);
})();
</script>

<?php require __DIR__ . '/../includes/footer.php'; ?>
