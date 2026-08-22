/* ============================================================================
   SCAS - FILE 09 : SCHEDULED EVENTS (the DBMS job scheduler)
   ---------------------------------------------------------------------------
   Four jobs run unattended inside the DBMS. They are events rather than
   Windows Task Scheduler entries for one reason: they must run even when no
   application server, browser or user is present. Attendance data must not
   depend on somebody remembering to click something at the end of the day.
   ========================================================================= */

SET NAMES utf8mb4;
USE scas_db;

/* The scheduler thread is OFF by default in XAMPP. This turns it on now; to
   make it survive a restart add  event_scheduler = ON  to the [mysqld]
   section of C:\xampp\mysql\bin\my.ini. */
SET GLOBAL event_scheduler = ON;

DELIMITER $$

/* ---------------------------------------------------------------------------
   ev_mark_daily_absentees - 23:30 every day.
   Closes the day: every scheduled session with no check-in becomes Absent, or
   Excused where approved leave covers it. This is what turns "no data" into
   an actual attendance verdict.
   NULL as the school parameter means "every school".
   ------------------------------------------------------------------------ */
DROP EVENT IF EXISTS ev_mark_daily_absentees $$
CREATE EVENT ev_mark_daily_absentees
ON SCHEDULE EVERY 1 DAY
    STARTS (CURRENT_DATE + INTERVAL 1 DAY + INTERVAL 23 HOUR + INTERVAL 30 MINUTE)
ON COMPLETION PRESERVE
ENABLE
COMMENT 'Closes the attendance day: marks Absent / Excused'
DO
BEGIN
    DECLARE v_absent  INT DEFAULT 0;
    DECLARE v_excused INT DEFAULT 0;
    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
        INSERT INTO security_event (event_type, detail, severity)
        VALUES ('DATA_EXPORT', 'ev_mark_daily_absentees failed', 'CRITICAL');

    CALL sp_mark_absentees(CURDATE(), NULL, v_absent, v_excused);

    INSERT INTO security_event (event_type, detail, severity)
    VALUES ('DATA_EXPORT',
            CONCAT('Daily close for ', CURDATE(), ': ', v_absent,
                   ' absent, ', v_excused, ' excused'),
            'INFO');
END $$

/* ---------------------------------------------------------------------------
   ev_refresh_summary - hourly.
   Rebuilds the materialised aggregate that the dashboards read, over a
   rolling 7-day window (older days no longer change, so re-aggregating them
   every hour would be waste).
   ------------------------------------------------------------------------ */
DROP EVENT IF EXISTS ev_refresh_summary $$
CREATE EVENT ev_refresh_summary
ON SCHEDULE EVERY 1 HOUR
ON COMPLETION PRESERVE
ENABLE
COMMENT 'Refreshes attendance_daily_summary for the last 7 days'
DO
BEGIN
    DECLARE v_rows INT DEFAULT 0;
    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION BEGIN END;
    CALL sp_refresh_attendance_summary(CURDATE() - INTERVAL 7 DAY, CURDATE(), v_rows);
END $$

/* ---------------------------------------------------------------------------
   ev_revoke_stale_codes - every 15 minutes.
   Marks expired, never-scanned codes as revoked. The expiry check at scan
   time already rejects them; this makes the state explicit in the data so the
   headteacher's screen shows why a session has no attendance.
   ------------------------------------------------------------------------ */
DROP EVENT IF EXISTS ev_revoke_stale_codes $$
CREATE EVENT ev_revoke_stale_codes
ON SCHEDULE EVERY 15 MINUTE
ON COMPLETION PRESERVE
ENABLE
COMMENT 'Flags expired unused QR codes'
DO
    UPDATE qr_code
       SET is_revoked = 1,
           revoked_reason = 'Expired without being scanned'
     WHERE is_revoked = 0
       AND scan_count = 0
       AND expiry_datetime < NOW() - INTERVAL 1 HOUR $$

/* ---------------------------------------------------------------------------
   ev_purge_security_events - weekly.
   Retention policy: security telemetry is kept for the configured number of
   days (default 180). The AUDIT trail is deliberately NOT purged - it is the
   evidential record and has no expiry.
   ------------------------------------------------------------------------ */
DROP EVENT IF EXISTS ev_purge_security_events $$
CREATE EVENT ev_purge_security_events
ON SCHEDULE EVERY 1 WEEK
ON COMPLETION PRESERVE
ENABLE
COMMENT 'Applies the retention policy to security_event'
DO
BEGIN
    DECLARE v_days INT DEFAULT 180;
    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION BEGIN END;

    SET v_days = CAST(IFNULL(fn_get_setting('security.event_retention_days'), '180') AS SIGNED);

    DELETE FROM security_event
     WHERE occurred_at < NOW() - INTERVAL v_days DAY
       AND severity = 'INFO';
END $$

DELIMITER ;

SELECT EVENT_NAME, STATUS, INTERVAL_VALUE, INTERVAL_FIELD, EVENT_COMMENT
FROM information_schema.EVENTS WHERE EVENT_SCHEMA = 'scas_db';

SELECT CONCAT('09 complete - ', COUNT(*), ' scheduled events; scheduler is ',
              @@event_scheduler) AS status
FROM information_schema.EVENTS WHERE EVENT_SCHEMA = 'scas_db';
