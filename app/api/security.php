<?php
/** SCAS API - security monitoring (school admin+). */
declare(strict_types=1);

require_once __DIR__ . '/jwt.php';
require_once __DIR__ . '/../lib/Auth.php';

$user = require_api_auth();
require_api_privilege($user, PRIV_SCHOOL_ADMIN);
$db = Database::get();

try {
    if ($_SERVER['REQUEST_METHOD'] === 'POST') {
        $in = api_input();
        if (api_str($in, 'action', '', 20) === 'unlock') {
            $db->callProc('sp_unlock_account', [api_int($in, 'user_id'), (int) $user['user_id']]);
            send_json_response(['status' => 'success', 'message' => 'Account unlocked.']);
        }
        send_json_response(['status' => 'error', 'message' => 'Unknown action.'], 400);
    }

    if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
        send_json_response(['status' => 'error', 'message' => 'Method not allowed.'], 405);
    }

    $hours = max(1, min(720, api_int([], 'hours', 24)));
    $type  = api_str([], 'type', '', 30);

    $sql  = 'SELECT event_id, event_type, username_attempted, user_id, ip_address,
                    detail, severity, occurred_at
             FROM security_event
             WHERE occurred_at >= NOW() - INTERVAL ? HOUR';
    $args = [$hours];
    if ($type !== '') {
        $sql .= ' AND event_type = ?';
        $args[] = $type;
    }
    $sql .= ' ORDER BY occurred_at DESC LIMIT 300';

    $events = $db->all($sql, $args, 'api security: events');
    $summary = $db->all(
        'SELECT event_type, severity, COUNT(*) AS occurrences, MAX(occurred_at) AS latest
         FROM security_event WHERE occurred_at >= NOW() - INTERVAL ? HOUR
         GROUP BY event_type, severity ORDER BY occurrences DESC',
        [$hours],
        'api security: summary'
    );
    $dashboard = $db->all(
        'SELECT * FROM v_security_dashboard ORDER BY failed_24h DESC, username LIMIT 40',
        [],
        'api security: dashboard'
    );
    $locked = $db->all(
        'SELECT user_id, full_name, username, locked_until, failed_login_attempts
         FROM app_user WHERE locked_until IS NOT NULL AND locked_until > NOW()
         ORDER BY locked_until DESC',
        [],
        'api security: locked'
    );

    send_json_response([
        'status'    => 'success',
        'hours'     => $hours,
        'events'    => $events,
        'summary'   => $summary,
        'dashboard' => $dashboard,
        'locked'    => $locked,
    ]);
} catch (DatabaseException $e) {
    send_json_response(['status' => 'error', 'message' => $e->getMessage()], 400);
} catch (Throwable $e) {
    send_json_response(['status' => 'error', 'message' => $e->getMessage()], 500);
}
