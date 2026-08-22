/* ============================================================================
   SCAS - FILE 08 : TRANSACTION MANAGEMENT AND RECOVERY
   Objective (b).
   ---------------------------------------------------------------------------
   This file has two halves.

   HALF 1 - the recovery INFRASTRUCTURE that ships with the system:
            backup registration procedures, the integrity/restore helpers,
            and the temporal (point-in-time) query support.

   HALF 2 - the DEMONSTRATIONS that prove each ACID property and each
            isolation level actually behaves as claimed. Single-session demos
            run automatically. The concurrency demos (dirty read, lost update,
            deadlock) genuinely need two connections, so they are written as
            clearly labelled SESSION A / SESSION B scripts to be pasted into
            two mysql clients side by side.

   WHY InnoDB GIVES US ACID
     Atomicity   - the undo log. Uncommitted changes can always be reversed.
     Consistency - constraints + triggers, checked inside the transaction.
     Isolation   - row-level locks + MVCC read views.
     Durability  - the redo log (ib_logfile*), flushed on COMMIT. After a
                   power cut the server replays the redo log on startup and
                   rolls back anything not committed. This is why the engine
                   choice in 01_schema.sql was not a formality.
   ========================================================================= */

SET NAMES utf8mb4;
USE scas_db;

/* ###########################################################################
   PART 1 - DURABILITY AND RECOVERY CONFIGURATION
   Read the current settings; the values SCAS expects are in the comments.
   Anything marked [my.ini] must be set in C:\xampp\mysql\bin\my.ini and the
   service restarted - it cannot be changed at runtime.
   ######################################################################### */

SELECT 'Durability and recovery settings' AS section;
SELECT @@innodb_flush_log_at_trx_commit AS flush_log_at_trx_commit,
       @@innodb_doublewrite             AS doublewrite,
       @@innodb_file_per_table          AS file_per_table,
       @@autocommit                     AS autocommit,
       @@tx_isolation                   AS default_isolation,
       @@log_bin                        AS binary_logging,
       @@innodb_lock_wait_timeout       AS lock_wait_timeout;

/*  innodb_flush_log_at_trx_commit = 1  [my.ini]
       1 = flush and fsync the redo log at every COMMIT. This is the only
       setting that survives a power cut with zero committed-transaction loss,
       and it is the correct setting for an attendance register, where a lost
       check-in is a dispute with a teacher's employer.
       (2 and 0 are faster but can lose up to a second of committed work.)

    innodb_doublewrite = 1  [my.ini]
       Protects against torn pages - a 16 KB page half-written when the power
       fails. InnoDB writes each page twice: once to the doublewrite buffer,
       then to its real location, so a torn page can always be reconstructed.

    log_bin = mysql-bin  [my.ini]
       The binary log records every change as a replayable event. A full
       backup plus the binary logs written since gives POINT-IN-TIME RECOVERY:
       restore the dump, then replay the log up to the second before the
       mistake. Without it, recovery granularity is "the last backup", which
       for a daily backup means losing up to a day of attendance.
       XAMPP ships with the binary log DISABLED. To enable, add to the
       [mysqld] section of my.ini:

           log_bin                        = mysql-bin
           binlog_format                  = ROW
           expire_logs_days               = 14
           innodb_flush_log_at_trx_commit = 1
           sync_binlog                    = 1

       then restart MySQL from the XAMPP control panel. tools/enable_binlog.md
       walks through it with screenshots of the expected output.
*/

/* ###########################################################################
   PART 2 - BACKUP REGISTRATION
   Every backup and restore is recorded in backup_log, together with the
   binary-log coordinates at the moment the backup was taken. Those
   coordinates are what a point-in-time recovery replays FROM - a backup
   whose position was never recorded can only be restored as a whole.
   ######################################################################### */

DELIMITER $$

DROP PROCEDURE IF EXISTS sp_backup_start $$
CREATE PROCEDURE sp_backup_start(
        IN  p_type  VARCHAR(25),
        IN  p_path  VARCHAR(255),
        IN  p_notes VARCHAR(255),
        OUT p_backup_id INT UNSIGNED)
MODIFIES SQL DATA
BEGIN
    INSERT INTO backup_log (backup_type, file_path, status, performed_by, notes)
    VALUES (p_type, p_path, 'RUNNING', CURRENT_USER(), p_notes);
    SET p_backup_id = LAST_INSERT_ID();
END $$

DROP PROCEDURE IF EXISTS sp_backup_finish $$
CREATE PROCEDURE sp_backup_finish(
        IN p_backup_id  INT UNSIGNED,
        IN p_status     VARCHAR(10),
        IN p_size       BIGINT UNSIGNED,
        IN p_binlog     VARCHAR(100),
        IN p_position   BIGINT UNSIGNED)
MODIFIES SQL DATA
BEGIN
    UPDATE backup_log
       SET status          = p_status,
           completed_at    = NOW(),
           file_size_bytes = p_size,
           binlog_file     = p_binlog,
           binlog_position = p_position
     WHERE backup_id = p_backup_id;
END $$

/* ---------------------------------------------------------------------------
   sp_recovery_report - what could we restore, and how far back?
   The gap between the newest successful backup and now is the exposure
   window: the amount of work that would be lost in a total loss right now.
   ------------------------------------------------------------------------ */
DROP PROCEDURE IF EXISTS sp_recovery_report $$
CREATE PROCEDURE sp_recovery_report()
READS SQL DATA
BEGIN
    SELECT  backup_id, backup_type, file_path,
            started_at, completed_at, status,
            ROUND(file_size_bytes / 1024 / 1024, 2) AS size_mb,
            binlog_file, binlog_position,
            TIMESTAMPDIFF(HOUR, completed_at, NOW()) AS hours_old
    FROM backup_log
    ORDER BY started_at DESC
    LIMIT 20;

    SELECT  MAX(completed_at) AS last_successful_backup,
            TIMESTAMPDIFF(HOUR, MAX(completed_at), NOW()) AS exposure_window_hours,
            CASE
                WHEN MAX(completed_at) IS NULL THEN 'NO BACKUP HAS EVER SUCCEEDED'
                WHEN TIMESTAMPDIFF(HOUR, MAX(completed_at), NOW()) > 48 THEN 'CRITICAL - backup overdue'
                WHEN TIMESTAMPDIFF(HOUR, MAX(completed_at), NOW()) > 26 THEN 'WARNING - backup late'
                ELSE 'OK'
            END AS recovery_posture
    FROM backup_log
    WHERE status = 'SUCCESS' AND backup_type IN ('FULL','LOGICAL');
END $$

/* ###########################################################################
   PART 3 - LOGICAL POINT-IN-TIME RECOVERY WITHOUT A BACKUP
   system_setting is a system-versioned (temporal) table. MariaDB keeps every
   previous version of each row, so the configuration in force at any past
   instant can be read back directly. This recovers a bad configuration change
   in seconds, with no restore and no downtime.
   ######################################################################### */

DROP PROCEDURE IF EXISTS sp_settings_as_of $$
CREATE PROCEDURE sp_settings_as_of(IN p_when DATETIME)
READS SQL DATA
BEGIN
    /* FOR SYSTEM_TIME AS OF cannot take a parameter directly, so the
       statement is prepared. This is the only dynamic SQL in the project. */
    SET @q = CONCAT(
        'SELECT setting_key, setting_value, data_type, updated_by ',
        'FROM system_setting FOR SYSTEM_TIME AS OF TIMESTAMP ''',
        DATE_FORMAT(p_when, '%Y-%m-%d %H:%i:%s'),
        ''' ORDER BY setting_key');
    PREPARE stmt FROM @q;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;
END $$

/* Restore one setting to the value it held at a past instant. */
DROP PROCEDURE IF EXISTS sp_restore_setting_as_of $$
CREATE PROCEDURE sp_restore_setting_as_of(
        IN p_key  VARCHAR(60),
        IN p_when DATETIME)
MODIFIES SQL DATA
BEGIN
    DECLARE v_old VARCHAR(255) DEFAULT NULL;
    DECLARE v_msg TEXT;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
        ROLLBACK;
        RESIGNAL;
    END;

    SET @k = p_key;
    SET @q = CONCAT(
        'SELECT setting_value INTO @restored FROM system_setting ',
        'FOR SYSTEM_TIME AS OF TIMESTAMP ''',
        DATE_FORMAT(p_when, '%Y-%m-%d %H:%i:%s'),
        ''' WHERE setting_key = ?');
    PREPARE stmt FROM @q;
    EXECUTE stmt USING @k;
    DEALLOCATE PREPARE stmt;

    SET v_old = @restored;

    IF v_old IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'SCAS: that setting did not exist at the requested time';
    END IF;

    START TRANSACTION;
        UPDATE system_setting SET setting_value = v_old WHERE setting_key = p_key;
    COMMIT;

    SELECT p_key AS setting_key, v_old AS restored_value, p_when AS restored_from;
END $$

/* ###########################################################################
   PART 4 - SINGLE-SESSION ACID DEMONSTRATIONS
   These run as part of the install and print their own evidence.
   ######################################################################### */

/* ---------------------------------------------------------------------------
   DEMO 1 - ATOMICITY and SAVEPOINT.
   A partial rollback inside a transaction: two rows are inserted, a SAVEPOINT
   is taken, a third is inserted and rolled back to the savepoint. The first
   two survive the COMMIT, the third does not.
   ------------------------------------------------------------------------ */
DROP PROCEDURE IF EXISTS sp_demo_savepoint $$
CREATE PROCEDURE sp_demo_savepoint()
MODIFIES SQL DATA
BEGIN
    DECLARE v_after_two   INT;
    DECLARE v_after_three INT;
    DECLARE v_after_rb    INT;
    DECLARE v_final       INT;

    DELETE FROM backup_log WHERE notes = 'SAVEPOINT DEMO';

    START TRANSACTION;
        INSERT INTO backup_log (backup_type, file_path, status, notes)
        VALUES ('LOGICAL', 'demo/one.sql', 'SUCCESS', 'SAVEPOINT DEMO');
        INSERT INTO backup_log (backup_type, file_path, status, notes)
        VALUES ('LOGICAL', 'demo/two.sql', 'SUCCESS', 'SAVEPOINT DEMO');

        SELECT COUNT(*) INTO v_after_two FROM backup_log WHERE notes = 'SAVEPOINT DEMO';

        SAVEPOINT sp_two_written;

        INSERT INTO backup_log (backup_type, file_path, status, notes)
        VALUES ('LOGICAL', 'demo/three.sql', 'FAILED', 'SAVEPOINT DEMO');

        SELECT COUNT(*) INTO v_after_three FROM backup_log WHERE notes = 'SAVEPOINT DEMO';

        ROLLBACK TO SAVEPOINT sp_two_written;

        SELECT COUNT(*) INTO v_after_rb FROM backup_log WHERE notes = 'SAVEPOINT DEMO';
    COMMIT;

    SELECT COUNT(*) INTO v_final FROM backup_log WHERE notes = 'SAVEPOINT DEMO';

    SELECT 'ATOMICITY / SAVEPOINT' AS demo,
           v_after_two   AS after_two_inserts,
           v_after_three AS after_third_insert,
           v_after_rb    AS after_rollback_to_savepoint,
           v_final       AS after_commit,
           IF(v_after_three = 3 AND v_after_rb = 2 AND v_final = 2,
              'PASS - the third insert was discarded, the first two committed',
              'FAIL') AS result;

    DELETE FROM backup_log WHERE notes = 'SAVEPOINT DEMO';
END $$

/* ---------------------------------------------------------------------------
   DEMO 2 - CONSISTENCY.
   A transaction that violates a constraint cannot commit. The whole
   transaction is discarded, not just the offending statement, so the database
   moves from one valid state to another with nothing in between.
   ------------------------------------------------------------------------ */
DROP PROCEDURE IF EXISTS sp_demo_consistency $$
CREATE PROCEDURE sp_demo_consistency()
MODIFIES SQL DATA
BEGIN
    DECLARE v_before INT;
    DECLARE v_after  INT;
    DECLARE v_caught VARCHAR(200) DEFAULT 'no error raised';

    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 v_caught = MESSAGE_TEXT;
        ROLLBACK;
    END;

    SELECT COUNT(*) INTO v_before FROM school;

    START TRANSACTION;
        /* valid */
        INSERT INTO school (school_code, school_name, district, region)
        VALUES ('DEMO-CONS', 'Consistency Demo School', 'Ho', 'Volta');
        /* invalid: ck_school_name_len requires 3+ characters */
        INSERT INTO school (school_code, school_name, district, region)
        VALUES ('DEMO-BAD', 'X', 'Ho', 'Volta');
    COMMIT;

    SELECT COUNT(*) INTO v_after FROM school;

    SELECT 'CONSISTENCY' AS demo,
           v_before AS schools_before,
           v_after  AS schools_after,
           v_caught AS constraint_error,
           IF(v_before = v_after,
              'PASS - the valid insert was rolled back with the invalid one',
              'FAIL - a partial transaction survived') AS result;

    DELETE FROM school WHERE school_code IN ('DEMO-CONS','DEMO-BAD');
END $$

/* ---------------------------------------------------------------------------
   DEMO 3 - ISOLATION LEVELS, read-only half.
   Shows the four levels and what each one permits. The anomalies themselves
   need two sessions (Part 5), but the cost/benefit table is worth printing
   next to them.
   ------------------------------------------------------------------------ */
DROP PROCEDURE IF EXISTS sp_demo_isolation_levels $$
CREATE PROCEDURE sp_demo_isolation_levels()
READS SQL DATA
BEGIN
    SELECT @@tx_isolation AS current_session_isolation;

    SELECT 'READ UNCOMMITTED' AS isolation_level,
           'YES' AS dirty_read, 'YES' AS non_repeatable_read, 'YES' AS phantom_read,
           'Never used in SCAS - a headteacher could see a check-in that is about to be rolled back' AS scas_usage
    UNION ALL
    SELECT 'READ COMMITTED', 'no', 'YES', 'YES',
           'Used by the live board: each refresh should see the newest committed scans'
    UNION ALL
    SELECT 'REPEATABLE READ', 'no', 'no', 'no (InnoDB gap locks)',
           'The default, and what sp_record_attendance runs under'
    UNION ALL
    SELECT 'SERIALIZABLE', 'no', 'no', 'no',
           'Used by the month-end report so totals cannot shift mid-report';
END $$

/* ---------------------------------------------------------------------------
   sp_month_end_report_serializable
   A real use of an explicit isolation level. A month-end report reads the
   ledger several times; at REPEATABLE READ that is already stable, but the
   report also has to be provably free of rows appearing underneath it, so it
   is run SERIALIZABLE and READ ONLY. READ ONLY lets InnoDB skip transaction
   -id assignment, so the stricter level costs almost nothing here.
   ------------------------------------------------------------------------ */
DROP PROCEDURE IF EXISTS sp_month_end_report_serializable $$
CREATE PROCEDURE sp_month_end_report_serializable(
        IN p_school_id INT UNSIGNED,
        IN p_year      SMALLINT,
        IN p_month     TINYINT)
READS SQL DATA
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;
        RESIGNAL;
    END;

    SET SESSION TRANSACTION ISOLATION LEVEL SERIALIZABLE;
    START TRANSACTION READ ONLY;

        SELECT  'Header' AS part,
                COUNT(DISTINCT teacher_id) AS teachers,
                COUNT(*)                   AS sessions,
                SUM(status = 'Absent')     AS absences
        FROM v_attendance_detail
        WHERE school_id = p_school_id
          AND session_year = p_year AND session_month = p_month;

        SELECT  staff_number, teacher_name, department,
                present_count, late_count, absent_count, excused_count, attendance_rate
        FROM v_monthly_attendance_summary
        WHERE school_id = p_school_id
          AND session_year = p_year AND session_month = p_month
        ORDER BY attendance_rate DESC;

    COMMIT;
    SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;
END $$

/* ---------------------------------------------------------------------------
   sp_show_locks - what is blocking what, right now. The first thing to run
   when the application reports "Lock wait timeout exceeded".
   ------------------------------------------------------------------------ */
DROP PROCEDURE IF EXISTS sp_show_locks $$
CREATE PROCEDURE sp_show_locks()
READS SQL DATA
BEGIN
    SELECT  r.trx_id            AS waiting_trx,
            r.trx_mysql_thread_id AS waiting_thread,
            LEFT(r.trx_query, 80) AS waiting_query,
            b.trx_id            AS blocking_trx,
            b.trx_mysql_thread_id AS blocking_thread,
            LEFT(b.trx_query, 80) AS blocking_query,
            TIMESTAMPDIFF(SECOND, r.trx_wait_started, NOW()) AS seconds_waiting
    FROM information_schema.INNODB_LOCK_WAITS w
    JOIN information_schema.INNODB_TRX b ON b.trx_id = w.blocking_trx_id
    JOIN information_schema.INNODB_TRX r ON r.trx_id = w.requesting_trx_id;

    SELECT trx_id, trx_state, trx_started,
           TIMESTAMPDIFF(SECOND, trx_started, NOW()) AS age_seconds,
           trx_isolation_level, trx_rows_locked, trx_rows_modified,
           LEFT(IFNULL(trx_query, '(idle)'), 80) AS current_query
    FROM information_schema.INNODB_TRX
    ORDER BY trx_started;
END $$

DELIMITER ;

/* ###########################################################################
   PART 5 - TWO-SESSION CONCURRENCY DEMONSTRATIONS
   These cannot run inside one script. Open two mysql clients:

       C:\xampp\mysql\bin\mysql.exe -u root scas_db

   and paste the SESSION A / SESSION B blocks alternately, in the order shown
   by the step numbers. Expected output is stated after each step.
   ---------------------------------------------------------------------------

   -- ======================================================================
   -- DEMO 4: DIRTY READ, and why SCAS never uses READ UNCOMMITTED
   -- ======================================================================
   -- A1) SESSION A
   --     SET SESSION TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
   --     START TRANSACTION;
   --
   -- B1) SESSION B
   --     START TRANSACTION;
   --     UPDATE system_setting SET setting_value = '999'
   --      WHERE setting_key = 'attendance.grace_minutes';
   --     -- do NOT commit
   --
   -- A2) SESSION A
   --     SELECT setting_value FROM system_setting
   --      WHERE setting_key = 'attendance.grace_minutes';
   --     -- => 999. Session A is reading a value that does not exist yet.
   --
   -- B2) SESSION B
   --     ROLLBACK;
   --
   -- A3) SESSION A
   --     SELECT setting_value FROM system_setting
   --      WHERE setting_key = 'attendance.grace_minutes';
   --     -- => 10. The 999 was a phantom of an abandoned transaction.
   --     COMMIT;
   --     SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;
   --
   -- Consequence for SCAS: at READ UNCOMMITTED a lateness threshold of 999
   -- minutes would have marked a whole morning Present. Hence the default is
   -- never lowered.

   -- ======================================================================
   -- DEMO 5: NON-REPEATABLE READ - READ COMMITTED vs REPEATABLE READ
   -- ======================================================================
   -- A1) SESSION A
   --     SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED;
   --     START TRANSACTION;
   --     SELECT COUNT(*) FROM attendance WHERE status = 'Absent';   -- note N
   --
   -- B1) SESSION B
   --     CALL sp_mark_absentees(CURDATE() - INTERVAL 1 DAY, 1, @a, @e);
   --
   -- A2) SESSION A  (same transaction, same query)
   --     SELECT COUNT(*) FROM attendance WHERE status = 'Absent';
   --     -- => a DIFFERENT number. The read was not repeatable.
   --     COMMIT;
   --
   -- A3) Repeat the whole demo with
   --     SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;
   --     -- => both counts are identical: InnoDB's MVCC read view is fixed at
   --     --    the first read, so the report cannot shift underneath itself.

   -- ======================================================================
   -- DEMO 6: LOST UPDATE, and why sp_record_attendance uses FOR UPDATE
   -- ======================================================================
   -- Without the lock, two teachers scanning a single-use code simultaneously
   -- would both read scan_count = 0 and both be accepted.
   --
   -- A1) SESSION A
   --     START TRANSACTION;
   --     SELECT scan_count FROM qr_code WHERE qr_code_id = 1 FOR UPDATE;
   --
   -- B1) SESSION B
   --     START TRANSACTION;
   --     SELECT scan_count FROM qr_code WHERE qr_code_id = 1 FOR UPDATE;
   --     -- => B BLOCKS here. That is the isolation guarantee working.
   --
   -- A2) SESSION A
   --     UPDATE qr_code SET scan_count = scan_count + 1 WHERE qr_code_id = 1;
   --     COMMIT;
   --     -- => B now unblocks and sees scan_count = 1, so B is rejected as
   --     --    EXHAUSTED instead of double-recording.
   --
   -- B2) SESSION B
   --     ROLLBACK;

   -- ======================================================================
   -- DEMO 7: DEADLOCK DETECTION AND VICTIM SELECTION
   -- ======================================================================
   -- Two transactions taking the same two rows in opposite orders.
   --
   -- A1) SESSION A
   --     START TRANSACTION;
   --     UPDATE school SET district = district WHERE school_id = 1;
   --
   -- B1) SESSION B
   --     START TRANSACTION;
   --     UPDATE school SET district = district WHERE school_id = 2;
   --
   -- A2) SESSION A
   --     UPDATE school SET district = district WHERE school_id = 2;  -- waits
   --
   -- B2) SESSION B
   --     UPDATE school SET district = district WHERE school_id = 1;
   --     -- => ERROR 1213 (40001): Deadlock found when trying to get lock.
   --     --    InnoDB detected the cycle and killed the cheaper transaction
   --     --    rather than letting both wait forever.
   --
   -- A3) SESSION A   -- succeeded; finish it
   --     COMMIT;
   --
   -- Then inspect the post-mortem:
   --     SHOW ENGINE INNODB STATUS\G       -- section "LATEST DETECTED DEADLOCK"
   --     CALL sp_show_locks();
   --
   -- SCAS avoids deadlocks by always taking locks in the same order
   -- (qr_code, then attendance) in every procedure that touches both.

   -- ======================================================================
   -- DEMO 8: XA (TWO-PHASE COMMIT) - distributed transactions
   -- ======================================================================
   -- Relevant when a district office database must be updated atomically with
   -- the school database. XA splits COMMIT into PREPARE and COMMIT so a
   -- coordinator can guarantee all-or-nothing across two servers.
   --
   --     XA START 'scas_tx_demo';
   --       INSERT INTO backup_log (backup_type, file_path, status, notes)
   --       VALUES ('LOGICAL','demo/xa.sql','SUCCESS','XA DEMO');
   --     XA END 'scas_tx_demo';
   --     XA PREPARE 'scas_tx_demo';     -- durable, but not yet visible
   --     XA RECOVER;                    -- the coordinator can see it pending
   --     XA COMMIT 'scas_tx_demo';      -- or XA ROLLBACK 'scas_tx_demo';
   --
   --     SELECT * FROM backup_log WHERE notes = 'XA DEMO';
   --     DELETE FROM backup_log WHERE notes = 'XA DEMO';
   ######################################################################### */

/* ###########################################################################
   PART 6 - THE RECOVERY DRILL
   A backup that has never been restored is a hypothesis, not a backup.
   The full procedure with commands is in docs/RECOVERY.md; the scripts are
   tools/backup.bat and tools/restore.bat. In summary:

     1. tools\backup.bat            - mysqldump with --single-transaction
                                      (a consistent snapshot without locking
                                      the school out of the system), plus
                                      --master-data=2 to stamp the binary log
                                      position into the dump.
     2. Record the position         - CALL sp_backup_finish(...).
     3. Simulate the disaster       - DROP DATABASE scas_db;
     4. tools\restore.bat <file>    - reload the dump.
     5. Replay the gap              - mysqlbinlog --start-position=<pos>
                                      --stop-datetime="<just before mistake>"
                                      | mysql -u root
     6. Verify                      - CALL sp_run_integrity_check();
                                      every rule must report 0 violations.
   ######################################################################### */

/* ###########################################################################
   PART 7 - GRANTS FOR THE PROCEDURES DEFINED IN THIS FILE
   These belong logically in 07_security_authorization.sql, but MariaDB
   refuses GRANT EXECUTE on a routine that does not exist yet and 07 runs
   first, so they are issued here instead.
   ######################################################################### */

GRANT EXECUTE ON PROCEDURE scas_db.sp_recovery_report               TO 'scas_app'@'localhost';
GRANT EXECUTE ON PROCEDURE scas_db.sp_settings_as_of                TO 'scas_app'@'localhost';
GRANT EXECUTE ON PROCEDURE scas_db.sp_restore_setting_as_of         TO 'scas_app'@'localhost';
GRANT EXECUTE ON PROCEDURE scas_db.sp_show_locks                    TO 'scas_app'@'localhost';
GRANT EXECUTE ON PROCEDURE scas_db.sp_month_end_report_serializable TO 'scas_app'@'localhost';
GRANT EXECUTE ON PROCEDURE scas_db.sp_demo_savepoint                TO 'scas_app'@'localhost';
GRANT EXECUTE ON PROCEDURE scas_db.sp_demo_consistency              TO 'scas_app'@'localhost';
GRANT EXECUTE ON PROCEDURE scas_db.sp_demo_isolation_levels         TO 'scas_app'@'localhost';

GRANT EXECUTE ON PROCEDURE scas_db.sp_recovery_report TO scas_dba_role;
GRANT EXECUTE ON PROCEDURE scas_db.sp_show_locks      TO scas_dba_role;
GRANT EXECUTE ON PROCEDURE scas_db.sp_backup_start    TO scas_backup_role;
GRANT EXECUTE ON PROCEDURE scas_db.sp_backup_finish   TO scas_backup_role;

FLUSH PRIVILEGES;

SELECT '08 complete - transaction and recovery infrastructure installed' AS status;
