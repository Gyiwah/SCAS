<?php
/** SCAS API - session code issue and listing (headteacher+). */
declare(strict_types=1);

require_once __DIR__ . '/jwt.php';
require_once __DIR__ . '/../lib/Auth.php';

$user = require_api_auth();
require_api_privilege($user, PRIV_HEADTEACHER);
$db = Database::get();
$in = $_SERVER['REQUEST_METHOD'] === 'POST' ? api_input() : [];
$date = preg_match('/^\d{4}-\d{2}-\d{2}$/', api_str($in, 'date', ''))
    ? api_str($in, 'date')
    : date('Y-m-d');

try {
    if ($_SERVER['REQUEST_METHOD'] === 'POST') {
        $action = api_str($in, 'action', '', 20);
        $userId = (int) $user['user_id'];

        if ($action === 'generate') {
            $out = $db->callProc(
                'sp_generate_qr_code',
                [api_int($in, 'timetable_id'), $date, max(1, min(600, api_int($in, 'validity', 30))), $userId],
                ['qr_code_id', 'code_value']
            );
            send_json_response(['status' => 'success', 'message' => 'Session code issued.', 'data' => $out]);
        }

        if ($action === 'generate_all') {
            $validity = max(1, min(600, api_int($in, 'validity', 60)));
            $targets = $db->all(
                'SELECT vt.timetable_id
                 FROM v_active_timetable vt
                 LEFT JOIN qr_code q ON q.timetable_id = vt.timetable_id AND q.session_date = ?
                 WHERE vt.day_of_week = DAYNAME(?) AND q.qr_code_id IS NULL',
                [$date, $date]
            );
            $made = 0;
            $failed = 0;
            foreach ($targets as $t) {
                try {
                    $db->callProc(
                        'sp_generate_qr_code',
                        [(int) $t['timetable_id'], $date, $validity, $userId],
                        ['qr_code_id', 'code_value']
                    );
                    $made++;
                } catch (Throwable) {
                    $failed++;
                }
            }
            send_json_response([
                'status'  => 'success',
                'message' => "Issued {$made} code(s)" . ($failed ? ", {$failed} could not be issued." : '.'),
                'made'    => $made,
                'failed'  => $failed,
            ]);
        }

        if ($action === 'revoke') {
            $db->callProc('sp_revoke_qr_code', [
                api_int($in, 'qr_code_id'),
                api_str($in, 'reason', 'Revoked by administrator', 100),
                $userId,
            ]);
            send_json_response(['status' => 'success', 'message' => 'Code revoked. It can no longer be scanned.']);
        }

        send_json_response(['status' => 'error', 'message' => 'Unknown action.'], 400);
    }

    if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
        send_json_response(['status' => 'error', 'message' => 'Method not allowed.'], 405);
    }

    $sessions = $db->all(
        "SELECT vt.timetable_id, vt.subject, vt.class_group, vt.room_name,
                vt.teacher_name, vt.start_time, vt.end_time,
                q.qr_code_id, q.code_value, q.expiry_datetime, q.generated_datetime,
                q.is_revoked, q.revoked_reason, q.scan_count, q.max_scans,
                CASE WHEN q.qr_code_id IS NULL THEN 'Not issued'
                     ELSE fn_qr_status(q.code_value) END AS code_state,
                a.status AS attendance_status
         FROM v_active_timetable vt
         LEFT JOIN qr_code q
                ON q.timetable_id = vt.timetable_id AND q.session_date = ?
         LEFT JOIN attendance a
                ON a.timetable_id = vt.timetable_id AND a.session_date = ?
               AND a.teacher_id = vt.teacher_id
         WHERE vt.day_of_week = DAYNAME(?)
         ORDER BY vt.start_time, vt.room_name",
        [$date, $date, $date],
        'api qrcodes'
    );

    $isHoliday = (int) $db->scalar(
        'SELECT fn_is_holiday(?, ?)',
        [isset($user['school_id']) ? (int) $user['school_id'] : null, $date]
    );

    send_json_response([
        'status'     => 'success',
        'date'       => $date,
        'is_holiday' => $isHoliday === 1,
        'data'       => $sessions,
    ]);
} catch (DatabaseException $e) {
    send_json_response(['status' => 'error', 'message' => $e->getMessage()], 400);
} catch (Throwable $e) {
    send_json_response(['status' => 'error', 'message' => $e->getMessage()], 500);
}
