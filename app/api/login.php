<?php
/**
 * SCAS - REST API Login Endpoint.
 */
declare(strict_types=1);

require_once __DIR__ . '/jwt.php';
require_once __DIR__ . '/../lib/Auth.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    send_json_response(['status' => 'error', 'message' => 'Method not allowed. Use POST.'], 405);
}

$rawInput = file_get_contents('php://input');
$input = json_decode($rawInput, true);

if (!is_array($input)) {
    $input = $_POST;
}

$username = trim((string)($input['username'] ?? ''));
$password = (string)($input['password'] ?? '');

if ($username === '' || $password === '') {
    send_json_response([
        'status' => 'error',
        'message' => 'Both username and password are required.'
    ], 400);
}

$db    = Database::get();
$ip    = Auth::clientIp();
$agent = mb_substr($_SERVER['HTTP_USER_AGENT'] ?? 'SCAS-Mobile-App', 0, 200);

$usernameLower = mb_strtolower($username);

$res = $db->callProc(
    'sp_authenticate_start',
    [$usernameLower, $ip],
    ['user_id', 'password_hash', 'state']
);

$state = $res['state'] ?? 'NOT_FOUND';

if ($state === 'LOCKED') {
    send_json_response([
        'status' => 'error',
        'message' => 'This account is temporarily locked after repeated failed sign-in attempts.'
    ], 403);
}

if ($state === 'INACTIVE') {
    send_json_response([
        'status' => 'error',
        'message' => 'This account has been deactivated. Please contact your administrator.'
    ], 403);
}

if ($state !== 'OK' || empty($res['password_hash'])) {
    password_verify($password, '$2y$10$usesomesillystringfoxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx');
    $db->callProc('sp_login_failure', [$usernameLower, $ip, $agent]);
    send_json_response(['status' => 'error', 'message' => 'Invalid username or password.'], 401);
}

if (!password_verify($password, $res['password_hash'])) {
    $db->callProc('sp_login_failure', [$usernameLower, $ip, $agent]);
    send_json_response(['status' => 'error', 'message' => 'Invalid username or password.'], 401);
}

$userId = (int)$res['user_id'];

// Elevate context to query user profile details
$db->setSessionContext($userId, null, PRIV_SYS_ADMIN);

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
    'api login profile'
);

if ($profile === null) {
    send_json_response(['status' => 'error', 'message' => 'User profile not found.'], 404);
}

$db->callProc('sp_login_success', [$userId, $ip, $agent]);

// Generate JWT payload
$jwtPayload = [
    'user_id'               => (int)$profile['user_id'],
    'full_name'             => $profile['full_name'],
    'username'              => $profile['username'],
    'school_id'             => $profile['school_id'] === null ? null : (int)$profile['school_id'],
    'school_name'           => $profile['school_name'],
    'teacher_id'            => $profile['teacher_id'] === null ? null : (int)$profile['teacher_id'],
    'staff_number'          => $profile['staff_number'],
    'role_id'               => (int)$profile['role_id'],
    'role_name'             => $profile['role_name'],
    'privilege_level'       => (int)$profile['privilege_level'],
    'privilege'             => (int)$profile['privilege_level'],
    'department'            => $profile['department'],
    'must_change_password'  => (int)($profile['must_change_password'] ?? 0),
    'last_login_at'         => $profile['last_login_at'],
];

$token = jwt_encode($jwtPayload);

send_json_response([
    'status'  => 'success',
    'message' => 'Signed in successfully.',
    'token'   => $token,
    'user'    => $jwtPayload
]);
