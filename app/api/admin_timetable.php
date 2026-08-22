<?php
/** SCAS API - school timetable administration (school admin+). */
declare(strict_types=1);

require_once __DIR__ . '/jwt.php';
require_once __DIR__ . '/../lib/Auth.php';

$user = require_api_auth();
require_api_privilege($user, PRIV_SCHOOL_ADMIN);
$db     = Database::get();
$priv   = (int) ($user['privilege_level'] ?? 0);
$scoped = $priv < PRIV_SYS_ADMIN ? 1 : 0;
$schoolId = isset($user['school_id']) ? (int) $user['school_id'] : null;

try {
    if ($_SERVER['REQUEST_METHOD'] === 'POST') {
        $in = api_input();
        $action = api_str($in, 'action', '', 20);
        if ($action === 'create') {
            $db->callProc('sp_create_timetable_session', [
                api_int($in, 'teacher_id'),
                api_int($in, 'classroom_id'),
                api_int($in, 'term_id'),
                api_str($in, 'subject', '', 60),
                api_str($in, 'class_group', '', 30),
                api_str($in, 'day_of_week', 'Monday', 10),
                api_str($in, 'start_time', '07:30', 8),
                api_str($in, 'end_time', '08:40', 8),
                (int) $user['user_id'],
            ], ['timetable_id']);
            send_json_response(['status' => 'success', 'message' => 'Session added to the timetable.']);
        }
        if ($action === 'toggle') {
            $db->callProc('sp_set_timetable_active', [
                api_int($in, 'timetable_id'),
                api_int($in, 'active', 0),
                (int) $user['user_id'],
            ]);
            send_json_response(['status' => 'success', 'message' => 'Session updated.']);
        }
        send_json_response(['status' => 'error', 'message' => 'Unknown action.'], 400);
    }

    if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
        send_json_response(['status' => 'error', 'message' => 'Method not allowed.'], 405);
    }

    $rows = $db->all(
        'SELECT tt.timetable_id, tt.subject, tt.class_group, tt.day_of_week,
                tt.start_time, tt.end_time, tt.duration_minutes, tt.is_active,
                u.full_name AS teacher_name, t.staff_number, t.department,
                c.room_name, c.school_id, s.school_name, at.term_name
         FROM timetable tt
         JOIN teacher       t  ON t.teacher_id   = tt.teacher_id
         JOIN app_user      u  ON u.user_id      = t.user_id
         JOIN classroom     c  ON c.classroom_id = tt.classroom_id
         JOIN school        s  ON s.school_id    = c.school_id
         JOIN academic_term at ON at.term_id     = tt.term_id
         WHERE at.is_current = 1 AND (? = 0 OR c.school_id = ?)
         ORDER BY FIELD(tt.day_of_week, "Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday"),
                  tt.start_time, c.room_name',
        [$scoped, $schoolId],
        'api admin timetable'
    );

    $teachers = $db->all(
        'SELECT teacher_id, full_name, staff_number, department
         FROM v_my_school_teachers WHERE is_active = 1 ORDER BY full_name',
        [],
        'api admin timetable: teachers'
    );
    $classrooms = $db->all(
        'SELECT classroom_id, room_name, building, school_id FROM classroom
         WHERE is_active = 1 AND (? = 0 OR school_id = ?) ORDER BY room_name',
        [$scoped, $schoolId]
    );
    $terms = $db->all(
        'SELECT term_id, term_name, school_id FROM academic_term
         WHERE is_current = 1 AND (? = 0 OR school_id = ?)',
        [$scoped, $schoolId]
    );
    $conflicts = $db->callProcRows('sp_detect_timetable_conflicts', [$terms[0]['term_id'] ?? null]);

    send_json_response([
        'status'     => 'success',
        'data'       => $rows,
        'teachers'   => $teachers,
        'classrooms' => $classrooms,
        'terms'      => $terms,
        'conflicts'  => $conflicts,
    ]);
} catch (DatabaseException $e) {
    send_json_response(['status' => 'error', 'message' => $e->getMessage()], 400);
} catch (Throwable $e) {
    send_json_response(['status' => 'error', 'message' => $e->getMessage()], 500);
}
