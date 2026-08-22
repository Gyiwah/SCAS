<?php
/** SCAS API - staff directory (headteacher+). */
declare(strict_types=1);

require_once __DIR__ . '/jwt.php';
require_once __DIR__ . '/../lib/Auth.php';

if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    send_json_response(['status' => 'error', 'message' => 'Method not allowed.'], 405);
}

$user = require_api_auth();
require_api_privilege($user, PRIV_HEADTEACHER);
$db = Database::get();

$search = api_str([], 'q', '', 60);
$dept   = api_str([], 'dept', '', 60);
$from   = preg_match('/^\d{4}-\d{2}-\d{2}$/', api_str([], 'from', '')) ? api_str([], 'from') : date('Y-m-01');
$to     = preg_match('/^\d{4}-\d{2}-\d{2}$/', api_str([], 'to', '')) ? api_str([], 'to') : date('Y-m-d');

try {
    $sql = 'SELECT teacher_id, staff_number, full_name, department, qualification,
                   date_employed, employment_status, email, phone_masked,
                   school_name, years_of_service, is_active
            FROM v_my_school_teachers WHERE 1 = 1';
    $args = [];
    if ($search !== '') {
        $sql .= ' AND (full_name LIKE ? OR staff_number LIKE ?)';
        $args[] = '%' . $search . '%';
        $args[] = '%' . $search . '%';
    }
    if ($dept !== '') {
        $sql .= ' AND department = ?';
        $args[] = $dept;
    }
    $sql .= ' ORDER BY full_name';

    $teachers = $db->all($sql, $args, 'api teachers');

    $statsRows = $db->all(
        'SELECT teacher_id,
                SUM(present_count) AS present_count,
                SUM(late_count)    AS late_count,
                SUM(absent_count)  AS absent_count,
                SUM(sessions_recorded) AS sessions
         FROM v_monthly_attendance_summary
         WHERE (session_year * 100 + session_month) BETWEEN ? AND ?
         GROUP BY teacher_id',
        [(int) date('Ym', strtotime($from)), (int) date('Ym', strtotime($to))],
        'api teachers: stats'
    );
    $stats = [];
    foreach ($statsRows as $s) {
        $stats[(int) $s['teacher_id']] = $s;
    }

    $departments = $db->all(
        'SELECT DISTINCT department FROM v_my_school_teachers ORDER BY department',
        [],
        'api teachers: depts'
    );

    send_json_response([
        'status'       => 'success',
        'from'         => $from,
        'to'           => $to,
        'departments'  => $departments,
        'stats'        => $stats,
        'data'         => $teachers,
    ]);
} catch (Throwable $e) {
    send_json_response(['status' => 'error', 'message' => $e->getMessage()], 500);
}
