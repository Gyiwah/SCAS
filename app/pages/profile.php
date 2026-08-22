<?php
/**
 * SCAS - the signed-in user's own account.
 *
 * Changing a password requires proving the current one. The check runs the
 * same way as sign-in: fetch the stored hash through sp_authenticate_start
 * and compare with password_verify(). The plaintext never reaches the
 * database, and the new hash is produced here.
 */
declare(strict_types=1);

$db   = Database::get();
$user = Auth::user();

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $current = (string) ($_POST['current_password'] ?? '');
    $new     = (string) ($_POST['new_password'] ?? '');
    $confirm = (string) ($_POST['confirm_password'] ?? '');

    try {
        if (strlen($new) < 8) {
            throw new DatabaseException('The new password must be at least 8 characters long.');
        }
        if ($new !== $confirm) {
            throw new DatabaseException('The two new passwords do not match.');
        }
        if ($new === $current) {
            throw new DatabaseException('The new password must be different from the current one.');
        }

        $check = $db->callProc(
            'sp_authenticate_start',
            [$user['username'], Auth::clientIp()],
            ['user_id', 'password_hash', 'state']
        );

        if (($check['state'] ?? '') !== 'OK'
            || !password_verify($current, (string) $check['password_hash'])) {
            throw new DatabaseException('Your current password is not correct.');
        }

        $db->callProc('sp_change_password', [
            Auth::userId(),
            password_hash($new, PASSWORD_BCRYPT, ['cost' => 10]),
            Auth::clientIp(),
        ]);

        $_SESSION['user']['must_change_password'] = 0;
        Flash::add('success', 'Your password has been changed.');
    } catch (DatabaseException $ex) {
        Flash::add('danger', $ex->getMessage());
    }
    header('Location: ' . url('profile'));
    exit;
}

$recent = $db->all(
    'SELECT event_type, ip_address, detail, occurred_at
     FROM security_event WHERE user_id = ?
     ORDER BY occurred_at DESC LIMIT 15',
    [Auth::userId()],
    'profile: my security events'
);

$pageTitle = 'My account';
$pageDesc  = 'Your details and recent sign-in activity.';

require __DIR__ . '/../includes/header.php';
?>

<?php if (!empty($user['must_change_password'])): ?>
  <div class="alert warning">
    <strong>Choose a new password</strong>
    This account is still using the password issued by your administrator.
  </div>
<?php endif; ?>

<div class="grid grid-2">
  <div class="card">
    <h2>Details</h2>
    <div class="table-scroll">
      <table class="data">
        <tbody>
          <tr><th>Name</th><td><?= e($user['full_name']) ?></td></tr>
          <tr><th>Username</th><td class="mono"><?= e($user['username']) ?></td></tr>
          <tr><th>Role</th><td><?= e($user['role_name']) ?>
              <span class="sub">(privilege level <?= (int) $user['privilege_level'] ?>)</span></td></tr>
          <tr><th>School</th><td><?= e($user['school_name'] ?? 'All schools') ?></td></tr>
          <?php if (!empty($user['staff_number'])): ?>
            <tr><th>Staff number</th><td class="mono"><?= e($user['staff_number']) ?></td></tr>
            <tr><th>Department</th><td><?= e($user['department']) ?></td></tr>
          <?php endif; ?>
          <tr><th>Previous sign-in</th><td><?= $user['last_login_at'] ? fmtDateTime($user['last_login_at']) : 'first session' ?></td></tr>
        </tbody>
      </table>
    </div>
  </div>

  <div class="card">
    <h2>Change password</h2>
    <div class="card-body">
      <form method="post">
        <?= Auth::csrfField() ?>
        <div class="field">
          <label for="current_password">Current password</label>
          <input type="password" id="current_password" name="current_password" required maxlength="200">
        </div>
        <div class="field">
          <label for="new_password">New password <span class="hint">&mdash; at least 8 characters</span></label>
          <input type="password" id="new_password" name="new_password" required minlength="8" maxlength="200">
        </div>
        <div class="field">
          <label for="confirm_password">Confirm new password</label>
          <input type="password" id="confirm_password" name="confirm_password" required minlength="8" maxlength="200">
        </div>
        <button class="btn" type="submit">Change password</button>
      </form>
      <div class="note">
        Passwords are stored only as bcrypt hashes. Nobody, including the
        system administrator, can read your password out of the database.
      </div>
    </div>
  </div>
</div>

<div class="card">
  <h2>My recent security events</h2>
  <?php if (!$recent): ?>
    <div class="empty">No events recorded.</div>
  <?php else: ?>
  <div class="table-scroll">
    <table class="data">
      <thead><tr><th>When</th><th>Event</th><th>IP</th><th>Detail</th></tr></thead>
      <tbody>
      <?php foreach ($recent as $r): ?>
        <tr>
          <td><?= fmtDateTime($r['occurred_at']) ?></td>
          <td class="mono"><?= e($r['event_type']) ?></td>
          <td class="mono"><?= e($r['ip_address'] ?? '-') ?></td>
          <td><?= e($r['detail']) ?></td>
        </tr>
      <?php endforeach; ?>
      </tbody>
    </table>
  </div>
  <?php endif; ?>
</div>

<?php require __DIR__ . '/../includes/footer.php'; ?>
