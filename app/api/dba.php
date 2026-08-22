<?php
/** SCAS API - DBA console (system administrator). */
declare(strict_types=1);

require_once __DIR__ . '/jwt.php';
require_once __DIR__ . '/../lib/Auth.php';

$user = require_api_auth();
require_api_privilege($user, PRIV_SYS_ADMIN);
$db = Database::get();
$tab = api_str(api_input(), 'tab', 'overview', 20);

try {
    if ($_SERVER['REQUEST_METHOD'] === 'POST') {
        $in = api_input();
        $action = api_str($in, 'action', '', 30);

        if ($action === 'explain') {
            $userSql = trim((string) ($in['sql'] ?? ''));
            if (!preg_match('/^\s*(SELECT|WITH)\b/i', $userSql)) {
                send_json_response(['status' => 'error', 'message' => 'Only SELECT (or WITH ... SELECT) statements can be explained here.'], 400);
            }
            if (str_contains($userSql, ';')) {
                send_json_response(['status' => 'error', 'message' => 'Remove the semicolon: only one statement at a time.'], 400);
            }
            $rows = $db->explain($userSql);
            send_json_response(['status' => 'success', 'data' => $rows]);
        }

        if ($action === 'demo_savepoint') {
            send_json_response(['status' => 'success', 'data' => $db->callProcRows('sp_demo_savepoint')]);
        }
        if ($action === 'demo_consistency') {
            send_json_response(['status' => 'success', 'data' => $db->callProcRows('sp_demo_consistency')]);
        }
        if ($action === 'restore_setting') {
            $db->callProc('sp_restore_setting_as_of', [
                api_str($in, 'setting_key', '', 60),
                api_str($in, 'as_of', '', 30),
            ]);
            send_json_response(['status' => 'success', 'message' => 'Setting restored from the temporal history.']);
        }

        send_json_response(['status' => 'error', 'message' => 'Unknown action.'], 400);
    }

    if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
        send_json_response(['status' => 'error', 'message' => 'Method not allowed.'], 405);
    }

    if ($tab === 'indexes') {
        send_json_response([
            'status'    => 'success',
            'tab'       => $tab,
            'indexes'   => $db->all('SELECT * FROM v_index_inventory', [], 'api dba: indexes'),
            'redundant' => $db->all('SELECT * FROM v_redundant_indexes', [], 'api dba: redundant'),
        ]);
    }

    if ($tab === 'integrity') {
        send_json_response([
            'status' => 'success',
            'tab'    => $tab,
            'checks' => $db->callProcRows('sp_run_integrity_check'),
        ]);
    }

    if ($tab === 'transactions') {
        send_json_response([
            'status' => 'success',
            'tab'    => $tab,
            'locks'  => $db->callProcRows('sp_show_locks'),
        ]);
    }

    if ($tab === 'recovery') {
        send_json_response([
            'status'   => 'success',
            'tab'      => $tab,
            'recovery' => $db->callProcRows('sp_recovery_report'),
            'settings' => $db->all(
                'SELECT setting_key, setting_value, data_type, description, updated_by
                 FROM system_setting ORDER BY setting_key',
                [],
                'api dba: settings'
            ),
        ]);
    }

    if ($tab === 'performance') {
        send_json_response([
            'status' => 'success',
            'tab'    => $tab,
            'slow'   => $db->all(
                'SELECT log_id, query_label, exec_ms, rows_returned, executed_by, executed_at,
                        LEFT(sql_text, 400) AS sql_text
                 FROM query_performance_log ORDER BY executed_at DESC LIMIT 100',
                [],
                'api dba: slow'
            ),
            'worst'  => $db->all(
                'SELECT query_label, COUNT(*) AS occurrences,
                        ROUND(AVG(exec_ms), 1) AS avg_ms, ROUND(MAX(exec_ms), 1) AS max_ms
                 FROM query_performance_log GROUP BY query_label ORDER BY avg_ms DESC LIMIT 20',
                [],
                'api dba: worst'
            ),
        ]);
    }

    $objects = $db->all(
        "SELECT 'tables' AS object_type, COUNT(*) AS count FROM information_schema.TABLES
          WHERE TABLE_SCHEMA = 'scas_db' AND TABLE_TYPE <> 'VIEW'
         UNION ALL SELECT 'views',      COUNT(*) FROM information_schema.VIEWS    WHERE TABLE_SCHEMA = 'scas_db'
         UNION ALL SELECT 'procedures', COUNT(*) FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA = 'scas_db' AND ROUTINE_TYPE = 'PROCEDURE'
         UNION ALL SELECT 'functions',  COUNT(*) FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA = 'scas_db' AND ROUTINE_TYPE = 'FUNCTION'
         UNION ALL SELECT 'triggers',   COUNT(*) FROM information_schema.TRIGGERS WHERE TRIGGER_SCHEMA = 'scas_db'
         UNION ALL SELECT 'events',     COUNT(*) FROM information_schema.EVENTS   WHERE EVENT_SCHEMA = 'scas_db'",
        [],
        'api dba: inventory'
    );
    $sizes = $db->all(
        "SELECT TABLE_NAME, ENGINE, TABLE_ROWS,
                ROUND((DATA_LENGTH) / 1024, 1)  AS data_kb,
                ROUND((INDEX_LENGTH) / 1024, 1) AS index_kb
         FROM information_schema.TABLES
         WHERE TABLE_SCHEMA = 'scas_db' AND TABLE_TYPE <> 'VIEW'
         ORDER BY (DATA_LENGTH + INDEX_LENGTH) DESC",
        [],
        'api dba: sizes'
    );

    send_json_response([
        'status'  => 'success',
        'tab'     => 'overview',
        'objects' => $objects,
        'sizes'   => $sizes,
    ]);
} catch (DatabaseException $e) {
    send_json_response(['status' => 'error', 'message' => $e->getMessage()], 400);
} catch (Throwable $e) {
    send_json_response(['status' => 'error', 'message' => $e->getMessage()], 500);
}
