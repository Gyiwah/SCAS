/* ============================================================================
   SMART CLASSROOM ATTENDANCE SYSTEM (SCAS)
   University of Education, Winneba - MPhil ICT - ICTE825
   FILE 01 : PHYSICAL SCHEMA (DDL)
   TARGET  : MariaDB 10.4+ (XAMPP)
   ---------------------------------------------------------------------------
   Design notes
   - Engine  : InnoDB everywhere. It is the only engine shipped with XAMPP that
               provides ACID transactions, row-level locking, foreign keys and
               redo-log crash recovery, all of which the Transaction Management
               and Recovery objective depends on.
   - Charset : utf8mb4 / utf8mb4_unicode_ci so Ghanaian names store correctly.
   - Keys    : single-column surrogate primary keys (proposal 5.2) PLUS natural
               UNIQUE keys, so the surrogate key never hides a real duplicate.
   - 3NF     : every non-key attribute depends on the key, the whole key, and
               nothing but the key. The one deliberate exception is flagged
               CONTROLLED REDUNDANCY on table attendance and is maintained by a
               trigger, never by the application.
   ========================================================================= */

SET SESSION sql_mode = 'STRICT_ALL_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION';
SET FOREIGN_KEY_CHECKS = 1;

DROP DATABASE IF EXISTS scas_db;
CREATE DATABASE scas_db
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;
SET NAMES utf8mb4;
USE scas_db;

/* ===========================================================================
   1. SCHOOL - participating Senior High Schools
   =========================================================================*/
CREATE TABLE school (
    school_id     INT UNSIGNED NOT NULL AUTO_INCREMENT,
    school_code   VARCHAR(20)  NOT NULL COMMENT 'GES institution code',
    school_name   VARCHAR(100) NOT NULL,
    district      VARCHAR(60)  NOT NULL,
    region        VARCHAR(60)  NOT NULL,
    address       VARCHAR(150) NULL,
    phone_number  VARCHAR(20)  NULL,
    email         VARCHAR(100) NULL,
    is_active     TINYINT(1)   NOT NULL DEFAULT 1,
    created_at    TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at    TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT pk_school PRIMARY KEY (school_id),
    CONSTRAINT uk_school_code UNIQUE (school_code),
    CONSTRAINT uk_school_name UNIQUE (school_name),
    CONSTRAINT ck_school_name_len CHECK (CHAR_LENGTH(TRIM(school_name)) >= 3),
    CONSTRAINT ck_school_phone    CHECK (phone_number IS NULL OR phone_number REGEXP '^[+0-9][0-9 -]{6,19}$')
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Participating Senior High Schools (proposal 4.1)';

/* ===========================================================================
   2. USER_ROLE - access level of each system user.
   Named user_role because ROLE is a MariaDB keyword (CREATE ROLE).
   privilege_level drives authorisation in views, procedures and PHP.
   =========================================================================*/
CREATE TABLE user_role (
    role_id         TINYINT UNSIGNED NOT NULL AUTO_INCREMENT,
    role_name       VARCHAR(40)  NOT NULL,
    description     VARCHAR(150) NULL,
    privilege_level TINYINT UNSIGNED NOT NULL
        COMMENT '10=Teacher 50=Headteacher 90=School Admin 99=System Admin',
    created_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_user_role PRIMARY KEY (role_id),
    CONSTRAINT uk_role_name UNIQUE (role_name),
    CONSTRAINT ck_role_privilege CHECK (privilege_level BETWEEN 1 AND 99)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Role catalogue - basis of role-based access control (proposal 4.2)';

/* ===========================================================================
   3. APP_USER - login identity for everyone who uses SCAS.
   The security columns implement account lockout at the data layer.
   =========================================================================*/
CREATE TABLE app_user (
    user_id               INT UNSIGNED NOT NULL AUTO_INCREMENT,
    full_name             VARCHAR(100) NOT NULL,
    username              VARCHAR(40)  NOT NULL,
    password_hash         VARCHAR(255) NOT NULL COMMENT 'bcrypt only, never plaintext',
    role_id               TINYINT UNSIGNED NOT NULL,
    school_id             INT UNSIGNED NULL COMMENT 'NULL only for System Administrator',
    phone_number          VARCHAR(20)  NULL,
    email                 VARCHAR(100) NULL,
    is_active             TINYINT(1)   NOT NULL DEFAULT 1,
    failed_login_attempts TINYINT UNSIGNED NOT NULL DEFAULT 0,
    locked_until          DATETIME     NULL,
    last_login_at         DATETIME     NULL,
    last_login_ip         VARCHAR(45)  NULL,
    password_changed_at   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    must_change_password  TINYINT(1)   NOT NULL DEFAULT 0,
    created_at            TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at            TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT pk_app_user PRIMARY KEY (user_id),
    CONSTRAINT uk_app_user_username UNIQUE (username),
    CONSTRAINT uk_app_user_email    UNIQUE (email),
    CONSTRAINT fk_app_user_role
        FOREIGN KEY (role_id)   REFERENCES user_role (role_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_app_user_school
        FOREIGN KEY (school_id) REFERENCES school (school_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT ck_user_username CHECK (CHAR_LENGTH(username) >= 4 AND username NOT REGEXP '[[:space:]]'),
    CONSTRAINT ck_user_email    CHECK (email IS NULL OR email REGEXP '^[^@ ]+@[^@ ]+[.][A-Za-z]{2,}$'),
    CONSTRAINT ck_user_pwd_hash CHECK (CHAR_LENGTH(password_hash) >= 20)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='System accounts and authentication state (proposal 4.3)';

/* ===========================================================================
   4. TEACHER - employment detail, exactly 1:1 with app_user.
   =========================================================================*/
CREATE TABLE teacher (
    teacher_id        INT UNSIGNED NOT NULL AUTO_INCREMENT,
    user_id           INT UNSIGNED NOT NULL,
    staff_number      VARCHAR(20)  NOT NULL COMMENT 'GES staff / payroll number',
    department        VARCHAR(60)  NOT NULL,
    qualification     VARCHAR(60)  NULL,
    date_employed     DATE         NOT NULL,
    employment_status ENUM('Active','Suspended','Study Leave','Transferred','Retired')
                      NOT NULL DEFAULT 'Active',
    created_at        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT pk_teacher PRIMARY KEY (teacher_id),
    /* uk_teacher_user is what enforces the 1:1 relationship in proposal 5.1 */
    CONSTRAINT uk_teacher_user  UNIQUE (user_id),
    CONSTRAINT uk_teacher_staff UNIQUE (staff_number),
    CONSTRAINT fk_teacher_user
        FOREIGN KEY (user_id) REFERENCES app_user (user_id)
        ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT ck_teacher_employed CHECK (date_employed >= '1957-03-06')
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Teacher employment record (proposal 4.4)';

/* ===========================================================================
   5. CLASSROOM - physical rooms in which attendance is captured.
   =========================================================================*/
CREATE TABLE classroom (
    classroom_id INT UNSIGNED NOT NULL AUTO_INCREMENT,
    school_id    INT UNSIGNED NOT NULL,
    room_name    VARCHAR(40)  NOT NULL,
    building     VARCHAR(40)  NULL,
    capacity     SMALLINT UNSIGNED NOT NULL DEFAULT 40,
    is_active    TINYINT(1)   NOT NULL DEFAULT 1,
    created_at   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_classroom PRIMARY KEY (classroom_id),
    CONSTRAINT uk_classroom_room UNIQUE (school_id, room_name),
    CONSTRAINT fk_classroom_school
        FOREIGN KEY (school_id) REFERENCES school (school_id)
        ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT ck_classroom_capacity CHECK (capacity BETWEEN 1 AND 500)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Rooms in which sessions are held (proposal 4.5)';

/* ===========================================================================
   6. ACADEMIC_TERM - bounds the validity of a timetable.
   Added during design: without it a timetable row has no validity period, so
   last year's schedule would still be flagged as unstaffed today.
   =========================================================================*/
CREATE TABLE academic_term (
    term_id       SMALLINT UNSIGNED NOT NULL AUTO_INCREMENT,
    school_id     INT UNSIGNED NOT NULL,
    term_name     VARCHAR(40) NOT NULL COMMENT 'e.g. 2025/2026 Term 1',
    academic_year CHAR(9)     NOT NULL COMMENT 'e.g. 2025/2026',
    start_date    DATE NOT NULL,
    end_date      DATE NOT NULL,
    is_current    TINYINT(1) NOT NULL DEFAULT 0,
    CONSTRAINT pk_academic_term PRIMARY KEY (term_id),
    CONSTRAINT uk_term_name UNIQUE (school_id, term_name),
    CONSTRAINT fk_term_school
        FOREIGN KEY (school_id) REFERENCES school (school_id)
        ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT ck_term_dates CHECK (end_date > start_date),
    CONSTRAINT ck_term_year  CHECK (academic_year REGEXP '^[0-9]{4}/[0-9]{4}$')
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Academic terms - bounds timetable validity';

/* ===========================================================================
   7. HOLIDAY - non-teaching days, so the nightly absentee job does not mark a
   whole school absent on a public holiday.
   school_key is a PERSISTENT generated column that exists solely so a UNIQUE
   key can treat "national holiday" (school_id IS NULL) as a real value,
   because SQL UNIQUE does not constrain NULLs.
   =========================================================================*/
CREATE TABLE holiday (
    holiday_id   INT UNSIGNED NOT NULL AUTO_INCREMENT,
    school_id    INT UNSIGNED NULL COMMENT 'NULL = national holiday (all schools)',
    holiday_date DATE NOT NULL,
    description  VARCHAR(100) NOT NULL,
    school_key   INT UNSIGNED AS (IFNULL(school_id, 0)) PERSISTENT,
    CONSTRAINT pk_holiday PRIMARY KEY (holiday_id),
    CONSTRAINT uk_holiday UNIQUE (school_key, holiday_date),
    CONSTRAINT fk_holiday_school
        FOREIGN KEY (school_id) REFERENCES school (school_id)
        ON UPDATE CASCADE ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Public and school holidays excluded from absenteeism';

/* ===========================================================================
   8. TIMETABLE - a scheduled session: teacher x classroom x subject x slot.
   The two UNIQUE keys are the declarative half of double-booking prevention
   (identical slots). Overlapping-but-not-identical slots cannot be expressed
   as a UNIQUE key, so they are caught by trg_timetable_bi / trg_timetable_bu.
   =========================================================================*/
CREATE TABLE timetable (
    timetable_id     INT UNSIGNED NOT NULL AUTO_INCREMENT,
    teacher_id       INT UNSIGNED NOT NULL,
    classroom_id     INT UNSIGNED NOT NULL,
    term_id          SMALLINT UNSIGNED NOT NULL,
    subject          VARCHAR(60) NOT NULL,
    class_group      VARCHAR(30) NULL COMMENT 'e.g. SHS 2 Science A',
    day_of_week      ENUM('Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday') NOT NULL,
    start_time       TIME NOT NULL,
    end_time         TIME NOT NULL,
    is_active        TINYINT(1) NOT NULL DEFAULT 1,
    duration_minutes SMALLINT UNSIGNED AS
        ((TIME_TO_SEC(end_time) - TIME_TO_SEC(start_time)) DIV 60) PERSISTENT,
    created_at       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT pk_timetable PRIMARY KEY (timetable_id),
    CONSTRAINT uk_timetable_room    UNIQUE (classroom_id, term_id, day_of_week, start_time),
    CONSTRAINT uk_timetable_teacher UNIQUE (teacher_id, term_id, day_of_week, start_time),
    CONSTRAINT fk_timetable_teacher
        FOREIGN KEY (teacher_id)   REFERENCES teacher (teacher_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_timetable_classroom
        FOREIGN KEY (classroom_id) REFERENCES classroom (classroom_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_timetable_term
        FOREIGN KEY (term_id)      REFERENCES academic_term (term_id)
        ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT ck_timetable_times CHECK (end_time > start_time),
    CONSTRAINT ck_timetable_len   CHECK (TIME_TO_SEC(end_time) - TIME_TO_SEC(start_time) BETWEEN 900 AND 14400)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Scheduled sessions - every scan is validated against this (proposal 4.6)';

/* ===========================================================================
   9. QR_CODE - one time-boxed code per session per day.
   The expiry window is what stops a code being photographed and reused later;
   is_revoked lets a headteacher kill a leaked code immediately.
   =========================================================================*/
CREATE TABLE qr_code (
    qr_code_id         INT UNSIGNED NOT NULL AUTO_INCREMENT,
    timetable_id       INT UNSIGNED NOT NULL,
    code_value         VARCHAR(64) NOT NULL COMMENT 'cryptographically random token',
    session_date       DATE NOT NULL,
    generated_datetime DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expiry_datetime    DATETIME NOT NULL,
    generated_by       INT UNSIGNED NULL,
    is_revoked         TINYINT(1) NOT NULL DEFAULT 0,
    revoked_reason     VARCHAR(100) NULL,
    max_scans          SMALLINT UNSIGNED NOT NULL DEFAULT 1,
    scan_count         SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    CONSTRAINT pk_qr_code PRIMARY KEY (qr_code_id),
    CONSTRAINT uk_qr_code_value UNIQUE (code_value),
    /* exactly one code per session per day */
    CONSTRAINT uk_qr_session    UNIQUE (timetable_id, session_date),
    CONSTRAINT fk_qr_timetable
        FOREIGN KEY (timetable_id) REFERENCES timetable (timetable_id)
        ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT fk_qr_generated_by
        FOREIGN KEY (generated_by) REFERENCES app_user (user_id)
        ON UPDATE CASCADE ON DELETE SET NULL,
    CONSTRAINT ck_qr_window    CHECK (expiry_datetime > generated_datetime),
    CONSTRAINT ck_qr_max_scans CHECK (max_scans BETWEEN 1 AND 100),
    CONSTRAINT ck_qr_value_len CHECK (CHAR_LENGTH(code_value) >= 16)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Time-boxed session codes (proposal 4.7)';

/* ===========================================================================
   10. ATTENDANCE - the check-in ledger.

   CONTROLLED REDUNDANCY (documented 3NF exception):
     timetable_id and session_date are functionally determined by qr_code_id,
     so strictly they are transitively dependent on the key. They are stored
     anyway for two reasons:
       (a) system-generated Absent / Excused rows have NO qr_code at all, so
           the session they refer to must be identified directly; and
       (b) every report filters by date, so a stored session_date lets those
           queries use an index (see 02) and lets attendance_archive partition
           by range (see 08).
     Both columns are written ONLY by trg_attendance_bi, never by the
     application, so they cannot drift out of step with the QR code.

   qr_code_id is NULL exactly for Absent / Excused rows - no scan happened.
   =========================================================================*/
CREATE TABLE attendance (
    attendance_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    teacher_id    INT UNSIGNED NOT NULL,
    qr_code_id    INT UNSIGNED NULL,
    timetable_id  INT UNSIGNED NOT NULL,
    session_date  DATE NOT NULL,
    scan_datetime DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    status        ENUM('Present','Late','Absent','Excused') NOT NULL,
    minutes_late  SMALLINT NOT NULL DEFAULT 0,
    scan_ip       VARCHAR(45)  NULL,
    device_info   VARCHAR(120) NULL,
    recorded_by   INT UNSIGNED NULL COMMENT 'NULL = automatic system job',
    remarks       VARCHAR(150) NULL,
    created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_attendance PRIMARY KEY (attendance_id),
    /* one attendance verdict per teacher per session per day */
    CONSTRAINT uk_attendance_session UNIQUE (timetable_id, session_date, teacher_id),
    /* replay protection: a teacher cannot scan the same code twice */
    CONSTRAINT uk_attendance_scan UNIQUE (teacher_id, qr_code_id),
    CONSTRAINT fk_attendance_teacher
        FOREIGN KEY (teacher_id)   REFERENCES teacher (teacher_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_attendance_qr
        FOREIGN KEY (qr_code_id)   REFERENCES qr_code (qr_code_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_attendance_timetable
        FOREIGN KEY (timetable_id) REFERENCES timetable (timetable_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_attendance_recorded_by
        FOREIGN KEY (recorded_by)  REFERENCES app_user (user_id)
        ON UPDATE CASCADE ON DELETE SET NULL,
    CONSTRAINT ck_attendance_qr_required
        CHECK (status IN ('Absent','Excused') OR qr_code_id IS NOT NULL),
    CONSTRAINT ck_attendance_late
        CHECK (minutes_late >= 0 AND minutes_late <= 1440)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Check-in ledger - DELETE blocked by trigger (proposal 4.8)';

/* ===========================================================================
   11. LEAVE_REQUEST - approved absence, excluded from absenteeism figures.
   =========================================================================*/
CREATE TABLE leave_request (
    leave_request_id INT UNSIGNED NOT NULL AUTO_INCREMENT,
    teacher_id       INT UNSIGNED NOT NULL,
    leave_type       ENUM('Casual','Sick','Maternity','Study','Compassionate','Official Duty')
                     NOT NULL DEFAULT 'Casual',
    start_date       DATE NOT NULL,
    end_date         DATE NOT NULL,
    reason           VARCHAR(150) NOT NULL,
    status           ENUM('Pending','Approved','Rejected','Cancelled') NOT NULL DEFAULT 'Pending',
    approved_by      INT UNSIGNED NULL,
    requested_at     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    actioned_at      DATETIME NULL,
    remarks          VARCHAR(200) NULL,
    days_requested   SMALLINT UNSIGNED AS (DATEDIFF(end_date, start_date) + 1) PERSISTENT,
    CONSTRAINT pk_leave_request PRIMARY KEY (leave_request_id),
    CONSTRAINT fk_leave_teacher
        FOREIGN KEY (teacher_id)  REFERENCES teacher (teacher_id)
        ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT fk_leave_approver
        FOREIGN KEY (approved_by) REFERENCES app_user (user_id)
        ON UPDATE CASCADE ON DELETE SET NULL,
    CONSTRAINT ck_leave_dates  CHECK (end_date >= start_date),
    CONSTRAINT ck_leave_reason CHECK (CHAR_LENGTH(TRIM(reason)) >= 5),
    CONSTRAINT ck_leave_actioned
        CHECK (status <> 'Pending' OR (approved_by IS NULL AND actioned_at IS NULL))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Leave workflow (proposal 4.9)';

/* ###########################################################################
   SUPPORTING TABLES FOR THE ADVANCED DBMS FEATURES
   These are not part of the nine business entities; they exist to support
   security, auditing, recovery and query evaluation.
   ######################################################################### */

/* ===========================================================================
   12. AUDIT_LOG - written only by triggers (see 06_triggers.sql).
   Deliberately has NO foreign key to app_user: an audit record must survive
   the deletion of the user it refers to, otherwise the audit trail could be
   erased by deleting an account.
   =========================================================================*/
CREATE TABLE audit_log (
    audit_id           BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    table_name         VARCHAR(64) NOT NULL,
    record_id          VARCHAR(40) NOT NULL,
    action             ENUM('INSERT','UPDATE','DELETE') NOT NULL,
    old_values         TEXT NULL COMMENT 'JSON snapshot before change',
    new_values         TEXT NULL COMMENT 'JSON snapshot after change',
    changed_by_user_id INT UNSIGNED NULL COMMENT 'from session var @scas_user_id',
    db_user            VARCHAR(100) NOT NULL COMMENT 'CURRENT_USER() at change time',
    client_host        VARCHAR(100) NULL,
    changed_at         DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    CONSTRAINT pk_audit_log PRIMARY KEY (audit_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Append-only audit trail maintained by triggers';

/* ===========================================================================
   13. SECURITY_EVENT - authentication and authorisation telemetry.
   =========================================================================*/
CREATE TABLE security_event (
    event_id           BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    event_type         ENUM('LOGIN_SUCCESS','LOGIN_FAILED','ACCOUNT_LOCKED','ACCOUNT_UNLOCKED',
                            'LOGOUT','PASSWORD_CHANGED','PRIVILEGE_DENIED','QR_REPLAY_BLOCKED',
                            'QR_EXPIRED_BLOCKED','USER_CREATED','USER_DEACTIVATED','DATA_EXPORT') NOT NULL,
    username_attempted VARCHAR(40)  NULL,
    user_id            INT UNSIGNED NULL,
    ip_address         VARCHAR(45)  NULL,
    user_agent         VARCHAR(200) NULL,
    detail             VARCHAR(255) NULL,
    severity           ENUM('INFO','WARNING','CRITICAL') NOT NULL DEFAULT 'INFO',
    occurred_at        DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    CONSTRAINT pk_security_event PRIMARY KEY (event_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Security telemetry - feeds the admin security dashboard';

/* ===========================================================================
   14. BACKUP_LOG - register of backups and restores, including the binary log
   coordinates needed for point-in-time recovery.
   =========================================================================*/
CREATE TABLE backup_log (
    backup_id       INT UNSIGNED NOT NULL AUTO_INCREMENT,
    backup_type     ENUM('FULL','LOGICAL','BINLOG','PRE_RESTORE_SNAPSHOT','RESTORE') NOT NULL,
    file_path       VARCHAR(255) NULL,
    file_size_bytes BIGINT UNSIGNED NULL,
    started_at      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    completed_at    DATETIME NULL,
    status          ENUM('RUNNING','SUCCESS','FAILED') NOT NULL DEFAULT 'RUNNING',
    binlog_file     VARCHAR(100) NULL,
    binlog_position BIGINT UNSIGNED NULL,
    performed_by    VARCHAR(100) NULL,
    notes           VARCHAR(255) NULL,
    CONSTRAINT pk_backup_log PRIMARY KEY (backup_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Backup / restore register for the recovery drill';

/* ===========================================================================
   15. SYSTEM_SETTING - runtime configuration (late threshold, QR validity...).
   Declared WITH SYSTEM VERSIONING (MariaDB temporal table). Every UPDATE keeps
   the previous row version invisibly, so the settings in force at any past
   moment can be recovered with
       SELECT * FROM system_setting FOR SYSTEM_TIME AS OF TIMESTAMP '...';
   That is logical point-in-time recovery for configuration, without restoring
   a backup. See 08_transactions_recovery.sql for the demonstration.
   =========================================================================*/
CREATE TABLE system_setting (
    setting_key   VARCHAR(60)  NOT NULL,
    setting_value VARCHAR(255) NOT NULL,
    data_type     ENUM('INT','DECIMAL','STRING','BOOLEAN','TIME') NOT NULL DEFAULT 'STRING',
    description   VARCHAR(200) NULL,
    updated_by    VARCHAR(100) NULL,
    CONSTRAINT pk_system_setting PRIMARY KEY (setting_key)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  WITH SYSTEM VERSIONING
  COMMENT='Runtime configuration - system-versioned temporal table';

/* ===========================================================================
   16. ATTENDANCE_ARCHIVE - cold storage for closed academic years.
   PARTITION BY RANGE on the year of session_date so that a query for one year
   touches exactly one partition (partition pruning), and so that dropping a
   whole year is an instant DDL instead of a mass DELETE.
   InnoDB partitioned tables cannot carry foreign keys, which is precisely why
   archiving is done by a stored procedure that validates first (see 08).
   =========================================================================*/
CREATE TABLE attendance_archive (
    attendance_id BIGINT UNSIGNED NOT NULL,
    teacher_id    INT UNSIGNED NOT NULL,
    qr_code_id    INT UNSIGNED NULL,
    timetable_id  INT UNSIGNED NOT NULL,
    session_date  DATE NOT NULL,
    scan_datetime DATETIME NOT NULL,
    status        ENUM('Present','Late','Absent','Excused') NOT NULL,
    minutes_late  SMALLINT NOT NULL DEFAULT 0,
    remarks       VARCHAR(150) NULL,
    archived_at   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (attendance_id, session_date),
    KEY ix_arch_teacher_date (teacher_id, session_date)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Partitioned cold storage for old attendance'
  PARTITION BY RANGE (YEAR(session_date)) (
      PARTITION p2023 VALUES LESS THAN (2024),
      PARTITION p2024 VALUES LESS THAN (2025),
      PARTITION p2025 VALUES LESS THAN (2026),
      PARTITION p2026 VALUES LESS THAN (2027),
      PARTITION pmax  VALUES LESS THAN MAXVALUE
  );

/* ===========================================================================
   17. ATTENDANCE_DAILY_SUMMARY - a materialised aggregate.
   MariaDB has no materialised views, so the pattern is: a physical summary
   table refreshed by sp_refresh_attendance_summary and by a scheduled EVENT.
   Dashboards read this table instead of re-aggregating the ledger every time.
   =========================================================================*/
CREATE TABLE attendance_daily_summary (
    summary_id         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    school_id          INT UNSIGNED NOT NULL,
    teacher_id         INT UNSIGNED NOT NULL,
    summary_date       DATE NOT NULL,
    sessions_scheduled SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    present_count      SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    late_count         SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    absent_count       SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    excused_count      SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    /* NULL is meaningful here and is not the same as 0.00: it means the
       teacher had no REQUIRED sessions that day because every scheduled
       session was excused (approved leave). Storing 0.00 would report a
       teacher on approved leave as having 0% attendance, which is exactly the
       injustice proposal problem 4 asks the system to avoid. NULL is ignored
       by AVG(), so trend charts skip such days instead of dragging the
       average down. */
    attendance_rate    DECIMAL(5,2) NULL DEFAULT NULL,
    refreshed_at       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT pk_attendance_daily_summary PRIMARY KEY (summary_id),
    CONSTRAINT uk_summary UNIQUE (teacher_id, summary_date),
    CONSTRAINT ck_summary_rate CHECK (attendance_rate BETWEEN 0 AND 100)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Materialised daily aggregate refreshed by event ev_refresh_summary';

/* ===========================================================================
   18. QUERY_PERFORMANCE_LOG - evidence for the Query Processing objective.
   The PHP data-access layer times every statement and writes the slow ones
   here together with the plan captured from EXPLAIN.
   =========================================================================*/
CREATE TABLE query_performance_log (
    log_id        BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    query_label   VARCHAR(80) NOT NULL,
    sql_text      TEXT NOT NULL,
    exec_ms       DECIMAL(10,3) NOT NULL,
    rows_returned INT UNSIGNED NULL,
    plan_summary  TEXT NULL COMMENT 'EXPLAIN output captured at run time',
    executed_by   VARCHAR(100) NULL,
    executed_at   DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    CONSTRAINT pk_query_performance_log PRIMARY KEY (log_id),
    CONSTRAINT ck_qpl_ms CHECK (exec_ms >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Slow-query register used by the DBA console';

/* ===========================================================================
   19. NOTIFICATION - in-app messages raised by triggers and procedures.
   =========================================================================*/
CREATE TABLE notification (
    notification_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    user_id         INT UNSIGNED NOT NULL,
    title           VARCHAR(100) NOT NULL,
    message         VARCHAR(255) NOT NULL,
    notif_type      ENUM('INFO','SUCCESS','WARNING','ALERT') NOT NULL DEFAULT 'INFO',
    is_read         TINYINT(1) NOT NULL DEFAULT 0,
    created_at      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_notification PRIMARY KEY (notification_id),
    CONSTRAINT fk_notification_user
        FOREIGN KEY (user_id) REFERENCES app_user (user_id)
        ON UPDATE CASCADE ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='In-app notifications';

SELECT CONCAT('01_schema.sql complete - ', COUNT(*), ' tables created') AS status
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = 'scas_db' AND TABLE_TYPE = 'BASE TABLE';
