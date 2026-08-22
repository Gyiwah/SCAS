<?php
/**
 * SCAS - leave approval queue.
 *
 * The approval itself is done by sp_action_leave_request, which re-checks the
 * approver's privilege inside the database. This page having a button is not
 * what authorises the action; a teacher calling the same procedure directly
 * is refused and the attempt is logged as PRIVILEGE_DENIED.
 */
declare(strict_types=1);

$db = Database::get();

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    try {
        $out = $db->callProc(
            'sp_action_leave_request',
            [
                intParam('leave_request_id'),
                strParam('decision', 'Rejected', 10),
                Auth::userId(),
                strParam('remarks', '', 200),
            ],
            ['rows_corrected']
        );
        $corrected = (int) ($out['rows_corrected'] ?? 0);
        Flash::add('success',
            'Request ' . strtolower(strParam('decision', '', 10)) . '.'
            . ($corrected > 0
                ? " {$corrected} attendance record(s) already marked Absent were reclassified as Excused."
                : ''));
    } catch (DatabaseException $ex) {
        Flash::add('danger', $ex->getMessage());
    }
    header('Location: ' . url('approvals'));
    exit;
}

$pending = $db->all(
    'SELECT * FROM v_leave_pending ORDER BY requested_at',
    [],
    'approvals: pending queue'
);

$recent = $db->all(
    "SELECT * FROM v_leave_history
     WHERE status <> 'Pending' ORDER BY actioned_at DESC LIMIT 20",
    [],
    'approvals: recent decisions'
);

$pageTitle = 'Leave approvals';
$pageDesc  = 'Approving a request also corrects any Absent records already written for those dates.';

require __DIR__ . '/../includes/header.php';
?>

<div class="card">
  <h2>Awaiting a decision <span class="sub"><?= count($pending) ?> pending</span></h2>
  <?php if (!$pending): ?>
    <div class="empty"><strong>The queue is empty</strong>No requests are waiting.</div>
  <?php else: ?>
  <div class="table-scroll">
    <table class="data">
      <thead><tr>
        <th>Teacher</th><th>Type</th><th>Dates</th><th class="num">Days</th>
        <th>Reason</th><th class="num">Waiting</th><th class="num">Sessions</th><th class="no-print">Decision</th>
      </tr></thead>
      <tbody>
      <?php foreach ($pending as $p): ?>
        <tr>
          <td><strong><?= e($p['teacher_name']) ?></strong><br>
              <span class="sub"><?= e($p['staff_number']) ?> &middot; <?= e($p['department']) ?></span></td>
          <td><?= e($p['leave_type']) ?></td>
          <td><?= fmtDate($p['start_date'], 'd M') ?> &ndash; <?= fmtDate($p['end_date']) ?></td>
          <td class="num"><?= (int) $p['days_requested'] ?></td>
          <td style="max-width:300px"><?= e($p['reason']) ?></td>
          <td class="num">
            <span class="badge <?= (int) $p['days_waiting'] > 3 ? 'warn' : 'muted' ?>">
              <?= (int) $p['days_waiting'] ?>d
            </span>
          </td>
          <td class="num"><?= (int) $p['sessions_affected'] ?></td>
          <td class="no-print" style="min-width:230px">
            <form method="post">
              <?= Auth::csrfField() ?>
              <input type="hidden" name="leave_request_id" value="<?= (int) $p['leave_request_id'] ?>">
              <input type="text" name="remarks" placeholder="Remarks (optional)" maxlength="200"
                     style="margin-bottom:6px;font-size:13px">
              <button class="btn small" type="submit" name="decision" value="Approved">Approve</button>
              <button class="btn small danger" type="submit" name="decision" value="Rejected">Reject</button>
            </form>
          </td>
        </tr>
      <?php endforeach; ?>
      </tbody>
    </table>
  </div>
  <?php endif; ?>
</div>

<div class="card">
  <h2>Recent decisions</h2>
  <?php if (!$recent): ?>
    <div class="empty">No requests have been actioned yet.</div>
  <?php else: ?>
  <div class="table-scroll">
    <table class="data">
      <thead><tr><th>Teacher</th><th>Type</th><th>Dates</th><th>Status</th><th>Actioned</th><th>By</th><th>Remarks</th></tr></thead>
      <tbody>
      <?php foreach ($recent as $r): ?>
        <tr>
          <td><?= e($r['teacher_name']) ?></td>
          <td><?= e($r['leave_type']) ?></td>
          <td><?= fmtDate($r['start_date'], 'd M') ?> &ndash; <?= fmtDate($r['end_date']) ?></td>
          <td><span class="badge <?= match ($r['status']) {
                'Approved' => 'ok', 'Rejected' => 'bad', default => 'muted' } ?>"><?= e($r['status']) ?></span></td>
          <td><?= fmtDateTime($r['actioned_at']) ?></td>
          <td><?= e($r['approved_by_name'] ?? '-') ?></td>
          <td><span class="sub"><?= e($r['remarks']) ?></span></td>
        </tr>
      <?php endforeach; ?>
      </tbody>
    </table>
  </div>
  <?php endif; ?>
</div>

<?php require __DIR__ . '/../includes/footer.php'; ?>
