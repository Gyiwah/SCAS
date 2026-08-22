<?php
/**
 * SCAS - front controller.
 *
 * Every request enters here, which is what makes the access checks
 * dependable: authentication, the privilege gate and CSRF validation happen
 * once, in one place, before any page code runs. A page file cannot be
 * reached directly because pages/ contains no entry point of its own and is
 * blocked by its .htaccess.
 */

declare(strict_types=1);

require __DIR__ . '/config/config.php';
require __DIR__ . '/lib/Helpers.php';
require __DIR__ . '/lib/Database.php';
require __DIR__ . '/lib/Auth.php';
require __DIR__ . '/lib/QrCode.php';

Auth::boot();
Auth::requireLogin();
Auth::requireCsrf();

/**
 * The routing table is also the authorisation table: page => required
 * privilege level. A page that is not listed here cannot be reached at all,
 * so adding a file to pages/ does not silently expose it.
 */
const ROUTES = [
    'dashboard'     => ['file' => 'dashboard.php',     'priv' => 0],
    'checkin'       => ['file' => 'checkin.php',       'priv' => 0,                 'teacher' => true],
    'my_attendance' => ['file' => 'my_attendance.php', 'priv' => 0,                 'teacher' => true],
    'my_timetable'  => ['file' => 'my_timetable.php',  'priv' => 0,                 'teacher' => true],
    'leave'         => ['file' => 'leave.php',         'priv' => 0],
    'notifications' => ['file' => 'notifications.php', 'priv' => 0],
    'profile'       => ['file' => 'profile.php',       'priv' => 0],

    'board'         => ['file' => 'board.php',         'priv' => PRIV_HEADTEACHER],
    'qrcodes'       => ['file' => 'qrcodes.php',       'priv' => PRIV_HEADTEACHER],
    'approvals'     => ['file' => 'approvals.php',     'priv' => PRIV_HEADTEACHER],
    'teachers'      => ['file' => 'teachers.php',      'priv' => PRIV_HEADTEACHER],
    'reports'       => ['file' => 'reports.php',       'priv' => PRIV_HEADTEACHER],

    'timetable'     => ['file' => 'timetable.php',     'priv' => PRIV_SCHOOL_ADMIN],
    'users'         => ['file' => 'users.php',         'priv' => PRIV_SCHOOL_ADMIN],
    'audit'         => ['file' => 'audit.php',         'priv' => PRIV_SCHOOL_ADMIN],
    'security'      => ['file' => 'security.php',      'priv' => PRIV_SCHOOL_ADMIN],

    'dba'           => ['file' => 'dba.php',           'priv' => PRIV_SYS_ADMIN],
];

$currentPage = strParam('page', 'dashboard', 40);
if (!isset(ROUTES[$currentPage])) {
    $currentPage = 'dashboard';
}
$route = ROUTES[$currentPage];

if (!empty($route['teacher'])) {
    Auth::requireTeacher();
}
Auth::requirePrivilege($route['priv']);

// A teacher landing on the dashboard with no teacher record still works;
// pages themselves handle their own empty states.
$pageFile = __DIR__ . '/pages/' . $route['file'];
if (!is_file($pageFile)) {
    http_response_code(500);
    exit('Page not found on disk: ' . e($route['file']));
}

try {
    require $pageFile;
} catch (DatabaseException $e) {
    // A business rule raised by the database. Show it; it was written for
    // the user.
    require __DIR__ . '/includes/header.php';
    echo '<div class="alert danger"><strong>The database refused that request</strong>'
       . e($e->getMessage()) . '</div>';
    require __DIR__ . '/includes/footer.php';
} catch (Throwable $e) {
    http_response_code(500);
    $pageTitle = 'Something went wrong';
    require __DIR__ . '/includes/header.php';
    echo '<div class="alert danger"><strong>Unexpected error</strong>'
       . e(DEBUG_ERRORS ? $e->getMessage() : 'Please try again, or contact the administrator.')
       . '</div>';
    require __DIR__ . '/includes/footer.php';
}
