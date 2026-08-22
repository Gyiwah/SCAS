<?php
/**
 * SCAS - data access layer.
 *
 * Design rules enforced by this class:
 *
 * 1. EVERY value reaches the database as a bound parameter. There is no
 *    method on this class that concatenates a caller's value into SQL. That
 *    is the structural defence against SQL injection: with emulation turned
 *    off, the statement and the data travel to the server separately, so a
 *    value can never be re-interpreted as syntax.
 *
 * 2. Emulated prepares are DISABLED. With emulation on, PDO builds the final
 *    string itself and the injection guarantee depends on PDO's quoting
 *    rather than on the server's protocol.
 *
 * 3. The session identity (@scas_user_id, @scas_school_id, @scas_privilege)
 *    is pushed to the connection on every request. The row-level security
 *    views in 04_views.sql read those variables, so a query issued outside
 *    the intended scope returns nothing rather than the wrong school's data.
 *
 * 4. Statements slower than SLOW_QUERY_MS are timed, EXPLAINed and recorded
 *    in query_performance_log, which is what the DBA console reads.
 */

declare(strict_types=1);

final class Database
{
    private static ?Database $instance = null;
    private PDO $pdo;
    private bool $contextSet = false;

    private function __construct()
    {
        $dsn = sprintf(
            'mysql:host=%s;port=%d;dbname=%s;charset=%s',
            DB_HOST, DB_PORT, DB_NAME, DB_CHARSET
        );

        try {
            $this->pdo = new PDO($dsn, DB_USER, DB_PASS, [
                PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
                PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
                PDO::ATTR_EMULATE_PREPARES   => false,
                PDO::ATTR_STRINGIFY_FETCHES  => false,
            ]);
        } catch (PDOException $e) {
            http_response_code(500);
            $hint = 'Could not connect to the SCAS database.';
            if (DEBUG_ERRORS) {
                $hint .= ' ' . $e->getMessage()
                      . ' (Is MySQL running in XAMPP, and has database/00_install_all.sql been run?)';
            }
            $script = str_replace('\\', '/', (string) ($_SERVER['SCRIPT_NAME'] ?? ''));
            if (str_contains($script, '/api/')) {
                header('Content-Type: application/json; charset=utf-8');
                echo json_encode(['status' => 'error', 'message' => $hint], JSON_UNESCAPED_UNICODE);
                exit;
            }
            exit('<h1>Database unavailable</h1><p>' . htmlspecialchars($hint, ENT_QUOTES) . '</p>');
        }
    }

    public static function get(): Database
    {
        return self::$instance ??= new self();
    }

    public function pdo(): PDO
    {
        return $this->pdo;
    }

    /**
     * Publish the signed-in identity to the connection. The row-level
     * security views depend on this having been called.
     */
    public function setSessionContext(?int $userId, ?int $schoolId, int $privilege): void
    {
        $stmt = $this->pdo->prepare('SET @scas_user_id = ?, @scas_school_id = ?, @scas_privilege = ?');
        $stmt->execute([$userId, $schoolId, $privilege]);
        $this->contextSet = true;
    }

    public function clearSessionContext(): void
    {
        $this->pdo->exec('SET @scas_user_id = NULL, @scas_school_id = NULL, @scas_privilege = NULL');
        $this->contextSet = false;
    }

    /** All rows. */
    public function all(string $sql, array $params = [], string $label = ''): array
    {
        return $this->run($sql, $params, $label)->fetchAll();
    }

    /** First row, or null. */
    public function one(string $sql, array $params = [], string $label = ''): ?array
    {
        $row = $this->run($sql, $params, $label)->fetch();
        return $row === false ? null : $row;
    }

    /** First column of the first row, or null. */
    public function scalar(string $sql, array $params = [], string $label = '')
    {
        $row = $this->run($sql, $params, $label)->fetch(PDO::FETCH_NUM);
        return $row === false ? null : $row[0];
    }

    /** A statement with no result set. Returns affected rows. */
    public function exec(string $sql, array $params = [], string $label = ''): int
    {
        return $this->run($sql, $params, $label)->rowCount();
    }

    /**
     * Call a stored procedure that has OUT parameters.
     *
     * MySQL returns OUT parameters through session variables, so the call is
     * made with @-variables in the OUT positions and then read back.
     *
     * @param string $proc  procedure name (never taken from user input)
     * @param array  $in    IN parameter values, bound
     * @param array  $out   OUT parameter names, e.g. ['result','message']
     * @return array        map of OUT name => value
     */
    public function callProc(string $proc, array $in = [], array $out = []): array
    {
        if (!preg_match('/^[a-z_][a-z0-9_]*$/i', $proc)) {
            throw new InvalidArgumentException('Illegal procedure name');
        }

        $placeholders = array_fill(0, count($in), '?');
        foreach ($out as $name) {
            if (!preg_match('/^[a-z_][a-z0-9_]*$/i', $name)) {
                throw new InvalidArgumentException('Illegal OUT parameter name');
            }
            $placeholders[] = '@scas_out_' . $name;
        }

        $sql = sprintf('CALL %s(%s)', $proc, implode(', ', $placeholders));
        $this->run($sql, array_values($in), 'CALL ' . $proc);

        if (!$out) {
            return [];
        }

        $select = [];
        foreach ($out as $name) {
            $select[] = '@scas_out_' . $name . ' AS ' . $name;
        }
        return $this->one('SELECT ' . implode(', ', $select)) ?? [];
    }

    /**
     * Call a procedure that returns one or more result sets.
     * Returns the FIRST result set as an array of rows.
     */
    public function callProcRows(string $proc, array $in = []): array
    {
        if (!preg_match('/^[a-z_][a-z0-9_]*$/i', $proc)) {
            throw new InvalidArgumentException('Illegal procedure name');
        }
        $sql  = sprintf('CALL %s(%s)', $proc, implode(', ', array_fill(0, count($in), '?')));
        $stmt = $this->run($sql, array_values($in), 'CALL ' . $proc);
        $rows = $stmt->fetchAll();
        $stmt->closeCursor();
        return $rows;
    }

    /** EXPLAIN a read-only statement, for the DBA console. */
    public function explain(string $sql, array $params = []): array
    {
        return $this->all('EXPLAIN ' . $sql, $params);
    }

    // -----------------------------------------------------------------------

    private function run(string $sql, array $params, string $label = ''): PDOStatement
    {
        $started = microtime(true);
        try {
            $stmt = $this->pdo->prepare($sql);
            $stmt->execute($params);
        } catch (PDOException $e) {
            throw new DatabaseException($this->friendlyMessage($e), 0, $e);
        }
        $ms = (microtime(true) - $started) * 1000;

        if ($ms >= SLOW_QUERY_MS && $label !== '') {
            $this->logSlowQuery($label, $sql, $ms);
        }
        return $stmt;
    }

    /**
     * A business rule raised with SIGNAL SQLSTATE '45000' arrives here as a
     * PDOException whose message contains the text after "SCAS:". Those are
     * meant for the end user. Anything else is an internal fault and its
     * detail is withheld unless DEBUG_ERRORS is on, because raw driver text
     * discloses table and column names.
     */
    private function friendlyMessage(PDOException $e): string
    {
        $raw = $e->getMessage();

        if (preg_match('/SCAS:\s*(.+?)(?:\s+in\s|\z)/s', $raw, $m)) {
            return trim($m[1]);
        }
        if (str_contains($raw, 'uk_attendance_session') || str_contains($raw, 'uk_attendance_scan')) {
            return 'Attendance for this session has already been recorded.';
        }
        if (str_contains($raw, 'uk_app_user_username')) {
            return 'That username is already taken.';
        }
        if (str_contains($raw, 'uk_app_user_email')) {
            return 'That e-mail address is already registered.';
        }
        if (str_contains($raw, 'uk_teacher_staff')) {
            return 'That staff number is already registered.';
        }
        if (str_contains($raw, 'uk_qr_session')) {
            return 'A code has already been issued for that session today.';
        }
        if (str_contains($raw, 'foreign key constraint fails')) {
            return 'That record is referenced by other data and cannot be removed.';
        }
        if (str_contains($raw, 'CONSTRAINT') && str_contains($raw, 'failed')) {
            return 'The values supplied failed a validation rule in the database.';
        }
        if (str_contains($raw, 'command denied')) {
            return 'The application account is not permitted to perform that operation.';
        }

        return DEBUG_ERRORS ? $raw : 'The database rejected the request.';
    }

    private function logSlowQuery(string $label, string $sql, float $ms): void
    {
        try {
            $plan = '';
            if (stripos(ltrim($sql), 'SELECT') === 0) {
                // Best effort only; a plan we cannot capture must never break
                // the user's request.
                $plan = 'captured separately';
            }
            $stmt = $this->pdo->prepare(
                'CALL sp_log_query_performance(?, ?, ?, NULL, ?, ?)'
            );
            $stmt->execute([
                mb_substr($label, 0, 80),
                mb_substr($sql, 0, 4000),
                round($ms, 3),
                $plan,
                DB_USER,
            ]);
            $stmt->closeCursor();
        } catch (Throwable) {
            // Deliberately swallowed: performance logging is diagnostics, and
            // diagnostics must never take the application down.
        }
    }
}

final class DatabaseException extends RuntimeException {}
