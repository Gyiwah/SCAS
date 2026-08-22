/* ============================================================================
   SCAS - FILE 02 : ACCESS PATHS, INDEXES AND OPTIMISER STATISTICS
   Objective (a) Query Processing & Evaluation - part 1 of 2.
   File 09 measures the plans; this file builds the structures the optimiser
   chooses between.
   ---------------------------------------------------------------------------
   Indexing method used
   1. List the real query workload (below).
   2. For each query decide the driving predicate, then order the composite
      index columns: equality predicates first, then range, then columns that
      only need to be covered.
   3. Do not index low-cardinality flags on their own - the optimiser will
      correctly ignore them and the index only costs write time.
   4. Re-measure with ANALYZE (file 09) and keep only indexes that change a
      plan.

   THE WORKLOAD (derived from proposal 6 - Queries / SQL and the app screens)
   Q1 live board      : who is scheduled right now and has not scanned
   Q2 teacher history : one teacher's attendance between two dates
   Q3 monthly report  : per-teacher present/late/absent counts for a month
   Q4 scan validation : find a QR code by its token value           (hot path)
   Q5 absence trend   : daily absence counts across a term
   Q6 leave conflicts : approved leave overlapping a date
   Q7 audit lookup    : all changes to one record
   Q8 security review : failed logins in the last hour
   ========================================================================= */

SET NAMES utf8mb4;
USE scas_db;

/* ---------------------------------------------------------------------------
   Q4 - SCAN VALIDATION (the hot path: every check-in runs it)
   uk_qr_code_value already gives an O(log n) unique lookup on the token.
   What it does NOT cover is the follow-up test "is this code still valid?",
   which reads expiry_datetime, is_revoked, scan_count and max_scans. Adding
   them to a secondary index makes the validation a covering index read, so
   InnoDB never touches the clustered index at all.
   Column order: code_value is the equality predicate and is unique, so it
   leads; the rest are payload.
   ------------------------------------------------------------------------ */
CREATE INDEX ix_qr_validation
    ON qr_code (code_value, expiry_datetime, is_revoked, scan_count, max_scans);

/* Sessions for a given day, used by the QR generation screen and by the
   nightly absentee job. session_date is a range/equality predicate. */
CREATE INDEX ix_qr_session_date
    ON qr_code (session_date, timetable_id);

/* ---------------------------------------------------------------------------
   Q2 / Q3 - TEACHER HISTORY AND MONTHLY REPORT
   Predicate shape: teacher_id = ? AND session_date BETWEEN ? AND ?
   then GROUP BY status, SUM(minutes_late).
   Equality (teacher_id) first, range (session_date) second, and the two
   aggregated columns appended so the whole query is answered from the index
   - EXPLAIN reports "Using index" and zero row fetches from the table.
   ------------------------------------------------------------------------ */
CREATE INDEX ix_att_teacher_period
    ON attendance (teacher_id, session_date, status, minutes_late);

/* ---------------------------------------------------------------------------
   Q5 - ABSENCE TREND ACROSS A TERM
   Predicate shape: session_date BETWEEN ? AND ? AND status = 'Absent'
   session_date leads because it is the selective range; status follows.
   ------------------------------------------------------------------------ */
CREATE INDEX ix_att_date_status
    ON attendance (session_date, status);

/* ---------------------------------------------------------------------------
   Q1 - LIVE BOARD
   The live board joins timetable to attendance on (timetable_id,session_date).
   That pair is already the leading edge of uk_attendance_session, so NO new
   index is created here. This is the "index we deliberately did not build" -
   see 09 for the EXPLAIN proving the unique key is used for the join.
   ------------------------------------------------------------------------ */

/* Timetable access paths: the live board scans by day + time window, and the
   term screens filter by term. */
CREATE INDEX ix_timetable_slot
    ON timetable (day_of_week, start_time, end_time, is_active);
CREATE INDEX ix_timetable_term
    ON timetable (term_id, is_active, teacher_id);
CREATE INDEX ix_timetable_classroom
    ON timetable (classroom_id, day_of_week);

/* ---------------------------------------------------------------------------
   Q6 - LEAVE OVERLAP
   Predicate shape: teacher_id = ? AND status='Approved'
                    AND ? BETWEEN start_date AND end_date
   A B-tree cannot fully resolve a BETWEEN over two different columns, so the
   index gets us to the teacher's approved rows cheaply and the residual
   date test is applied to that small set.
   ------------------------------------------------------------------------ */
CREATE INDEX ix_leave_lookup
    ON leave_request (teacher_id, status, start_date, end_date);

/* Headteacher approval queue: pending requests oldest first. */
CREATE INDEX ix_leave_queue
    ON leave_request (status, requested_at);

/* ---------------------------------------------------------------------------
   Q7 / Q8 - AUDIT AND SECURITY
   ------------------------------------------------------------------------ */
CREATE INDEX ix_audit_record  ON audit_log (table_name, record_id, changed_at);
CREATE INDEX ix_audit_when    ON audit_log (changed_at);
CREATE INDEX ix_audit_who     ON audit_log (changed_by_user_id, changed_at);

CREATE INDEX ix_sec_type_time ON security_event (event_type, occurred_at);
CREATE INDEX ix_sec_username  ON security_event (username_attempted, occurred_at);
CREATE INDEX ix_sec_time      ON security_event (occurred_at);

/* Authentication and administration lookups. */
CREATE INDEX ix_user_school_role ON app_user (school_id, role_id, is_active);
CREATE INDEX ix_user_locked      ON app_user (locked_until);
CREATE INDEX ix_teacher_dept     ON teacher (department, employment_status);

/* Summary table is read by school + date range on every dashboard load. */
CREATE INDEX ix_summary_school_date ON attendance_daily_summary (school_id, summary_date);

/* ---------------------------------------------------------------------------
   PREFIX INDEX
   device_info is a long free-text string. Indexing the whole column would
   waste space; the first 20 characters ("Android 14 / Chrome...") are enough
   selectivity to investigate a suspected shared device, so only that prefix
   is indexed.
   ------------------------------------------------------------------------ */
CREATE INDEX ix_att_device_prefix ON attendance (device_info(20));

/* ---------------------------------------------------------------------------
   FULL-TEXT INDEX
   Leave reasons are natural language. LIKE '%funeral%' can never use a B-tree
   (leading wildcard), so a full-text index with an inverted word list is the
   correct structure. InnoDB supports FULLTEXT from MariaDB 10.0.5.
   Query with: WHERE MATCH(reason) AGAINST ('funeral' IN NATURAL LANGUAGE MODE)
   ------------------------------------------------------------------------ */
CREATE FULLTEXT INDEX ftx_leave_reason ON leave_request (reason);

/* ===========================================================================
   OPTIMISER STATISTICS
   The optimiser is cost-based: it needs cardinality data to choose a plan.
   MariaDB offers two levels, both enabled here.
   1. Engine-independent statistics: stored in mysql.table_stats /
      column_stats / index_stats, survive restarts and cover columns that have
      no index at all.
   2. Histograms: a distribution of values per column, which lets the
      optimiser estimate the selectivity of a predicate such as
      status = 'Absent' (rare) versus status = 'Present' (common) instead of
      assuming every value is equally likely.
   =========================================================================*/
SET GLOBAL use_stat_tables       = 'preferably';
SET GLOBAL histogram_size        = 254;
SET GLOBAL histogram_type        = 'DOUBLE_PREC_HB';
SET GLOBAL optimizer_use_condition_selectivity = 4;

/* Collect them. Re-run this block after any bulk load, otherwise the
   optimiser plans against stale cardinalities. */
ANALYZE TABLE attendance      PERSISTENT FOR ALL;
ANALYZE TABLE qr_code         PERSISTENT FOR ALL;
ANALYZE TABLE timetable       PERSISTENT FOR ALL;
ANALYZE TABLE teacher         PERSISTENT FOR ALL;
ANALYZE TABLE app_user        PERSISTENT FOR ALL;
ANALYZE TABLE leave_request   PERSISTENT FOR ALL;
ANALYZE TABLE classroom       PERSISTENT FOR ALL;
ANALYZE TABLE audit_log       PERSISTENT FOR ALL;
ANALYZE TABLE security_event  PERSISTENT FOR ALL;

/* ===========================================================================
   MAINTENANCE HELPERS
   =========================================================================*/

/* Redundant-index detector: an index whose column list is a left-prefix of a
   longer index is dead weight - it costs writes and buys nothing. Run this
   before adding any new index.

   IMPORTANT correctness point, found while testing this view against the real
   schema: a UNIQUE index is NEVER redundant just because a longer index
   starts with the same columns. uk_qr_code_value(code_value) looks redundant
   beside ix_qr_validation(code_value, expiry_datetime, ...), but the unique
   index is doing a second job the longer one cannot do - it ENFORCES that no
   two QR codes share a token. Dropping it would remove a constraint, not just
   an access path. The view therefore only reports non-unique indexes as
   redundant candidates. */
CREATE OR REPLACE VIEW v_redundant_indexes AS
SELECT  a.TABLE_NAME,
        a.INDEX_NAME  AS redundant_index,
        b.INDEX_NAME  AS covered_by,
        a.cols        AS redundant_columns,
        b.cols        AS covering_columns
FROM (
    SELECT TABLE_SCHEMA, TABLE_NAME, INDEX_NAME,
           GROUP_CONCAT(COLUMN_NAME ORDER BY SEQ_IN_INDEX) AS cols
    FROM information_schema.STATISTICS
    WHERE TABLE_SCHEMA = 'scas_db'
      AND NON_UNIQUE = 1          /* a UNIQUE index also enforces a rule */
    GROUP BY TABLE_SCHEMA, TABLE_NAME, INDEX_NAME
) a
JOIN (
    SELECT TABLE_SCHEMA, TABLE_NAME, INDEX_NAME,
           GROUP_CONCAT(COLUMN_NAME ORDER BY SEQ_IN_INDEX) AS cols
    FROM information_schema.STATISTICS
    WHERE TABLE_SCHEMA = 'scas_db'
    GROUP BY TABLE_SCHEMA, TABLE_NAME, INDEX_NAME
) b
  ON  a.TABLE_NAME  = b.TABLE_NAME
  AND a.INDEX_NAME <> b.INDEX_NAME
  AND b.cols LIKE CONCAT(a.cols, ',%');

/* Index inventory with cardinality - the DBA console reads this. */
CREATE OR REPLACE VIEW v_index_inventory AS
SELECT  TABLE_NAME,
        INDEX_NAME,
        NON_UNIQUE,
        GROUP_CONCAT(COLUMN_NAME ORDER BY SEQ_IN_INDEX) AS index_columns,
        MAX(CARDINALITY) AS cardinality,
        INDEX_TYPE
FROM information_schema.STATISTICS
WHERE TABLE_SCHEMA = 'scas_db'
GROUP BY TABLE_NAME, INDEX_NAME, NON_UNIQUE, INDEX_TYPE
ORDER BY TABLE_NAME, INDEX_NAME;

SELECT CONCAT('02 complete - ', COUNT(DISTINCT TABLE_NAME, INDEX_NAME), ' indexes on scas_db') AS status
FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = 'scas_db';
