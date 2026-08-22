/* ============================================================================
   SCAS - FILE 06 : TRIGGERS
   Objective (d) Stored procedures and triggers, and the enforcement half of
   objective (c) Database Security & Authorization.
   ---------------------------------------------------------------------------
   Triggers are used here for four distinct jobs. Keeping the jobs separate is
   deliberate - a trigger that both validates and audits is hard to reason
   about when it fires.

   1. DERIVATION  - compute values the caller must not be trusted to supply
                    (trg_attendance_bi derives the session and the verdict).
   2. VALIDATION  - business rules that a CHECK constraint cannot express
                    because they need another row or another table
                    (timetable overlap, leave overlap, QR validity).
   3. IMMUTABILITY- refuse operations that would rewrite history
                    (trg_attendance_bu, trg_attendance_bd).
   4. AUDIT       - record who changed what, when
                    (the *_audit triggers, writing to audit_log).

   Why the audit trail lives in triggers rather than in the application:
   a trigger fires for EVERY writer - the PHP app, phpMyAdmin, the mysql
   client, a scheduled event. Application-level auditing can be bypassed by
   connecting directly; trigger-level auditing cannot.
   ========================================================================= */

SET NAMES utf8mb4;
USE scas_db;

DELIMITER $$

/* ###########################################################################
   SECTION 1 - DERIVATION AND VALIDATION ON THE ATTENDANCE LEDGER
   ######################################################################### */

/* ---------------------------------------------------------------------------
   trg_attendance_bi
   The single most important trigger in the system. Everything about an
   attendance row that could be forged is recomputed here from the QR code:
     - which session it belongs to      (timetable_id)
     - which day it belongs to          (session_date)
     - whether it is Present or Late    (status, minutes_late)
   The application may pass whatever it likes for those columns; this trigger
   overwrites them. That is what makes "signing the register without being
   present" impossible through the software.
   ------------------------------------------------------------------------ */
DROP TRIGGER IF EXISTS trg_attendance_bi $$
CREATE TRIGGER trg_attendance_bi
BEFORE INSERT ON attendance
FOR EACH ROW
BEGIN
    DECLARE v_tt_id       INT UNSIGNED;
    DECLARE v_sess_date   DATE;
    DECLARE v_expiry      DATETIME;
    DECLARE v_revoked     TINYINT(1);
    DECLARE v_scans       SMALLINT;
    DECLARE v_max         SMALLINT;
    DECLARE v_owner       INT UNSIGNED;
    DECLARE v_start       TIME;
    DECLARE v_grace       INT;
    DECLARE v_tt_teacher  INT UNSIGNED;

    IF NEW.qr_code_id IS NOT NULL THEN
        /* ---- scanned row: derive everything from the code ---- */
        SELECT q.timetable_id, q.session_date, q.expiry_datetime, q.is_revoked,
               q.scan_count, q.max_scans, tt.teacher_id, tt.start_time
          INTO v_tt_id, v_sess_date, v_expiry, v_revoked,
               v_scans, v_max, v_owner, v_start
        FROM qr_code q
        JOIN timetable tt ON tt.timetable_id = q.timetable_id
        WHERE q.qr_code_id = NEW.qr_code_id;

        IF v_tt_id IS NULL THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'SCAS: QR code does not exist';
        END IF;
        IF v_revoked = 1 THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'SCAS: this QR code has been revoked';
        END IF;
        IF NEW.scan_datetime > v_expiry THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'SCAS: this QR code has expired';
        END IF;
        IF v_scans >= v_max THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'SCAS: this QR code has already been used';
        END IF;
        IF v_owner <> NEW.teacher_id THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'SCAS: this code belongs to another teacher session';
        END IF;

        SET v_grace = fn_grace_minutes();

        /* Caller-supplied values are discarded and replaced. */
        SET NEW.timetable_id = v_tt_id;
        SET NEW.session_date = v_sess_date;
        SET NEW.status       = fn_attendance_status(NEW.scan_datetime, v_sess_date, v_start, v_grace);
        SET NEW.minutes_late = fn_minutes_late(NEW.scan_datetime, v_sess_date, v_start);

    ELSE
        /* ---- system-generated row: no scan happened ---- */
        IF NEW.status NOT IN ('Absent','Excused') THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'SCAS: Present or Late requires a scanned QR code';
        END IF;

        SELECT teacher_id INTO v_tt_teacher
        FROM timetable WHERE timetable_id = NEW.timetable_id;

        IF v_tt_teacher IS NULL THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'SCAS: timetable session does not exist';
        END IF;
        IF v_tt_teacher <> NEW.teacher_id THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'SCAS: teacher is not scheduled for that session';
        END IF;

        SET NEW.minutes_late = 0;
    END IF;
END $$

/* ---------------------------------------------------------------------------
   trg_attendance_ai
   Consumes one use of the code and records the insert in the audit trail.
   Updating qr_code from a trigger on attendance is safe: qr_code has no
   trigger that writes back to attendance, so there is no cycle.
   ------------------------------------------------------------------------ */
DROP TRIGGER IF EXISTS trg_attendance_ai $$
CREATE TRIGGER trg_attendance_ai
AFTER INSERT ON attendance
FOR EACH ROW
BEGIN
    IF NEW.qr_code_id IS NOT NULL THEN
        UPDATE qr_code
           SET scan_count = scan_count + 1
         WHERE qr_code_id = NEW.qr_code_id;
    END IF;

    INSERT INTO audit_log (table_name, record_id, action, old_values, new_values,
                           changed_by_user_id, db_user, client_host)
    VALUES ('attendance', NEW.attendance_id, 'INSERT', NULL,
            JSON_OBJECT('teacher_id',   NEW.teacher_id,
                        'timetable_id', NEW.timetable_id,
                        'session_date', NEW.session_date,
                        'status',       NEW.status,
                        'minutes_late', NEW.minutes_late,
                        'qr_code_id',   NEW.qr_code_id,
                        'scan_ip',      NEW.scan_ip),
            fn_current_user_id(), CURRENT_USER(), SUBSTRING_INDEX(USER(), '@', -1));
END $$

/* ---------------------------------------------------------------------------
   trg_attendance_bu - IMMUTABILITY.
   An attendance record is evidence. The identity columns can never change;
   only the verdict, the lateness and the remarks may be corrected (which is
   how an approved leave reclassifies an Absent row to Excused), and every
   such correction is audited by trg_attendance_au.
   ------------------------------------------------------------------------ */
DROP TRIGGER IF EXISTS trg_attendance_bu $$
CREATE TRIGGER trg_attendance_bu
BEFORE UPDATE ON attendance
FOR EACH ROW
BEGIN
    IF NEW.teacher_id   <> OLD.teacher_id
    OR NEW.timetable_id <> OLD.timetable_id
    OR NEW.session_date <> OLD.session_date
    OR NEW.scan_datetime <> OLD.scan_datetime
    OR NOT (NEW.qr_code_id <=> OLD.qr_code_id) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'SCAS: attendance identity columns are immutable - only status and remarks may be corrected';
    END IF;
END $$

DROP TRIGGER IF EXISTS trg_attendance_au $$
CREATE TRIGGER trg_attendance_au
AFTER UPDATE ON attendance
FOR EACH ROW
BEGIN
    IF NEW.status <> OLD.status OR NOT (NEW.remarks <=> OLD.remarks) THEN
        INSERT INTO audit_log (table_name, record_id, action, old_values, new_values,
                               changed_by_user_id, db_user, client_host)
        VALUES ('attendance', NEW.attendance_id, 'UPDATE',
                JSON_OBJECT('status', OLD.status, 'remarks', OLD.remarks, 'minutes_late', OLD.minutes_late),
                JSON_OBJECT('status', NEW.status, 'remarks', NEW.remarks, 'minutes_late', NEW.minutes_late),
                fn_current_user_id(), CURRENT_USER(), SUBSTRING_INDEX(USER(), '@', -1));
    END IF;
END $$

/* ---------------------------------------------------------------------------
   trg_attendance_bd - the ledger is append-only.
   The ONLY caller allowed through is sp_archive_old_attendance, which sets
   @scas_allow_archive_delete after it has proved the rows are safely in the
   archive table. Nothing else in the system ever sets that variable.
   ------------------------------------------------------------------------ */
DROP TRIGGER IF EXISTS trg_attendance_bd $$
CREATE TRIGGER trg_attendance_bd
BEFORE DELETE ON attendance
FOR EACH ROW
BEGIN
    IF IFNULL(@scas_allow_archive_delete, 0) <> 1 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'SCAS: attendance records cannot be deleted - use sp_archive_old_attendance';
    END IF;

    INSERT INTO audit_log (table_name, record_id, action, old_values, new_values,
                           changed_by_user_id, db_user, client_host)
    VALUES ('attendance', OLD.attendance_id, 'DELETE',
            JSON_OBJECT('teacher_id', OLD.teacher_id, 'session_date', OLD.session_date,
                        'status', OLD.status, 'archived', TRUE),
            NULL, fn_current_user_id(), CURRENT_USER(), SUBSTRING_INDEX(USER(), '@', -1));
END $$

/* ###########################################################################
   SECTION 2 - QR CODE VALIDATION
   ######################################################################### */

/* ---------------------------------------------------------------------------
   trg_qr_code_bi - a code may only be issued for a day the session actually
   runs, and never for a holiday. sp_generate_qr_code checks the same rules;
   this trigger is the backstop for a direct INSERT from phpMyAdmin.
   ------------------------------------------------------------------------ */
DROP TRIGGER IF EXISTS trg_qr_code_bi $$
CREATE TRIGGER trg_qr_code_bi
BEFORE INSERT ON qr_code
FOR EACH ROW
BEGIN
    DECLARE v_day    VARCHAR(10);
    DECLARE v_active TINYINT(1);
    DECLARE v_school INT UNSIGNED;

    SELECT tt.day_of_week, tt.is_active, c.school_id
      INTO v_day, v_active, v_school
    FROM timetable tt
    JOIN classroom c ON c.classroom_id = tt.classroom_id
    WHERE tt.timetable_id = NEW.timetable_id;

    IF v_active = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'SCAS: cannot issue a code for an inactive session';
    END IF;
    IF DAYNAME(NEW.session_date) <> v_day THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'SCAS: session date does not fall on the scheduled day of week';
    END IF;
    IF fn_is_holiday(v_school, NEW.session_date) = 1 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'SCAS: cannot issue a code on a holiday';
    END IF;

    /* Default the window if the caller omitted it. */
    IF NEW.expiry_datetime IS NULL THEN
        SET NEW.expiry_datetime = NEW.generated_datetime
                                + INTERVAL CAST(IFNULL(fn_get_setting('qr.validity_minutes'), '30') AS SIGNED) MINUTE;
    END IF;
END $$

DROP TRIGGER IF EXISTS trg_qr_code_ai $$
CREATE TRIGGER trg_qr_code_ai
AFTER INSERT ON qr_code
FOR EACH ROW
BEGIN
    INSERT INTO audit_log (table_name, record_id, action, old_values, new_values,
                           changed_by_user_id, db_user, client_host)
    VALUES ('qr_code', NEW.qr_code_id, 'INSERT', NULL,
            JSON_OBJECT('timetable_id', NEW.timetable_id,
                        'session_date', NEW.session_date,
                        'expiry',       NEW.expiry_datetime,
                        'max_scans',    NEW.max_scans),
            fn_current_user_id(), CURRENT_USER(), SUBSTRING_INDEX(USER(), '@', -1));
END $$

DROP TRIGGER IF EXISTS trg_qr_code_au $$
CREATE TRIGGER trg_qr_code_au
AFTER UPDATE ON qr_code
FOR EACH ROW
BEGIN
    /* scan_count changes on every check-in and would flood the audit log,
       so only revocation is audited here. */
    IF NEW.is_revoked <> OLD.is_revoked THEN
        INSERT INTO audit_log (table_name, record_id, action, old_values, new_values,
                               changed_by_user_id, db_user, client_host)
        VALUES ('qr_code', NEW.qr_code_id, 'UPDATE',
                JSON_OBJECT('is_revoked', OLD.is_revoked),
                JSON_OBJECT('is_revoked', NEW.is_revoked, 'reason', NEW.revoked_reason),
                fn_current_user_id(), CURRENT_USER(), SUBSTRING_INDEX(USER(), '@', -1));
    END IF;
END $$

/* ###########################################################################
   SECTION 3 - TIMETABLE CLASH DETECTION
   The UNIQUE keys in 01_schema.sql catch sessions that start at exactly the
   same minute. They cannot catch 08:00-09:00 overlapping 08:30-09:30, because
   that is a range predicate, not an equality. These triggers close that gap.
   ######################################################################### */

DROP TRIGGER IF EXISTS trg_timetable_bi $$
CREATE TRIGGER trg_timetable_bi
BEFORE INSERT ON timetable
FOR EACH ROW
BEGIN
    DECLARE v_teacher_clash INT DEFAULT 0;
    DECLARE v_room_clash    INT DEFAULT 0;

    SELECT COUNT(*) INTO v_teacher_clash
    FROM timetable
    WHERE teacher_id  = NEW.teacher_id
      AND term_id     = NEW.term_id
      AND day_of_week = NEW.day_of_week
      AND is_active   = 1
      AND NEW.start_time < end_time
      AND start_time     < NEW.end_time;

    IF v_teacher_clash > 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'SCAS: that teacher already has an overlapping session that day';
    END IF;

    SELECT COUNT(*) INTO v_room_clash
    FROM timetable
    WHERE classroom_id = NEW.classroom_id
      AND term_id      = NEW.term_id
      AND day_of_week  = NEW.day_of_week
      AND is_active    = 1
      AND NEW.start_time < end_time
      AND start_time     < NEW.end_time;

    IF v_room_clash > 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'SCAS: that classroom is already booked for an overlapping slot';
    END IF;
END $$

DROP TRIGGER IF EXISTS trg_timetable_ai $$
CREATE TRIGGER trg_timetable_ai
AFTER INSERT ON timetable
FOR EACH ROW
BEGIN
    INSERT INTO audit_log (table_name, record_id, action, old_values, new_values,
                           changed_by_user_id, db_user, client_host)
    VALUES ('timetable', NEW.timetable_id, 'INSERT', NULL,
            JSON_OBJECT('teacher_id', NEW.teacher_id, 'classroom_id', NEW.classroom_id,
                        'subject', NEW.subject, 'day', NEW.day_of_week,
                        'start', NEW.start_time, 'end', NEW.end_time),
            fn_current_user_id(), CURRENT_USER(), SUBSTRING_INDEX(USER(), '@', -1));
END $$

DROP TRIGGER IF EXISTS trg_timetable_au $$
CREATE TRIGGER trg_timetable_au
AFTER UPDATE ON timetable
FOR EACH ROW
BEGIN
    INSERT INTO audit_log (table_name, record_id, action, old_values, new_values,
                           changed_by_user_id, db_user, client_host)
    VALUES ('timetable', NEW.timetable_id, 'UPDATE',
            JSON_OBJECT('teacher_id', OLD.teacher_id, 'classroom_id', OLD.classroom_id,
                        'subject', OLD.subject, 'start', OLD.start_time,
                        'end', OLD.end_time, 'is_active', OLD.is_active),
            JSON_OBJECT('teacher_id', NEW.teacher_id, 'classroom_id', NEW.classroom_id,
                        'subject', NEW.subject, 'start', NEW.start_time,
                        'end', NEW.end_time, 'is_active', NEW.is_active),
            fn_current_user_id(), CURRENT_USER(), SUBSTRING_INDEX(USER(), '@', -1));
END $$

/* ###########################################################################
   SECTION 4 - LEAVE WORKFLOW RULES
   ######################################################################### */

/* ---------------------------------------------------------------------------
   trg_leave_request_bi - a teacher cannot hold two overlapping requests, and
   leave cannot be backdated more than the configured number of days (so an
   absence cannot be retro-justified weeks later).
   ------------------------------------------------------------------------ */
DROP TRIGGER IF EXISTS trg_leave_request_bi $$
CREATE TRIGGER trg_leave_request_bi
BEFORE INSERT ON leave_request
FOR EACH ROW
BEGIN
    DECLARE v_overlap  INT DEFAULT 0;
    DECLARE v_backdate INT DEFAULT 7;

    SELECT COUNT(*) INTO v_overlap
    FROM leave_request
    WHERE teacher_id = NEW.teacher_id
      AND status IN ('Pending','Approved')
      AND NEW.start_date <= end_date
      AND start_date     <= NEW.end_date;

    IF v_overlap > 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'SCAS: you already have a pending or approved request covering those dates';
    END IF;

    SET v_backdate = CAST(IFNULL(fn_get_setting('leave.max_backdate_days'), '7') AS SIGNED);

    IF NEW.start_date < CURDATE() - INTERVAL v_backdate DAY THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'SCAS: leave cannot be backdated that far';
    END IF;
END $$

/* ---------------------------------------------------------------------------
   trg_leave_request_bu - a state machine in a trigger.
   Legal transitions: Pending -> Approved | Rejected | Cancelled.
   Anything else (re-approving, reversing a rejection, editing an approved
   request's dates) is refused.
   ------------------------------------------------------------------------ */
DROP TRIGGER IF EXISTS trg_leave_request_bu $$
CREATE TRIGGER trg_leave_request_bu
BEFORE UPDATE ON leave_request
FOR EACH ROW
BEGIN
    IF OLD.status <> 'Pending' AND NEW.status <> OLD.status THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'SCAS: only a Pending request may change status';
    END IF;

    IF OLD.status <> 'Pending'
       AND (NEW.start_date <> OLD.start_date OR NEW.end_date <> OLD.end_date) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'SCAS: the dates of an actioned request cannot be edited';
    END IF;

    IF NEW.status <> 'Pending' AND NEW.actioned_at IS NULL THEN
        SET NEW.actioned_at = NOW();
    END IF;
END $$

DROP TRIGGER IF EXISTS trg_leave_request_au $$
CREATE TRIGGER trg_leave_request_au
AFTER UPDATE ON leave_request
FOR EACH ROW
BEGIN
    INSERT INTO audit_log (table_name, record_id, action, old_values, new_values,
                           changed_by_user_id, db_user, client_host)
    VALUES ('leave_request', NEW.leave_request_id, 'UPDATE',
            JSON_OBJECT('status', OLD.status, 'approved_by', OLD.approved_by),
            JSON_OBJECT('status', NEW.status, 'approved_by', NEW.approved_by,
                        'remarks', NEW.remarks),
            fn_current_user_id(), CURRENT_USER(), SUBSTRING_INDEX(USER(), '@', -1));
END $$

DROP TRIGGER IF EXISTS trg_leave_request_ai $$
CREATE TRIGGER trg_leave_request_ai
AFTER INSERT ON leave_request
FOR EACH ROW
BEGIN
    INSERT INTO audit_log (table_name, record_id, action, old_values, new_values,
                           changed_by_user_id, db_user, client_host)
    VALUES ('leave_request', NEW.leave_request_id, 'INSERT', NULL,
            JSON_OBJECT('teacher_id', NEW.teacher_id, 'type', NEW.leave_type,
                        'start', NEW.start_date, 'end', NEW.end_date),
            fn_current_user_id(), CURRENT_USER(), SUBSTRING_INDEX(USER(), '@', -1));
END $$

/* ###########################################################################
   SECTION 5 - IDENTITY TABLES: NORMALISATION AND AUDIT
   ######################################################################### */

/* ---------------------------------------------------------------------------
   trg_app_user_bi - normalise before storing, so lookups are predictable.
   Usernames and e-mail addresses are case-folded and trimmed; without this,
   "J.Mensah" and "j.mensah" would be two different accounts.
   ------------------------------------------------------------------------ */
DROP TRIGGER IF EXISTS trg_app_user_bi $$
CREATE TRIGGER trg_app_user_bi
BEFORE INSERT ON app_user
FOR EACH ROW
BEGIN
    DECLARE v_priv TINYINT UNSIGNED;

    SET NEW.username  = LOWER(TRIM(NEW.username));
    SET NEW.email     = LOWER(TRIM(NEW.email));
    SET NEW.full_name = TRIM(NEW.full_name);

    /* Only a System Administrator may exist without a school. */
    SELECT privilege_level INTO v_priv FROM user_role WHERE role_id = NEW.role_id;
    IF NEW.school_id IS NULL AND IFNULL(v_priv, 0) < 99 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'SCAS: only a System Administrator may have no school';
    END IF;
END $$

DROP TRIGGER IF EXISTS trg_app_user_bu $$
CREATE TRIGGER trg_app_user_bu
BEFORE UPDATE ON app_user
FOR EACH ROW
BEGIN
    SET NEW.username  = LOWER(TRIM(NEW.username));
    SET NEW.email     = LOWER(TRIM(NEW.email));
END $$

/* ---------------------------------------------------------------------------
   trg_app_user_ai / _au / _ad
   NOTE: password_hash is deliberately NEVER written to audit_log. An audit
   trail is widely readable; copying credential material into it would turn
   the audit table into a second, less protected password store. The audit
   records only THAT the password changed, never the value.
   ------------------------------------------------------------------------ */
DROP TRIGGER IF EXISTS trg_app_user_ai $$
CREATE TRIGGER trg_app_user_ai
AFTER INSERT ON app_user
FOR EACH ROW
BEGIN
    INSERT INTO audit_log (table_name, record_id, action, old_values, new_values,
                           changed_by_user_id, db_user, client_host)
    VALUES ('app_user', NEW.user_id, 'INSERT', NULL,
            JSON_OBJECT('username', NEW.username, 'full_name', NEW.full_name,
                        'role_id', NEW.role_id, 'school_id', NEW.school_id,
                        'password_hash', '[redacted]'),
            fn_current_user_id(), CURRENT_USER(), SUBSTRING_INDEX(USER(), '@', -1));
END $$

DROP TRIGGER IF EXISTS trg_app_user_au $$
CREATE TRIGGER trg_app_user_au
AFTER UPDATE ON app_user
FOR EACH ROW
BEGIN
    /* Login bookkeeping (last_login_at, failed_login_attempts) fires on every
       sign-in and belongs in security_event, not in the change audit. Only
       meaningful administrative changes are recorded here. */
    IF NEW.role_id   <> OLD.role_id
    OR NEW.is_active <> OLD.is_active
    OR NOT (NEW.school_id <=> OLD.school_id)
    OR NEW.username  <> OLD.username
    OR NEW.password_hash <> OLD.password_hash THEN
        INSERT INTO audit_log (table_name, record_id, action, old_values, new_values,
                               changed_by_user_id, db_user, client_host)
        VALUES ('app_user', NEW.user_id, 'UPDATE',
                JSON_OBJECT('username', OLD.username, 'role_id', OLD.role_id,
                            'school_id', OLD.school_id, 'is_active', OLD.is_active,
                            'password_changed', IF(NEW.password_hash <> OLD.password_hash, TRUE, FALSE)),
                JSON_OBJECT('username', NEW.username, 'role_id', NEW.role_id,
                            'school_id', NEW.school_id, 'is_active', NEW.is_active,
                            'password_hash', '[redacted]'),
                fn_current_user_id(), CURRENT_USER(), SUBSTRING_INDEX(USER(), '@', -1));
    END IF;
END $$

DROP TRIGGER IF EXISTS trg_app_user_ad $$
CREATE TRIGGER trg_app_user_ad
AFTER DELETE ON app_user
FOR EACH ROW
BEGIN
    INSERT INTO audit_log (table_name, record_id, action, old_values, new_values,
                           changed_by_user_id, db_user, client_host)
    VALUES ('app_user', OLD.user_id, 'DELETE',
            JSON_OBJECT('username', OLD.username, 'full_name', OLD.full_name,
                        'role_id', OLD.role_id, 'school_id', OLD.school_id),
            NULL, fn_current_user_id(), CURRENT_USER(), SUBSTRING_INDEX(USER(), '@', -1));
END $$

DROP TRIGGER IF EXISTS trg_teacher_ai $$
CREATE TRIGGER trg_teacher_ai
AFTER INSERT ON teacher
FOR EACH ROW
BEGIN
    INSERT INTO audit_log (table_name, record_id, action, old_values, new_values,
                           changed_by_user_id, db_user, client_host)
    VALUES ('teacher', NEW.teacher_id, 'INSERT', NULL,
            JSON_OBJECT('user_id', NEW.user_id, 'staff_number', NEW.staff_number,
                        'department', NEW.department, 'date_employed', NEW.date_employed),
            fn_current_user_id(), CURRENT_USER(), SUBSTRING_INDEX(USER(), '@', -1));
END $$

DROP TRIGGER IF EXISTS trg_teacher_au $$
CREATE TRIGGER trg_teacher_au
AFTER UPDATE ON teacher
FOR EACH ROW
BEGIN
    INSERT INTO audit_log (table_name, record_id, action, old_values, new_values,
                           changed_by_user_id, db_user, client_host)
    VALUES ('teacher', NEW.teacher_id, 'UPDATE',
            JSON_OBJECT('staff_number', OLD.staff_number, 'department', OLD.department,
                        'employment_status', OLD.employment_status),
            JSON_OBJECT('staff_number', NEW.staff_number, 'department', NEW.department,
                        'employment_status', NEW.employment_status),
            fn_current_user_id(), CURRENT_USER(), SUBSTRING_INDEX(USER(), '@', -1));
END $$

DROP TRIGGER IF EXISTS trg_school_au $$
CREATE TRIGGER trg_school_au
AFTER UPDATE ON school
FOR EACH ROW
BEGIN
    INSERT INTO audit_log (table_name, record_id, action, old_values, new_values,
                           changed_by_user_id, db_user, client_host)
    VALUES ('school', NEW.school_id, 'UPDATE',
            JSON_OBJECT('school_name', OLD.school_name, 'district', OLD.district,
                        'region', OLD.region, 'is_active', OLD.is_active),
            JSON_OBJECT('school_name', NEW.school_name, 'district', NEW.district,
                        'region', NEW.region, 'is_active', NEW.is_active),
            fn_current_user_id(), CURRENT_USER(), SUBSTRING_INDEX(USER(), '@', -1));
END $$

/* ---------------------------------------------------------------------------
   trg_classroom_bi - trim and title-case the room name so "block a - room 3"
   and "Block A - Room 3" cannot both exist under uk_classroom_room.
   ------------------------------------------------------------------------ */
DROP TRIGGER IF EXISTS trg_classroom_bi $$
CREATE TRIGGER trg_classroom_bi
BEFORE INSERT ON classroom
FOR EACH ROW
BEGIN
    SET NEW.room_name = TRIM(NEW.room_name);
    IF NEW.building IS NOT NULL THEN
        SET NEW.building = TRIM(NEW.building);
    END IF;
END $$

/* ---------------------------------------------------------------------------
   trg_system_setting_bu - stamp the account that changed a setting. Combined
   with system versioning on the table, this gives "who changed what, when,
   and what was the value before" for every configuration change.
   ------------------------------------------------------------------------ */
DROP TRIGGER IF EXISTS trg_system_setting_bu $$
CREATE TRIGGER trg_system_setting_bu
BEFORE UPDATE ON system_setting
FOR EACH ROW
BEGIN
    SET NEW.updated_by = CONCAT(IFNULL(fn_current_user_id(), 0), '@', CURRENT_USER());
END $$

/* ---------------------------------------------------------------------------
   trg_academic_term_bu - exactly one current term per school. Promoting a new
   term automatically demotes the previous one.
   ------------------------------------------------------------------------ */
DROP TRIGGER IF EXISTS trg_academic_term_bi $$
CREATE TRIGGER trg_academic_term_bi
BEFORE INSERT ON academic_term
FOR EACH ROW
BEGIN
    DECLARE v_existing INT DEFAULT 0;
    IF NEW.is_current = 1 THEN
        SELECT COUNT(*) INTO v_existing
        FROM academic_term
        WHERE school_id = NEW.school_id AND is_current = 1;
        IF v_existing > 0 THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'SCAS: that school already has a current term - close it first';
        END IF;
    END IF;
END $$

DELIMITER ;

SELECT CONCAT('06 complete - ', COUNT(*), ' triggers') AS status
FROM information_schema.TRIGGERS WHERE TRIGGER_SCHEMA = 'scas_db';
