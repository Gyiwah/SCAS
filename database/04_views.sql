/* ============================================================================
   SCAS - FILE 04 : VIEWS
   Two jobs in this file.
   1. Presentation - collapse the normalised joins into the shapes the reports
      and screens actually need, so the PHP layer never writes an eight-table
      join by hand.
   2. Security - a view is the classic SQL mechanism for row- and column-level
      authorisation. Every view here is SQL SECURITY DEFINER, so the low
      privileged application account can be granted SELECT on the VIEW while
      having no privilege at all on the underlying tables. Combined with the
      @scas_school_id session variable this gives row-level security on a DBMS
      that has no native RLS. See 07_security_authorization.sql for the grants.
   ========================================================================= */

SET NAMES utf8mb4;
USE scas_db;

/* ===========================================================================
   1. v_teacher_directory - one row per teacher with identity and school.
   Note fn_mask_phone: contact numbers are masked at the view layer so a
   report consumer never receives the full number.
   =========================================================================*/
CREATE OR REPLACE
    SQL SECURITY DEFINER
    VIEW v_teacher_directory AS
SELECT  t.teacher_id,
        t.staff_number,
        u.user_id,
        u.full_name,
        u.username,
        t.department,
        t.qualification,
        t.date_employed,
        t.employment_status,
        u.email,
        fn_mask_phone(u.phone_number) AS phone_masked,
        u.is_active,
        s.school_id,
        s.school_name,
        s.district,
        s.region,
        r.role_name,
        r.privilege_level,
        TIMESTAMPDIFF(YEAR, t.date_employed, CURDATE()) AS years_of_service
FROM teacher   t
JOIN app_user  u ON u.user_id  = t.user_id
JOIN user_role r ON r.role_id  = u.role_id
LEFT JOIN school s ON s.school_id = u.school_id;

/* ===========================================================================
   2. v_active_timetable - the live schedule of the current term only.
   =========================================================================*/
CREATE OR REPLACE
    SQL SECURITY DEFINER
    VIEW v_active_timetable AS
SELECT  tt.timetable_id,
        tt.subject,
        tt.class_group,
        tt.day_of_week,
        tt.start_time,
        tt.end_time,
        tt.duration_minutes,
        t.teacher_id,
        u.full_name    AS teacher_name,
        t.staff_number,
        t.department,
        c.classroom_id,
        c.room_name,
        c.building,
        sc.school_id,
        sc.school_name,
        at.term_id,
        at.term_name,
        at.academic_year
FROM timetable      tt
JOIN teacher        t  ON t.teacher_id    = tt.teacher_id
JOIN app_user       u  ON u.user_id       = t.user_id
JOIN classroom      c  ON c.classroom_id  = tt.classroom_id
JOIN school         sc ON sc.school_id    = c.school_id
JOIN academic_term  at ON at.term_id      = tt.term_id
WHERE tt.is_active = 1
  AND at.is_current = 1;

/* ===========================================================================
   3. v_attendance_detail - the reporting spine. Every attendance row with
   everything a report could need, so reports never re-join.
   =========================================================================*/
CREATE OR REPLACE
    SQL SECURITY DEFINER
    VIEW v_attendance_detail AS
SELECT  a.attendance_id,
        a.session_date,
        a.scan_datetime,
        a.status,
        a.minutes_late,
        a.remarks,
        a.scan_ip,
        t.teacher_id,
        t.staff_number,
        u.full_name AS teacher_name,
        t.department,
        tt.timetable_id,
        tt.subject,
        tt.class_group,
        tt.day_of_week,
        tt.start_time,
        tt.end_time,
        c.room_name,
        sc.school_id,
        sc.school_name,
        q.qr_code_id,
        q.code_value,
        q.expiry_datetime,
        YEAR(a.session_date)  AS session_year,
        MONTH(a.session_date) AS session_month,
        MONTHNAME(a.session_date) AS session_month_name
FROM attendance a
JOIN teacher    t  ON t.teacher_id    = a.teacher_id
JOIN app_user   u  ON u.user_id       = t.user_id
JOIN timetable  tt ON tt.timetable_id = a.timetable_id
JOIN classroom  c  ON c.classroom_id  = tt.classroom_id
JOIN school     sc ON sc.school_id    = c.school_id
LEFT JOIN qr_code q ON q.qr_code_id   = a.qr_code_id;

/* ===========================================================================
   4. v_live_session_board - today's timetable with its current scan state.
   This is the headteacher's home screen and directly answers proposal
   problem 3: "no real-time view of which classes are currently unstaffed".
   =========================================================================*/
CREATE OR REPLACE
    SQL SECURITY DEFINER
    VIEW v_live_session_board AS
SELECT  vt.timetable_id,
        vt.school_id,
        vt.school_name,
        vt.teacher_id,
        vt.teacher_name,
        vt.staff_number,
        vt.subject,
        vt.class_group,
        vt.room_name,
        vt.start_time,
        vt.end_time,
        CURDATE() AS session_date,
        CASE
            WHEN CURTIME() <  vt.start_time THEN 'Upcoming'
            WHEN CURTIME() BETWEEN vt.start_time AND vt.end_time THEN 'In Progress'
            ELSE 'Ended'
        END AS session_state,
        q.qr_code_id,
        q.expiry_datetime,
        CASE WHEN q.qr_code_id IS NULL THEN 'Not Generated'
             ELSE fn_qr_status(q.code_value) END AS qr_state,
        a.attendance_id,
        COALESCE(a.status,
                 CASE WHEN fn_is_on_leave(vt.teacher_id, CURDATE()) = 1 THEN 'On Leave'
                      ELSE 'No Scan' END) AS attendance_state,
        a.scan_datetime,
        a.minutes_late
FROM v_active_timetable vt
LEFT JOIN qr_code q
       ON q.timetable_id = vt.timetable_id
      AND q.session_date  = CURDATE()
LEFT JOIN attendance a
       ON a.timetable_id = vt.timetable_id
      AND a.session_date  = CURDATE()
      AND a.teacher_id    = vt.teacher_id
WHERE vt.day_of_week = DAYNAME(CURDATE());

/* ===========================================================================
   5. v_unstaffed_now - the alert list: sessions running right now with no
   scan and no approved leave.
   =========================================================================*/
CREATE OR REPLACE
    SQL SECURITY DEFINER
    VIEW v_unstaffed_now AS
SELECT  timetable_id, school_id, school_name, teacher_id, teacher_name,
        staff_number, subject, class_group, room_name, start_time, end_time,
        TIMESTAMPDIFF(MINUTE, TIMESTAMP(CURDATE(), start_time), NOW()) AS minutes_into_session
FROM v_live_session_board
WHERE session_state     = 'In Progress'
  AND attendance_state  = 'No Scan';

/* ===========================================================================
   6. v_monthly_attendance_summary - the printable monthly report
   (proposal 6: "Printable/exportable monthly attendance ... per school").
   =========================================================================*/
CREATE OR REPLACE
    SQL SECURITY DEFINER
    VIEW v_monthly_attendance_summary AS
SELECT  school_id,
        school_name,
        teacher_id,
        staff_number,
        teacher_name,
        department,
        session_year,
        session_month,
        session_month_name,
        COUNT(*)                                        AS sessions_recorded,
        SUM(status = 'Present')                         AS present_count,
        SUM(status = 'Late')                            AS late_count,
        SUM(status = 'Absent')                          AS absent_count,
        SUM(status = 'Excused')                         AS excused_count,
        SUM(minutes_late)                               AS total_minutes_late,
        ROUND(AVG(NULLIF(minutes_late, 0)), 1)          AS avg_lateness_when_late,
        ROUND(SUM(status IN ('Present','Late')) * 100.0
              / NULLIF(SUM(status <> 'Excused'), 0), 2) AS attendance_rate
FROM v_attendance_detail
GROUP BY school_id, school_name, teacher_id, staff_number, teacher_name,
         department, session_year, session_month, session_month_name;

/* ===========================================================================
   7. v_teacher_ranking - uses WINDOW FUNCTIONS (MariaDB 10.2+).
   RANK() and the department average are computed in a single pass over the
   summary rather than with a correlated subquery per teacher; file 09 shows
   the ANALYZE evidence for why that matters.
   =========================================================================*/
CREATE OR REPLACE
    SQL SECURITY DEFINER
    VIEW v_teacher_ranking AS
SELECT  school_id,
        school_name,
        teacher_id,
        teacher_name,
        department,
        SUM(sessions_recorded) AS sessions_recorded,
        SUM(present_count)     AS present_count,
        SUM(late_count)        AS late_count,
        SUM(absent_count)      AS absent_count,
        ROUND(SUM(present_count + late_count) * 100.0
              / NULLIF(SUM(sessions_recorded - excused_count), 0), 2) AS attendance_rate,
        RANK() OVER (
            PARTITION BY school_id
            ORDER BY SUM(present_count + late_count) * 100.0
                     / NULLIF(SUM(sessions_recorded - excused_count), 0) DESC
        ) AS school_rank,
        ROUND(AVG(SUM(present_count + late_count) * 100.0
              / NULLIF(SUM(sessions_recorded - excused_count), 0))
              OVER (PARTITION BY department), 2) AS department_average
FROM v_monthly_attendance_summary
GROUP BY school_id, school_name, teacher_id, teacher_name, department;

/* ===========================================================================
   8. v_absence_trend - daily absence counts, with a 7-day moving average
   computed by a window frame.
   =========================================================================*/
CREATE OR REPLACE
    SQL SECURITY DEFINER
    VIEW v_absence_trend AS
SELECT  school_id,
        school_name,
        session_date,
        COUNT(*)                AS sessions_recorded,
        SUM(status = 'Absent')  AS absences,
        SUM(status = 'Late')    AS lateness,
        ROUND(SUM(status = 'Absent') * 100.0 / COUNT(*), 2) AS absence_pct,
        ROUND(AVG(SUM(status = 'Absent')) OVER (
                  PARTITION BY school_id
                  ORDER BY session_date
                  ROWS BETWEEN 6 PRECEDING AND CURRENT ROW), 2) AS absences_7day_avg
FROM v_attendance_detail
GROUP BY school_id, school_name, session_date;

/* ===========================================================================
   9. v_leave_pending - the headteacher's approval queue.
   =========================================================================*/
CREATE OR REPLACE
    SQL SECURITY DEFINER
    VIEW v_leave_pending AS
SELECT  lr.leave_request_id,
        lr.teacher_id,
        u.full_name AS teacher_name,
        t.staff_number,
        t.department,
        u.school_id,
        lr.leave_type,
        lr.start_date,
        lr.end_date,
        lr.days_requested,
        lr.reason,
        lr.status,
        lr.requested_at,
        DATEDIFF(CURDATE(), DATE(lr.requested_at)) AS days_waiting,
        (SELECT COUNT(*) FROM timetable tt
          WHERE tt.teacher_id = lr.teacher_id AND tt.is_active = 1) AS sessions_affected
FROM leave_request lr
JOIN teacher  t ON t.teacher_id = lr.teacher_id
JOIN app_user u ON u.user_id    = t.user_id
WHERE lr.status = 'Pending';

/* ===========================================================================
   10. v_leave_history - every request with its approver resolved.
   =========================================================================*/
CREATE OR REPLACE
    SQL SECURITY DEFINER
    VIEW v_leave_history AS
SELECT  lr.leave_request_id,
        lr.teacher_id,
        tu.full_name AS teacher_name,
        t.staff_number,
        t.department,
        tu.school_id,
        lr.leave_type,
        lr.start_date,
        lr.end_date,
        lr.days_requested,
        lr.reason,
        lr.status,
        lr.requested_at,
        lr.actioned_at,
        lr.remarks,
        au.full_name AS approved_by_name
FROM leave_request lr
JOIN teacher   t  ON t.teacher_id = lr.teacher_id
JOIN app_user  tu ON tu.user_id   = t.user_id
LEFT JOIN app_user au ON au.user_id = lr.approved_by;

/* ===========================================================================
   11. v_qr_active - codes that can still be scanned right now.
   =========================================================================*/
CREATE OR REPLACE
    SQL SECURITY DEFINER
    VIEW v_qr_active AS
SELECT  q.qr_code_id,
        q.code_value,
        q.session_date,
        q.generated_datetime,
        q.expiry_datetime,
        TIMESTAMPDIFF(MINUTE, NOW(), q.expiry_datetime) AS minutes_remaining,
        q.scan_count,
        q.max_scans,
        vt.timetable_id,
        vt.subject,
        vt.teacher_name,
        vt.teacher_id,
        vt.room_name,
        vt.school_id,
        vt.start_time,
        vt.end_time
FROM qr_code q
JOIN v_active_timetable vt ON vt.timetable_id = q.timetable_id
WHERE q.is_revoked = 0
  AND NOW() BETWEEN q.generated_datetime AND q.expiry_datetime
  AND q.scan_count < q.max_scans;

/* ===========================================================================
   12. v_audit_trail - the audit log with the actor resolved to a name.
   LEFT JOIN, never INNER: an audit row must remain visible even after the
   user who caused it has been deleted.
   =========================================================================*/
CREATE OR REPLACE
    SQL SECURITY DEFINER
    VIEW v_audit_trail AS
SELECT  al.audit_id,
        al.changed_at,
        al.table_name,
        al.record_id,
        al.action,
        al.changed_by_user_id,
        COALESCE(u.full_name, CONCAT('(deleted user #', al.changed_by_user_id, ')'),
                 'system') AS changed_by_name,
        al.db_user,
        al.client_host,
        al.old_values,
        al.new_values
FROM audit_log al
LEFT JOIN app_user u ON u.user_id = al.changed_by_user_id;

/* ===========================================================================
   13. v_security_dashboard - failed logins and lockouts per account in the
   last 24 hours, for the admin security screen.
   =========================================================================*/
CREATE OR REPLACE
    SQL SECURITY DEFINER
    VIEW v_security_dashboard AS
SELECT  COALESCE(se.username_attempted, u.username) AS username,
        u.user_id,
        u.full_name,
        u.is_active,
        u.locked_until,
        CASE WHEN u.locked_until IS NOT NULL AND u.locked_until > NOW()
             THEN 'LOCKED' ELSE 'OPEN' END AS account_state,
        SUM(se.event_type = 'LOGIN_FAILED')   AS failed_24h,
        SUM(se.event_type = 'LOGIN_SUCCESS')  AS success_24h,
        SUM(se.event_type = 'ACCOUNT_LOCKED') AS lockouts_24h,
        SUM(se.severity   = 'CRITICAL')       AS critical_events_24h,
        MAX(se.occurred_at)                   AS last_event_at
FROM security_event se
LEFT JOIN app_user u ON u.user_id = se.user_id
WHERE se.occurred_at >= NOW() - INTERVAL 24 HOUR
GROUP BY COALESCE(se.username_attempted, u.username), u.user_id,
         u.full_name, u.is_active, u.locked_until;

/* ###########################################################################
   ROW-LEVEL SECURITY VIEWS
   MariaDB has no native row-level security. The standard substitute is a view
   whose WHERE clause references the caller's identity. The application sets
   @scas_school_id / @scas_user_id / @scas_privilege at connection time, and
   the application account is granted SELECT on these views only - never on
   the base tables - so it is not possible for a headteacher of School A to
   read School B's rows even with a hand-written query.
   ######################################################################### */

/* 14. Teachers visible to the caller: own school only, unless the caller is a
   System Administrator (privilege 99), who sees every school. */
CREATE OR REPLACE
    SQL SECURITY DEFINER
    VIEW v_my_school_teachers AS
SELECT *
FROM v_teacher_directory
WHERE fn_current_privilege() >= 99
   OR school_id = fn_current_school_id();

/* 15. Attendance visible to the caller, same rule. */
CREATE OR REPLACE
    SQL SECURITY DEFINER
    VIEW v_my_school_attendance AS
SELECT *
FROM v_attendance_detail
WHERE fn_current_privilege() >= 99
   OR school_id = fn_current_school_id();

/* 16. A teacher's own record only - the strictest scope, used by the teacher
   self-service screens. */
CREATE OR REPLACE
    SQL SECURITY DEFINER
    VIEW v_my_attendance AS
SELECT vad.*
FROM v_attendance_detail vad
JOIN teacher t ON t.teacher_id = vad.teacher_id
WHERE t.user_id = fn_current_user_id();

/* 17. A teacher's own timetable. */
CREATE OR REPLACE
    SQL SECURITY DEFINER
    VIEW v_my_timetable AS
SELECT vt.*
FROM v_active_timetable vt
JOIN teacher t ON t.teacher_id = vt.teacher_id
WHERE t.user_id = fn_current_user_id();

/* 18. Department statistics, for the school administrator screen. */
CREATE OR REPLACE
    SQL SECURITY DEFINER
    VIEW v_department_stats AS
SELECT  school_id,
        school_name,
        department,
        COUNT(DISTINCT teacher_id) AS teachers,
        SUM(sessions_recorded)     AS sessions_recorded,
        SUM(absent_count)          AS absences,
        SUM(late_count)            AS lateness,
        ROUND(SUM(present_count + late_count) * 100.0
              / NULLIF(SUM(sessions_recorded - excused_count), 0), 2) AS attendance_rate
FROM v_monthly_attendance_summary
GROUP BY school_id, school_name, department;

SELECT CONCAT('04 complete - ', COUNT(*), ' views') AS status
FROM information_schema.VIEWS WHERE TABLE_SCHEMA = 'scas_db';
