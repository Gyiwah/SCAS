<?php
/** SCAS API - leave approvals (headteacher+). */
declare(strict_types=1);

require_once __DIR__ . '/jwt.php';
require_once __DIR__ . '/../lib/Auth.php';

$user = require_api_auth();
require_api_privilege($user, PRIV_HEADTEACHER);
$db = Database::get();

try {
    if ($_SERVER['REQUEST_METHOD'] === 'POST') {
        $in = api_input();
        $out = $db->callProc(
            'sp_action_leave_request',
            [
                api_int($in, 'leave_request_id'),
                api_str($in, 'decision', 'Rejected', 10),
                (int) $user['user_id'],
                api_str($in, 'remarks', '', 200),
            ],
            ['rows_corrected']
        );
        $corrected = (int) ($out['rows_corrected'] ?? 0);
        $decision = strtolower(api_str($in, 'decision', '', 10));
        send_json_response([
            'status'  => 'success',
            'message' => 'Request ' . $decision . '.'
                . ($corrected > 0
                    ? " {$corrected} attendance record(s) already marked Absent were reclassified as Excused."
                    : ''),
            'data'    => $out,
        ]);
    }

    if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
        send_json_response(['status' => 'error', 'message' => 'Method not allowed.'], 405);
    }

    $pending = $db->all(
        'SELECT * FROM v_leave_pending ORDER BY requested_at',
        [],
        'api approvals: pending'
    );
    $recent = $db->all(
        "SELECT * FROM v_leave_history
         WHERE status <> 'Pending' ORDER BY actioned_at DESC LIMIT 20",
        [],
        'api approvals: recent'
    );

    send_json_response([
        'status'  => 'success',
        'pending' => $pending,
        'recent'  => $recent,
    ]);
} catch (DatabaseException $e) {
    send_json_response(['status' => 'error', 'message' => $e->getMessage()], 400);
} catch (Throwable $e) {
    send_json_response(['status' => 'error', 'message' => $e->getMessage()], 500);
}
