<?php
/**
 * SCAS - REST API JWT Authentication Helper & Middleware.
 */
declare(strict_types=1);

require_once __DIR__ . '/../config/config.php';
require_once __DIR__ . '/../lib/Database.php';

function jwt_base64url_encode(string $data): string
{
    return rtrim(strtr(base64_encode($data), '+/', '-_'), '=');
}

function jwt_base64url_decode(string $data): string
{
    $remainder = strlen($data) % 4;
    if ($remainder > 0) {
        $data .= str_repeat('=', 4 - $remainder);
    }
    $decoded = base64_decode(strtr($data, '-_', '+/'), true);
    return $decoded === false ? '' : $decoded;
}

function jwt_encode(array $payload, int $ttl = 86400 * 7): string
{
    $header = ['typ' => 'JWT', 'alg' => 'HS256'];
    $now = time();
    $payload['iat'] = $now;
    $payload['exp'] = $now + $ttl;

    $base64Header = jwt_base64url_encode((string) json_encode($header));
    $base64Payload = jwt_base64url_encode((string) json_encode($payload));

    $signature = hash_hmac('sha256', $base64Header . '.' . $base64Payload, JWT_SECRET, true);
    $base64Signature = jwt_base64url_encode($signature);

    return $base64Header . '.' . $base64Payload . '.' . $base64Signature;
}

function jwt_decode(string $jwt): ?array
{
    $parts = explode('.', $jwt);
    if (count($parts) !== 3) {
        return null;
    }

    list($base64Header, $base64Payload, $base64Signature) = $parts;

    $signature = jwt_base64url_decode($base64Signature);
    $expectedSignature = hash_hmac('sha256', $base64Header . '.' . $base64Payload, JWT_SECRET, true);

    if (strlen($signature) !== strlen($expectedSignature) || !hash_equals($expectedSignature, $signature)) {
        return null;
    }

    $payload = json_decode(jwt_base64url_decode($base64Payload), true);
    if (!is_array($payload)) {
        return null;
    }

    if (isset($payload['exp']) && time() >= $payload['exp']) {
        return null;
    }

    return $payload;
}

function send_json_response(array $data, int $statusCode = 200): void
{
    http_response_code($statusCode);
    header('Content-Type: application/json; charset=utf-8');
    header('Access-Control-Allow-Origin: *');
    header('Access-Control-Allow-Headers: Content-Type, Authorization');
    header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
    echo json_encode($data, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
    exit;
}

// Handle CORS OPTIONS preflight request
if (($_SERVER['REQUEST_METHOD'] ?? '') === 'OPTIONS') {
    send_json_response(['status' => 'ok']);
}

function require_api_auth(): array
{
    $headers = function_exists('getallheaders') ? getallheaders() : [];
    if (!is_array($headers)) {
        $headers = [];
    }
    $authHeader = $headers['Authorization'] ?? $headers['authorization'] ?? $_SERVER['HTTP_AUTHORIZATION'] ?? '';

    if (!preg_match('/Bearer\s+(.*)$/i', $authHeader, $matches)) {
        send_json_response([
            'status' => 'error',
            'message' => 'Missing or invalid Authorization header. Expected Bearer token.'
        ], 401);
    }

    $token = trim($matches[1]);
    $payload = jwt_decode($token);

    if ($payload === null) {
        send_json_response([
            'status' => 'error',
            'message' => 'Invalid or expired authentication token.'
        ], 401);
    }

    // Set database session context so Row-Level Security (RLS) views work seamlessly
    $userId    = isset($payload['user_id']) ? (int)$payload['user_id'] : null;
    $schoolId  = isset($payload['school_id']) ? (int)$payload['school_id'] : null;
    $privilege = isset($payload['privilege_level'])
        ? (int)$payload['privilege_level']
        : (isset($payload['privilege']) ? (int)$payload['privilege'] : 0);

    Database::get()->setSessionContext($userId, $schoolId, $privilege);

    return $payload;
}

function api_input(): array
{
    $raw = file_get_contents('php://input');
    $input = json_decode((string) $raw, true);
    if (!is_array($input)) {
        $input = $_POST;
    }
    return is_array($input) ? $input : [];
}

function require_api_privilege(array $user, int $min): void
{
    $priv = (int) ($user['privilege_level'] ?? $user['privilege'] ?? 0);
    if ($priv < $min) {
        send_json_response([
            'status'  => 'error',
            'message' => 'You do not have permission to use this function.',
        ], 403);
    }
}

function require_api_teacher(array $user): void
{
    if (empty($user['teacher_id'])) {
        send_json_response([
            'status'  => 'error',
            'message' => 'This function is available only to teaching staff.',
        ], 403);
    }
}

function api_str(array $input, string $key, string $default = '', int $max = 200): string
{
    $val = trim((string) ($input[$key] ?? $_GET[$key] ?? $default));
    if ($max > 0 && mb_strlen($val) > $max) {
        $val = mb_substr($val, 0, $max);
    }
    return $val;
}

function api_int(array $input, string $key, int $default = 0): int
{
    $raw = $input[$key] ?? $_GET[$key] ?? $default;
    return (int) $raw;
}
