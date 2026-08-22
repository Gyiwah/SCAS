<?php
/**
 * SCAS - sign in.
 *
 * The failure message is identical whatever went wrong (unknown user, wrong
 * password), so an attacker cannot use this page to discover which usernames
 * exist. The real reason is recorded in security_event for the administrator.
 */

declare(strict_types=1);

require __DIR__ . '/config/config.php';
require __DIR__ . '/lib/Helpers.php';
require __DIR__ . '/lib/Database.php';
require __DIR__ . '/lib/Auth.php';

Auth::boot();

if (Auth::check()) {
    header('Location: ' . url('dashboard'));
    exit;
}

$error = '';

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    Auth::requireCsrf();

    $result = Auth::login(
        strParam('username', '', 40),
        (string) ($_POST['password'] ?? '')
    );

    if ($result['ok']) {
        if (!empty($_SESSION['user']['must_change_password'])) {
            Flash::add('warning', 'Please choose a new password before continuing.');
            header('Location: ' . url('profile'));
            exit;
        }
        Flash::add('success', 'Welcome back, ' . ($_SESSION['user']['full_name'] ?? '') . '.');
        header('Location: ' . url('dashboard'));
        exit;
    }
    $error = $result['message'];
}
?>
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Sign in &middot; <?= e(APP_SHORT) ?></title>
<link rel="stylesheet" href="<?= e(APP_BASE_URL) ?>assets/app.css?v=<?= e(APP_VERSION) ?>">
</head>
<body class="login-page">

<div class="login-card">
  <div class="login-brand">
    <h1>Smart Classroom<br>Attendance System</h1>
    <div class="tag">QR-code teacher attendance for Senior High Schools</div>
    <ul>
      <li>Check in by scanning the code displayed in your classroom</li>
      <li>Codes expire, so a register cannot be signed from home</li>
      <li>Headteachers see unstaffed classes in real time</li>
      <li>Approved leave is never counted as absenteeism</li>
      <li>Every change is recorded in an audit trail</li>
    </ul>
    <div class="inst">
      University of Education, Winneba<br>
      MPhil (Information and Communication Technology)<br>
      Database Management System &mdash; ICTE825
    </div>
  </div>

  <div class="login-form">
    <h2>Sign in</h2>
    <div class="sub">Use the account issued by your school administrator.</div>

    <?php if ($error !== ''): ?>
      <div class="alert danger"><?= e($error) ?></div>
    <?php endif; ?>

    <form method="post" autocomplete="off">
      <?= Auth::csrfField() ?>
      <div class="field">
        <label for="username">Username</label>
        <input type="text" id="username" name="username" required autofocus
               maxlength="40" value="<?= e(strParam('username', '', 40)) ?>">
      </div>
      <div class="field">
        <label for="password">Password</label>
        <input type="password" id="password" name="password" required maxlength="200">
      </div>
      <button class="btn" type="submit" style="width:100%">Sign in</button>
    </form>

    <div class="demo-accounts">
      <strong>Demonstration accounts</strong>
      <table>
        <tr><td>System administrator</td><td><code>sysadmin</code></td><td><code>Sys@dmin2026</code></td></tr>
        <tr><td>Headteacher</td>         <td><code>head.winneba</code></td><td><code>Head@2026</code></td></tr>
        <tr><td>School administrator</td><td><code>admin.winneba</code></td><td><code>School@2026</code></td></tr>
        <tr><td>Teacher</td>             <td><code>k.mensah</code></td><td><code>Teach@2026</code></td></tr>
      </table>
      Five failed attempts lock an account for 15 minutes &mdash; that rule is
      enforced by the database, so it applies here too.
    </div>
  </div>
</div>

</body>
</html>
