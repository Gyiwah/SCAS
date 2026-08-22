/* ============================================================================
   SCAS - FILE 11 : QUERY PROCESSING AND EVALUATION
   Objective (a) - part 2 of 2. File 02 built the access paths; this file
   measures what the optimiser actually does with them.
   ---------------------------------------------------------------------------
   HOW MariaDB PROCESSES A QUERY

     SQL text
        |  1. PARSER          syntax -> parse tree
        |  2. RESOLVER        names -> real tables, columns, privileges
        |  3. REWRITER        view merging, subquery -> join conversion,
        |                     constant folding, predicate push-down
        |  4. OPTIMISER       cost-based: for each candidate access path,
        |                     estimate rows x cost using index cardinality
        |                     and histograms, then pick the cheapest join
        |                     order and access method
        |  5. EXECUTOR        runs the chosen plan
        v
     result set

   The tools used below inspect stages 4 and 5:
     EXPLAIN               - the plan the optimiser CHOSE          (estimates)
     EXPLAIN FORMAT=JSON   - the same plan with costs and attached conditions
     ANALYZE               - runs the query and reports ESTIMATED vs ACTUAL
                             rows. The gap between them is the single most
                             useful diagnostic in query tuning.
     optimizer_trace       - WHY it chose that plan: every rejected
                             alternative, with its cost.

   Read the r_rows column in ANALYZE output against rows: when they diverge by
   an order of magnitude, the statistics are stale or the predicate is not
   sargable, and the plan is built on a false premise.
   ========================================================================= */

SET NAMES utf8mb4;
USE scas_db;

SELECT '########## Q1: THE SCAN VALIDATION HOT PATH ##########' AS demonstration;
/* Every check-in runs this. It must be O(log n) regardless of how many terms
   of history the table holds. */
SET @sample_code = (SELECT code_value FROM qr_code ORDER BY qr_code_id DESC LIMIT 1);

SELECT '--- plan: lookup by token ---' AS step;
EXPLAIN
SELECT qr_code_id, timetable_id, session_date, expiry_datetime, is_revoked, scan_count, max_scans
FROM qr_code WHERE code_value = @sample_code;
/* EXPECTED: type=const or ref, key=uk_qr_code_value or ix_qr_validation,
   rows=1, Extra="Using index" when ix_qr_validation covers every column read.
   "Using index" means the row was answered entirely from the index pages -
   InnoDB never had to visit the clustered index at all. */

SELECT '--- measured: estimated vs actual ---' AS step;
ANALYZE
SELECT qr_code_id, timetable_id, session_date, expiry_datetime, is_revoked, scan_count, max_scans
FROM qr_code WHERE code_value = @sample_code;

SELECT '########## Q2: SARGABILITY - THE MOST COMMON TUNING MISTAKE ##########' AS demonstration;
/* Both queries return the SAME rows. Only one of them can use an index.
   A predicate is "sargable" (Search ARGument able) when the indexed column
   appears bare on one side of the comparison. Wrapping it in a function
   destroys that: the B-tree is ordered by session_date, not by
   YEAR(session_date), so the engine has no choice but to read every row and
   compute the function for each one. */

SELECT '--- BAD: function applied to the indexed column ---' AS step;
EXPLAIN
SELECT COUNT(*) FROM attendance
WHERE YEAR(session_date) = 2026 AND MONTH(session_date) = 7;
/* EXPECTED: type=index or ALL, key is NULL or a full index scan, and rows is
   the whole table. */

SELECT '--- GOOD: the same question as a range on the bare column ---' AS step;
EXPLAIN
SELECT COUNT(*) FROM attendance
WHERE session_date >= '2026-07-01' AND session_date < '2026-08-01';
/* EXPECTED: type=range, key=ix_att_date_status, rows = only July. */

SELECT '--- measured, bad ---' AS step;
ANALYZE SELECT COUNT(*) FROM attendance
WHERE YEAR(session_date) = 2026 AND MONTH(session_date) = 7;

SELECT '--- measured, good ---' AS step;
ANALYZE SELECT COUNT(*) FROM attendance
WHERE session_date >= '2026-07-01' AND session_date < '2026-08-01';
/* Compare r_rows on the two ANALYZE outputs: the sargable form examines only
   the July rows, the non-sargable form examines the entire table to return
   exactly the same number. */

SELECT '########## Q3: COVERING INDEX ##########' AS demonstration;
/* ix_att_teacher_period is (teacher_id, session_date, status, minutes_late).
   The query below reads only those four columns, so the index alone can
   answer it. */
SELECT '--- covered: every column read is in the index ---' AS step;
EXPLAIN
SELECT status, COUNT(*), SUM(minutes_late)
FROM attendance
WHERE teacher_id = 1 AND session_date BETWEEN '2026-05-04' AND '2026-08-18'
GROUP BY status;
/* EXPECTED: Extra contains "Using index" - no table access. */

SELECT '--- not covered: remarks is not in the index ---' AS step;
EXPLAIN
SELECT status, remarks
FROM attendance
WHERE teacher_id = 1 AND session_date BETWEEN '2026-05-04' AND '2026-08-18';
/* EXPECTED: "Using index condition" or no "Using index" - the engine must now
   follow each index entry back to the clustered index to fetch remarks. That
   extra step is the cost of one column. */

SELECT '########## Q4: QUERY REWRITING - THREE WAYS TO ASK ONE QUESTION ##########' AS demonstration;
/* "Which teachers were absent more often than the school average?"
   Semantically identical; very different execution. */

SELECT '--- form A: correlated subquery (recomputes the average per row) ---' AS step;
EXPLAIN
SELECT t.teacher_id, u.full_name,
       (SELECT COUNT(*) FROM attendance a
         WHERE a.teacher_id = t.teacher_id AND a.status = 'Absent') AS absences
FROM teacher t
JOIN app_user u ON u.user_id = t.user_id
WHERE (SELECT COUNT(*) FROM attendance a
        WHERE a.teacher_id = t.teacher_id AND a.status = 'Absent')
      > (SELECT COUNT(*) / COUNT(DISTINCT teacher_id) FROM attendance WHERE status = 'Absent');

SELECT '--- form B: derived table, aggregate once then join ---' AS step;
EXPLAIN
SELECT x.teacher_id, u.full_name, x.absences
FROM (SELECT teacher_id, COUNT(*) AS absences
      FROM attendance WHERE status = 'Absent'
      GROUP BY teacher_id) x
JOIN teacher  t ON t.teacher_id = x.teacher_id
JOIN app_user u ON u.user_id    = t.user_id
WHERE x.absences > (SELECT COUNT(*) / COUNT(DISTINCT teacher_id)
                    FROM attendance WHERE status = 'Absent');

SELECT '--- form C: window function, one pass, no self-join ---' AS step;
EXPLAIN
WITH per_teacher AS (
    SELECT teacher_id, COUNT(*) AS absences
    FROM attendance WHERE status = 'Absent'
    GROUP BY teacher_id
)
SELECT teacher_id, absences, AVG(absences) OVER () AS school_average
FROM per_teacher
WHERE absences > (SELECT AVG(absences) FROM per_teacher);

SELECT '--- measured: A ---' AS step;
ANALYZE
SELECT t.teacher_id, u.full_name,
       (SELECT COUNT(*) FROM attendance a
         WHERE a.teacher_id = t.teacher_id AND a.status = 'Absent') AS absences
FROM teacher t
JOIN app_user u ON u.user_id = t.user_id
WHERE (SELECT COUNT(*) FROM attendance a
        WHERE a.teacher_id = t.teacher_id AND a.status = 'Absent')
      > (SELECT COUNT(*) / COUNT(DISTINCT teacher_id) FROM attendance WHERE status = 'Absent');

SELECT '--- measured: C ---' AS step;
ANALYZE
WITH per_teacher AS (
    SELECT teacher_id, COUNT(*) AS absences
    FROM attendance WHERE status = 'Absent'
    GROUP BY teacher_id
)
SELECT teacher_id, absences, AVG(absences) OVER () AS school_average
FROM per_teacher
WHERE absences > (SELECT AVG(absences) FROM per_teacher);
/* Form C is the version used in v_teacher_ranking. */

SELECT '########## Q5: FULL-TEXT vs LEADING-WILDCARD LIKE ##########' AS demonstration;
SELECT '--- LIKE with a leading wildcard cannot use any B-tree ---' AS step;
EXPLAIN
SELECT leave_request_id, reason FROM leave_request WHERE reason LIKE '%funeral%';
/* EXPECTED: type=ALL. A B-tree is ordered by the START of the string, so a
   leading % gives it nothing to seek on. */

SELECT '--- FULLTEXT uses an inverted word index ---' AS step;
EXPLAIN
SELECT leave_request_id, reason FROM leave_request
WHERE MATCH(reason) AGAINST ('funeral' IN NATURAL LANGUAGE MODE);
/* EXPECTED: type=fulltext, key=ftx_leave_reason. */

SELECT '--- results, with relevance ranking ---' AS step;
SELECT leave_request_id, teacher_id, LEFT(reason, 60) AS reason,
       ROUND(MATCH(reason) AGAINST ('funeral hospital leave' IN NATURAL LANGUAGE MODE), 4) AS relevance
FROM leave_request
WHERE MATCH(reason) AGAINST ('funeral hospital leave' IN NATURAL LANGUAGE MODE)
ORDER BY relevance DESC;

SELECT '########## Q6: JOIN ORDER AND INDEX HINTS ##########' AS demonstration;
/* The optimiser normally picks the join order. These show what it chose and
   what the alternatives would cost - hints are a diagnostic tool here, not a
   recommendation. Hard-coded hints go stale as data grows. */

SELECT '--- optimiser choice ---' AS step;
EXPLAIN
SELECT u.full_name, COUNT(*) AS sessions
FROM attendance a
JOIN teacher  t ON t.teacher_id = a.teacher_id
JOIN app_user u ON u.user_id    = t.user_id
WHERE a.session_date BETWEEN '2026-08-01' AND '2026-08-18'
GROUP BY u.full_name;

SELECT '--- forced: read attendance first, whatever the cost model says ---' AS step;
EXPLAIN
SELECT STRAIGHT_JOIN u.full_name, COUNT(*) AS sessions
FROM attendance a
JOIN teacher  t ON t.teacher_id = a.teacher_id
JOIN app_user u ON u.user_id    = t.user_id
WHERE a.session_date BETWEEN '2026-08-01' AND '2026-08-18'
GROUP BY u.full_name;

SELECT '--- index deliberately withheld, to price the index ---' AS step;
EXPLAIN
SELECT COUNT(*) FROM attendance IGNORE INDEX (ix_att_date_status, ix_att_teacher_period)
WHERE session_date BETWEEN '2026-08-01' AND '2026-08-18';

SELECT '########## Q7: MATERIALISED AGGREGATE vs LIVE AGGREGATE ##########' AS demonstration;
/* The dashboard could aggregate the ledger on every page load, or read the
   summary table refreshed hourly by ev_refresh_summary. */

SELECT '--- live aggregation over the ledger ---' AS step;
ANALYZE
SELECT teacher_id, SUM(status='Present') AS present, SUM(status='Absent') AS absent
FROM attendance
WHERE session_date BETWEEN '2026-05-04' AND '2026-08-18'
GROUP BY teacher_id;

SELECT '--- the same figures from the materialised summary ---' AS step;
ANALYZE
SELECT teacher_id, SUM(present_count) AS present, SUM(absent_count) AS absent
FROM attendance_daily_summary
WHERE summary_date BETWEEN '2026-05-04' AND '2026-08-18'
GROUP BY teacher_id;
/* The trade-off: the summary is one refresh interval stale. That is
   acceptable for a monthly trend chart and NOT acceptable for the live
   unstaffed-classroom alert, which is why v_unstaffed_now reads the ledger
   directly. Choosing per screen rather than globally is the point. */

SELECT '########## Q8: PARTITION PRUNING ##########' AS demonstration;
/* attendance_archive is RANGE partitioned by YEAR(session_date). A query
   confined to one year should touch exactly one partition. */
SELECT '--- partitions actually read ---' AS step;
EXPLAIN PARTITIONS
SELECT COUNT(*) FROM attendance_archive
WHERE session_date BETWEEN '2025-01-01' AND '2025-12-31';
/* EXPECTED: the partitions column names p2025 alone. Without pruning the
   engine would scan every partition to find rows that provably cannot be
   there. */

SELECT '########## Q9: OPTIMISER TRACE - WHY THIS PLAN? ##########' AS demonstration;
/* EXPLAIN says what was chosen. The trace says what was considered and
   rejected, with the cost of each alternative. */
SET optimizer_trace = 'enabled=on';

SELECT COUNT(*) FROM attendance a
JOIN timetable tt ON tt.timetable_id = a.timetable_id
WHERE a.session_date = '2026-08-18' AND a.status = 'Absent';

SELECT '--- considered access paths and their costs ---' AS step;
SELECT LEFT(TRACE, 3500) AS optimizer_trace_extract
FROM information_schema.OPTIMIZER_TRACE;

SET optimizer_trace = 'enabled=off';

SELECT '########## Q10: STATISTICS AND SELECTIVITY ##########' AS demonstration;
/* The optimiser's row estimates come from these. When they are wrong, every
   downstream decision is wrong. */

SELECT '--- index cardinality ---' AS step;
SELECT TABLE_NAME, INDEX_NAME, index_columns, cardinality
FROM v_index_inventory
WHERE TABLE_NAME IN ('attendance','qr_code','timetable')
ORDER BY TABLE_NAME, cardinality DESC;

SELECT '--- engine-independent column statistics, incl. histograms ---' AS step;
SELECT db_name, table_name, column_name, min_value, max_value,
       nulls_ratio, avg_frequency, hist_size, hist_type
FROM mysql.column_stats
WHERE db_name = 'scas_db' AND table_name = 'attendance';

SELECT '--- why the histogram matters: status is very unevenly distributed ---' AS step;
SELECT status, COUNT(*) AS rows_with_value,
       ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS pct_of_table
FROM attendance GROUP BY status ORDER BY rows_with_value DESC;
/* Without a histogram the optimiser assumes each of the four status values
   covers 25% of the table. The real distribution is roughly 76/12/11/1, so
   status='Excused' is far more selective than the flat assumption implies and
   status='Present' far less. The histogram is what lets it tell the
   difference, and therefore what lets it decide whether the status index is
   worth using at all. */

SELECT '--- redundant index check (should be empty) ---' AS step;
SELECT * FROM v_redundant_indexes;

SELECT '11 complete - query processing and evaluation' AS status;
