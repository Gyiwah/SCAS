/* ============================================================================
   SCAS - FILE 03 : STORED FUNCTIONS
   Objective (d) Stored procedures and triggers - the reusable expressions.
   ---------------------------------------------------------------------------
   Why functions and not application code:
   the rule "a scan more than N minutes after the bell is Late" must give the
   same answer to the PHP app, to the nightly absentee job, to a trigger and to
   an ad-hoc report. Encoded once here, it cannot drift between them.

   Every function declares its data access (DETERMINISTIC / READS SQL DATA)
   so the optimiser knows whether it may cache or reorder the call.
   ========================================================================= */

SET NAMES utf8mb4;
USE scas_db;

DELIMITER $$

/* ---------------------------------------------------------------------------
   fn_get_setting - single point of access to runtime configuration.
   ------------------------------------------------------------------------ */
DROP FUNCTION IF EXISTS fn_get_setting $$
CREATE FUNCTION fn_get_setting(p_key VARCHAR(60))
    RETURNS VARCHAR(255)
    READS SQL DATA
    COMMENT 'Reads one row from the system-versioned settings table'
BEGIN
    DECLARE v_value VARCHAR(255) DEFAULT NULL;
    SELECT setting_value INTO v_value
    FROM system_setting
    WHERE setting_key = p_key;
    RETURN v_value;
END $$

/* ---------------------------------------------------------------------------
   fn_grace_minutes - how long after the bell a teacher is still "Present".
   Falls back to 10 minutes if the setting row is missing, so the attendance
   rule can never fail closed on a configuration error.
   ------------------------------------------------------------------------ */
DROP FUNCTION IF EXISTS fn_grace_minutes $$
CREATE FUNCTION fn_grace_minutes()
    RETURNS INT
    READS SQL DATA
BEGIN
    RETURN CAST(IFNULL(fn_get_setting('attendance.grace_minutes'), '10') AS SIGNED);
END $$

/* ---------------------------------------------------------------------------
   fn_attendance_status - THE attendance rule.
   Present if scanned at or before (bell + grace); Late after that.
   Scanning before the bell is still Present (teachers arrive early).
   ------------------------------------------------------------------------ */
DROP FUNCTION IF EXISTS fn_attendance_status $$
CREATE FUNCTION fn_attendance_status(
        p_scan_datetime DATETIME,
        p_session_date  DATE,
        p_start_time    TIME,
        p_grace_minutes INT)
    RETURNS VARCHAR(10)
    DETERMINISTIC
    COMMENT 'Present / Late verdict for one scan'
BEGIN
    DECLARE v_bell    DATETIME;
    DECLARE v_minutes INT;

    SET v_bell    = TIMESTAMP(p_session_date, p_start_time);
    SET v_minutes = TIMESTAMPDIFF(MINUTE, v_bell, p_scan_datetime);

    IF v_minutes <= p_grace_minutes THEN
        RETURN 'Present';
    ELSE
        RETURN 'Late';
    END IF;
END $$

/* ---------------------------------------------------------------------------
   fn_minutes_late - 0 when on time, otherwise minutes past the bell.
   ------------------------------------------------------------------------ */
DROP FUNCTION IF EXISTS fn_minutes_late $$
CREATE FUNCTION fn_minutes_late(
        p_scan_datetime DATETIME,
        p_session_date  DATE,
        p_start_time    TIME)
    RETURNS INT
    DETERMINISTIC
BEGIN
    DECLARE v_minutes INT;
    SET v_minutes = TIMESTAMPDIFF(MINUTE, TIMESTAMP(p_session_date, p_start_time), p_scan_datetime);
    IF v_minutes < 0 THEN
        SET v_minutes = 0;
    END IF;
    IF v_minutes > 1440 THEN
        SET v_minutes = 1440;
    END IF;
    RETURN v_minutes;
END $$

/* ---------------------------------------------------------------------------
   fn_is_on_leave - is this teacher covered by APPROVED leave on this date?
   Used to exclude approved absence from absenteeism (proposal problem 4).
   Uses ix_leave_lookup.
   ------------------------------------------------------------------------ */
DROP FUNCTION IF EXISTS fn_is_on_leave $$
CREATE FUNCTION fn_is_on_leave(p_teacher_id INT UNSIGNED, p_date DATE)
    RETURNS TINYINT(1)
    READS SQL DATA
BEGIN
    DECLARE v_hits INT DEFAULT 0;
    SELECT COUNT(*) INTO v_hits
    FROM leave_request
    WHERE teacher_id = p_teacher_id
      AND status     = 'Approved'
      AND p_date BETWEEN start_date AND end_date;
    RETURN IF(v_hits > 0, 1, 0);
END $$

/* ---------------------------------------------------------------------------
   fn_is_holiday - national (school_id IS NULL) or school-specific holiday.
   ------------------------------------------------------------------------ */
DROP FUNCTION IF EXISTS fn_is_holiday $$
CREATE FUNCTION fn_is_holiday(p_school_id INT UNSIGNED, p_date DATE)
    RETURNS TINYINT(1)
    READS SQL DATA
BEGIN
    DECLARE v_hits INT DEFAULT 0;
    SELECT COUNT(*) INTO v_hits
    FROM holiday
    WHERE holiday_date = p_date
      AND (school_id IS NULL OR school_id = p_school_id);
    RETURN IF(v_hits > 0, 1, 0);
END $$

/* ---------------------------------------------------------------------------
   fn_teacher_school - the school a teacher belongs to, via their user record.
   ------------------------------------------------------------------------ */
DROP FUNCTION IF EXISTS fn_teacher_school $$
CREATE FUNCTION fn_teacher_school(p_teacher_id INT UNSIGNED)
    RETURNS INT UNSIGNED
    READS SQL DATA
BEGIN
    DECLARE v_school INT UNSIGNED DEFAULT NULL;
    SELECT u.school_id INTO v_school
    FROM teacher t
    JOIN app_user u ON u.user_id = t.user_id
    WHERE t.teacher_id = p_teacher_id;
    RETURN v_school;
END $$

/* ---------------------------------------------------------------------------
   fn_attendance_rate - percentage of scheduled sessions actually attended.
   Present and Late both count as attendance; Excused sessions are removed
   from the denominator because the teacher was not required to be there.
   ------------------------------------------------------------------------ */
DROP FUNCTION IF EXISTS fn_attendance_rate $$
CREATE FUNCTION fn_attendance_rate(
        p_teacher_id INT UNSIGNED,
        p_from       DATE,
        p_to         DATE)
    RETURNS DECIMAL(5,2)
    READS SQL DATA
BEGIN
    DECLARE v_attended INT DEFAULT 0;
    DECLARE v_required INT DEFAULT 0;

    SELECT SUM(status IN ('Present','Late')),
           SUM(status <> 'Excused')
      INTO v_attended, v_required
    FROM attendance
    WHERE teacher_id  = p_teacher_id
      AND session_date BETWEEN p_from AND p_to;

    IF v_required IS NULL OR v_required = 0 THEN
        RETURN 0.00;
    END IF;
    RETURN ROUND(v_attended * 100.0 / v_required, 2);
END $$

/* ---------------------------------------------------------------------------
   fn_qr_status - full validity verdict for a scanned token.
   Returns exactly one of:
     NOT_FOUND | REVOKED | NOT_YET_VALID | EXPIRED | EXHAUSTED | VALID
   The scan procedure and the trigger both call this, so a code can never be
   accepted by one path and rejected by the other.
   ------------------------------------------------------------------------ */
DROP FUNCTION IF EXISTS fn_qr_status $$
CREATE FUNCTION fn_qr_status(p_code_value VARCHAR(64))
    RETURNS VARCHAR(20)
    READS SQL DATA
BEGIN
    DECLARE v_generated DATETIME;
    DECLARE v_expiry    DATETIME;
    DECLARE v_revoked   TINYINT(1);
    DECLARE v_scans     SMALLINT;
    DECLARE v_max       SMALLINT;
    DECLARE v_found     INT DEFAULT 0;

    SELECT COUNT(*) INTO v_found FROM qr_code WHERE code_value = p_code_value;
    IF v_found = 0 THEN
        RETURN 'NOT_FOUND';
    END IF;

    SELECT generated_datetime, expiry_datetime, is_revoked, scan_count, max_scans
      INTO v_generated, v_expiry, v_revoked, v_scans, v_max
    FROM qr_code
    WHERE code_value = p_code_value;

    IF v_revoked = 1                THEN RETURN 'REVOKED';       END IF;
    IF NOW() < v_generated          THEN RETURN 'NOT_YET_VALID'; END IF;
    IF NOW() > v_expiry             THEN RETURN 'EXPIRED';       END IF;
    IF v_scans >= v_max             THEN RETURN 'EXHAUSTED';     END IF;
    RETURN 'VALID';
END $$

/* ---------------------------------------------------------------------------
   fn_generate_token - cryptographically-flavoured session token.
   NOT DETERMINISTIC by definition: a new value every call is the whole point.
   Combines two UUIDs with a random salt and hashes them, so the token cannot
   be guessed from the timetable id or the date.
   ------------------------------------------------------------------------ */
DROP FUNCTION IF EXISTS fn_generate_token $$
CREATE FUNCTION fn_generate_token(p_timetable_id INT UNSIGNED, p_session_date DATE)
    RETURNS VARCHAR(64)
    NOT DETERMINISTIC
BEGIN
    /* Truncated to 32 hex characters = 128 bits of entropy. That is far
       beyond guessable (a code is also valid for only ~30 minutes) and it
       keeps the printed QR code at version 3 - 29x29 modules - which scans
       reliably from a phone held at arm's length. A full 64-character digest
       would force version 6 and a visibly denser symbol for no security gain. */
    RETURN LEFT(SHA2(CONCAT(UUID(), ':', p_timetable_id, ':', p_session_date,
                            ':', RAND(), ':', UNIX_TIMESTAMP(NOW(6))), 256), 32);
END $$

/* ---------------------------------------------------------------------------
   fn_mask_phone - data masking for the Security & Authorization objective.
   A user with read access to a report should not automatically see full
   personal contact numbers: 0244123456 is shown as 024****456.
   ------------------------------------------------------------------------ */
DROP FUNCTION IF EXISTS fn_mask_phone $$
CREATE FUNCTION fn_mask_phone(p_phone VARCHAR(20))
    RETURNS VARCHAR(20)
    DETERMINISTIC
BEGIN
    IF p_phone IS NULL OR CHAR_LENGTH(p_phone) < 7 THEN
        RETURN p_phone;
    END IF;
    RETURN CONCAT(LEFT(p_phone, 3), '****', RIGHT(p_phone, 3));
END $$

/* ---------------------------------------------------------------------------
   fn_current_user_id / fn_current_school_id / fn_current_privilege
   The application sets @scas_user_id, @scas_school_id and @scas_privilege
   immediately after connecting. Views and triggers read them through these
   accessors, which is how row-level filtering and audit attribution work
   without every query having to pass the identity explicitly.
   ------------------------------------------------------------------------ */
DROP FUNCTION IF EXISTS fn_current_user_id $$
CREATE FUNCTION fn_current_user_id()
    RETURNS INT UNSIGNED
    NOT DETERMINISTIC
BEGIN
    RETURN @scas_user_id;
END $$

DROP FUNCTION IF EXISTS fn_current_school_id $$
CREATE FUNCTION fn_current_school_id()
    RETURNS INT UNSIGNED
    NOT DETERMINISTIC
BEGIN
    RETURN @scas_school_id;
END $$

DROP FUNCTION IF EXISTS fn_current_privilege $$
CREATE FUNCTION fn_current_privilege()
    RETURNS TINYINT UNSIGNED
    NOT DETERMINISTIC
BEGIN
    RETURN IFNULL(@scas_privilege, 0);
END $$

DELIMITER ;

SELECT CONCAT('03 complete - ', COUNT(*), ' stored functions') AS status
FROM information_schema.ROUTINES
WHERE ROUTINE_SCHEMA = 'scas_db' AND ROUTINE_TYPE = 'FUNCTION';
