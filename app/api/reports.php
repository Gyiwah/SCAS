<?php
/** SCAS API - monthly reports (headteacher+). */
declare(strict_types=1);

require_once __DIR__ . '/jwt.php';
require_once __DIR__ . '/../lib/Auth.php';

if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    send_json_response(['status' => 'error', 'message' => 'Method not allowed.'], 405);
}

$user  = require_api_auth();
require_api_privilege($user, PRIV_HEADTEACHER);
$db    = Database::get();
$priv  = (int) ($user['privilege_level'] ?? 0);
$year  = api_int([], 'year', (int) date('Y'));
$month = api_int([], 'month', (int) date('n'));
$school = api_int([], 'school_id', (int) ($user['school_id'] ?? 1));

if ($priv < PRIV_SYS_ADMIN) {
    $school = (int) ($user['school_id'] ?? $school);
}

try {
    $schools = $priv >= PRIV_SYS_ADMIN
        ? $db->all('SELECT school_id, school_name FROM school WHERE is_active = 1 ORDER BY school_name')
        : [];

    $report = $db->callProcRows('sp_monthly_attendance_report', [$school, $year, $month]);

    $ranking = $db->all(
        'SELECT teacher_name, department, sessions_recorded, present_count, late_count,
                absent_count, attendance_rate, school_rank, department_average
         FROM v_teacher_ranking WHERE school_id = ? ORDER BY school_rank LIMIT 25',
        [$school],
        'api reports: ranking'
    );

    $departments = $db->all(
        'SELECT department, teachers, sessions_recorded, absences, lateness, attendance_rate
         FROM v_department_stats WHERE school_id = ? ORDER BY attendance_rate DESC',
        [$school],
        'api reports: departments'
    );

    $trend = $db->all(
        'SELECT session_date, sessions_recorded, absences, lateness, absence_pct, absences_7day_avg
         FROM v_absence_trend WHERE school_id = ? AND session_date >= ?
         ORDER BY session_date DESC LIMIT 30',
        [$school, date('Y-m-d', strtotime('-45 days'))],
        'api reports: trend'
    );

    $schoolName = (string) $db->scalar('SELECT school_name FROM school WHERE school_id = ?', [$school]);

    send_json_response([
        'status'      => 'success',
        'school_id'   => $school,
        'school_name' => $schoolName,
        'year'        => $year,
        'month'       => $month,
        'schools'     => $schools,
        'report'      => $report,
        'ranking'     => $ranking,
        'departments' => $departments,
        'trend'       => $trend,
    ]);
} catch (Throwable $e) {
    send_json_response(['status' => 'error', 'message' => $e->getMessage()], 500);
}
