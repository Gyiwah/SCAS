<?php
/**
 * SCAS API - dashboard. Same teacher / headteacher queries as pages/dashboard.php.
 */
declare(strict_types=1);

require_once __DIR__ . '/jwt.php';
require_once __DIR__ . '/../lib/Auth.php';

if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    send_json_response(['status' => 'error', 'message' => 'Method not allowed.'], 405);
}

$user = require_api_auth();
$db   = Database::get();
$priv = (int) ($user['privilege_level'] ?? 0);
$today = date('Y-m-d');
$out = [
    'status' => 'success',
    'date'   => $today,
    'teacher' => null,
    'school'  => null,
];

try {
    if (!empty($user['teacher_id'])) {
        $sessions = $db->all(
            "SELECT vt.timetable_id, vt.subject, vt.class_group, vt.room_name,
                    vt.start_time, vt.end_time,
                    a.status, a.scan_datetime, a.minutes_late,
                    q.qr_code_id,
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
            'api dashboard: my sessions'
        );

        $stats = $db->one(
            "SELECT COUNT(*) AS sessions,
                    SUM(status = 'Present') AS present_count,
                    SUM(status = 'Late')    AS late_count,
                    SUM(status = 'Absent')  AS absent_count,
                    SUM(status = 'Excused') AS excused_count,
                    fn_attendance_rate(?, ?, ?) AS rate
             FROM v_my_attendance
             WHERE session_date BETWEEN ? AND ?",
            [(int) $user['teacher_id'], date('Y-m-01'), $today, date('Y-m-01'), $today],
            'api dashboard: my month'
        );

        $out['teacher'] = ['sessions' => $sessions, 'stats' => $stats];
    }

    if ($priv >= PRIV_HEADTEACHER) {
        $schoolToday = $db->one(
            "SELECT COUNT(*) AS sessions,
                    SUM(attendance_state = 'Present')  AS present_count,
                    SUM(attendance_state = 'Late')     AS late_count,
                    SUM(attendance_state = 'No Scan')  AS no_scan,
                    SUM(attendance_state = 'On Leave') AS on_leave,
                    SUM(session_state = 'In Progress') AS running_now
             FROM v_live_session_board",
            [],
            'api dashboard: school today'
        );

        $unstaffed = $db->all(
            'SELECT teacher_name, subject, room_name, class_group, start_time, end_time,
                    minutes_into_session
             FROM v_unstaffed_now ORDER BY minutes_into_session DESC',
            [],
            'api dashboard: unstaffed'
        );

        $pendingLeave = (int) $db->scalar('SELECT COUNT(*) FROM v_leave_pending', [], 'api dashboard: pending leave');

        $trend = $db->all(
            'SELECT session_date, sessions_recorded, absences, lateness, absence_pct
             FROM v_absence_trend
             WHERE session_date >= ? ORDER BY session_date DESC LIMIT 14',
            [date('Y-m-d', strtotime('-21 days'))],
            'api dashboard: trend'
        );

        $worst = $db->all(
            "SELECT teacher_name, department, absent_count, late_count, attendance_rate
             FROM v_monthly_attendance_summary
             WHERE session_year = ? AND session_month = ?
             ORDER BY attendance_rate ASC, absent_count DESC LIMIT 6",
            [(int) date('Y'), (int) date('n')],
            'api dashboard: attention'
        );

        $out['school'] = [
            'today'         => $schoolToday,
            'unstaffed'     => $unstaffed,
            'pending_leave' => $pendingLeave,
            'trend'         => $trend,
            'attention'     => $worst,
        ];
    }

    send_json_response($out);
} catch (Throwable $e) {
    send_json_response(['status' => 'error', 'message' => $e->getMessage()], 500);
}
