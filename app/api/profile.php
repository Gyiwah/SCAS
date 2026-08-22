<?php
/**
 * SCAS API - signed-in account: details, password change, recent security events.
 */
declare(strict_types=1);

require_once __DIR__ . '/jwt.php';
require_once __DIR__ . '/../lib/Auth.php';

$user = require_api_auth();
$db   = Database::get();
$userId = (int) $user['user_id'];

try {
    if ($_SERVER['REQUEST_METHOD'] === 'POST') {
        $in      = api_input();
        $current = (string) ($in['current_password'] ?? '');
        $new     = (string) ($in['new_password'] ?? '');
        $confirm = (string) ($in['confirm_password'] ?? '');

        if (strlen($new) < 8) {
            send_json_response(['status' => 'error', 'message' => 'The new password must be at least 8 characters long.'], 400);
        }
        if ($new !== $confirm) {
            send_json_response(['status' => 'error', 'message' => 'The two new passwords do not match.'], 400);
        }
        if ($new === $current) {
            send_json_response(['status' => 'error', 'message' => 'The new password must be different from the current one.'], 400);
        }

        $check = $db->callProc(
            'sp_authenticate_start',
            [(string) $user['username'], Auth::clientIp()],
            ['user_id', 'password_hash', 'state']
        );

        if (($check['state'] ?? '') !== 'OK'
            || !password_verify($current, (string) ($check['password_hash'] ?? ''))) {
            send_json_response(['status' => 'error', 'message' => 'Your current password is not correct.'], 400);
        }

        $db->callProc('sp_change_password', [
            $userId,
            password_hash($new, PASSWORD_BCRYPT, ['cost' => 10]),
            Auth::clientIp(),
        ]);

        send_json_response(['status' => 'success', 'message' => 'Your password has been changed.']);
    }

    if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
        send_json_response(['status' => 'error', 'message' => 'Method not allowed.'], 405);
    }

    $profile = $db->one(
        'SELECT u.user_id, u.full_name, u.username, u.school_id, u.role_id,
                u.must_change_password, u.last_login_at,
                r.role_name, r.privilege_level,
                s.school_name,
                t.teacher_id, t.staff_number, t.department
         FROM app_user u
         JOIN user_role r ON r.role_id = u.role_id
         LEFT JOIN school  s ON s.school_id = u.school_id
         LEFT JOIN teacher t ON t.user_id   = u.user_id
         WHERE u.user_id = ?',
        [$userId],
        'api profile'
    );

    $recent = $db->all(
        'SELECT event_type, ip_address, detail, occurred_at
         FROM security_event WHERE user_id = ?
         ORDER BY occurred_at DESC LIMIT 15',
        [$userId],
        'api profile: security events'
    );

    send_json_response([
        'status' => 'success',
        'user'   => $profile,
        'events' => $recent,
    ]);
} catch (DatabaseException $e) {
    send_json_response(['status' => 'error', 'message' => $e->getMessage()], 400);
} catch (Throwable $e) {
    send_json_response(['status' => 'error', 'message' => $e->getMessage()], 500);
}
