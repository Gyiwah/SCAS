# SCAS — Requirement to Implementation Map

Where each required advanced DBMS feature lives, and how to see it working.
Object counts are as installed: **20 tables, 21 views, 14 functions,
42 procedures, 26 triggers, 4 events, 22 CHECKs, 19 FKs, 17 uniques.**

---

## (a) Query Processing and Evaluation

**Files:** [`02_indexes_and_optimization.sql`](../database/02_indexes_and_optimization.sql),
[`11_query_processing_evaluation.sql`](../database/11_query_processing_evaluation.sql)
**In the app:** DBA Console → *Query Plans* tab (live `EXPLAIN` runner)

| Technique | Where | What it shows |
|-----------|-------|---------------|
| `EXPLAIN` | `11`, §1 | Chosen access path, key, rows |
| `EXPLAIN FORMAT=JSON` | `11`, §2 | Cost numbers behind the choice |
| `EXPLAIN PARTITIONS` | `11`, §6 | Partition pruning actually happening |
| `ANALYZE` | `11`, §3 | Estimated vs **actual** rows — where the optimiser was wrong |
| `optimizer_trace` | `11`, §4 | Plans considered **and rejected**, with costs |
| Histograms | `02`, §7 | `histogram_size=254` on skewed columns |
| Engine-independent stats | `02`, §7 | `ANALYZE TABLE ... PERSISTENT FOR ALL` |
| Covering index | `02`, §2 | `Using index` — table never touched |
| Composite ordering | `02`, §2 | Equality → range → covered columns |
| Prefix index | `02`, §4 | Long `VARCHAR` indexed on a prefix |
| FULLTEXT | `02`, §5 | Remarks search |
| Redundant-index detection | `v_redundant_indexes` | Indexes made pointless by a wider one |
| Measured results | `query_performance_log` | Plans recorded, not just printed |

**The demonstration to look at first** — sargability, measured on the shipped
data:

| Query | Access type | Rows examined |
|-------|-------------|---------------|
| `WHERE YEAR(session_date)=2026 AND MONTH(session_date)=7` | `index` (full scan) | **1172** |
| `WHERE session_date >= '2026-07-01' AND session_date < '2026-08-01'` | `range` | **340** |

Same result, same index available. Wrapping the column in a function is what
makes it unusable. Reproduce it live in the DBA console's *Query Plans* tab —
it runs real `EXPLAIN` against whatever `SELECT` you paste, and refuses anything
that is not a `SELECT`.

There is also an index deliberately **not** created, with the reasoning written
out in `02`, §8: a second index on `attendance(teacher_id)` would be fully
covered by the existing `(teacher_id, session_date)` and would only add write
cost.

---

## (b) Transaction Management and Recovery

**Files:** [`05_stored_procedures.sql`](../database/05_stored_procedures.sql),
[`08_transactions_recovery.sql`](../database/08_transactions_recovery.sql)
**In the app:** DBA Console → *Transactions* and *Recovery* tabs
**Docs:** [RECOVERY.md](RECOVERY.md)

| Property / technique | Where | Demonstration |
|---------------------|-------|---------------|
| **A**tomicity | `sp_demo_savepoint` | 2 inserts commit, a third is rolled back to a `SAVEPOINT` |
| **C**onsistency | `sp_demo_consistency` | A `CHECK` violation rolls back the valid insert alongside it |
| **I**solation | `sp_demo_isolation_levels` | All four levels, with paired SESSION A/B scripts |
| **D**urability | `08`, §7 | `innodb_flush_log_at_trx_commit`, redo log, crash recovery |
| Error handling | every procedure | `EXIT HANDLER FOR SQLEXCEPTION` → `GET DIAGNOSTICS` → `ROLLBACK` |
| Partial rollback | `sp_action_leave_request` | `SAVEPOINT` so a failed reclassification cannot half-apply an approval |
| Pessimistic locking | `sp_record_attendance` | `SELECT ... FOR UPDATE` on the QR row — this is what makes double-scanning impossible |
| Dirty read | `08`, §3 | `READ UNCOMMITTED` reads uncommitted data; `READ COMMITTED` does not |
| Non-repeatable read | `08`, §3 | Differs between `READ COMMITTED` and `REPEATABLE READ` |
| Lost update | `08`, §4 | Prevented by `FOR UPDATE` |
| Deadlock | `08`, §5 | Provoked deliberately, then resolved by lock ordering |
| Serializable reporting | `sp_month_end_report_serializable` | `SERIALIZABLE READ ONLY` for a stable month-end figure |
| Two-phase commit | `08`, §6 | `XA START / END / PREPARE / COMMIT` |
| Lock inspection | `sp_show_locks` | Live `information_schema` lock view |
| Temporal recovery | `system_setting`, `sp_settings_as_of`, `sp_restore_setting_as_of` | Recover a configuration value from any past instant — no backup, no downtime |
| Backup | `tools/backup.bat` | `--single-transaction --routines --triggers --events`, artefact verified, logged |
| Restore | `tools/restore.bat` | Pre-restore snapshot, then integrity sweep |
| Integrity sweep | `sp_run_integrity_check` | 7 cross-table rules that must all read 0 |
| Recovery posture | `sp_recovery_report`, `backup_log` | How far back the system could actually be recovered |

**Verified, not asserted:** the restore drill has been run against a real dump —
all 7 integrity rules returned 0, 26 triggers / 42 procedures / 4 events came
back, and the application reconnected. See RECOVERY.md §3.

---

## (c) Database Security and Authorization

**File:** [`07_security_authorization.sql`](../database/07_security_authorization.sql)
**In the app:** Security Dashboard, Audit Trail, User Management
**Docs:** [SECURITY.md](SECURITY.md)

| Control | Where | Note |
|---------|-------|------|
| Roles | `07`, Part 2 | 5 roles, granted to accounts rather than to people |
| Least-privilege accounts | `07`, Part 3 | `scas_app`, `scas_readonly`, `scas_auditor`, `scas_backup`, `scas_dba` |
| **Procedure-only writes** | `07`, Part 4 | `scas_app` holds **one** write grant in the whole database: `notification.is_read` |
| Column-level grants | `07`, Part 4 | `password_hash` is not granted to the application at all |
| Row-level security | `04_views.sql` | `v_my_attendance`, `v_my_school_attendance` filter by `fn_current_school_id()` |
| Resource limits | `07`, Part 3 | `MAX_UPDATES_PER_HOUR 0` on the reporting account |
| Encryption at rest | `07`, Part 5 | AES-256 on `teacher_sensitive`; key held outside the database |
| Password storage | `app/lib/Auth.php` | bcrypt, `password_verify()`, never compared in SQL |
| Account lockout | `sp_login_failure`, `sp_authenticate_start` | 5 failures → 15 minutes, enforced in the database so it covers every route |
| Audit trail | `06_triggers.sql` | Append-only by privilege; old and new values as JSON |
| Security events | `security_event` | Sign-ins, lockouts, denials, and every rejected scan with its reason |
| SQL injection defence | `app/lib/Database.php` | Prepared statements only; no concatenation anywhere |
| CSRF | `app/index.php` | Verified centrally before any page code runs |

**Self-proving:** the installer prints the complete list of write grants held by
the application — checking `COLUMN_PRIVILEGES` as well as `TABLE_PRIVILEGES`,
since a column grant is invisible to the latter — and asserts there is exactly
one. It also asserts `password_hash` is unreachable. Both print `PASS`.

---

## (d) Stored Procedures and Triggers

**Files:** [`03_functions.sql`](../database/03_functions.sql),
[`05_stored_procedures.sql`](../database/05_stored_procedures.sql),
[`06_triggers.sql`](../database/06_triggers.sql)

### 14 functions
`fn_attendance_rate`, `fn_attendance_status`, `fn_current_privilege`,
`fn_current_school_id`, `fn_current_user_id`, `fn_generate_token`,
`fn_get_setting`, `fn_grace_minutes`, `fn_is_holiday`, `fn_is_on_leave`,
`fn_mask_phone`, `fn_minutes_late`, `fn_qr_status`, `fn_teacher_school`

### 42 procedures, by purpose

| Purpose | Procedures |
|---------|-----------|
| Attendance | `sp_record_attendance`, `sp_mark_absentees`, `sp_archive_old_attendance`, `sp_refresh_attendance_summary` |
| QR lifecycle | `sp_generate_qr_code`, `sp_revoke_qr_code`, `sp_create_timetable_session` |
| Leave | `sp_submit_leave_request`, `sp_action_leave_request` |
| Reporting | `sp_monthly_attendance_report`, `sp_teacher_attendance_summary`, `sp_month_end_report_serializable` |
| Users and auth | `sp_create_user`, `sp_authenticate_start`, `sp_login_success`, `sp_login_failure`, `sp_change_password`, `sp_unlock_account`, `sp_set_user_active` |
| Sensitive data | `sp_store_sensitive`, `sp_read_sensitive` |
| Timetable | `sp_seed_timetable`, `sp_set_timetable_active`, `sp_detect_timetable_conflicts`, `sp_transfer_teacher_sessions` |
| Settings | `sp_update_setting`, `sp_settings_as_of`, `sp_restore_setting_as_of` |
| Ops and recovery | `sp_backup_start`, `sp_backup_finish`, `sp_recovery_report`, `sp_run_integrity_check`, `sp_show_locks`, `sp_log_query_performance` |
| Demonstrations | `sp_demo_savepoint`, `sp_demo_consistency`, `sp_demo_isolation_levels` |
| Test harness | `sp_assert_equals`, `sp_assert_refused`, `sp_assert_allowed` |
| Seeding | `sp_seed_history`, `sp_seed_today` |

### 26 triggers, doing four separate jobs

Kept deliberately separate so it is always clear which one fired:

| Job | Example | Effect |
|-----|---------|--------|
| **Derivation** | `trg_attendance_bi` | Recomputes `timetable_id`, `session_date`, `status`, `minutes_late` **from the QR code**, discarding whatever the caller supplied |
| **Validation** | `trg_qr_code_bi`, `trg_timetable_bi` | Rejects illegal state that a `CHECK` cannot express |
| **Immutability** | `trg_attendance_bu`, `trg_attendance_bd` | Freezes the evidence columns; refuses deletes |
| **Audit** | `trg_attendance_au`, `trg_app_user_au`, `trg_leave_request_au` | Writes old and new values to `audit_log` |

Distribution: `attendance` 5, `app_user` 5, `leave_request` 4, `qr_code` 3,
`timetable` 3, `teacher` 2, and one each on `academic_term`, `classroom`,
`school`, `system_setting`.

**The single most important object in the system** is `trg_attendance_bi`. It
does not trust the caller: it re-derives the identity of the session and the
present/late verdict from the scanned QR code. That is what makes "sign the
register without being there" impossible through *any* route — the application,
the DBA console, or a direct `INSERT` at the command line.

### 4 scheduled events

| Event | Interval | Job |
|-------|----------|-----|
| `ev_mark_daily_absentees` | 1 day | Close the day; writes `Excused` for approved leave, `Absent` otherwise |
| `ev_refresh_summary` | 1 hour | Rebuild the materialised rollup |
| `ev_revoke_stale_codes` | 15 min | Expire codes past their window |
| `ev_purge_security_events` | 1 week | Retention on the security log |

---

## Verification

```bash
C:\xampp\mysql\bin\mysql.exe -u root -t < database\12_verification_tests.sql
```

47 assertions, 9 areas, all passing. The majority assert a **refusal** — that
the database rejects an expired code, a colleague's code, a reused code, a
deleted attendance row, an unauthorised approval. A system like this is defined
by what it will not do, so that is what the tests measure.

```
| tests_run | passed | failed | pass_rate | verdict          |
|        47 |     47 |      0 | 100.0%    | ALL TESTS PASSED |
```
