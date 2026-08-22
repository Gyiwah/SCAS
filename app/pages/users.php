<?php
/**
 * SCAS - user account administration.
 *
 * The password is hashed HERE with bcrypt and only the hash is sent to the
 * database. sp_create_user rejects anything that is not a plausible hash, so
 * a plaintext password cannot be stored even by mistake.
 */
declare(strict_types=1);

$db = Database::get();

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $action = strParam('action', '', 20);
    try {
        if ($action === 'create') {
            $password = (string) ($_POST['password'] ?? '');
            if (strlen($password) < 8) {
                throw new DatabaseException('The password must be at least 8 characters long.');
            }
            $roleId = intParam('role_id', 1, 1, 4);
            if ($roleId >= 4 && Auth::privilege() < PRIV_SYS_ADMIN) {
                throw new DatabaseException('Only a system administrator may create another system administrator.');
            }

            $schoolId = Auth::privilege() >= PRIV_SYS_ADMIN
                ? (intParam('school_id', 0) ?: null)
                : Auth::schoolId();

            $out = $db->callProc('sp_create_user', [
                strParam('full_name', '', 100),
                strParam('username', '', 40),
                password_hash($password, PASSWORD_BCRYPT, ['cost' => 10]),
                $roleId,
                $schoolId,
                strParam('phone', '', 20) ?: null,
                strParam('email', '', 100) ?: null,
                strParam('staff_number', '', 20) ?: null,
                strParam('department', '', 60) ?: null,
                strParam('qualification', '', 60) ?: null,
                dateParam('date_employed', date('Y-m-d')),
            ], ['user_id', 'teacher_id']);

            Flash::add('success', 'Account created. The user must change this password at first sign-in.');
        } elseif ($action === 'toggle') {
            $db->callProc('sp_set_user_active',
                [intParam('user_id'), intParam('active', 0, 0, 1), Auth::userId()]);
            Flash::add('success', 'Account updated.');
        } elseif ($action === 'unlock') {
            $db->callProc('sp_unlock_account', [intParam('user_id'), Auth::userId()]);
            Flash::add('success', 'Account unlocked.');
        }
    } catch (DatabaseException $ex) {
        Flash::add('danger', $ex->getMessage());
    }
    header('Location: ' . url('users'));
    exit;
}

$scoped   = Auth::privilege() < PRIV_SYS_ADMIN;
$users = $db->all(
    'SELECT u.user_id, u.full_name, u.username, u.email, u.is_active,
            u.last_login_at, u.locked_until, u.failed_login_attempts,
            u.must_change_password, u.created_at,
            r.role_name, r.privilege_level, s.school_name, t.staff_number, t.department
     FROM app_user u
     JOIN user_role r ON r.role_id = u.role_id
     LEFT JOIN school  s ON s.school_id = u.school_id
     LEFT JOIN teacher t ON t.user_id   = u.user_id
     WHERE (? = 0 OR u.school_id = ?)
     ORDER BY r.privilege_level DESC, u.full_name',
    [$scoped ? 1 : 0, Auth::schoolId()],
    'users: list'
);

$roles   = $db->all('SELECT role_id, role_name, privilege_level FROM user_role ORDER BY privilege_level');
$schools = $db->all('SELECT school_id, school_name FROM school WHERE is_active = 1 ORDER BY school_name');

$pageTitle = 'User accounts';
$pageDesc  = 'Accounts are deactivated, never deleted: attendance history and the audit trail reference them, and the foreign keys enforce that.';

require __DIR__ . '/../includes/header.php';
?>

<div class="card">
  <h2>Create an account</h2>
  <div class="card-body">
    <form method="post">
      <?= Auth::csrfField() ?>
      <input type="hidden" name="action" value="create">
      <div class="form-row">
        <div class="field"><label for="full_name">Full name</label>
          <input type="text" id="full_name" name="full_name" required maxlength="100"></div>
        <div class="field"><label for="username">Username <span class="hint">&mdash; 4+ characters, no spaces</span></label>
          <input type="text" id="username" name="username" required maxlength="40"></div>
        <div class="field"><label for="password">Initial password <span class="hint">&mdash; 8+ characters</span></label>
          <input type="password" id="password" name="password" required minlength="8" maxlength="200"></div>
        <div class="field"><label for="role_id">Role</label>
          <select id="role_id" name="role_id" required>
            <?php foreach ($roles as $r):
                if ((int) $r['privilege_level'] > Auth::privilege()) { continue; } ?>
              <option value="<?= (int) $r['role_id'] ?>"><?= e($r['role_name']) ?></option>
            <?php endforeach; ?>
          </select></div>
        <?php if (!$scoped): ?>
        <div class="field"><label for="school_id">School</label>
          <select id="school_id" name="school_id">
            <option value="0">None (system administrator only)</option>
            <?php foreach ($schools as $s): ?>
              <option value="<?= (int) $s['school_id'] ?>"><?= e($s['school_name']) ?></option>
            <?php endforeach; ?>
          </select></div>
        <?php endif; ?>
        <div class="field"><label for="email">E-mail</label>
          <input type="email" id="email" name="email" maxlength="100"></div>
        <div class="field"><label for="phone">Phone</label>
          <input type="tel" id="phone" name="phone" maxlength="20"></div>
      </div>

      <div class="note">
        Fill the staff number to create a teacher record at the same time. The
        two halves are written in one transaction, so an account can never
        exist half-created.
      </div>

      <div class="form-row">
        <div class="field"><label for="staff_number">Staff number <span class="hint">&mdash; teachers only</span></label>
          <input type="text" id="staff_number" name="staff_number" maxlength="20" placeholder="GES/2026/00000"></div>
        <div class="field"><label for="department">Department</label>
          <input type="text" id="department" name="department" maxlength="60"></div>
        <div class="field"><label for="qualification">Qualification</label>
          <input type="text" id="qualification" name="qualification" maxlength="60"></div>
        <div class="field"><label for="date_employed">Date employed</label>
          <input type="date" id="date_employed" name="date_employed" value="<?= e(date('Y-m-d')) ?>"></div>
      </div>

      <button class="btn" type="submit">Create account</button>
    </form>
  </div>
</div>

<div class="card">
  <h2>Accounts <span class="sub"><?= count($users) ?> visible to you</span></h2>
  <div class="table-scroll">
    <table class="data">
      <thead><tr>
        <th>Name</th><th>Username</th><th>Role</th><th>School</th><th>Staff number</th>
        <th>Last sign-in</th><th>State</th><th class="no-print">Actions</th>
      </tr></thead>
      <tbody>
      <?php foreach ($users as $u):
          $locked = $u['locked_until'] !== null && strtotime($u['locked_until']) > time(); ?>
        <tr>
          <td><strong><?= e($u['full_name']) ?></strong>
            <?php if ($u['must_change_password']): ?><br><span class="badge warn">must change password</span><?php endif; ?>
          </td>
          <td class="mono"><?= e($u['username']) ?></td>
          <td><?= e($u['role_name']) ?> <span class="sub">(<?= (int) $u['privilege_level'] ?>)</span></td>
          <td><?= e($u['school_name'] ?? '-') ?></td>
          <td class="mono"><?= e($u['staff_number'] ?? '-') ?></td>
          <td><?= $u['last_login_at'] ? fmtDateTime($u['last_login_at']) : '<span class="sub">never</span>' ?></td>
          <td>
            <?php if (!$u['is_active']): ?>
              <span class="badge muted">inactive</span>
            <?php elseif ($locked): ?>
              <span class="badge bad">locked</span><br>
              <span class="sub">until <?= fmtDateTime($u['locked_until']) ?></span>
            <?php else: ?>
              <span class="badge ok">active</span>
              <?php if ((int) $u['failed_login_attempts'] > 0): ?>
                <br><span class="sub"><?= (int) $u['failed_login_attempts'] ?> failed attempt(s)</span>
              <?php endif; ?>
            <?php endif; ?>
          </td>
          <td class="no-print" style="white-space:nowrap">
            <?php if ((int) $u['user_id'] !== Auth::userId()): ?>
              <form method="post" style="display:inline">
                <?= Auth::csrfField() ?>
                <input type="hidden" name="action" value="toggle">
                <input type="hidden" name="user_id" value="<?= (int) $u['user_id'] ?>">
                <input type="hidden" name="active" value="<?= $u['is_active'] ? 0 : 1 ?>">
                <button class="btn small <?= $u['is_active'] ? 'danger' : 'secondary' ?>" type="submit">
                  <?= $u['is_active'] ? 'Deactivate' : 'Reactivate' ?>
                </button>
              </form>
              <?php if ($locked): ?>
                <form method="post" style="display:inline">
                  <?= Auth::csrfField() ?>
                  <input type="hidden" name="action" value="unlock">
                  <input type="hidden" name="user_id" value="<?= (int) $u['user_id'] ?>">
                  <button class="btn small" type="submit">Unlock</button>
                </form>
              <?php endif; ?>
            <?php else: ?>
              <span class="sub">this is you</span>
            <?php endif; ?>
          </td>
        </tr>
      <?php endforeach; ?>
      </tbody>
    </table>
  </div>
</div>

<?php require __DIR__ . '/../includes/footer.php'; ?>
