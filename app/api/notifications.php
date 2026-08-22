<?php
/**
 * SCAS API - in-app notifications.
 */
declare(strict_types=1);

require_once __DIR__ . '/jwt.php';
require_once __DIR__ . '/../lib/Auth.php';

$user = require_api_auth();
$db   = Database::get();
$userId = (int) $user['user_id'];

try {
    if ($_SERVER['REQUEST_METHOD'] === 'POST') {
        $in = api_input();
        if (api_str($in, 'action', '', 20) === 'mark_read') {
            $db->exec('UPDATE notification SET is_read = 1 WHERE user_id = ?', [$userId]);
            send_json_response(['status' => 'success', 'message' => 'All notifications marked as read.']);
        }
        send_json_response(['status' => 'error', 'message' => 'Unknown action.'], 400);
    }

    if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
        send_json_response(['status' => 'error', 'message' => 'Method not allowed.'], 405);
    }

    $rows = $db->all(
        'SELECT notification_id, title, message, notif_type, is_read, created_at
         FROM notification WHERE user_id = ? ORDER BY created_at DESC LIMIT 100',
        [$userId],
        'api: notifications'
    );
    $unread = 0;
    foreach ($rows as $r) {
        if (!(int) $r['is_read']) {
            $unread++;
        }
    }

    send_json_response([
        'status' => 'success',
        'unread' => $unread,
        'data'   => $rows,
    ]);
} catch (Throwable $e) {
    send_json_response(['status' => 'error', 'message' => $e->getMessage()], 500);
}
