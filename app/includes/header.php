<?php
/**
 * SCAS - page chrome. Expects $pageTitle, optionally $pageDesc and
 * $pageActions, and $currentPage (set by the front controller).
 */
declare(strict_types=1);

$user        = Auth::user();
$currentPage = $currentPage ?? 'dashboard';
$priv        = Auth::privilege();

/**
 * The navigation is built from the same privilege levels the database
 * enforces. Hiding a link is a courtesy, not a control: the front controller
 * re-checks the privilege on every request, and the database refuses the
 * underlying operation regardless of what the browser sends.
 */
$navGroups = [
    'Attendance' => array_filter([
        'dashboard'     => ['Dashboard', 0],
        'checkin'       => ['Check in', 0, 'teacherOnly' => true],
        'my_attendance' => ['My attendance', 0, 'teacherOnly' => true],
        'my_timetable'  => ['My timetable', 0, 'teacherOnly' => true],
        'board'         => ['Live board', PRIV_HEADTEACHER],
        'qrcodes'       => ['Session codes', PRIV_HEADTEACHER],
    ]),
    'People' => [
        'leave'      => ['My leave', 0],
        'approvals'  => ['Leave approvals', PRIV_HEADTEACHER],
        'teachers'   => ['Staff directory', PRIV_HEADTEACHER],
        'timetable'  => ['Timetable', PRIV_SCHOOL_ADMIN],
        'users'      => ['User accounts', PRIV_SCHOOL_ADMIN],
    ],
    'Insight' => [
        'reports'  => ['Reports', PRIV_HEADTEACHER],
        'audit'    => ['Audit trail', PRIV_SCHOOL_ADMIN],
        'security' => ['Security', PRIV_SCHOOL_ADMIN],
        'dba'      => ['DBA console', PRIV_SYS_ADMIN],
    ],
];

$unread = 0;
try {
    $unread = (int) Database::get()->scalar(
        'SELECT COUNT(*) FROM notification WHERE user_id = ? AND is_read = 0',
        [Auth::userId()]
    );
} catch (Throwable) {
    $unread = 0;
}
?>
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title><?= e($pageTitle ?? 'SCAS') ?> &middot; <?= e(APP_SHORT) ?></title>
<link rel="stylesheet" href="<?= e(APP_BASE_URL) ?>assets/app.css?v=<?= e(APP_VERSION) ?>">
<link rel="icon" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 32 32'><rect width='32' height='32' rx='6' fill='%230f4c81'/><text x='16' y='22' font-size='15' font-family='sans-serif' font-weight='bold' fill='white' text-anchor='middle'>S</text></svg>">
</head>
<body>

<header class="masthead">
  <div class="masthead-inner">
    <div class="logo"><span class="mark">SCAS</span></div>
    <div class="school">
      <?= e($user['school_name'] ?? 'All schools') ?>
      <?php if (!empty($user['role_name'])): ?>
        &middot; <?= e($user['role_name']) ?>
      <?php endif; ?>
    </div>
    <div class="spacer"></div>
    <?php if ($unread > 0): ?>
      <a class="signout" href="<?= e(url('notifications')) ?>"><?= $unread ?> new</a>
    <?php endif; ?>
    <div class="who">
      <strong><?= e($user['full_name'] ?? '') ?></strong>
      <span><?= e($user['username'] ?? '') ?></span>
    </div>
    <a class="signout" href="<?= e(url('profile')) ?>">Account</a>
    <a class="signout" href="<?= e(APP_BASE_URL) ?>logout.php">Sign out</a>
  </div>
</header>

<nav class="nav">
  <div class="nav-inner">
    <?php foreach ($navGroups as $groupName => $items): ?>
      <?php
        $visible = [];
        foreach ($items as $key => $spec) {
            $needed      = $spec[1];
            $teacherOnly = $spec['teacherOnly'] ?? false;
            if ($teacherOnly && !Auth::isTeacher()) {
                continue;
            }
            if ($priv < $needed) {
                continue;
            }
            $visible[$key] = $spec[0];
        }
        if (!$visible) {
            continue;
        }
      ?>
      <span class="group-label"><?= e($groupName) ?></span>
      <?php foreach ($visible as $key => $label): ?>
        <a href="<?= e(url($key)) ?>" class="<?= $currentPage === $key ? 'active' : '' ?>"><?= e($label) ?></a>
      <?php endforeach; ?>
    <?php endforeach; ?>
  </div>
</nav>

<main class="wrap">
  <?php foreach (Flash::drain() as $flash): ?>
    <div class="alert <?= e($flash['type']) ?>"><?= e($flash['message']) ?></div>
  <?php endforeach; ?>

  <?php if (!empty($pageTitle)): ?>
  <div class="page-head">
    <div>
      <h1><?= e($pageTitle) ?></h1>
      <?php if (!empty($pageDesc)): ?><p><?= e($pageDesc) ?></p><?php endif; ?>
    </div>
    <?php if (!empty($pageActions)): ?>
      <div class="actions no-print"><?= $pageActions ?></div>
    <?php endif; ?>
  </div>
  <?php endif; ?>
