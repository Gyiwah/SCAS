<?php
/** SCAS API - live session board (headteacher+). */
declare(strict_types=1);

require_once __DIR__ . '/jwt.php';
require_once __DIR__ . '/../lib/Auth.php';

if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    send_json_response(['status' => 'error', 'message' => 'Method not allowed.'], 405);
}

$user = require_api_auth();
require_api_privilege($user, PRIV_HEADTEACHER);
$db = Database::get();

try {
    $rows = $db->all(
        'SELECT * FROM v_live_session_board ORDER BY start_time, room_name',
        [],
        'api board'
    );

    $counts = ['Present' => 0, 'Late' => 0, 'No Scan' => 0, 'On Leave' => 0, 'Absent' => 0, 'Excused' => 0];
    $running = 0;
    foreach ($rows as $r) {
        $state = $r['attendance_state'] ?? '';
        if (isset($counts[$state])) {
            $counts[$state]++;
        }
        if (($r['session_state'] ?? '') === 'In Progress') {
            $running++;
        }
    }

    send_json_response([
        'status'  => 'success',
        'date'    => date('Y-m-d'),
        'counts'  => $counts,
        'running' => $running,
        'data'    => $rows,
    ]);
} catch (Throwable $e) {
    send_json_response(['status' => 'error', 'message' => $e->getMessage()], 500);
}
