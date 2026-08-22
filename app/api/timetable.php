<?php
/**
 * SCAS API - teacher timetable.
 * ?scope=today (default) matches check-in / dashboard.
 * ?scope=week matches pages/my_timetable.php.
 */
declare(strict_types=1);

require_once __DIR__ . '/jwt.php';
require_once __DIR__ . '/../lib/Auth.php';

if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    send_json_response(['status' => 'error', 'message' => 'Method not allowed.'], 405);
}

$user = require_api_auth();
require_api_teacher($user);

$db    = Database::get();
$today = date('Y-m-d');
$scope = strtolower(api_str([], 'scope', 'today', 10));

try {
    if ($scope === 'week') {
        $rows = $db->all(
            'SELECT * FROM v_my_timetable
             ORDER BY FIELD(day_of_week, "Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday"),
                      start_time',
            [],
            'api: my timetable week'
        );
        send_json_response([
            'status'    => 'success',
            'scope'     => 'week',
            'term_name' => $rows[0]['term_name'] ?? null,
            'data'      => $rows,
        ]);
    }

    $sessions = $db->all(
        "SELECT vt.timetable_id, vt.subject, vt.class_group, vt.room_name,
                vt.start_time, vt.end_time, vt.building,
                a.status, a.minutes_late, a.scan_datetime,
                q.qr_code_id, q.expiry_datetime,
                CASE WHEN CURTIME() < vt.start_time THEN 'Upcoming'
                     WHEN CURTIME() BETWEEN vt.start_time AND vt.end_time THEN 'In Progress'
                     ELSE 'Ended' END AS session_state
         FROM v_my_timetable vt
         LEFT JOIN qr_code q
                ON q.timetable_id = vt.timetable_id AND q.session_date = ?
         LEFT JOIN attendance a
                ON a.timetable_id = vt.timetable_id AND a.session_date = ?
               AND a.teacher_id = vt.teacher_id
         WHERE vt.day_of_week = DAYNAME(?)
         ORDER BY vt.start_time",
        [$today, $today, $today],
        'api: my sessions today'
    );

    send_json_response([
        'status' => 'success',
        'scope'  => 'today',
        'date'   => $today,
        'data'   => $sessions,
    ]);
} catch (Throwable $e) {
    send_json_response(['status' => 'error', 'message' => $e->getMessage()], 500);
}
