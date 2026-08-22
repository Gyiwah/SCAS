<?php
/**
 * SCAS - a teacher's own leave requests.
 *
 * Nothing is validated here beyond presence. Whether the dates overlap an
 * existing request, and whether the request is backdated too far, is decided
 * by trg_leave_request_bi. That keeps one copy of the rule, and it applies
 * equally to a request made through this form and to one inserted directly.
 */
declare(strict_types=1);

$db = Database::get();

if ($_SERVER['REQUEST_METHOD'] === 'POST' && Auth::isTeacher()) {
    try {
        $out = $db->callProc(
            'sp_submit_leave_request',
            [
                Auth::teacherId(),
                strParam('leave_type', 'Casual', 20),
                dateParam('start_date', date('Y-m-d')),
                dateParam('end_date', date('Y-m-d')),
                strParam('reason', '', 150),
            ],
            ['request_id']
        );
        Flash::add('success', 'Request submitted. Your headteacher has been notified.');
    } catch (DatabaseException $ex) {
        Flash::add('danger', $ex->getMessage());
    }
    header('Location: ' . url('leave'));
    exit;
}

$rows = [];
if (Auth::isTeacher()) {
    $rows = $db->all(
        'SELECT leave_request_id, leave_type, start_date, end_date, days_requested,
                reason, status, requested_at, actioned_at, remarks, approved_by_name
         FROM v_leave_history WHERE teacher_id = ?
         ORDER BY requested_at DESC',
        [Auth::teacherId()],
        'leave: my history'
    );
}

$pageTitle = 'My leave';
$pageDesc  = 'Approved leave is excluded from absenteeism figures, so a day covered by approved leave is recorded as Excused rather than Absent.';

require __DIR__ . '/../includes/header.php';
?>

<?php if (!Auth::isTeacher()): ?>
  <div class="card"><div class="empty">
    <strong>No teacher record</strong>
    Only teaching staff submit leave requests through this page.
  </div></div>
<?php else: ?>

<div class="grid grid-2">
  <div class="card">
    <h2>New request</h2>
    <div class="card-body">
      <form method="post">
        <?= Auth::csrfField() ?>
        <div class="field">
          <label for="leave_type">Type of leave</label>
          <select id="leave_type" name="leave_type" required>
            <?php foreach (['Casual','Sick','Maternity','Study','Compassionate','Official Duty'] as $t): ?>
              <option value="<?= e($t) ?>"><?= e($t) ?></option>
            <?php endforeach; ?>
          </select>
        </div>
        <div class="form-row">
          <div class="field">
            <label for="start_date">First day</label>
            <input type="date" id="start_date" name="start_date" required value="<?= e(date('Y-m-d')) ?>">
          </div>
          <div class="field">
            <label for="end_date">Last day</label>
            <input type="date" id="end_date" name="end_date" required value="<?= e(date('Y-m-d')) ?>">
          </div>
        </div>
        <div class="field">
          <label for="reason">Reason <span class="hint">&mdash; at least 5 characters</span></label>
          <textarea id="reason" name="reason" required maxlength="150"
                    placeholder="e.g. Admitted at Winneba Trauma Hospital with malaria"></textarea>
        </div>
        <button class="btn" type="submit">Submit request</button>
      </form>
      <div class="note">
        Leave cannot be backdated by more than
        <?= e((string) $db->scalar("SELECT fn_get_setting('leave.max_backdate_days')")) ?>
        days, and cannot overlap a request you already have pending or approved.
      </div>
    </div>
  </div>

  <div class="card">
    <h2>My requests <span class="sub"><?= count($rows) ?> in total</span></h2>
    <?php if (!$rows): ?>
      <div class="empty"><strong>No requests yet</strong>Submitted requests appear here.</div>
    <?php else: ?>
    <div class="table-scroll">
      <table class="data">
        <thead><tr><th>Type</th><th>Dates</th><th class="num">Days</th><th>Status</th><th>Actioned by</th></tr></thead>
        <tbody>
        <?php foreach ($rows as $r): ?>
          <tr>
            <td><?= e($r['leave_type']) ?><br><span class="sub"><?= e($r['reason']) ?></span></td>
            <td><?= fmtDate($r['start_date'], 'd M') ?> &ndash; <?= fmtDate($r['end_date']) ?></td>
            <td class="num"><?= (int) $r['days_requested'] ?></td>
            <td><span class="badge <?= match ($r['status']) {
                  'Approved' => 'ok', 'Rejected' => 'bad', 'Cancelled' => 'muted', default => 'warn' } ?>">
              <?= e($r['status']) ?></span></td>
            <td>
              <?= e($r['approved_by_name'] ?? '-') ?>
              <?php if ($r['remarks']): ?><br><span class="sub"><?= e($r['remarks']) ?></span><?php endif; ?>
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

<?php require __DIR__ . '/../includes/footer.php'; ?>
