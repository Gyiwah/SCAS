<?php
/** SCAS API - user accounts (school admin+). */
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
            $password = (string) ($in['password'] ?? '');
            if (strlen($password) < 8) {
                send_json_response(['status' => 'error', 'message' => 'The password must be at least 8 characters long.'], 400);
            }
            $roleId = api_int($in, 'role_id', 1);
            if ($roleId >= 4 && $priv < PRIV_SYS_ADMIN) {
                send_json_response(['status' => 'error', 'message' => 'Only a system administrator may create another system administrator.'], 403);
            }
            $newSchool = $priv >= PRIV_SYS_ADMIN
                ? (api_int($in, 'school_id', 0) ?: null)
                : $schoolId;

            $out = $db->callProc('sp_create_user', [
                api_str($in, 'full_name', '', 100),
                api_str($in, 'username', '', 40),
                password_hash($password, PASSWORD_BCRYPT, ['cost' => 10]),
                $roleId,
                $newSchool,
                api_str($in, 'phone', '', 20) ?: null,
                api_str($in, 'email', '', 100) ?: null,
                api_str($in, 'staff_number', '', 20) ?: null,
                api_str($in, 'department', '', 60) ?: null,
                api_str($in, 'qualification', '', 60) ?: null,
                api_str($in, 'date_employed', date('Y-m-d'), 10),
            ], ['user_id', 'teacher_id']);

            send_json_response([
                'status'  => 'success',
                'message' => 'Account created. The user must change this password at first sign-in.',
                'data'    => $out,
            ]);
        }

        if ($action === 'toggle') {
            $db->callProc('sp_set_user_active', [
                api_int($in, 'user_id'),
                api_int($in, 'active', 0),
                (int) $user['user_id'],
            ]);
            send_json_response(['status' => 'success', 'message' => 'Account updated.']);
        }

        if ($action === 'unlock') {
            $db->callProc('sp_unlock_account', [api_int($in, 'user_id'), (int) $user['user_id']]);
            send_json_response(['status' => 'success', 'message' => 'Account unlocked.']);
        }

        send_json_response(['status' => 'error', 'message' => 'Unknown action.'], 400);
    }

    if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
        send_json_response(['status' => 'error', 'message' => 'Method not allowed.'], 405);
    }

    $users = $db->all(
        'SELECT u.user_id, u.full_name, u.username, u.email, u.is_active,
                u.last_login_at, u.locked_until, u.failed_login_attempts,
                u.must_change_password, u.created_at,
                r.role_id, r.role_name, r.privilege_level, s.school_name, t.staff_number, t.department
         FROM app_user u
         JOIN user_role r ON r.role_id = u.role_id
         LEFT JOIN school  s ON s.school_id = u.school_id
         LEFT JOIN teacher t ON t.user_id   = u.user_id
         WHERE (? = 0 OR u.school_id = ?)
         ORDER BY r.privilege_level DESC, u.full_name',
        [$scoped, $schoolId],
        'api users'
    );
    $roles   = $db->all('SELECT role_id, role_name, privilege_level FROM user_role ORDER BY privilege_level');
    $schools = $db->all('SELECT school_id, school_name FROM school WHERE is_active = 1 ORDER BY school_name');

    send_json_response([
        'status'  => 'success',
        'data'    => $users,
        'roles'   => $roles,
        'schools' => $schools,
    ]);
} catch (DatabaseException $e) {
    send_json_response(['status' => 'error', 'message' => $e->getMessage()], 400);
} catch (Throwable $e) {
    send_json_response(['status' => 'error', 'message' => $e->getMessage()], 500);
}
