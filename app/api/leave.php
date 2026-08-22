<?php
/**
 * SCAS API - teacher leave requests. Mirrors pages/leave.php.
 */
declare(strict_types=1);

require_once __DIR__ . '/jwt.php';
require_once __DIR__ . '/../lib/Auth.php';

$user = require_api_auth();
require_api_teacher($user);
$db = Database::get();

try {
    if ($_SERVER['REQUEST_METHOD'] === 'POST') {
        $in = api_input();
        $out = $db->callProc(
            'sp_submit_leave_request',
            [
                (int) $user['teacher_id'],
                api_str($in, 'leave_type', 'Casual', 20),
                api_str($in, 'start_date', date('Y-m-d'), 10),
                api_str($in, 'end_date', date('Y-m-d'), 10),
                api_str($in, 'reason', '', 150),
            ],
            ['request_id']
        );
        send_json_response([
            'status'  => 'success',
            'message' => 'Request submitted. Your headteacher has been notified.',
            'data'    => $out,
        ]);
    }

    if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
        send_json_response(['status' => 'error', 'message' => 'Method not allowed.'], 405);
    }

    $rows = $db->all(
        'SELECT leave_request_id, leave_type, start_date, end_date, days_requested,
                reason, status, requested_at, actioned_at, remarks, approved_by_name
         FROM v_leave_history WHERE teacher_id = ?
         ORDER BY requested_at DESC',
        [(int) $user['teacher_id']],
        'api: my leave'
    );

    $maxBackdate = $db->scalar("SELECT fn_get_setting('leave.max_backdate_days')");

    send_json_response([
        'status'           => 'success',
        'max_backdate_days'=> $maxBackdate,
        'data'             => $rows,
    ]);
} catch (DatabaseException $e) {
    send_json_response(['status' => 'error', 'message' => $e->getMessage()], 400);
} catch (Throwable $e) {
    send_json_response(['status' => 'error', 'message' => $e->getMessage()], 500);
}
