<?php
/**
 * SCAS API - teacher's own attendance. Same view and summary as pages/my_attendance.php.
 */
declare(strict_types=1);

require_once __DIR__ . '/jwt.php';
require_once __DIR__ . '/../lib/Auth.php';

if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    send_json_response(['status' => 'error', 'message' => 'Method not allowed.'], 405);
}

$user = require_api_auth();
require_api_teacher($user);

$from = preg_match('/^\d{4}-\d{2}-\d{2}$/', api_str([], 'from', '')) ? api_str([], 'from') : date('Y-m-01');
$to   = preg_match('/^\d{4}-\d{2}-\d{2}$/', api_str([], 'to', '')) ? api_str([], 'to') : date('Y-m-d');
$teacherId = (int) $user['teacher_id'];

$db = Database::get();

try {
    $rows = $db->all(
        'SELECT session_date, subject, class_group, room_name, start_time,
                status, minutes_late, scan_datetime, remarks
         FROM v_my_attendance
         WHERE session_date BETWEEN ? AND ?
         ORDER BY session_date DESC, start_time DESC',
        [$from, $to],
        'api: my attendance history'
    );

    $sum = $db->one(
        "SELECT COUNT(*) AS sessions,
                SUM(status='Present') AS present_count,
                SUM(status='Late')    AS late_count,
                SUM(status='Absent')  AS absent_count,
                SUM(status='Excused') AS excused_count,
                SUM(minutes_late)     AS total_late_minutes,
                fn_attendance_rate(?, ?, ?) AS rate
         FROM v_my_attendance WHERE session_date BETWEEN ? AND ?",
        [$teacherId, $from, $to, $from, $to],
        'api: my attendance summary'
    );

    send_json_response([
        'status'  => 'success',
        'from'    => $from,
        'to'      => $to,
        'summary' => $sum,
        'data'    => $rows,
    ]);
} catch (Throwable $e) {
    send_json_response(['status' => 'error', 'message' => $e->getMessage()], 500);
}
