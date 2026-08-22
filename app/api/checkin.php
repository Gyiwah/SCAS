<?php
/**
 * SCAS - REST API Teacher Check-in Endpoint.
 */
declare(strict_types=1);

require_once __DIR__ . '/jwt.php';
require_once __DIR__ . '/../lib/Auth.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    send_json_response(['status' => 'error', 'message' => 'Method not allowed. Use POST.'], 405);
}

// Authenticate via Bearer Token & set DB context
$user = require_api_auth();

$userId    = (int)($user['user_id'] ?? 0);
$teacherId = isset($user['teacher_id']) ? (int)$user['teacher_id'] : null;

if ($userId <= 0) {
    send_json_response(['status' => 'error', 'message' => 'Invalid user context.'], 401);
}

$rawInput = file_get_contents('php://input');
$input = json_decode($rawInput, true);

if (!is_array($input)) {
    $input = $_POST;
}

$rawCode = trim((string)($input['code'] ?? ''));

if ($rawCode === '') {
    send_json_response([
        'status' => 'error',
        'message' => 'QR session code is required.'
    ], 400);
}

// Extract code parameter if a full URL was scanned
if (strpos($rawCode, 'code=') !== false) {
    $parsedUrl = parse_url($rawCode);
    if (isset($parsedUrl['query'])) {
        parse_str($parsedUrl['query'], $queryParams);
        if (!empty($queryParams['code'])) {
            $rawCode = trim((string)$queryParams['code']);
        }
    }
}

$db    = Database::get();
$ip    = Auth::clientIp();
$agent = mb_substr($_SERVER['HTTP_USER_AGENT'] ?? 'SCAS-Mobile-App', 0, 120);

try {
    $out = $db->callProc(
        'sp_record_attendance',
        [$userId, $rawCode, $ip, $agent],
        ['result', 'message', 'attendance_id', 'status']
    );

    $isOk = ($out['result'] ?? '') === 'OK';

    if ($isOk) {
        send_json_response([
            'status' => 'success',
            'data'   => [
                'result'            => 'OK',
                'attendance_id'     => $out['attendance_id'] ?? null,
                'attendance_status' => $out['status'] ?? 'Present',
                'status'            => $out['status'] ?? 'Present',
                'message'           => $out['message'] ?? 'Check-in recorded.'
            ]
        ], 200);
    } else {
        send_json_response([
            'status' => 'error',
            'message' => $out['message'] ?? 'Failed to record check-in.'
        ], 400);
    }
} catch (Throwable $e) {
    send_json_response([
        'status' => 'error',
        'message' => $e->getMessage()
    ], 500);
}
