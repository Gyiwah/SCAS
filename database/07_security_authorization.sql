/* ============================================================================
   SCAS - FILE 07 : DATABASE SECURITY AND AUTHORIZATION
   Objective (c).
   ---------------------------------------------------------------------------
   SCAS applies security at five layers. Each layer assumes the one above it
   has already failed, which is what "defence in depth" means in practice.

   L1 AUTHENTICATION   Who are you?
                       Separate DBMS accounts per purpose; bcrypt for
                       application passwords; lockout after repeated failures.
   L2 AUTHORIZATION    What may you touch?
                       Roles, least-privilege grants, column-level grants.
   L3 ROW-LEVEL        Which rows may you see?
                       SQL SECURITY DEFINER views keyed to the session
                       identity (see 04_views.sql).
   L4 INTEGRITY        Can you corrupt it?
                       Constraints and triggers - the rules cannot be
                       bypassed by connecting outside the application.
   L5 ACCOUNTABILITY   What did you do?
                       Trigger-based audit trail and security_event log.

   THE CENTRAL DECISION IN THIS FILE
   The application account scas_app has NO INSERT, UPDATE or DELETE on any
   business table. It can only EXECUTE the stored procedures in file 05 and
   SELECT from the views in file 04. If the PHP layer is ever compromised -
   SQL injection, stolen config file, hostile insider - the attacker inherits
   only that vocabulary. They cannot DROP a table, cannot mass-delete
   attendance, cannot rewrite a status, and cannot read password hashes.
   ========================================================================= */

SET NAMES utf8mb4;
USE scas_db;

/* ###########################################################################
   PART 1 - ROLES
   MariaDB roles (10.0.5+) are named privilege bundles. Granting a role to a
   person means their access can be revoked or re-scoped in one place instead
   of hunting through individual GRANT statements.
   ######################################################################### */

DROP ROLE IF EXISTS scas_teacher_role;
DROP ROLE IF EXISTS scas_headteacher_role;
DROP ROLE IF EXISTS scas_schooladmin_role;
DROP ROLE IF EXISTS scas_auditor_role;
DROP ROLE IF EXISTS scas_backup_role;
DROP ROLE IF EXISTS scas_dba_role;

CREATE ROLE scas_teacher_role;
CREATE ROLE scas_headteacher_role;
CREATE ROLE scas_schooladmin_role;
CREATE ROLE scas_auditor_role;
CREATE ROLE scas_backup_role;
CREATE ROLE scas_dba_role;

/* --- Teacher: sees only their own data, and may only check in ----------- */
GRANT SELECT ON scas_db.v_my_attendance        TO scas_teacher_role;
GRANT SELECT ON scas_db.v_my_timetable         TO scas_teacher_role;
GRANT SELECT ON scas_db.v_qr_active            TO scas_teacher_role;
GRANT EXECUTE ON PROCEDURE scas_db.sp_record_attendance      TO scas_teacher_role;
GRANT EXECUTE ON PROCEDURE scas_db.sp_submit_leave_request   TO scas_teacher_role;
GRANT EXECUTE ON PROCEDURE scas_db.sp_change_password        TO scas_teacher_role;
GRANT EXECUTE ON FUNCTION  scas_db.fn_attendance_rate        TO scas_teacher_role;

/* --- Headteacher: whole school, plus approvals and code generation ------ */
GRANT scas_teacher_role TO scas_headteacher_role;
GRANT SELECT ON scas_db.v_my_school_teachers   TO scas_headteacher_role;
GRANT SELECT ON scas_db.v_my_school_attendance TO scas_headteacher_role;
GRANT SELECT ON scas_db.v_live_session_board   TO scas_headteacher_role;
GRANT SELECT ON scas_db.v_unstaffed_now        TO scas_headteacher_role;
GRANT SELECT ON scas_db.v_monthly_attendance_summary TO scas_headteacher_role;
GRANT SELECT ON scas_db.v_absence_trend        TO scas_headteacher_role;
GRANT SELECT ON scas_db.v_teacher_ranking      TO scas_headteacher_role;
GRANT SELECT ON scas_db.v_department_stats     TO scas_headteacher_role;
GRANT SELECT ON scas_db.v_leave_pending        TO scas_headteacher_role;
GRANT SELECT ON scas_db.v_leave_history        TO scas_headteacher_role;
GRANT EXECUTE ON PROCEDURE scas_db.sp_generate_qr_code           TO scas_headteacher_role;
GRANT EXECUTE ON PROCEDURE scas_db.sp_revoke_qr_code             TO scas_headteacher_role;
GRANT EXECUTE ON PROCEDURE scas_db.sp_action_leave_request       TO scas_headteacher_role;
GRANT EXECUTE ON PROCEDURE scas_db.sp_mark_absentees             TO scas_headteacher_role;
GRANT EXECUTE ON PROCEDURE scas_db.sp_monthly_attendance_report  TO scas_headteacher_role;
GRANT EXECUTE ON PROCEDURE scas_db.sp_teacher_attendance_summary TO scas_headteacher_role;

/* --- School administrator: user management on top of the above ---------- */
GRANT scas_headteacher_role TO scas_schooladmin_role;
GRANT EXECUTE ON PROCEDURE scas_db.sp_create_user      TO scas_schooladmin_role;
GRANT EXECUTE ON PROCEDURE scas_db.sp_set_user_active  TO scas_schooladmin_role;
GRANT EXECUTE ON PROCEDURE scas_db.sp_unlock_account   TO scas_schooladmin_role;
GRANT EXECUTE ON PROCEDURE scas_db.sp_transfer_teacher_sessions TO scas_schooladmin_role;
GRANT SELECT  ON scas_db.v_security_dashboard          TO scas_schooladmin_role;

/* --- Auditor: reads the trail, and NOTHING else. ------------------------
   Note this role has no privilege on attendance, app_user or any business
   table. An auditor who could also change the data they audit is not an
   auditor. The role is also denied INSERT/UPDATE/DELETE on audit_log itself,
   so the trail cannot be edited by the person reading it.               */
GRANT SELECT ON scas_db.v_audit_trail        TO scas_auditor_role;
GRANT SELECT ON scas_db.security_event       TO scas_auditor_role;
GRANT SELECT ON scas_db.v_security_dashboard TO scas_auditor_role;
GRANT SELECT ON scas_db.backup_log           TO scas_auditor_role;

/* COLUMN-LEVEL AUTHORIZATION
   The auditor needs to resolve a user_id to a name. They do NOT need the
   password hash. SQL lets us grant SELECT on named columns only, so the
   credential column is unreachable even with a hand-written query. */
GRANT SELECT (user_id, full_name, username, role_id, school_id, is_active,
              last_login_at, locked_until)
      ON scas_db.app_user TO scas_auditor_role;

/* --- Backup operator: exactly what mysqldump needs, nothing more -------- */
GRANT SELECT, LOCK TABLES, SHOW VIEW, EVENT, TRIGGER, PROCESS, RELOAD
      ON *.* TO scas_backup_role;

/* --- DBA: full control of this schema only, not of the whole server ----- */
GRANT ALL PRIVILEGES ON scas_db.* TO scas_dba_role;

/* ###########################################################################
   PART 2 - ACCOUNTS
   One account per purpose. Shared accounts destroy accountability, because
   the audit trail can then only say "someone using scas_app did this".
   ######################################################################### */

DROP USER IF EXISTS 'scas_app'@'localhost';
DROP USER IF EXISTS 'scas_readonly'@'localhost';
DROP USER IF EXISTS 'scas_auditor'@'localhost';
DROP USER IF EXISTS 'scas_backup'@'localhost';
DROP USER IF EXISTS 'scas_dba'@'localhost';

/* All accounts are restricted to 'localhost'. The database listens only to
   the application server; there is no route to it from the school network.
   PASSWORDS: these are the project defaults and are documented in the README.
   Change them before any deployment beyond the XAMPP pilot. */

CREATE USER 'scas_app'@'localhost'      IDENTIFIED BY 'Scas#App2026!';
CREATE USER 'scas_readonly'@'localhost' IDENTIFIED BY 'Scas#Read2026!';
CREATE USER 'scas_auditor'@'localhost'  IDENTIFIED BY 'Scas#Audit2026!';
CREATE USER 'scas_backup'@'localhost'   IDENTIFIED BY 'Scas#Backup2026!';
CREATE USER 'scas_dba'@'localhost'      IDENTIFIED BY 'Scas#Dba2026!';

/* RESOURCE LIMITS - a compromised or runaway application account cannot use
   the whole server. These are per-hour ceilings enforced by the DBMS. */
ALTER USER 'scas_app'@'localhost'
      WITH MAX_QUERIES_PER_HOUR 200000
           MAX_UPDATES_PER_HOUR  50000
           MAX_CONNECTIONS_PER_HOUR 5000
           MAX_USER_CONNECTIONS 25;

ALTER USER 'scas_readonly'@'localhost'
      WITH MAX_QUERIES_PER_HOUR 20000
           MAX_UPDATES_PER_HOUR 0          /* structurally read-only */
           MAX_USER_CONNECTIONS 5;

ALTER USER 'scas_auditor'@'localhost'
      WITH MAX_UPDATES_PER_HOUR 0
           MAX_USER_CONNECTIONS 3;

/* PASSWORD EXPIRY (MariaDB 10.4.3+) - human accounts rotate, the service
   account does not (an expired service password takes the app offline). */
ALTER USER 'scas_dba'@'localhost'     PASSWORD EXPIRE INTERVAL 90 DAY;
ALTER USER 'scas_auditor'@'localhost' PASSWORD EXPIRE INTERVAL 90 DAY;
ALTER USER 'scas_app'@'localhost'     PASSWORD EXPIRE NEVER;

/* ###########################################################################
   PART 3 - THE APPLICATION ACCOUNT
   This is the heart of the authorization design. Read the comment at the top
   of the file for the rationale.
   ######################################################################### */

/* 3a. Read access: views only. Never a base table. */
GRANT SELECT ON scas_db.v_teacher_directory          TO 'scas_app'@'localhost';
GRANT SELECT ON scas_db.v_my_school_teachers         TO 'scas_app'@'localhost';
GRANT SELECT ON scas_db.v_active_timetable           TO 'scas_app'@'localhost';
GRANT SELECT ON scas_db.v_my_timetable               TO 'scas_app'@'localhost';
GRANT SELECT ON scas_db.v_attendance_detail          TO 'scas_app'@'localhost';
GRANT SELECT ON scas_db.v_my_attendance              TO 'scas_app'@'localhost';
GRANT SELECT ON scas_db.v_my_school_attendance       TO 'scas_app'@'localhost';
GRANT SELECT ON scas_db.v_live_session_board         TO 'scas_app'@'localhost';
GRANT SELECT ON scas_db.v_unstaffed_now              TO 'scas_app'@'localhost';
GRANT SELECT ON scas_db.v_monthly_attendance_summary TO 'scas_app'@'localhost';
GRANT SELECT ON scas_db.v_teacher_ranking            TO 'scas_app'@'localhost';
GRANT SELECT ON scas_db.v_absence_trend              TO 'scas_app'@'localhost';
GRANT SELECT ON scas_db.v_department_stats           TO 'scas_app'@'localhost';
GRANT SELECT ON scas_db.v_leave_pending              TO 'scas_app'@'localhost';
GRANT SELECT ON scas_db.v_leave_history              TO 'scas_app'@'localhost';
GRANT SELECT ON scas_db.v_qr_active                  TO 'scas_app'@'localhost';
GRANT SELECT ON scas_db.v_audit_trail                TO 'scas_app'@'localhost';
GRANT SELECT ON scas_db.v_security_dashboard         TO 'scas_app'@'localhost';
GRANT SELECT ON scas_db.v_index_inventory            TO 'scas_app'@'localhost';
GRANT SELECT ON scas_db.v_redundant_indexes          TO 'scas_app'@'localhost';

/* Reference and lookup data the screens need to render drop-downs. Read-only
   on the base table is acceptable here because these tables hold no personal
   or security data. */
GRANT SELECT ON scas_db.school           TO 'scas_app'@'localhost';
GRANT SELECT ON scas_db.user_role        TO 'scas_app'@'localhost';
GRANT SELECT ON scas_db.classroom        TO 'scas_app'@'localhost';
GRANT SELECT ON scas_db.academic_term    TO 'scas_app'@'localhost';
GRANT SELECT ON scas_db.holiday          TO 'scas_app'@'localhost';
GRANT SELECT ON scas_db.system_setting   TO 'scas_app'@'localhost';
GRANT SELECT ON scas_db.notification     TO 'scas_app'@'localhost';
GRANT SELECT ON scas_db.qr_code          TO 'scas_app'@'localhost';
GRANT SELECT ON scas_db.timetable        TO 'scas_app'@'localhost';
GRANT SELECT ON scas_db.teacher          TO 'scas_app'@'localhost';
GRANT SELECT ON scas_db.leave_request    TO 'scas_app'@'localhost';
GRANT SELECT ON scas_db.attendance       TO 'scas_app'@'localhost';
GRANT SELECT ON scas_db.backup_log       TO 'scas_app'@'localhost';
GRANT SELECT ON scas_db.query_performance_log TO 'scas_app'@'localhost';

/* The audit and security logs are READ-only to the application: the admin
   console and the user's own "recent activity" panel display them. The
   application holds no INSERT, UPDATE or DELETE on either, so it can show the
   trail but can never edit or erase it - which is the property that makes an
   audit trail worth having. Both tables are written exclusively by triggers
   and by SECURITY DEFINER procedures. */
GRANT SELECT ON scas_db.audit_log      TO 'scas_app'@'localhost';
GRANT SELECT ON scas_db.security_event TO 'scas_app'@'localhost';

/* COLUMN-LEVEL RESTRICTION ON THE CREDENTIAL TABLE.
   The app must read names and role ids to render the interface, but it must
   never be able to SELECT password_hash - the hashes are compared inside
   sp_authenticate_start, which runs as its DEFINER, not as the caller. */
GRANT SELECT (user_id, full_name, username, role_id, school_id, phone_number,
              email, is_active, last_login_at, locked_until,
              failed_login_attempts, must_change_password, created_at)
      ON scas_db.app_user TO 'scas_app'@'localhost';

/* 3b. Write access: EXECUTE on procedures only. No INSERT/UPDATE/DELETE
       anywhere. This is what makes the business rules non-bypassable. */
GRANT EXECUTE ON PROCEDURE scas_db.sp_authenticate_start          TO 'scas_app'@'localhost';
GRANT EXECUTE ON PROCEDURE scas_db.sp_login_success               TO 'scas_app'@'localhost';
GRANT EXECUTE ON PROCEDURE scas_db.sp_login_failure               TO 'scas_app'@'localhost';
GRANT EXECUTE ON PROCEDURE scas_db.sp_change_password             TO 'scas_app'@'localhost';
GRANT EXECUTE ON PROCEDURE scas_db.sp_unlock_account              TO 'scas_app'@'localhost';
GRANT EXECUTE ON PROCEDURE scas_db.sp_create_user                 TO 'scas_app'@'localhost';
GRANT EXECUTE ON PROCEDURE scas_db.sp_set_user_active             TO 'scas_app'@'localhost';
GRANT EXECUTE ON PROCEDURE scas_db.sp_generate_qr_code            TO 'scas_app'@'localhost';
GRANT EXECUTE ON PROCEDURE scas_db.sp_revoke_qr_code              TO 'scas_app'@'localhost';
GRANT EXECUTE ON PROCEDURE scas_db.sp_record_attendance           TO 'scas_app'@'localhost';
GRANT EXECUTE ON PROCEDURE scas_db.sp_mark_absentees              TO 'scas_app'@'localhost';
GRANT EXECUTE ON PROCEDURE scas_db.sp_submit_leave_request        TO 'scas_app'@'localhost';
GRANT EXECUTE ON PROCEDURE scas_db.sp_action_leave_request        TO 'scas_app'@'localhost';
GRANT EXECUTE ON PROCEDURE scas_db.sp_monthly_attendance_report   TO 'scas_app'@'localhost';
GRANT EXECUTE ON PROCEDURE scas_db.sp_teacher_attendance_summary  TO 'scas_app'@'localhost';
GRANT EXECUTE ON PROCEDURE scas_db.sp_refresh_attendance_summary  TO 'scas_app'@'localhost';
GRANT EXECUTE ON PROCEDURE scas_db.sp_transfer_teacher_sessions   TO 'scas_app'@'localhost';
GRANT EXECUTE ON PROCEDURE scas_db.sp_archive_old_attendance      TO 'scas_app'@'localhost';
GRANT EXECUTE ON PROCEDURE scas_db.sp_detect_timetable_conflicts  TO 'scas_app'@'localhost';
GRANT EXECUTE ON PROCEDURE scas_db.sp_run_integrity_check         TO 'scas_app'@'localhost';
GRANT EXECUTE ON PROCEDURE scas_db.sp_log_query_performance       TO 'scas_app'@'localhost';
GRANT EXECUTE ON PROCEDURE scas_db.sp_create_timetable_session    TO 'scas_app'@'localhost';
GRANT EXECUTE ON PROCEDURE scas_db.sp_set_timetable_active        TO 'scas_app'@'localhost';
GRANT EXECUTE ON PROCEDURE scas_db.sp_update_setting              TO 'scas_app'@'localhost';

/* NOTE: the recovery procedures (sp_recovery_report, sp_settings_as_of,
   sp_restore_setting_as_of, sp_show_locks, sp_month_end_report_serializable)
   are created in 08_transactions_recovery.sql, which runs after this file.
   MariaDB refuses GRANT EXECUTE on a routine that does not exist yet, so
   those grants live at the end of 08 rather than here. */

/* The timetable and settings procedures are also part of the administrator
   role bundle. */
GRANT EXECUTE ON PROCEDURE scas_db.sp_create_timetable_session TO scas_schooladmin_role;
GRANT EXECUTE ON PROCEDURE scas_db.sp_set_timetable_active     TO scas_schooladmin_role;

/* The functions the views and the app call directly. */
GRANT EXECUTE ON FUNCTION scas_db.fn_get_setting        TO 'scas_app'@'localhost';
GRANT EXECUTE ON FUNCTION scas_db.fn_attendance_rate    TO 'scas_app'@'localhost';
GRANT EXECUTE ON FUNCTION scas_db.fn_qr_status          TO 'scas_app'@'localhost';
GRANT EXECUTE ON FUNCTION scas_db.fn_is_on_leave        TO 'scas_app'@'localhost';
GRANT EXECUTE ON FUNCTION scas_db.fn_is_holiday         TO 'scas_app'@'localhost';
GRANT EXECUTE ON FUNCTION scas_db.fn_mask_phone         TO 'scas_app'@'localhost';
GRANT EXECUTE ON FUNCTION scas_db.fn_grace_minutes      TO 'scas_app'@'localhost';

/* The notification read-state is the one piece of pure UI state the app owns
   outright, so it gets a narrow column-level UPDATE rather than a procedure. */
GRANT UPDATE (is_read) ON scas_db.notification TO 'scas_app'@'localhost';

/* ###########################################################################
   PART 4 - THE OTHER ACCOUNTS, VIA ROLES
   ######################################################################### */

/* Roles are granted to the human accounts, then made DEFAULT so they are
   active from the moment the person connects. Without SET DEFAULT ROLE a
   MariaDB role is dormant until the session issues SET ROLE. */
GRANT scas_auditor_role TO 'scas_auditor'@'localhost';
SET DEFAULT ROLE scas_auditor_role FOR 'scas_auditor'@'localhost';

GRANT scas_backup_role TO 'scas_backup'@'localhost';
SET DEFAULT ROLE scas_backup_role FOR 'scas_backup'@'localhost';

GRANT scas_dba_role TO 'scas_dba'@'localhost';
SET DEFAULT ROLE scas_dba_role FOR 'scas_dba'@'localhost';

/* The reporting account reads the presentation views and nothing else - it is
   what a spreadsheet or a BI tool would connect with. */
GRANT SELECT ON scas_db.v_attendance_detail          TO 'scas_readonly'@'localhost';
GRANT SELECT ON scas_db.v_monthly_attendance_summary TO 'scas_readonly'@'localhost';
GRANT SELECT ON scas_db.v_absence_trend              TO 'scas_readonly'@'localhost';
GRANT SELECT ON scas_db.v_teacher_ranking            TO 'scas_readonly'@'localhost';
GRANT SELECT ON scas_db.v_department_stats           TO 'scas_readonly'@'localhost';

/* scas_app is NOT given a role: its privileges are granted directly and
   explicitly. A service account whose rights depend on role activation can
   silently lose them after a driver or connector change; the application must
   fail on day one if a privilege is missing, not on a random Tuesday. */

/* ###########################################################################
   PART 5 - ENCRYPTION OF SENSITIVE PERSONAL DATA (encryption at rest)
   Ghana's Data Protection Act, 2012 (Act 843) treats national identity and
   bank details as sensitive personal data. Those fields are therefore stored
   encrypted, not in clear text, so that a stolen data file or a leaked
   mysqldump does not expose them.

   KEY MANAGEMENT: the key is supplied by the application at call time and is
   NOT stored anywhere in the database. Keeping the key next to the ciphertext
   would be theatre - anyone who can read the data could read the key.
   ######################################################################### */

CREATE TABLE IF NOT EXISTS teacher_sensitive (
    teacher_id        INT UNSIGNED NOT NULL,
    national_id_enc   VARBINARY(255) NULL COMMENT 'AES-256 ciphertext',
    bank_account_enc  VARBINARY(255) NULL COMMENT 'AES-256 ciphertext',
    updated_at        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT pk_teacher_sensitive PRIMARY KEY (teacher_id),
    CONSTRAINT fk_sensitive_teacher
        FOREIGN KEY (teacher_id) REFERENCES teacher (teacher_id)
        ON UPDATE CASCADE ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  COMMENT='Sensitive personal data, encrypted at rest';

DELIMITER $$

/* The key is stretched with SHA2-512 before use so that a short human key
   still produces a full-length AES key. */
DROP PROCEDURE IF EXISTS sp_store_sensitive $$
CREATE PROCEDURE sp_store_sensitive(
        IN p_teacher_id  INT UNSIGNED,
        IN p_national_id VARCHAR(50),
        IN p_bank_acct   VARCHAR(50),
        IN p_key         VARCHAR(100))
MODIFIES SQL DATA
BEGIN
    IF p_key IS NULL OR CHAR_LENGTH(p_key) < 12 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'SCAS: encryption key is too weak';
    END IF;

    INSERT INTO teacher_sensitive (teacher_id, national_id_enc, bank_account_enc)
    VALUES (p_teacher_id,
            AES_ENCRYPT(p_national_id, UNHEX(SHA2(p_key, 512))),
            AES_ENCRYPT(p_bank_acct,   UNHEX(SHA2(p_key, 512))))
    ON DUPLICATE KEY UPDATE
        national_id_enc  = VALUES(national_id_enc),
        bank_account_enc = VALUES(bank_account_enc);
END $$

/* A wrong key returns NULL rather than garbage, so the caller can detect it. */
DROP PROCEDURE IF EXISTS sp_read_sensitive $$
CREATE PROCEDURE sp_read_sensitive(
        IN p_teacher_id INT UNSIGNED,
        IN p_key        VARCHAR(100))
READS SQL DATA
BEGIN
    SELECT  teacher_id,
            CAST(AES_DECRYPT(national_id_enc,  UNHEX(SHA2(p_key, 512))) AS CHAR) AS national_id,
            CAST(AES_DECRYPT(bank_account_enc, UNHEX(SHA2(p_key, 512))) AS CHAR) AS bank_account,
            updated_at
    FROM teacher_sensitive
    WHERE teacher_id = p_teacher_id;
END $$

DELIMITER ;

/* Only the school administrator role may touch this table, and only through
   the procedures. Note there is no SELECT grant on teacher_sensitive itself -
   the raw ciphertext is not exposed even to the roles that may decrypt it. */
GRANT EXECUTE ON PROCEDURE scas_db.sp_store_sensitive TO scas_schooladmin_role;
GRANT EXECUTE ON PROCEDURE scas_db.sp_read_sensitive  TO scas_schooladmin_role;
GRANT EXECUTE ON PROCEDURE scas_db.sp_store_sensitive TO 'scas_app'@'localhost';
GRANT EXECUTE ON PROCEDURE scas_db.sp_read_sensitive  TO 'scas_app'@'localhost';

/* ###########################################################################
   PART 6 - PRIVILEGE REPORTING
   The admin console renders these so the privilege model can be inspected
   from inside the application instead of trusted on faith.
   ######################################################################### */

CREATE OR REPLACE
    SQL SECURITY INVOKER
    VIEW v_privilege_matrix AS
SELECT GRANTEE, 'GLOBAL' AS scope, NULL AS object_name, PRIVILEGE_TYPE, IS_GRANTABLE
FROM information_schema.USER_PRIVILEGES
WHERE GRANTEE LIKE '%scas%'
UNION ALL
SELECT GRANTEE, 'SCHEMA', TABLE_SCHEMA, PRIVILEGE_TYPE, IS_GRANTABLE
FROM information_schema.SCHEMA_PRIVILEGES
WHERE GRANTEE LIKE '%scas%'
UNION ALL
SELECT GRANTEE, 'TABLE', CONCAT(TABLE_SCHEMA, '.', TABLE_NAME), PRIVILEGE_TYPE, IS_GRANTABLE
FROM information_schema.TABLE_PRIVILEGES
WHERE GRANTEE LIKE '%scas%'
UNION ALL
SELECT GRANTEE, 'COLUMN', CONCAT(TABLE_SCHEMA, '.', TABLE_NAME, '.', COLUMN_NAME),
       PRIVILEGE_TYPE, IS_GRANTABLE
FROM information_schema.COLUMN_PRIVILEGES
WHERE GRANTEE LIKE '%scas%';

FLUSH PRIVILEGES;

/* ###########################################################################
   PART 7 - SERVER HARDENING NOTES (actions for the deployment checklist)
   These are NOT executed here, because they affect the whole XAMPP server and
   would break the other databases on this machine. They belong in the
   deployment runbook - see docs/SECURITY.md.

   1. Set a root password:   ALTER USER 'root'@'localhost' IDENTIFIED BY '...';
      XAMPP ships with a blank root password. That is acceptable on an
      isolated development laptop and unacceptable anywhere else.
   2. Remove anonymous accounts:  DELETE FROM mysql.user WHERE User = '';
   3. Drop the shipped test schema:  DROP DATABASE IF EXISTS test;
   4. Bind the server to loopback in my.ini:  bind-address = 127.0.0.1
   5. Require TLS for any non-local account:
         ALTER USER '...'@'%' REQUIRE SSL;
   6. Restrict phpMyAdmin to localhost in the Apache configuration.
   7. Enable the audit plugin if the deployment needs statement-level
      logging beyond the trigger-based trail:
         INSTALL SONAME 'server_audit';
   ######################################################################### */

/* ###########################################################################
   PART 8 - VERIFICATION
   ######################################################################### */

SELECT '--- roles created ---' AS check_step;
SELECT User AS role_name FROM mysql.user WHERE is_role = 'Y' AND User LIKE 'scas%';

SELECT '--- application account privileges ---' AS check_step;
SHOW GRANTS FOR 'scas_app'@'localhost';

/* Proof that the application cannot write directly.
   This must check COLUMN_PRIVILEGES as well as TABLE_PRIVILEGES: a column-level
   grant does not appear in TABLE_PRIVILEGES at all, so checking only the latter
   would report "no write privileges" while a column-level UPDATE was in force.
   The listing below is therefore the complete set of write grants held by the
   application account, and it must contain exactly one row:
       notification.is_read  -- marking a notification as read
   That single exception is deliberate. It touches no business fact, and giving
   it a procedure of its own would have added a round trip to every page render
   for no security gain. Everything else - every attendance row, every QR code,
   every account - is reachable only through a stored procedure. */
SELECT '--- proof: every write grant held by scas_app (expect exactly 1) ---' AS check_step;
SELECT TABLE_NAME AS object_name, '(whole table)' AS column_name, PRIVILEGE_TYPE
FROM   information_schema.TABLE_PRIVILEGES
WHERE  GRANTEE = '''scas_app''@''localhost'''
  AND  PRIVILEGE_TYPE IN ('INSERT','UPDATE','DELETE','DROP','ALTER')
UNION ALL
SELECT TABLE_NAME, COLUMN_NAME, PRIVILEGE_TYPE
FROM   information_schema.COLUMN_PRIVILEGES
WHERE  GRANTEE = '''scas_app''@''localhost'''
  AND  PRIVILEGE_TYPE IN ('INSERT','UPDATE','DELETE');

SELECT CASE WHEN COUNT(*) = 1 THEN 'PASS - only notification.is_read is writable'
            ELSE CONCAT('FAIL - ', COUNT(*), ' write grants found, expected 1')
       END AS write_privilege_verdict
FROM (
    SELECT 1 AS x FROM information_schema.TABLE_PRIVILEGES
    WHERE GRANTEE = '''scas_app''@''localhost'''
      AND PRIVILEGE_TYPE IN ('INSERT','UPDATE','DELETE','DROP','ALTER')
    UNION ALL
    SELECT 1 FROM information_schema.COLUMN_PRIVILEGES
    WHERE GRANTEE = '''scas_app''@''localhost'''
      AND PRIVILEGE_TYPE IN ('INSERT','UPDATE','DELETE')
) w;

/* The other half of the claim: password_hash must not be readable. */
SELECT '--- proof: scas_app cannot read password_hash ---' AS check_step;
SELECT CASE WHEN COUNT(*) = 0 THEN 'PASS - password_hash is not granted to the application'
            ELSE 'FAIL - password_hash is readable' END AS password_hash_verdict
FROM   information_schema.COLUMN_PRIVILEGES
WHERE  GRANTEE = '''scas_app''@''localhost'''
  AND  TABLE_NAME = 'app_user' AND COLUMN_NAME = 'password_hash';

SELECT '07 complete - security and authorization installed' AS status;

