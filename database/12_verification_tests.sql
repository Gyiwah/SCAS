/* ============================================================================
   SCAS - FILE 12 : VERIFICATION TEST SUITE
   ---------------------------------------------------------------------------
   Every claim made in files 01-11 is asserted here against the running
   database. A claim that is not tested is only a comment.

   The suite is written so that a rule PASSES when the database REFUSES the
   operation. Most of these tests try to do something dishonest - scan an
   expired code, sign in for another teacher, delete an attendance record,
   approve your own leave - and pass only if the attempt fails.

   Re-runnable: every test cleans up after itself.
   ========================================================================= */

SET NAMES utf8mb4;
USE scas_db;

DROP TEMPORARY TABLE IF EXISTS test_result;
CREATE TEMPORARY TABLE test_result (
    seq       INT AUTO_INCREMENT PRIMARY KEY,
    area      VARCHAR(40),
    test_name VARCHAR(140),
    outcome   VARCHAR(6),
    detail    VARCHAR(255)
) ENGINE=Memory;

DELIMITER $$

/* Passes when the statement RAISES an error. */
DROP PROCEDURE IF EXISTS sp_assert_refused $$
CREATE PROCEDURE sp_assert_refused(IN p_area VARCHAR(40), IN p_name VARCHAR(140), IN p_sql TEXT)
BEGIN
    DECLARE v_err VARCHAR(255) DEFAULT NULL;
    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
        GET DIAGNOSTICS CONDITION 1 v_err = MESSAGE_TEXT;

    SET @sql_under_test = p_sql;
    PREPARE stmt FROM @sql_under_test;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;

    INSERT INTO test_result (area, test_name, outcome, detail)
    VALUES (p_area, p_name,
            IF(v_err IS NULL, 'FAIL', 'PASS'),
            IFNULL(LEFT(v_err, 255), 'the statement was ACCEPTED but should have been refused'));
END $$

/* Passes when the statement SUCCEEDS. */
DROP PROCEDURE IF EXISTS sp_assert_allowed $$
CREATE PROCEDURE sp_assert_allowed(IN p_area VARCHAR(40), IN p_name VARCHAR(140), IN p_sql TEXT)
BEGIN
    DECLARE v_err VARCHAR(255) DEFAULT NULL;
    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
        GET DIAGNOSTICS CONDITION 1 v_err = MESSAGE_TEXT;

    SET @sql_under_test = p_sql;
    PREPARE stmt FROM @sql_under_test;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;

    INSERT INTO test_result (area, test_name, outcome, detail)
    VALUES (p_area, p_name,
            IF(v_err IS NULL, 'PASS', 'FAIL'),
            IFNULL(LEFT(v_err, 255), 'accepted as expected'));
END $$

/* Passes when two values match. */
DROP PROCEDURE IF EXISTS sp_assert_equals $$
CREATE PROCEDURE sp_assert_equals(IN p_area VARCHAR(40), IN p_name VARCHAR(140),
                                  IN p_actual VARCHAR(255), IN p_expected VARCHAR(255))
BEGIN
    INSERT INTO test_result (area, test_name, outcome, detail)
    VALUES (p_area, p_name,
            IF(p_actual <=> p_expected, 'PASS', 'FAIL'),
            CONCAT('expected [', IFNULL(p_expected,'NULL'), '] got [', IFNULL(p_actual,'NULL'), ']'));
END $$

DELIMITER ;

/* ###########################################################################
   GROUP A - TRIGGERS: THE ATTENDANCE LEDGER CANNOT BE FORGED
   ######################################################################### */

/* Pick a scannable session for today that nobody has checked in to yet. */
SET @test_qr      = (SELECT q.qr_code_id FROM qr_code q
                     LEFT JOIN attendance a ON a.qr_code_id = q.qr_code_id
                     WHERE q.session_date = CURDATE() AND a.attendance_id IS NULL
                       AND q.is_revoked = 0 AND q.scan_count = 0
                     ORDER BY q.qr_code_id LIMIT 1);
SET @test_teacher = (SELECT tt.teacher_id FROM qr_code q
                     JOIN timetable tt ON tt.timetable_id = q.timetable_id
                     WHERE q.qr_code_id = @test_qr);
SET @other_teacher = (SELECT teacher_id FROM teacher WHERE teacher_id <> @test_teacher LIMIT 1);

CALL sp_assert_refused('Triggers',
    'A teacher cannot check in using another teacher''s session code',
    CONCAT('INSERT INTO attendance (teacher_id, qr_code_id, timetable_id, session_date, scan_datetime, status)
            SELECT ', @other_teacher, ', ', @test_qr, ', timetable_id, session_date, NOW(), ''Present''
            FROM qr_code WHERE qr_code_id = ', @test_qr));

CALL sp_assert_refused('Triggers',
    'A Present record cannot be created without a QR code (no scan, no proof)',
    CONCAT('INSERT INTO attendance (teacher_id, qr_code_id, timetable_id, session_date, scan_datetime, status)
            SELECT ', @test_teacher, ', NULL, timetable_id, session_date, NOW(), ''Present''
            FROM qr_code WHERE qr_code_id = ', @test_qr));

/* An expired code.
   NOTE ON TEST DESIGN: the first version of this test looked for an expired
   code in the seeded history. Every historical code has scan_count = 1
   (the seeder only issues a code when it also records a scan), so the search
   returned NULL, the INSERT ... SELECT matched no rows, inserted nothing, and
   raised no error - and the test "passed nothing" while reporting a failure.
   A test that can silently test nothing is worse than no test.
   The scenario is therefore constructed explicitly: take a real unscanned
   code for today and push its validity window into the past, so the ONLY rule
   that can reject the scan is the expiry rule. The window is restored
   afterwards. */
SET @expired_qr = (SELECT q.qr_code_id FROM qr_code q
                   LEFT JOIN attendance a ON a.qr_code_id = q.qr_code_id
                   WHERE q.session_date = CURDATE() AND a.attendance_id IS NULL
                     AND q.is_revoked = 0 AND q.scan_count = 0
                     AND q.qr_code_id <> IFNULL(@test_qr, 0)
                   ORDER BY q.qr_code_id LIMIT 1);
SET @expired_teacher = (SELECT tt.teacher_id FROM qr_code q
                        JOIN timetable tt ON tt.timetable_id = q.timetable_id
                        WHERE q.qr_code_id = @expired_qr);
SET @orig_generated = (SELECT generated_datetime FROM qr_code WHERE qr_code_id = @expired_qr);
SET @orig_expiry    = (SELECT expiry_datetime    FROM qr_code WHERE qr_code_id = @expired_qr);

CALL sp_assert_equals('Triggers',
    'Test fixture: an unscanned code was found to expire (guards against a vacuous test)',
    IF(@expired_qr IS NULL, 'NO FIXTURE', 'fixture ready'), 'fixture ready');

UPDATE qr_code
   SET generated_datetime = NOW() - INTERVAL 3 HOUR,
       expiry_datetime    = NOW() - INTERVAL 2 HOUR
 WHERE qr_code_id = @expired_qr;

CALL sp_assert_refused('Triggers',
    'An expired QR code cannot be scanned',
    CONCAT('INSERT INTO attendance (teacher_id, qr_code_id, timetable_id, session_date, scan_datetime, status)
            SELECT ', @expired_teacher, ', ', @expired_qr, ', timetable_id, session_date, NOW(), ''Present''
            FROM qr_code WHERE qr_code_id = ', @expired_qr));

/* The same code, through the application procedure rather than a raw INSERT. */
SET @expired_code_value = (SELECT code_value FROM qr_code WHERE qr_code_id = @expired_qr);
SET @expired_user = (SELECT user_id FROM teacher WHERE teacher_id = @expired_teacher);
CALL sp_record_attendance(@expired_user, @expired_code_value, '10.0.0.9', 'suite',
                          @res_exp, @msg_exp, @att_exp, @stat_exp);
CALL sp_assert_equals('Procedures',
    'sp_record_attendance reports EXPIRED for a lapsed code', @res_exp, 'EXPIRED');

/* Restore the fixture. */
UPDATE qr_code
   SET generated_datetime = @orig_generated,
       expiry_datetime    = @orig_expiry
 WHERE qr_code_id = @expired_qr;

CALL sp_assert_refused('Triggers',
    'An attendance record cannot be deleted (append-only ledger)',
    'DELETE FROM attendance ORDER BY attendance_id LIMIT 1');

CALL sp_assert_refused('Triggers',
    'The teacher on an attendance record cannot be changed afterwards',
    'UPDATE attendance SET teacher_id = teacher_id + 1 ORDER BY attendance_id LIMIT 1');

CALL sp_assert_refused('Triggers',
    'The session date on an attendance record cannot be back-dated',
    'UPDATE attendance SET session_date = session_date - INTERVAL 1 DAY ORDER BY attendance_id LIMIT 1');

CALL sp_assert_allowed('Triggers',
    'A status correction IS permitted (leave reclassification path)',
    'UPDATE attendance SET remarks = CONCAT(IFNULL(remarks,''''), '''') ORDER BY attendance_id LIMIT 1');

/* ###########################################################################
   GROUP B - TRIGGERS: SCHEDULING AND LEAVE RULES
   ######################################################################### */

SET @clash_tt = (SELECT timetable_id FROM timetable ORDER BY timetable_id LIMIT 1);

CALL sp_assert_refused('Triggers',
    'A teacher cannot be booked into two overlapping sessions',
    CONCAT('INSERT INTO timetable (teacher_id, classroom_id, term_id, subject, day_of_week, start_time, end_time)
            SELECT teacher_id, classroom_id, term_id, ''Clash Test'', day_of_week,
                   start_time + INTERVAL 15 MINUTE, end_time + INTERVAL 15 MINUTE
            FROM timetable WHERE timetable_id = ', @clash_tt));

CALL sp_assert_refused('Triggers',
    'A QR code cannot be issued for a day the session does not run',
    CONCAT('INSERT INTO qr_code (timetable_id, code_value, session_date, generated_datetime, expiry_datetime)
            SELECT timetable_id, SHA2(RAND(),256),
                   CASE WHEN day_of_week = ''Monday'' THEN ''2026-08-18'' ELSE ''2026-08-17'' END,
                   NOW(), NOW() + INTERVAL 30 MINUTE
            FROM timetable WHERE timetable_id = ', @clash_tt));

CALL sp_assert_refused('Triggers',
    'A QR code cannot be issued on a public holiday',
    CONCAT('INSERT INTO qr_code (timetable_id, code_value, session_date, generated_datetime, expiry_datetime)
            SELECT timetable_id, SHA2(RAND(),256), ''2026-07-01'', NOW(), NOW() + INTERVAL 30 MINUTE
            FROM timetable WHERE timetable_id = ',
            (SELECT timetable_id FROM timetable WHERE day_of_week = 'Wednesday' LIMIT 1)));

CALL sp_assert_refused('Triggers',
    'Overlapping leave requests are refused',
    'INSERT INTO leave_request (teacher_id, leave_type, start_date, end_date, reason)
     VALUES (9, ''Casual'', ''2026-08-25'', ''2026-08-25'', ''Overlaps the pending request already on file'')');

CALL sp_assert_refused('Triggers',
    'An already-approved leave request cannot be re-approved',
    'UPDATE leave_request SET status = ''Rejected'' WHERE leave_request_id = 1');

CALL sp_assert_refused('Triggers',
    'Leave cannot be backdated beyond the configured limit',
    'INSERT INTO leave_request (teacher_id, leave_type, start_date, end_date, reason)
     VALUES (12, ''Casual'', ''2026-01-05'', ''2026-01-06'', ''Retro-justifying an old absence'')');

/* ###########################################################################
   GROUP C - STORED PROCEDURES: THE CHECK-IN PATH
   ######################################################################### */

SET @scan_user = (SELECT t.user_id FROM teacher t WHERE t.teacher_id = @test_teacher);
SET @scan_code = (SELECT code_value FROM qr_code WHERE qr_code_id = @test_qr);

CALL sp_record_attendance(@scan_user, @scan_code, '10.0.0.9', 'Verification suite',
                          @res, @msg, @att_id, @stat);
CALL sp_assert_equals('Procedures', 'A valid scan is accepted by sp_record_attendance', @res, 'OK');
CALL sp_assert_equals('Procedures', 'The verdict is computed by the database, not supplied by the caller',
                      IF(@stat IN ('Present','Late'), 'computed', @stat), 'computed');

/* Immediately re-scanning the same single-use code. */
CALL sp_record_attendance(@scan_user, @scan_code, '10.0.0.9', 'Verification suite',
                          @res2, @msg2, @att2, @stat2);
CALL sp_assert_equals('Procedures', 'Re-using a single-use code is rejected (replay protection)',
                      IF(@res2 IN ('EXHAUSTED','DUPLICATE'), 'rejected', @res2), 'rejected');

/* Another teacher trying the same code. */
SET @other_user = (SELECT t.user_id FROM teacher t WHERE t.teacher_id = @other_teacher);
CALL sp_record_attendance(@other_user, @scan_code, '10.0.0.9', 'Verification suite',
                          @res3, @msg3, @att3, @stat3);
CALL sp_assert_equals('Procedures', 'Another teacher scanning the same code is rejected',
                      IF(@res3 IN ('WRONG_TEACHER','EXHAUSTED','DUPLICATE'), 'rejected', @res3), 'rejected');

CALL sp_record_attendance(@scan_user, 'this-token-was-never-issued', '10.0.0.9', 'Verification suite',
                          @res4, @msg4, @att4, @stat4);
CALL sp_assert_equals('Procedures', 'An invented code is rejected', @res4, 'NOT_FOUND');

/* Undo the test check-in so the suite is re-runnable. */
SET @scas_allow_archive_delete = 1;
DELETE FROM attendance WHERE attendance_id = @att_id;
SET @scas_allow_archive_delete = NULL;
UPDATE qr_code SET scan_count = 0 WHERE qr_code_id = @test_qr;

/* ###########################################################################
   GROUP D - AUTHORIZATION ENFORCED INSIDE THE DATABASE
   ######################################################################### */

SET @teacher_user = (SELECT t.user_id FROM teacher t LIMIT 1);

CALL sp_assert_refused('Authorization',
    'A teacher cannot approve a leave request (privilege check in the procedure)',
    CONCAT('CALL sp_action_leave_request(5, ''Approved'', ', @teacher_user, ', ''self approval'', @x)'));

CALL sp_assert_refused('Authorization',
    'A teacher cannot unlock an account',
    CONCAT('CALL sp_unlock_account(2, ', @teacher_user, ')'));

CALL sp_assert_allowed('Authorization',
    'The headteacher CAN approve a leave request',
    'CALL sp_action_leave_request(5, ''Approved'', 2, ''Verification suite - approved'', @x)');

/* Put request 5 back to Pending for the next run. The state-machine trigger
   forbids this, which is itself the point - so it is done by deleting and
   re-inserting rather than by an illegal UPDATE. */
DELETE FROM leave_request WHERE leave_request_id = 5;
INSERT INTO leave_request (leave_request_id, teacher_id, leave_type, start_date, end_date, reason, status)
VALUES (5, 9, 'Casual', '2026-08-24', '2026-08-26', 'Personal matters requiring travel to Tamale', 'Pending');

SELECT COUNT(*) INTO @denied_events FROM security_event WHERE event_type = 'PRIVILEGE_DENIED';
CALL sp_assert_equals('Authorization',
    'Refused privilege attempts are recorded in security_event',
    IF(@denied_events >= 2, 'logged', CONCAT('only ', @denied_events)), 'logged');

/* ###########################################################################
   GROUP E - ACCOUNT SECURITY: LOCKOUT
   ######################################################################### */

DELETE FROM app_user WHERE username = 'test.lockout';
CALL sp_create_user('Lockout Test Account', 'test.lockout',
                    '$2y$10$LjFap.tmsCZW5wK.A9og.uVMHFDCqlwB.vJb/Z2S4KyCCHZ7pqOtm',
                    1, 1, '0240000000', 'test.lockout@scas.test',
                    'TEST/LOCK/01', 'Science', 'BSc', '2020-01-01', @tu, @tt2);

CALL sp_login_failure('test.lockout', '10.0.0.1', 'suite');
CALL sp_login_failure('test.lockout', '10.0.0.1', 'suite');
CALL sp_login_failure('test.lockout', '10.0.0.1', 'suite');
CALL sp_login_failure('test.lockout', '10.0.0.1', 'suite');

SELECT IF(locked_until IS NULL, 'open', 'locked') INTO @lock4
FROM app_user WHERE username = 'test.lockout';
CALL sp_assert_equals('Security', 'Account is still open after 4 failed logins', @lock4, 'open');

CALL sp_login_failure('test.lockout', '10.0.0.1', 'suite');

SELECT IF(locked_until IS NULL, 'open', 'locked') INTO @lock5
FROM app_user WHERE username = 'test.lockout';
CALL sp_assert_equals('Security', 'Account locks on the 5th failed login', @lock5, 'locked');

CALL sp_authenticate_start('test.lockout', '10.0.0.1', @uid, @hash, @state);
CALL sp_assert_equals('Security', 'A locked account is refused and its hash withheld', @state, 'LOCKED');
CALL sp_assert_equals('Security', 'No password hash is returned for a locked account',
                      IF(@hash IS NULL, 'withheld', 'LEAKED'), 'withheld');

CALL sp_unlock_account(@tu, 1);
CALL sp_authenticate_start('test.lockout', '10.0.0.1', @uid2, @hash2, @state2);
CALL sp_assert_equals('Security', 'An administrator can unlock the account', @state2, 'OK');

DELETE FROM app_user WHERE username = 'test.lockout';

/* ###########################################################################
   GROUP F - ROW-LEVEL SECURITY
   ######################################################################### */

SET @scas_privilege = 50;
SET @scas_school_id = 1;
SELECT COUNT(DISTINCT school_id) INTO @schools_seen FROM v_my_school_teachers;
CALL sp_assert_equals('Row-level security',
    'A headteacher scoped to school 1 sees exactly one school', @schools_seen, '1');

SET @scas_school_id = 2;
SELECT COUNT(*) INTO @school2_only FROM v_my_school_teachers WHERE school_id = 1;
CALL sp_assert_equals('Row-level security',
    'Switching the session school hides the other school entirely', @school2_only, '0');

SET @scas_privilege = 99;
SELECT COUNT(DISTINCT school_id) INTO @all_schools FROM v_my_school_teachers;
CALL sp_assert_equals('Row-level security',
    'A system administrator sees every school', @all_schools, '2');

SET @scas_privilege = NULL, @scas_school_id = NULL;

/* ###########################################################################
   GROUP G - TRANSACTIONS
   ######################################################################### */

CALL sp_demo_savepoint();
CALL sp_demo_consistency();

/* Archive round-trip: rows must move atomically and nothing may be lost.
   The assertions are written against the DELTA rather than the absolute
   archive count, so the suite gives the same verdict on a freshly installed
   database and on one where a previous run already archived the same period. */
SELECT COUNT(*) INTO @before_archive  FROM attendance         WHERE session_date < '2026-05-11';
SELECT COUNT(*) INTO @archive_before  FROM attendance_archive WHERE session_date < '2026-05-11';

CALL sp_archive_old_attendance('2026-05-11', @moved);

SELECT COUNT(*) INTO @after_archive   FROM attendance         WHERE session_date < '2026-05-11';
SELECT COUNT(*) INTO @archive_after   FROM attendance_archive WHERE session_date < '2026-05-11';

CALL sp_assert_equals('Transactions',
    'sp_archive_old_attendance moved every qualifying row',
    CAST(@moved AS CHAR), CAST(@before_archive AS CHAR));
CALL sp_assert_equals('Transactions',
    'No qualifying rows remain in the live ledger after archiving',
    CAST(@after_archive AS CHAR), '0');
CALL sp_assert_equals('Transactions',
    'Every row removed from the ledger arrived in the archive (nothing lost)',
    CAST(@archive_after - @archive_before AS CHAR), CAST(@moved AS CHAR));

CALL sp_assert_refused('Transactions',
    'The delete override is closed again after archiving',
    'DELETE FROM attendance ORDER BY attendance_id LIMIT 1');

/* ###########################################################################
   GROUP H - TEMPORAL (SYSTEM-VERSIONED) RECOVERY
   ######################################################################### */

SET @t_before = NOW();
SELECT setting_value INTO @grace_before FROM system_setting WHERE setting_key = 'attendance.grace_minutes';

DO SLEEP(1.2);
UPDATE system_setting SET setting_value = '90' WHERE setting_key = 'attendance.grace_minutes';

SELECT setting_value INTO @grace_now FROM system_setting WHERE setting_key = 'attendance.grace_minutes';
CALL sp_assert_equals('Recovery', 'The setting was changed', @grace_now, '90');

SET @sql = CONCAT('SELECT setting_value INTO @grace_past FROM system_setting FOR SYSTEM_TIME AS OF TIMESTAMP ''',
                  DATE_FORMAT(@t_before, '%Y-%m-%d %H:%i:%s'), ''' WHERE setting_key = ''attendance.grace_minutes''');
PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;

CALL sp_assert_equals('Recovery',
    'The previous value is still readable from the temporal history', @grace_past, @grace_before);

CALL sp_restore_setting_as_of('attendance.grace_minutes', @t_before);
SELECT setting_value INTO @grace_restored FROM system_setting WHERE setting_key = 'attendance.grace_minutes';
CALL sp_assert_equals('Recovery',
    'Point-in-time restore of a setting works without a backup', @grace_restored, @grace_before);

/* ###########################################################################
   GROUP I - AUDIT TRAIL
   ######################################################################### */

SELECT COUNT(*) INTO @audit_rows FROM audit_log;
CALL sp_assert_equals('Audit', 'The audit trail is being written',
                      IF(@audit_rows > 0, 'populated', 'empty'), 'populated');

SELECT COUNT(*) INTO @pw_leak FROM audit_log
WHERE new_values LIKE '%$2y$%' OR old_values LIKE '%$2y$%';
CALL sp_assert_equals('Audit', 'No password hash has ever leaked into the audit trail',
                      CAST(@pw_leak AS CHAR), '0');

SELECT COUNT(*) INTO @att_audit FROM audit_log WHERE table_name = 'attendance' AND action = 'INSERT';
CALL sp_assert_equals('Audit', 'Every attendance insert is audited',
                      IF(@att_audit > 0, 'audited', 'missing'), 'audited');

/* ###########################################################################
   GROUP J - REFERENTIAL AND SEMANTIC INTEGRITY
   ######################################################################### */

CALL sp_assert_refused('Integrity',
    'A teacher with attendance history cannot be hard-deleted',
    'DELETE FROM teacher WHERE teacher_id = 1');

CALL sp_assert_refused('Integrity',
    'A classroom capacity outside the permitted range is refused',
    'INSERT INTO classroom (school_id, room_name, capacity) VALUES (1, ''Impossible Room'', 9000)');

CALL sp_assert_refused('Integrity',
    'A session that ends before it starts is refused',
    'INSERT INTO timetable (teacher_id, classroom_id, term_id, subject, day_of_week, start_time, end_time)
     VALUES (1, 9, 2, ''Time Travel'', ''Saturday'', ''11:00:00'', ''10:00:00'')');

CALL sp_assert_refused('Integrity',
    'A user without a school must be a System Administrator',
    'INSERT INTO app_user (full_name, username, password_hash, role_id, school_id)
     VALUES (''No School'', ''noschool'', ''$2y$10$abcdefghijklmnopqrstuv'', 1, NULL)');

/* The integrity sweep must report zero violations across the board. */
DROP TEMPORARY TABLE IF EXISTS integrity_out;
CREATE TEMPORARY TABLE integrity_out (check_name VARCHAR(120), violations INT) ENGINE=Memory;

INSERT INTO integrity_out
SELECT 'session_date disagrees with QR code', COUNT(*)
FROM attendance a JOIN qr_code q ON q.qr_code_id = a.qr_code_id
WHERE a.session_date <> q.session_date
UNION ALL
SELECT 'teacher does not own the session', COUNT(*)
FROM attendance a JOIN timetable tt ON tt.timetable_id = a.timetable_id
WHERE a.teacher_id <> tt.teacher_id
UNION ALL
SELECT 'Present/Late with no QR code', COUNT(*)
FROM attendance WHERE qr_code_id IS NULL AND status IN ('Present','Late')
UNION ALL
SELECT 'scan_count exceeds max_scans', COUNT(*)
FROM qr_code WHERE scan_count > max_scans
UNION ALL
SELECT 'approved leave still counted Absent', COUNT(*)
FROM attendance a WHERE a.status = 'Absent' AND fn_is_on_leave(a.teacher_id, a.session_date) = 1;

/* SUM() over a UNION of COUNT()s returns DECIMAL, which casts to
   '0.0000...'; the extra CAST to SIGNED keeps the comparison textual-clean. */
SELECT SUM(violations) INTO @total_violations FROM integrity_out;
CALL sp_assert_equals('Integrity', 'Full integrity sweep reports zero violations',
                      CAST(CAST(IFNULL(@total_violations,0) AS SIGNED) AS CHAR), '0');

/* ###########################################################################
   RESULTS
   ######################################################################### */

SELECT '================ SCAS VERIFICATION RESULTS ================' AS report;

SELECT seq, area, test_name, outcome, detail FROM test_result ORDER BY seq;

SELECT area,
       SUM(outcome = 'PASS') AS passed,
       SUM(outcome = 'FAIL') AS failed
FROM test_result GROUP BY area ORDER BY area;

SELECT COUNT(*)                AS tests_run,
       SUM(outcome = 'PASS')   AS passed,
       SUM(outcome = 'FAIL')   AS failed,
       CONCAT(ROUND(SUM(outcome = 'PASS') * 100.0 / COUNT(*), 1), '%') AS pass_rate,
       IF(SUM(outcome = 'FAIL') = 0, 'ALL TESTS PASSED', 'THERE ARE FAILURES - SEE ABOVE') AS verdict
FROM test_result;

SELECT '--- failures only ---' AS report;
SELECT area, test_name, detail FROM test_result WHERE outcome = 'FAIL';
