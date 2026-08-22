<?php
/** SCAS API - audit trail (school admin+). */
declare(strict_types=1);

require_once __DIR__ . '/jwt.php';
require_once __DIR__ . '/../lib/Auth.php';

if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    send_json_response(['status' => 'error', 'message' => 'Method not allowed.'], 405);
}

$user = require_api_auth();
require_api_privilege($user, PRIV_SCHOOL_ADMIN);
$db = Database::get();

$table  = api_str([], 'table', '', 64);
$action = api_str([], 'action_type', '', 10);
$from   = preg_match('/^\d{4}-\d{2}-\d{2}$/', api_str([], 'from', '')) ? api_str([], 'from') : date('Y-m-d', strtotime('-7 days'));
$to     = preg_match('/^\d{4}-\d{2}-\d{2}$/', api_str([], 'to', '')) ? api_str([], 'to') : date('Y-m-d');
$record = api_str([], 'record', '', 40);

try {
    $sql  = 'SELECT audit_id, changed_at, table_name, record_id, action,
                    changed_by_name, db_user, client_host, old_values, new_values
             FROM v_audit_trail
             WHERE changed_at >= ? AND changed_at < ? + INTERVAL 1 DAY';
    $args = [$from, $to];
    if ($table !== '') {
        $sql .= ' AND table_name = ?';
        $args[] = $table;
    }
    if ($action !== '') {
        $sql .= ' AND action = ?';
        $args[] = $action;
    }
    if ($record !== '') {
        $sql .= ' AND record_id = ?';
        $args[] = $record;
    }
    $sql .= ' ORDER BY changed_at DESC LIMIT 300';

    $rows = $db->all($sql, $args, 'api audit');
    $byTable = $db->all(
        'SELECT table_name, action, COUNT(*) AS entries
         FROM audit_log
         WHERE changed_at >= ? AND changed_at < ? + INTERVAL 1 DAY
         GROUP BY table_name, action ORDER BY entries DESC',
        [$from, $to],
        'api audit: summary'
    );
    $tables = $db->all('SELECT DISTINCT table_name FROM audit_log ORDER BY table_name');

    send_json_response([
        'status'  => 'success',
        'from'    => $from,
        'to'      => $to,
        'summary' => $byTable,
        'tables'  => $tables,
        'data'    => $rows,
    ]);
} catch (Throwable $e) {
    send_json_response(['status' => 'error', 'message' => $e->getMessage()], 500);
}
