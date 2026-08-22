/* ============================================================================
   SCAS - FILE 05 : STORED PROCEDURES
   Objectives (b) Transaction Management & Recovery and (d) Stored procedures.
   ---------------------------------------------------------------------------
   Conventions used by every procedure in this file
   * Explicit transaction boundaries. Nothing relies on autocommit.
   * DECLARE EXIT HANDLER FOR SQLEXCEPTION -> GET DIAGNOSTICS -> ROLLBACK.
     A procedure never leaves a half-finished transaction behind, so the
     Atomicity guarantee holds even on an unexpected error.
   * SAVEPOINT is used where part of the work is optional: the optional part
     can be rolled back without discarding the part that already succeeded.
   * Business errors are raised with SIGNAL SQLSTATE '45000' so the PHP layer
     receives a real exception, not a magic return value.
   * SELECT ... FOR UPDATE is used on the QR row during a scan so that two
     simultaneous scans of a single-use code cannot both succeed
     (the Isolation guarantee).

   The application account has NO direct INSERT/UPDATE/DELETE on the business
   tables (see 07). Every write goes through one of these procedures, which
   is what makes the business rules non-bypassable.
   ========================================================================= */

SET NAMES utf8mb4;
USE scas_db;

DELIMITER $$

/* ###########################################################################
   SECTION 1 - AUTHENTICATION AND ACCOUNT SECURITY
   ######################################################################### */

/* ---------------------------------------------------------------------------
   sp_authenticate_start
   Step 1 of login. Returns the stored bcrypt hash ONLY if the account is in a
   usable state. PHP then calls password_verify() - the plaintext password is
   never sent to the database, and the hash never leaves this procedure for a
   locked or disabled account.
   ------------------------------------------------------------------------ */
DROP PROCEDURE IF EXISTS sp_authenticate_start $$
CREATE PROCEDURE sp_authenticate_start(
        IN  p_username     VARCHAR(40),
        IN  p_ip           VARCHAR(45),
        OUT p_user_id      INT UNSIGNED,
        OUT p_password_hash VARCHAR(255),
        OUT p_state        VARCHAR(20))
    READS SQL DATA
proc: BEGIN
    DECLARE v_active  TINYINT(1);
    DECLARE v_locked  DATETIME;
    DECLARE v_hash    VARCHAR(255);
    DECLARE v_id      INT UNSIGNED DEFAULT NULL;

    SET p_user_id = NULL, p_password_hash = NULL, p_state = 'NOT_FOUND';

    SELECT user_id, password_hash, is_active, locked_until
      INTO v_id, v_hash, v_active, v_locked
    FROM app_user
    WHERE username = p_username;

    IF v_id IS NULL THEN
        /* Logged, but the caller is told only "invalid credentials" by PHP -
           the response must not reveal whether the username exists. */
        INSERT INTO security_event (event_type, username_attempted, ip_address, detail, severity)
        VALUES ('LOGIN_FAILED', p_username, p_ip, 'Unknown username', 'WARNING');
        LEAVE proc;
    END IF;

    SET p_user_id = v_id;

    IF v_active = 0 THEN
        SET p_state = 'INACTIVE';
        INSERT INTO security_event (event_type, username_attempted, user_id, ip_address, detail, severity)
        VALUES ('LOGIN_FAILED', p_username, v_id, p_ip, 'Account is deactivated', 'WARNING');
        LEAVE proc;
    END IF;

    IF v_locked IS NOT NULL AND v_locked > NOW() THEN
        SET p_state = 'LOCKED';
        INSERT INTO security_event (event_type, username_attempted, user_id, ip_address, detail, severity)
        VALUES ('LOGIN_FAILED', p_username, v_id, p_ip,
                CONCAT('Locked until ', v_locked), 'WARNING');
        LEAVE proc;
    END IF;

    SET p_password_hash = v_hash;
    SET p_state         = 'OK';
END $$

/* ---------------------------------------------------------------------------
   sp_login_success - clears the failure counter and stamps the login.
   ------------------------------------------------------------------------ */
DROP PROCEDURE IF EXISTS sp_login_success $$
CREATE PROCEDURE sp_login_success(
        IN p_user_id INT UNSIGNED,
        IN p_ip      VARCHAR(45),
        IN p_agent   VARCHAR(200))
MODIFIES SQL DATA
BEGIN
    DECLARE v_msg TEXT;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;
        UPDATE app_user
           SET failed_login_attempts = 0,
               locked_until          = NULL,
               last_login_at         = NOW(),
               last_login_ip         = p_ip
         WHERE user_id = p_user_id;

        INSERT INTO security_event (event_type, user_id, username_attempted, ip_address, user_agent, detail)
        SELECT 'LOGIN_SUCCESS', user_id, username, p_ip, p_agent, 'Authenticated'
        FROM app_user WHERE user_id = p_user_id;
    COMMIT;
END $$

/* ---------------------------------------------------------------------------
   sp_login_failure - increments the counter and locks the account once the
   configured threshold is reached. Lockout duration is configurable.
   ------------------------------------------------------------------------ */
DROP PROCEDURE IF EXISTS sp_login_failure $$
CREATE PROCEDURE sp_login_failure(
        IN p_username VARCHAR(40),
        IN p_ip       VARCHAR(45),
        IN p_agent    VARCHAR(200))
MODIFIES SQL DATA
BEGIN
    DECLARE v_user_id   INT UNSIGNED DEFAULT NULL;
    DECLARE v_attempts  INT DEFAULT 0;
    DECLARE v_max       INT DEFAULT 5;
    DECLARE v_lock_mins INT DEFAULT 15;
    DECLARE v_msg       TEXT;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
        ROLLBACK;
        RESIGNAL;
    END;

    SET v_max       = CAST(IFNULL(fn_get_setting('security.max_failed_logins'), '5')  AS SIGNED);
    SET v_lock_mins = CAST(IFNULL(fn_get_setting('security.lockout_minutes'),   '15') AS SIGNED);

    SELECT user_id INTO v_user_id FROM app_user WHERE username = p_username;

    START TRANSACTION;
        IF v_user_id IS NOT NULL THEN
            UPDATE app_user
               SET failed_login_attempts = failed_login_attempts + 1
             WHERE user_id = v_user_id;

            SELECT failed_login_attempts INTO v_attempts
            FROM app_user WHERE user_id = v_user_id;

            INSERT INTO security_event (event_type, user_id, username_attempted, ip_address, user_agent, detail, severity)
            VALUES ('LOGIN_FAILED', v_user_id, p_username, p_ip, p_agent,
                    CONCAT('Wrong password, attempt ', v_attempts, ' of ', v_max), 'WARNING');

            IF v_attempts >= v_max THEN
                UPDATE app_user
                   SET locked_until = NOW() + INTERVAL v_lock_mins MINUTE
                 WHERE user_id = v_user_id;

                INSERT INTO security_event (event_type, user_id, username_attempted, ip_address, detail, severity)
                VALUES ('ACCOUNT_LOCKED', v_user_id, p_username, p_ip,
                        CONCAT('Locked for ', v_lock_mins, ' minutes after ', v_attempts, ' failures'),
                        'CRITICAL');
            END IF;
        ELSE
            INSERT INTO security_event (event_type, username_attempted, ip_address, user_agent, detail, severity)
            VALUES ('LOGIN_FAILED', p_username, p_ip, p_agent, 'Unknown username', 'WARNING');
        END IF;
    COMMIT;
END $$

/* ---------------------------------------------------------------------------
   sp_change_password
   ------------------------------------------------------------------------ */
DROP PROCEDURE IF EXISTS sp_change_password $$
CREATE PROCEDURE sp_change_password(
        IN p_user_id  INT UNSIGNED,
        IN p_new_hash VARCHAR(255),
        IN p_ip       VARCHAR(45))
MODIFIES SQL DATA
BEGIN
    DECLARE v_msg TEXT;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
        ROLLBACK;
        RESIGNAL;
    END;

    IF CHAR_LENGTH(p_new_hash) < 20 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'SCAS: password hash is not a valid bcrypt hash';
    END IF;

    START TRANSACTION;
        UPDATE app_user
           SET password_hash        = p_new_hash,
               password_changed_at  = NOW(),
               must_change_password = 0,
               failed_login_attempts = 0,
               locked_until         = NULL
         WHERE user_id = p_user_id;

        INSERT INTO security_event (event_type, user_id, ip_address, detail)
        VALUES ('PASSWORD_CHANGED', p_user_id, p_ip, 'Password updated by user');
    COMMIT;
END $$

/* ---------------------------------------------------------------------------
   sp_unlock_account - administrative unlock.
   ------------------------------------------------------------------------ */
DROP PROCEDURE IF EXISTS sp_unlock_account $$
CREATE PROCEDURE sp_unlock_account(
        IN p_user_id  INT UNSIGNED,
        IN p_actor_id INT UNSIGNED)
MODIFIES SQL DATA
BEGIN
    DECLARE v_priv TINYINT UNSIGNED DEFAULT 0;
    DECLARE v_msg  TEXT;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
        ROLLBACK;
        RESIGNAL;
    END;

    SELECT r.privilege_level INTO v_priv
    FROM app_user u JOIN user_role r ON r.role_id = u.role_id
    WHERE u.user_id = p_actor_id;

    IF IFNULL(v_priv, 0) < 90 THEN
        INSERT INTO security_event (event_type, user_id, detail, severity)
        VALUES ('PRIVILEGE_DENIED', p_actor_id, 'Attempt to unlock an account without admin rights', 'CRITICAL');
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'SCAS: only an administrator may unlock an account';
    END IF;

    START TRANSACTION;
        UPDATE app_user
           SET locked_until = NULL, failed_login_attempts = 0
         WHERE user_id = p_user_id;

        INSERT INTO security_event (event_type, user_id, detail)
        VALUES ('ACCOUNT_UNLOCKED', p_user_id, CONCAT('Unlocked by user #', p_actor_id));
    COMMIT;
END $$

/* ---------------------------------------------------------------------------
   sp_create_user
   Creates the login and, when a staff number is supplied, the matching
   teacher record - the two halves of the 1:1 relationship must both exist or
   neither must. This is the textbook Atomicity case, so the whole thing runs
   in one transaction with a SAVEPOINT before the optional teacher half.
   ------------------------------------------------------------------------ */
DROP PROCEDURE IF EXISTS sp_create_user $$
CREATE PROCEDURE sp_create_user(
        IN  p_full_name     VARCHAR(100),
        IN  p_username      VARCHAR(40),
        IN  p_password_hash VARCHAR(255),
        IN  p_role_id       TINYINT UNSIGNED,
        IN  p_school_id     INT UNSIGNED,
        IN  p_phone         VARCHAR(20),
        IN  p_email         VARCHAR(100),
        IN  p_staff_number  VARCHAR(20),
        IN  p_department    VARCHAR(60),
        IN  p_qualification VARCHAR(60),
        IN  p_date_employed DATE,
        OUT p_user_id       INT UNSIGNED,
        OUT p_teacher_id    INT UNSIGNED)
MODIFIES SQL DATA
BEGIN
    DECLARE v_msg TEXT;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
        ROLLBACK;
        SET p_user_id = NULL, p_teacher_id = NULL;
        RESIGNAL;
    END;

    SET p_teacher_id = NULL;

    START TRANSACTION;
        INSERT INTO app_user (full_name, username, password_hash, role_id, school_id,
                              phone_number, email, must_change_password)
        VALUES (p_full_name, LOWER(TRIM(p_username)), p_password_hash, p_role_id, p_school_id,
                p_phone, p_email, 1);

        SET p_user_id = LAST_INSERT_ID();

        SAVEPOINT before_teacher;

        IF p_staff_number IS NOT NULL AND p_staff_number <> '' THEN
            INSERT INTO teacher (user_id, staff_number, department, qualification, date_employed)
            VALUES (p_user_id, p_staff_number, IFNULL(p_department, 'Unassigned'),
                    p_qualification, IFNULL(p_date_employed, CURDATE()));
            SET p_teacher_id = LAST_INSERT_ID();
        END IF;

        INSERT INTO security_event (event_type, user_id, detail)
        VALUES ('USER_CREATED', p_user_id,
                CONCAT('Account created for ', p_full_name,
                       IF(p_teacher_id IS NULL, ' (non-teaching)', ' (teaching)')));
    COMMIT;
END $$

/* ---------------------------------------------------------------------------
   sp_set_user_active - deactivate / reactivate without deleting, so the audit
   trail and historical attendance stay intact (referential integrity would
   block a DELETE anyway - that is deliberate).
   ------------------------------------------------------------------------ */
DROP PROCEDURE IF EXISTS sp_set_user_active $$
CREATE PROCEDURE sp_set_user_active(
        IN p_user_id  INT UNSIGNED,
        IN p_active   TINYINT(1),
        IN p_actor_id INT UNSIGNED)
MODIFIES SQL DATA
BEGIN
    DECLARE v_msg TEXT;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;
        UPDATE app_user SET is_active = p_active WHERE user_id = p_user_id;

        INSERT INTO security_event (event_type, user_id, detail, severity)
        VALUES (IF(p_active = 1, 'USER_CREATED', 'USER_DEACTIVATED'), p_user_id,
                CONCAT(IF(p_active = 1, 'Reactivated', 'Deactivated'), ' by user #', p_actor_id),
                'WARNING');
    COMMIT;
END $$

/* ###########################################################################
   SECTION 2 - QR CODE LIFECYCLE
   ######################################################################### */

/* ---------------------------------------------------------------------------
   sp_generate_qr_code
   Produces the one code that is valid for a given session on a given day.
   Guards applied before anything is written:
     - the session must exist and be active
     - the requested date must fall on the session's day of the week
     - the date must not be a holiday
   If a code already exists for that session and day it is revoked and
   replaced, all inside one transaction, so there is never a moment when two
   codes are simultaneously valid for the same session.
   ------------------------------------------------------------------------ */
DROP PROCEDURE IF EXISTS sp_generate_qr_code $$
CREATE PROCEDURE sp_generate_qr_code(
        IN  p_timetable_id      INT UNSIGNED,
        IN  p_session_date      DATE,
        IN  p_validity_minutes  INT,
        IN  p_generated_by      INT UNSIGNED,
        OUT p_qr_code_id        INT UNSIGNED,
        OUT p_code_value        VARCHAR(64))
MODIFIES SQL DATA
BEGIN
    DECLARE v_day        VARCHAR(10);
    DECLARE v_active     TINYINT(1);
    DECLARE v_start      TIME;
    DECLARE v_end        TIME;
    DECLARE v_school     INT UNSIGNED;
    DECLARE v_existing   INT UNSIGNED DEFAULT NULL;
    DECLARE v_token      VARCHAR(64);
    DECLARE v_expiry     DATETIME;
    DECLARE v_msg        TEXT;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
        ROLLBACK;
        RESIGNAL;
    END;

    IF p_validity_minutes IS NULL OR p_validity_minutes < 1 THEN
        SET p_validity_minutes = CAST(IFNULL(fn_get_setting('qr.validity_minutes'), '30') AS SIGNED);
    END IF;

    SELECT tt.day_of_week, tt.is_active, tt.start_time, tt.end_time, c.school_id
      INTO v_day, v_active, v_start, v_end, v_school
    FROM timetable tt
    JOIN classroom c ON c.classroom_id = tt.classroom_id
    WHERE tt.timetable_id = p_timetable_id;

    IF v_day IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'SCAS: timetable session does not exist';
    END IF;
    IF v_active = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'SCAS: cannot issue a code for an inactive session';
    END IF;
    IF DAYNAME(p_session_date) <> v_day THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'SCAS: that session does not run on the requested day';
    END IF;
    IF fn_is_holiday(v_school, p_session_date) = 1 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'SCAS: the requested date is a holiday';
    END IF;

    SET v_token  = fn_generate_token(p_timetable_id, p_session_date);
    SET v_expiry = NOW() + INTERVAL p_validity_minutes MINUTE;

    START TRANSACTION;
        SELECT qr_code_id INTO v_existing
        FROM qr_code
        WHERE timetable_id = p_timetable_id AND session_date = p_session_date
        FOR UPDATE;

        IF v_existing IS NOT NULL THEN
            /* Replace, do not duplicate: uk_qr_session allows only one row. */
            DELETE FROM qr_code WHERE qr_code_id = v_existing AND scan_count = 0;

            IF ROW_COUNT() = 0 THEN
                /* The old code was already used, so it must be kept for the
                   audit trail. Revoke it in place and reissue is not possible
                   under uk_qr_session, so refuse clearly. */
                ROLLBACK;
                SIGNAL SQLSTATE '45000'
                    SET MESSAGE_TEXT = 'SCAS: a code for this session has already been scanned today';
            END IF;
        END IF;

        INSERT INTO qr_code (timetable_id, code_value, session_date,
                             generated_datetime, expiry_datetime, generated_by, max_scans)
        VALUES (p_timetable_id, v_token, p_session_date, NOW(), v_expiry, p_generated_by, 1);

        SET p_qr_code_id = LAST_INSERT_ID();
        SET p_code_value = v_token;
    COMMIT;
END $$

/* ---------------------------------------------------------------------------
   sp_revoke_qr_code - kill a leaked code immediately.
   ------------------------------------------------------------------------ */
DROP PROCEDURE IF EXISTS sp_revoke_qr_code $$
CREATE PROCEDURE sp_revoke_qr_code(
        IN p_qr_code_id INT UNSIGNED,
        IN p_reason     VARCHAR(100),
        IN p_actor_id   INT UNSIGNED)
MODIFIES SQL DATA
BEGIN
    DECLARE v_msg TEXT;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;
        UPDATE qr_code
           SET is_revoked = 1,
               revoked_reason = IFNULL(p_reason, 'Revoked by administrator')
         WHERE qr_code_id = p_qr_code_id;

        IF ROW_COUNT() = 0 THEN
            ROLLBACK;
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'SCAS: QR code not found';
        END IF;

        INSERT INTO security_event (event_type, user_id, detail, severity)
        VALUES ('QR_REPLAY_BLOCKED', p_actor_id,
                CONCAT('QR code #', p_qr_code_id, ' revoked: ', IFNULL(p_reason, 'no reason given')),
                'WARNING');
    COMMIT;
END $$

/* ###########################################################################
   SECTION 3 - ATTENDANCE CAPTURE (the hot path)
   ######################################################################### */

/* ---------------------------------------------------------------------------
   sp_record_attendance
   Called when a teacher scans a QR code.

   Concurrency: the QR row is locked with SELECT ... FOR UPDATE before the
   scan counter is read. Without that lock two concurrent scans of a
   single-use code could both read scan_count = 0 and both be accepted - the
   classic lost-update anomaly. With it, the second scan waits, then sees
   scan_count = 1 and is rejected as EXHAUSTED.

   Rejections are deliberately committed, not rolled back: the business insert
   is discarded but the security_event recording the attempt must survive,
   otherwise an attacker could probe codes and leave no trace. That is why the
   security write happens after ROLLBACK, in its own autocommitted statement.

   Output p_result: OK | NOT_A_TEACHER | NOT_FOUND | REVOKED | EXPIRED |
                    EXHAUSTED | NOT_YET_VALID | WRONG_TEACHER | DUPLICATE
   ------------------------------------------------------------------------ */
DROP PROCEDURE IF EXISTS sp_record_attendance $$
CREATE PROCEDURE sp_record_attendance(
        IN  p_user_id       INT UNSIGNED,
        IN  p_code_value    VARCHAR(64),
        IN  p_ip            VARCHAR(45),
        IN  p_device        VARCHAR(120),
        OUT p_result        VARCHAR(20),
        OUT p_message       VARCHAR(200),
        OUT p_attendance_id BIGINT UNSIGNED,
        OUT p_status        VARCHAR(10))
MODIFIES SQL DATA
proc: BEGIN
    DECLARE v_teacher_id     INT UNSIGNED DEFAULT NULL;
    DECLARE v_qr_id          INT UNSIGNED DEFAULT NULL;
    DECLARE v_qr_teacher     INT UNSIGNED DEFAULT NULL;
    DECLARE v_timetable_id   INT UNSIGNED;
    DECLARE v_session_date   DATE;
    DECLARE v_subject        VARCHAR(60);
    DECLARE v_qr_state       VARCHAR(20);
    DECLARE v_dupe           INT DEFAULT 0;
    DECLARE v_msg            TEXT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
        ROLLBACK;
        SET p_result  = 'ERROR';
        SET p_message = v_msg;
        SET p_attendance_id = NULL;
        SET p_status  = NULL;
    END;

    SET p_result = 'ERROR', p_message = NULL, p_attendance_id = NULL, p_status = NULL;

    /* Who is scanning? */
    SELECT teacher_id INTO v_teacher_id FROM teacher WHERE user_id = p_user_id;
    IF v_teacher_id IS NULL THEN
        SET p_result = 'NOT_A_TEACHER';
        SET p_message = 'This account is not linked to a teacher record.';
        LEAVE proc;
    END IF;

    START TRANSACTION;

    /* Lock the code row for the duration of the check-and-insert. */
    SELECT q.qr_code_id, q.timetable_id, q.session_date, tt.teacher_id, tt.subject
      INTO v_qr_id, v_timetable_id, v_session_date, v_qr_teacher, v_subject
    FROM qr_code q
    JOIN timetable tt ON tt.timetable_id = q.timetable_id
    WHERE q.code_value = p_code_value
    FOR UPDATE;

    IF v_qr_id IS NULL THEN
        ROLLBACK;
        SET p_result = 'NOT_FOUND';
        SET p_message = 'That code is not recognised.';
        INSERT INTO security_event (event_type, user_id, ip_address, detail, severity)
        VALUES ('QR_REPLAY_BLOCKED', p_user_id, p_ip, 'Scan of an unknown code value', 'WARNING');
        LEAVE proc;
    END IF;

    /* Validity: single source of truth, shared with the trigger. */
    SET v_qr_state = fn_qr_status(p_code_value);

    IF v_qr_state <> 'VALID' THEN
        ROLLBACK;
        SET p_result = v_qr_state;
        SET p_message = CASE v_qr_state
            WHEN 'REVOKED'       THEN 'This code was cancelled by the school administrator.'
            WHEN 'EXPIRED'       THEN 'This code has expired. Ask for a new one.'
            WHEN 'EXHAUSTED'     THEN 'This code has already been used.'
            WHEN 'NOT_YET_VALID' THEN 'This code is not active yet.'
            ELSE 'This code cannot be used.' END;

        INSERT INTO security_event (event_type, user_id, ip_address, detail, severity)
        VALUES (IF(v_qr_state = 'EXPIRED', 'QR_EXPIRED_BLOCKED', 'QR_REPLAY_BLOCKED'),
                p_user_id, p_ip,
                CONCAT('Scan rejected (', v_qr_state, ') for session #', v_timetable_id),
                'WARNING');
        LEAVE proc;
    END IF;

    /* A teacher may only check in to their OWN scheduled session. Without
       this test, teacher B could scan the code displayed in teacher A's
       classroom and be marked present for a class they do not teach. */
    IF v_qr_teacher <> v_teacher_id THEN
        ROLLBACK;
        SET p_result = 'WRONG_TEACHER';
        SET p_message = 'This code belongs to another teacher''s session.';
        INSERT INTO security_event (event_type, user_id, ip_address, detail, severity)
        VALUES ('QR_REPLAY_BLOCKED', p_user_id, p_ip,
                CONCAT('Teacher #', v_teacher_id, ' scanned a code for teacher #', v_qr_teacher),
                'CRITICAL');
        LEAVE proc;
    END IF;

    /* Already recorded for this session today? */
    SELECT COUNT(*) INTO v_dupe
    FROM attendance
    WHERE timetable_id = v_timetable_id
      AND session_date = v_session_date
      AND teacher_id   = v_teacher_id;

    IF v_dupe > 0 THEN
        ROLLBACK;
        SET p_result = 'DUPLICATE';
        SET p_message = 'Your attendance for this session has already been recorded.';
        LEAVE proc;
    END IF;

    /* The insert. status is a placeholder: trg_attendance_bi recomputes the
       Present/Late verdict and derives timetable_id and session_date from the
       QR code, so those values cannot be forged by the caller. */
    INSERT INTO attendance (teacher_id, qr_code_id, timetable_id, session_date,
                            scan_datetime, status, scan_ip, device_info, recorded_by)
    VALUES (v_teacher_id, v_qr_id, v_timetable_id, v_session_date,
            NOW(), 'Present', p_ip, p_device, p_user_id);

    SET p_attendance_id = LAST_INSERT_ID();

    SELECT status INTO p_status FROM attendance WHERE attendance_id = p_attendance_id;

    /* The notification is a convenience, not part of the attendance fact.
       SAVEPOINT lets a failure here be discarded without losing the scan. */
    SAVEPOINT after_attendance;
    BEGIN
        DECLARE CONTINUE HANDLER FOR SQLEXCEPTION ROLLBACK TO SAVEPOINT after_attendance;
        INSERT INTO notification (user_id, title, message, notif_type)
        VALUES (p_user_id, 'Attendance recorded',
                CONCAT(v_subject, ' on ', DATE_FORMAT(v_session_date, '%d %b %Y'),
                       ' marked ', p_status, '.'),
                IF(p_status = 'Late', 'WARNING', 'SUCCESS'));
    END;

    COMMIT;

    SET p_result  = 'OK';
    SET p_message = CONCAT('Checked in for ', v_subject, ' - marked ', p_status, '.');
END $$

/* ---------------------------------------------------------------------------
   sp_mark_absentees
   The nightly job. Walks every session that was scheduled on the given date
   and has no attendance row, and writes the missing verdict:
     - approved leave      -> Excused
     - anything else       -> Absent
   Holidays are skipped entirely. Uses an explicit CURSOR so each session is
   evaluated individually and one bad row cannot abort the whole run.
   ------------------------------------------------------------------------ */
DROP PROCEDURE IF EXISTS sp_mark_absentees $$
CREATE PROCEDURE sp_mark_absentees(
        IN  p_session_date DATE,
        IN  p_school_id    INT UNSIGNED,
        OUT p_absent_count INT,
        OUT p_excused_count INT)
MODIFIES SQL DATA
proc: BEGIN
    DECLARE v_done        TINYINT DEFAULT 0;
    DECLARE v_timetable   INT UNSIGNED;
    DECLARE v_teacher     INT UNSIGNED;
    DECLARE v_school      INT UNSIGNED;
    DECLARE v_msg         TEXT;

    DECLARE cur_missing CURSOR FOR
        SELECT tt.timetable_id, tt.teacher_id, c.school_id
        FROM timetable tt
        JOIN classroom c      ON c.classroom_id = tt.classroom_id
        JOIN academic_term at ON at.term_id     = tt.term_id
        WHERE tt.is_active = 1
          AND at.is_current = 1
          AND tt.day_of_week = DAYNAME(p_session_date)
          AND p_session_date BETWEEN at.start_date AND at.end_date
          AND (p_school_id IS NULL OR c.school_id = p_school_id)
          AND NOT EXISTS (
                SELECT 1 FROM attendance a
                WHERE a.timetable_id = tt.timetable_id
                  AND a.session_date = p_session_date
                  AND a.teacher_id   = tt.teacher_id);

    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_done = 1;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
        ROLLBACK;
        RESIGNAL;
    END;

    SET p_absent_count = 0, p_excused_count = 0;

    START TRANSACTION;

    OPEN cur_missing;
    read_loop: LOOP
        FETCH cur_missing INTO v_timetable, v_teacher, v_school;
        IF v_done = 1 THEN
            LEAVE read_loop;
        END IF;

        IF fn_is_holiday(v_school, p_session_date) = 0 THEN
            IF fn_is_on_leave(v_teacher, p_session_date) = 1 THEN
                INSERT INTO attendance (teacher_id, qr_code_id, timetable_id, session_date,
                                        scan_datetime, status, recorded_by, remarks)
                VALUES (v_teacher, NULL, v_timetable, p_session_date,
                        TIMESTAMP(p_session_date, '23:59:00'), 'Excused', NULL,
                        'Approved leave - excluded from absenteeism');
                SET p_excused_count = p_excused_count + 1;
            ELSE
                INSERT INTO attendance (teacher_id, qr_code_id, timetable_id, session_date,
                                        scan_datetime, status, recorded_by, remarks)
                VALUES (v_teacher, NULL, v_timetable, p_session_date,
                        TIMESTAMP(p_session_date, '23:59:00'), 'Absent', NULL,
                        'No check-in recorded for this session');
                SET p_absent_count = p_absent_count + 1;
            END IF;
        END IF;
    END LOOP;
    CLOSE cur_missing;

    COMMIT;
END $$

/* ###########################################################################
   SECTION 4 - LEAVE WORKFLOW
   ######################################################################### */

DROP PROCEDURE IF EXISTS sp_submit_leave_request $$
CREATE PROCEDURE sp_submit_leave_request(
        IN  p_teacher_id INT UNSIGNED,
        IN  p_leave_type VARCHAR(20),
        IN  p_start_date DATE,
        IN  p_end_date   DATE,
        IN  p_reason     VARCHAR(150),
        OUT p_request_id INT UNSIGNED)
MODIFIES SQL DATA
BEGIN
    DECLARE v_msg TEXT;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;
        INSERT INTO leave_request (teacher_id, leave_type, start_date, end_date, reason)
        VALUES (p_teacher_id, p_leave_type, p_start_date, p_end_date, p_reason);

        SET p_request_id = LAST_INSERT_ID();

        /* Notify every user who can approve leave at this teacher's school. */
        INSERT INTO notification (user_id, title, message, notif_type)
        SELECT hu.user_id, 'New leave request',
               CONCAT(tu.full_name, ' requested ', p_leave_type, ' leave, ',
                      DATE_FORMAT(p_start_date, '%d %b'), ' to ',
                      DATE_FORMAT(p_end_date, '%d %b %Y'), '.'),
               'INFO'
        FROM teacher   t
        JOIN app_user  tu ON tu.user_id = t.user_id
        JOIN app_user  hu ON hu.school_id = tu.school_id AND hu.is_active = 1
        JOIN user_role hr ON hr.role_id = hu.role_id AND hr.privilege_level >= 50
        WHERE t.teacher_id = p_teacher_id;
    COMMIT;
END $$

/* ---------------------------------------------------------------------------
   sp_action_leave_request
   Approve or reject. Two things make this more than an UPDATE:
   1. Authorisation is enforced in the database, not only in PHP - a caller
      below privilege 50 is refused and the attempt is logged.
   2. On approval, Absent rows already written for days inside the approved
      range are corrected to Excused, so approved leave stops counting as
      absenteeism (proposal problem 4). That correction is wrapped in a
      SAVEPOINT: if it fails, the approval itself still stands.
   ------------------------------------------------------------------------ */
DROP PROCEDURE IF EXISTS sp_action_leave_request $$
CREATE PROCEDURE sp_action_leave_request(
        IN  p_request_id  INT UNSIGNED,
        IN  p_action      VARCHAR(10),
        IN  p_actor_id    INT UNSIGNED,
        IN  p_remarks     VARCHAR(200),
        OUT p_rows_corrected INT)
MODIFIES SQL DATA
BEGIN
    DECLARE v_priv       TINYINT UNSIGNED DEFAULT 0;
    DECLARE v_status     VARCHAR(10);
    DECLARE v_teacher    INT UNSIGNED;
    DECLARE v_start      DATE;
    DECLARE v_end        DATE;
    DECLARE v_user       INT UNSIGNED;
    DECLARE v_msg        TEXT;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
        ROLLBACK;
        RESIGNAL;
    END;

    SET p_rows_corrected = 0;

    IF p_action NOT IN ('Approved','Rejected','Cancelled') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'SCAS: action must be Approved, Rejected or Cancelled';
    END IF;

    SELECT r.privilege_level INTO v_priv
    FROM app_user u JOIN user_role r ON r.role_id = u.role_id
    WHERE u.user_id = p_actor_id;

    IF IFNULL(v_priv, 0) < 50 THEN
        INSERT INTO security_event (event_type, user_id, detail, severity)
        VALUES ('PRIVILEGE_DENIED', p_actor_id,
                CONCAT('Attempt to action leave request #', p_request_id, ' without approver rights'),
                'CRITICAL');
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'SCAS: you are not authorised to action leave requests';
    END IF;

    SELECT lr.status, lr.teacher_id, lr.start_date, lr.end_date, t.user_id
      INTO v_status, v_teacher, v_start, v_end, v_user
    FROM leave_request lr
    JOIN teacher t ON t.teacher_id = lr.teacher_id
    WHERE lr.leave_request_id = p_request_id;

    IF v_status IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'SCAS: leave request not found';
    END IF;
    IF v_status <> 'Pending' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'SCAS: this request has already been actioned';
    END IF;

    START TRANSACTION;
        UPDATE leave_request
           SET status      = p_action,
               approved_by = p_actor_id,
               actioned_at = NOW(),
               remarks     = p_remarks
         WHERE leave_request_id = p_request_id;

        SAVEPOINT before_correction;
        BEGIN
            DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
                ROLLBACK TO SAVEPOINT before_correction;

            IF p_action = 'Approved' THEN
                UPDATE attendance
                   SET status  = 'Excused',
                       remarks = CONCAT('Reclassified by approved leave request #', p_request_id)
                 WHERE teacher_id  = v_teacher
                   AND status      = 'Absent'
                   AND session_date BETWEEN v_start AND v_end;
                SET p_rows_corrected = ROW_COUNT();
            END IF;
        END;

        INSERT INTO notification (user_id, title, message, notif_type)
        VALUES (v_user, CONCAT('Leave request ', p_action),
                CONCAT('Your leave for ', DATE_FORMAT(v_start, '%d %b'), ' to ',
                       DATE_FORMAT(v_end, '%d %b %Y'), ' was ', LOWER(p_action), '.'),
                IF(p_action = 'Approved', 'SUCCESS', 'WARNING'));
    COMMIT;
END $$

/* ###########################################################################
   SECTION 5 - REPORTING
   ######################################################################### */

DROP PROCEDURE IF EXISTS sp_monthly_attendance_report $$
CREATE PROCEDURE sp_monthly_attendance_report(
        IN p_school_id INT UNSIGNED,
        IN p_year      SMALLINT,
        IN p_month     TINYINT)
READS SQL DATA
BEGIN
    SELECT  staff_number,
            teacher_name,
            department,
            sessions_recorded,
            present_count,
            late_count,
            absent_count,
            excused_count,
            total_minutes_late,
            attendance_rate,
            CASE
                WHEN attendance_rate >= 95 THEN 'Excellent'
                WHEN attendance_rate >= 85 THEN 'Good'
                WHEN attendance_rate >= 70 THEN 'Needs improvement'
                ELSE 'Unsatisfactory'
            END AS rating
    FROM v_monthly_attendance_summary
    WHERE school_id     = p_school_id
      AND session_year  = p_year
      AND session_month = p_month
    ORDER BY attendance_rate DESC, teacher_name;
END $$

DROP PROCEDURE IF EXISTS sp_teacher_attendance_summary $$
CREATE PROCEDURE sp_teacher_attendance_summary(
        IN p_teacher_id INT UNSIGNED,
        IN p_from       DATE,
        IN p_to         DATE)
READS SQL DATA
BEGIN
    SELECT  session_date,
            subject,
            class_group,
            room_name,
            start_time,
            status,
            minutes_late,
            scan_datetime,
            remarks
    FROM v_attendance_detail
    WHERE teacher_id = p_teacher_id
      AND session_date BETWEEN p_from AND p_to
    ORDER BY session_date DESC, start_time;

    SELECT  COUNT(*)                    AS sessions,
            SUM(status = 'Present')     AS present_count,
            SUM(status = 'Late')        AS late_count,
            SUM(status = 'Absent')      AS absent_count,
            SUM(status = 'Excused')     AS excused_count,
            fn_attendance_rate(p_teacher_id, p_from, p_to) AS attendance_rate
    FROM attendance
    WHERE teacher_id = p_teacher_id
      AND session_date BETWEEN p_from AND p_to;
END $$

/* ---------------------------------------------------------------------------
   sp_refresh_attendance_summary - rebuilds the materialised aggregate for a
   date range. INSERT ... ON DUPLICATE KEY UPDATE makes the refresh idempotent,
   so re-running it never double counts.
   ------------------------------------------------------------------------ */
DROP PROCEDURE IF EXISTS sp_refresh_attendance_summary $$
CREATE PROCEDURE sp_refresh_attendance_summary(
        IN  p_from DATE,
        IN  p_to   DATE,
        OUT p_rows INT)
MODIFIES SQL DATA
BEGIN
    DECLARE v_msg TEXT;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;
        INSERT INTO attendance_daily_summary
            (school_id, teacher_id, summary_date, sessions_scheduled,
             present_count, late_count, absent_count, excused_count, attendance_rate)
        SELECT  c.school_id,
                a.teacher_id,
                a.session_date,
                COUNT(*),
                SUM(a.status = 'Present'),
                SUM(a.status = 'Late'),
                SUM(a.status = 'Absent'),
                SUM(a.status = 'Excused'),
                ROUND(SUM(a.status IN ('Present','Late')) * 100.0
                      / NULLIF(SUM(a.status <> 'Excused'), 0), 2)
        FROM attendance a
        JOIN timetable  tt ON tt.timetable_id = a.timetable_id
        JOIN classroom  c  ON c.classroom_id  = tt.classroom_id
        WHERE a.session_date BETWEEN p_from AND p_to
        GROUP BY c.school_id, a.teacher_id, a.session_date
        ON DUPLICATE KEY UPDATE
            sessions_scheduled = VALUES(sessions_scheduled),
            present_count      = VALUES(present_count),
            late_count         = VALUES(late_count),
            absent_count       = VALUES(absent_count),
            excused_count      = VALUES(excused_count),
            attendance_rate    = VALUES(attendance_rate);

        SET p_rows = ROW_COUNT();
    COMMIT;
END $$

/* ###########################################################################
   SECTION 6 - ADMINISTRATION AND MAINTENANCE
   ######################################################################### */

/* ---------------------------------------------------------------------------
   sp_transfer_teacher_sessions
   Reassign a departing teacher's sessions to a colleague. This is the
   procedure used in the teaching demonstration of partial rollback: the
   timetable rows move first, then the optional notification block runs inside
   a SAVEPOINT. A clash on any single session aborts the WHOLE transfer -
   a half-moved timetable would leave classes unstaffed, so all-or-nothing is
   the correct semantic here.
   ------------------------------------------------------------------------ */
DROP PROCEDURE IF EXISTS sp_transfer_teacher_sessions $$
CREATE PROCEDURE sp_transfer_teacher_sessions(
        IN  p_from_teacher INT UNSIGNED,
        IN  p_to_teacher   INT UNSIGNED,
        IN  p_actor_id     INT UNSIGNED,
        OUT p_moved        INT)
MODIFIES SQL DATA
BEGIN
    DECLARE v_msg TEXT;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
        ROLLBACK;
        SET p_moved = 0;
        RESIGNAL;
    END;

    IF p_from_teacher = p_to_teacher THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'SCAS: source and destination teacher are the same';
    END IF;

    START TRANSACTION;
        UPDATE timetable
           SET teacher_id = p_to_teacher
         WHERE teacher_id = p_from_teacher
           AND is_active  = 1;

        SET p_moved = ROW_COUNT();

        SAVEPOINT after_move;
        BEGIN
            DECLARE CONTINUE HANDLER FOR SQLEXCEPTION ROLLBACK TO SAVEPOINT after_move;
            INSERT INTO notification (user_id, title, message, notif_type)
            SELECT t.user_id, 'Timetable updated',
                   CONCAT(p_moved, ' session(s) were transferred to you.'), 'INFO'
            FROM teacher t WHERE t.teacher_id = p_to_teacher;
        END;
    COMMIT;
END $$

/* ---------------------------------------------------------------------------
   sp_archive_old_attendance
   Moves closed-year rows into the partitioned archive.
   @scas_allow_archive_delete is the controlled override for the trigger that
   otherwise forbids DELETE on attendance: the flag is set here, cleared here,
   and set nowhere else, so the ledger stays immutable to every other caller.
   ------------------------------------------------------------------------ */
DROP PROCEDURE IF EXISTS sp_archive_old_attendance $$
CREATE PROCEDURE sp_archive_old_attendance(
        IN  p_cutoff_date DATE,
        OUT p_moved       INT)
MODIFIES SQL DATA
BEGIN
    DECLARE v_copied INT DEFAULT 0;
    DECLARE v_msg    TEXT;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
        ROLLBACK;
        SET @scas_allow_archive_delete = NULL;
        SET p_moved = 0;
        RESIGNAL;
    END;

    SET p_moved = 0;

    START TRANSACTION;
        INSERT INTO attendance_archive
            (attendance_id, teacher_id, qr_code_id, timetable_id, session_date,
             scan_datetime, status, minutes_late, remarks)
        SELECT attendance_id, teacher_id, qr_code_id, timetable_id, session_date,
               scan_datetime, status, minutes_late, remarks
        FROM attendance
        WHERE session_date < p_cutoff_date;

        SET v_copied = ROW_COUNT();

        /* Only delete what is provably in the archive - never trust the
           WHERE clause alone when the operation is destructive. */
        SET @scas_allow_archive_delete = 1;

        DELETE a FROM attendance a
        JOIN attendance_archive ar
          ON ar.attendance_id = a.attendance_id
         AND ar.session_date  = a.session_date
        WHERE a.session_date < p_cutoff_date;

        SET p_moved = ROW_COUNT();
        SET @scas_allow_archive_delete = NULL;

        IF p_moved <> v_copied THEN
            ROLLBACK;
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'SCAS: archive row count mismatch - transaction rolled back';
        END IF;
    COMMIT;
END $$

/* ---------------------------------------------------------------------------
   sp_detect_timetable_conflicts - reports overlapping sessions that predate
   the clash triggers, or that a direct DBA edit introduced.
   ------------------------------------------------------------------------ */
DROP PROCEDURE IF EXISTS sp_detect_timetable_conflicts $$
CREATE PROCEDURE sp_detect_timetable_conflicts(IN p_term_id SMALLINT UNSIGNED)
READS SQL DATA
BEGIN
    SELECT  'TEACHER DOUBLE-BOOKED' AS conflict_type,
            a.timetable_id AS session_a, b.timetable_id AS session_b,
            ua.full_name   AS teacher_name,
            a.day_of_week, a.start_time AS a_start, a.end_time AS a_end,
            b.start_time AS b_start, b.end_time AS b_end
    FROM timetable a
    JOIN timetable b
      ON  a.teacher_id  = b.teacher_id
      AND a.term_id     = b.term_id
      AND a.day_of_week = b.day_of_week
      AND a.timetable_id < b.timetable_id
      AND a.start_time   < b.end_time
      AND b.start_time   < a.end_time
    JOIN teacher  t  ON t.teacher_id = a.teacher_id
    JOIN app_user ua ON ua.user_id   = t.user_id
    WHERE a.is_active = 1 AND b.is_active = 1
      AND (p_term_id IS NULL OR a.term_id = p_term_id)

    UNION ALL

    SELECT  'ROOM DOUBLE-BOOKED',
            a.timetable_id, b.timetable_id,
            c.room_name,
            a.day_of_week, a.start_time, a.end_time, b.start_time, b.end_time
    FROM timetable a
    JOIN timetable b
      ON  a.classroom_id = b.classroom_id
      AND a.term_id      = b.term_id
      AND a.day_of_week  = b.day_of_week
      AND a.timetable_id < b.timetable_id
      AND a.start_time    < b.end_time
      AND b.start_time    < a.end_time
    JOIN classroom c ON c.classroom_id = a.classroom_id
    WHERE a.is_active = 1 AND b.is_active = 1
      AND (p_term_id IS NULL OR a.term_id = p_term_id);
END $$

/* ---------------------------------------------------------------------------
   sp_run_integrity_check - a health report the DBA console displays.
   Each SELECT is a rule that should return zero rows in a healthy database.
   ------------------------------------------------------------------------ */
DROP PROCEDURE IF EXISTS sp_run_integrity_check $$
CREATE PROCEDURE sp_run_integrity_check()
READS SQL DATA
BEGIN
    SELECT 'Attendance rows whose session_date disagrees with its QR code' AS check_name,
           COUNT(*) AS violations
    FROM attendance a JOIN qr_code q ON q.qr_code_id = a.qr_code_id
    WHERE a.session_date <> q.session_date
    UNION ALL
    SELECT 'Attendance rows whose teacher does not own the session',
           COUNT(*)
    FROM attendance a JOIN timetable tt ON tt.timetable_id = a.timetable_id
    WHERE a.teacher_id <> tt.teacher_id
    UNION ALL
    SELECT 'Scanned rows with no QR code (should be Absent/Excused only)',
           COUNT(*)
    FROM attendance WHERE qr_code_id IS NULL AND status IN ('Present','Late')
    UNION ALL
    SELECT 'QR codes whose scan_count exceeds max_scans',
           COUNT(*)
    FROM qr_code WHERE scan_count > max_scans
    UNION ALL
    SELECT 'Teachers with no user account (orphans)',
           COUNT(*)
    FROM teacher t LEFT JOIN app_user u ON u.user_id = t.user_id
    WHERE u.user_id IS NULL
    UNION ALL
    SELECT 'Approved leave still counted as Absent',
           COUNT(*)
    FROM attendance a
    WHERE a.status = 'Absent' AND fn_is_on_leave(a.teacher_id, a.session_date) = 1
    UNION ALL
    SELECT 'Active sessions outside the current term',
           COUNT(*)
    FROM timetable tt JOIN academic_term at ON at.term_id = tt.term_id
    WHERE tt.is_active = 1 AND at.is_current = 0;
END $$

/* ---------------------------------------------------------------------------
   sp_create_timetable_session
   The application account has no INSERT on timetable, so scheduling a session
   has to come through here. The clash rules are not re-implemented: the
   INSERT fires trg_timetable_bi, which refuses an overlap and returns the
   message the user sees. This procedure only adds the authorisation check.
   ------------------------------------------------------------------------ */
DROP PROCEDURE IF EXISTS sp_create_timetable_session $$
CREATE PROCEDURE sp_create_timetable_session(
        IN  p_teacher_id   INT UNSIGNED,
        IN  p_classroom_id INT UNSIGNED,
        IN  p_term_id      SMALLINT UNSIGNED,
        IN  p_subject      VARCHAR(60),
        IN  p_class_group  VARCHAR(30),
        IN  p_day          VARCHAR(10),
        IN  p_start        TIME,
        IN  p_end          TIME,
        IN  p_actor_id     INT UNSIGNED,
        OUT p_timetable_id INT UNSIGNED)
MODIFIES SQL DATA
BEGIN
    DECLARE v_priv TINYINT UNSIGNED DEFAULT 0;
    DECLARE v_msg  TEXT;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
        ROLLBACK;
        SET p_timetable_id = NULL;
        RESIGNAL;
    END;

    SELECT r.privilege_level INTO v_priv
    FROM app_user u JOIN user_role r ON r.role_id = u.role_id
    WHERE u.user_id = p_actor_id;

    IF IFNULL(v_priv, 0) < 90 THEN
        INSERT INTO security_event (event_type, user_id, detail, severity)
        VALUES ('PRIVILEGE_DENIED', p_actor_id,
                'Attempt to schedule a session without administrator rights', 'CRITICAL');
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'SCAS: only a school administrator may change the timetable';
    END IF;

    START TRANSACTION;
        INSERT INTO timetable (teacher_id, classroom_id, term_id, subject,
                               class_group, day_of_week, start_time, end_time)
        VALUES (p_teacher_id, p_classroom_id, p_term_id, p_subject,
                NULLIF(p_class_group, ''), p_day, p_start, p_end);
        SET p_timetable_id = LAST_INSERT_ID();
    COMMIT;
END $$

/* ---------------------------------------------------------------------------
   sp_set_timetable_active - retire or restore a session.
   A timetable row is never deleted: attendance records reference it, and the
   foreign key is RESTRICT precisely so history cannot be orphaned.
   ------------------------------------------------------------------------ */
DROP PROCEDURE IF EXISTS sp_set_timetable_active $$
CREATE PROCEDURE sp_set_timetable_active(
        IN p_timetable_id INT UNSIGNED,
        IN p_active       TINYINT(1),
        IN p_actor_id     INT UNSIGNED)
MODIFIES SQL DATA
BEGIN
    DECLARE v_priv TINYINT UNSIGNED DEFAULT 0;
    DECLARE v_msg  TEXT;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
        ROLLBACK;
        RESIGNAL;
    END;

    SELECT r.privilege_level INTO v_priv
    FROM app_user u JOIN user_role r ON r.role_id = u.role_id
    WHERE u.user_id = p_actor_id;

    IF IFNULL(v_priv, 0) < 90 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'SCAS: only a school administrator may change the timetable';
    END IF;

    START TRANSACTION;
        UPDATE timetable SET is_active = p_active WHERE timetable_id = p_timetable_id;
    COMMIT;
END $$

/* ---------------------------------------------------------------------------
   sp_update_setting - change one runtime setting.
   system_setting is system-versioned, so the previous value is retained
   automatically and can be restored with sp_restore_setting_as_of.
   ------------------------------------------------------------------------ */
DROP PROCEDURE IF EXISTS sp_update_setting $$
CREATE PROCEDURE sp_update_setting(
        IN p_key      VARCHAR(60),
        IN p_value    VARCHAR(255),
        IN p_actor_id INT UNSIGNED)
MODIFIES SQL DATA
BEGIN
    DECLARE v_priv TINYINT UNSIGNED DEFAULT 0;
    DECLARE v_msg  TEXT;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
        ROLLBACK;
        RESIGNAL;
    END;

    SELECT r.privilege_level INTO v_priv
    FROM app_user u JOIN user_role r ON r.role_id = u.role_id
    WHERE u.user_id = p_actor_id;

    IF IFNULL(v_priv, 0) < 99 THEN
        INSERT INTO security_event (event_type, user_id, detail, severity)
        VALUES ('PRIVILEGE_DENIED', p_actor_id,
                CONCAT('Attempt to change setting ', p_key), 'CRITICAL');
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'SCAS: only a system administrator may change settings';
    END IF;

    START TRANSACTION;
        UPDATE system_setting SET setting_value = p_value WHERE setting_key = p_key;
        IF ROW_COUNT() = 0 THEN
            ROLLBACK;
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'SCAS: no such setting';
        END IF;
    COMMIT;
END $$

/* ---------------------------------------------------------------------------
   sp_log_query_performance - called by the PHP data-access layer for any
   statement slower than the configured threshold. Feeds the DBA console.
   ------------------------------------------------------------------------ */
DROP PROCEDURE IF EXISTS sp_log_query_performance $$
CREATE PROCEDURE sp_log_query_performance(
        IN p_label   VARCHAR(80),
        IN p_sql     TEXT,
        IN p_ms      DECIMAL(10,3),
        IN p_rows    INT UNSIGNED,
        IN p_plan    TEXT,
        IN p_by      VARCHAR(100))
MODIFIES SQL DATA
BEGIN
    INSERT INTO query_performance_log (query_label, sql_text, exec_ms, rows_returned, plan_summary, executed_by)
    VALUES (p_label, p_sql, p_ms, p_rows, p_plan, p_by);
END $$

DELIMITER ;

SELECT CONCAT('05 complete - ', COUNT(*), ' stored procedures') AS status
FROM information_schema.ROUTINES
WHERE ROUTINE_SCHEMA = 'scas_db' AND ROUTINE_TYPE = 'PROCEDURE';
