# Smart Classroom Attendance System (SCAS)

**University of Education, Winneba — MPhil (ICT) — Database Management System, ICTE825**
QR-code teacher attendance for Senior High Schools, implemented as an advanced
relational database on MariaDB (XAMPP) with a PHP application built on top of it.

---

## 1. What this is

The proposal identified four problems with paper registers in Ghanaian SHS:

| # | Problem from the proposal | How SCAS answers it |
|---|---------------------------|---------------------|
| 1 | Registers can be signed without the teacher being present | A check-in requires a QR token that is generated per session per day, expires after a set window, is single-use, and is bound to that teacher's own session. All four rules are enforced inside the database, not in the application. |
| 2 | Monthly summaries are slow and error-prone to compile | `sp_monthly_attendance_report` and the reporting views produce them instantly; a materialised summary table is refreshed hourly by a scheduled event. |
| 3 | Headteachers cannot see which classes are unstaffed right now | `v_unstaffed_now` and the Live Board page show sessions in progress with no check-in. |
| 4 | Approved leave is not distinguished from unapproved absence | Approving leave reclassifies existing `Absent` rows to `Excused` inside one transaction, and the nightly close writes `Excused` rather than `Absent` for teachers on approved leave. |

**The central design decision:** the application account (`scas_app`) holds
exactly **one write grant in the entire database** — `UPDATE (is_read)` on
`notification`, for marking a message read. It cannot INSERT, UPDATE or DELETE
anything else, and it cannot read `password_hash` at all. Every write that
matters goes through a stored procedure, and every rule is enforced by
constraints and triggers. If the PHP layer were completely compromised, the
attacker would inherit only the vocabulary of those procedures — they could not
rewrite an attendance record, delete the ledger, or read a password hash.

---

## 2. Quick start

**Prerequisites:** XAMPP with Apache and MySQL/MariaDB running.
Built and tested against **MariaDB 10.4.32** and **PHP 8.2.12**.

```bash
D:\SCAS\tools\install.bat
```

That drops and rebuilds `scas_db`, loads a full term of demonstration data, runs
the query-plan measurements and then runs the 47-test verification suite. It
takes about 20 seconds. No other database on the server is touched.

Then point Apache at the application. The `app` folder must be reachable from
`htdocs`; a directory junction avoids copying files:

```bash
cmd /c mklink /J "C:\xampp\htdocs\scas" "D:\SCAS\app"
```

Open **<http://localhost/scas/>**

### Demonstration accounts

| Role | Username | Password | Sees |
|------|----------|----------|------|
| System Administrator | `sysadmin` | `Sys@dmin2026` | Everything, including the DBA console |
| Headteacher | `head.winneba` | `Head@2026` | Winneba SHS: live board, codes, approvals, reports |
| School Administrator | `admin.winneba` | `School@2026` | Above, plus user accounts and the timetable |
| Teacher | `k.mensah` | `Teach@2026` | Own attendance, timetable, check-in, leave |

Other teachers use the same password: `a.boateng`, `y.owusu`, `e.danquah`,
`k.asante`, `am.adjei`, `kw.nyarko`, `ab.frimpong`, `em.tetteh`, `g.amoah`,
`s.quartey`, `h.appiah`.

Five failed sign-ins lock an account for 15 minutes. That is enforced by the
database, so it applies to every route in, not just the login form.

### Database accounts

| Account | Password | Purpose |
|---------|----------|---------|
| `scas_app` | `Scas#App2026!` | The application. EXECUTE on procedures + SELECT on views only. |
| `scas_readonly` | `Scas#Read2026!` | Reporting / BI. `MAX_UPDATES_PER_HOUR 0`. |
| `scas_auditor` | `Scas#Audit2026!` | Audit trail only. Cannot read `password_hash`. |
| `scas_backup` | `Scas#Backup2026!` | Exactly what `mysqldump` needs. |
| `scas_dba` | `Scas#Dba2026!` | Full control of `scas_db` only, not of the server. |

These are project defaults and are meant to be changed before any deployment
beyond the pilot.

---

## 3. Layout

```
D:\SCAS\
├── database\                   the DBMS, in dependency order
│   ├── 00_install_all.sql      master installer
│   ├── 01_schema.sql           20 tables, 19 FKs, 22 CHECKs, partitioning, temporal table
│   ├── 02_indexes_and_optimization.sql   access paths + optimiser statistics
│   ├── 03_functions.sql        14 stored functions
│   ├── 04_views.sql            21 views, including row-level security views
│   ├── 05_stored_procedures.sql          42 procedures
│   ├── 06_triggers.sql         26 triggers
│   ├── 07_security_authorization.sql     roles, accounts, grants, encryption
│   ├── 08_transactions_recovery.sql      ACID demos, isolation, recovery
│   ├── 09_events.sql           4 scheduled jobs
│   ├── 10_seed_data.sql        a full term of realistic data
│   ├── 11_query_processing_evaluation.sql  EXPLAIN / ANALYZE / optimizer trace
│   └── 12_verification_tests.sql         47 assertions
├── app\                        the PHP application (served from htdocs\scas)
│   ├── index.php               front controller: auth, RBAC, CSRF in one place
│   ├── login.php  logout.php
│   ├── config\config.php
│   ├── lib\                    Database, Auth, QrCode, Helpers
│   ├── includes\               page chrome
│   ├── pages\                  17 pages
│   ├── api\                    REST API for the mobile app (JWT, JSON)
│   └── assets\app.css
├── scas-mobile\                React Native (Expo) teacher app - see its README
├── docs\                       DESIGN, SECURITY, RECOVERY, FEATURE_MAP
├── tools\                      install.bat, backup.bat, restore.bat, qr_selftest.php
└── backups\                    written by backup.bat
```

### The REST API and the mobile app

`app/api/` exposes four JSON endpoints so the phone app can use the same
database rules as the web application. It is a thin layer: `checkin.php` calls
`sp_record_attendance` and returns whatever the database decided, so a scan is
accepted or refused for exactly the same reasons on the phone as on the web.

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `login.php` | POST | Verifies the password, returns a 7-day JWT |
| `timetable.php` | GET | Today's sessions with check-in state |
| `attendance.php` | GET | The teacher's own history and totals |
| `checkin.php` | POST | Records a scan through `sp_record_attendance` |

Authentication is a bearer JWT signed with HMAC-SHA256. Every authenticated
request re-establishes the database session context, so the row-level security
views filter for the caller exactly as they do in the web session.

[`scas-mobile/`](scas-mobile/README.md) is the Expo app: today's timetable, a
camera QR scanner, and personal attendance history. Setup and the LAN-address
step it depends on are in its own README.

---

## 4. The four required advanced features

Full detail is in [docs/FEATURE_MAP.md](docs/FEATURE_MAP.md). In summary:

### (a) Query processing and evaluation — `02` and `11`

Indexes designed from a stated workload (equality columns first, then range,
then covered columns), then **measured** rather than assumed:

- `EXPLAIN`, `EXPLAIN FORMAT=JSON`, `EXPLAIN PARTITIONS`
- `ANALYZE` — estimated versus **actual** rows, which is the diagnostic that
  matters
- `optimizer_trace` — not just the plan chosen but the alternatives rejected and
  their costs
- Engine-independent statistics and **histograms** (`histogram_size = 254`)
- Covering, composite, prefix and FULLTEXT indexes; partition pruning
- A redundant-index detector, and the reasoning for the index deliberately *not*
  created

The sargability demonstration, measured on the shipped dataset:

| Query | Access | Rows examined |
|-------|--------|---------------|
| `WHERE YEAR(session_date) = 2026 AND MONTH(...) = 7` | full index scan | **1172** |
| `WHERE session_date >= '2026-07-01' AND session_date < '2026-08-01'` | range | **340** |

Same answer, same table, one usable index. Wrapping the column in a function is
what destroys it.

### (b) Transaction management and recovery — `05` and `08`

- Explicit transactions everywhere; `EXIT HANDLER FOR SQLEXCEPTION` →
  `GET DIAGNOSTICS` → `ROLLBACK` in every procedure
- `SAVEPOINT` where part of the work is optional, so a failed notification never
  discards a recorded check-in
- `SELECT ... FOR UPDATE` on the QR row during a scan — this is what makes two
  simultaneous scans of a single-use code impossible
- All four isolation levels demonstrated, with paired SESSION A / SESSION B
  scripts for dirty read, non-repeatable read, lost update and deadlock
- `SERIALIZABLE READ ONLY` for the month-end report
- XA (two-phase commit) demonstration
- **System-versioned temporal table** for configuration: point-in-time recovery
  of a setting with no backup file and no downtime
- `mysqldump --single-transaction` backup, a pre-restore snapshot, and a
  restore verified by the integrity sweep

### (c) Database security and authorization — `07`

Five layers: authentication, authorization, row-level filtering, integrity,
accountability. Roles, per-purpose accounts, column-level grants that make
`password_hash` unreachable, resource limits, AES-256 encryption at rest for
sensitive personal data with the key held outside the database, bcrypt
passwords, account lockout, and a trigger-based audit trail that no application
account can edit.

Proof, from the installer output — the query lists every write grant the
application holds, checking column-level grants as well as table-level ones,
because a column grant is invisible to `TABLE_PRIVILEGES`:

```
--- proof: every write grant held by scas_app (expect exactly 1) ---
object_name   column_name   PRIVILEGE_TYPE
notification  is_read       UPDATE

write_privilege_verdict
PASS - only notification.is_read is writable

password_hash_verdict
PASS - password_hash is not granted to the application
```

### (d) Stored procedures and triggers — `03`, `05`, `06`

14 functions, 42 procedures, 26 triggers. Triggers do four separate jobs —
derivation, validation, immutability and audit — and are kept separate so it is
clear which one fired.

The most important is `trg_attendance_bi`: it recomputes `timetable_id`,
`session_date`, `status` and `minutes_late` from the QR code and **discards
whatever the caller supplied**. That is what makes "signing the register without
being present" impossible through any route.

---

## 5. Verification

```bash
C:\xampp\mysql\bin\mysql.exe -u root -t < database\12_verification_tests.sql
```

47 assertions across 9 areas. Most of them pass only when the database
**refuses** something — scanning an expired code, checking in for a colleague,
deleting an attendance record, approving your own leave.

```
| tests_run | passed | failed | pass_rate | verdict          |
|        47 |     47 |      0 | 100.0%    | ALL TESTS PASSED |
```

The QR encoder has its own test against constants published in ISO/IEC 18004:

```bash
C:\xampp\php\php.exe tools\qr_selftest.php     # 14 passed, 0 failed
```

---

## 6. Notes and limitations

- **Binary logging is off**, as XAMPP ships it. Point-in-time recovery therefore
  needs `log_bin` enabling in `my.ini` first — the exact steps are in
  [docs/RECOVERY.md](docs/RECOVERY.md). Until then, recovery granularity is the
  last backup. The DBA console shows this state rather than hiding it.
- **The XAMPP `root` account has no password.** That is acceptable on an
  isolated development machine and nowhere else. It was deliberately left alone
  because changing it would break the other project databases on this machine;
  the hardening checklist is in `07_security_authorization.sql`, Part 7.
- **The camera scanner** uses the browser's built-in `BarcodeDetector`, which
  Chrome and Edge support. Other browsers fall back to typing the 32-character
  code, which always works. No JavaScript QR library is bundled.
- **The QR codes should be test-scanned once** with a real phone. The encoder is
  verified against the standard's published format-information, version-
  information and Reed-Solomon constants, and the structural checks pass, but a
  scan with real optics is the only end-to-end proof.
- **Demonstration data** runs from 2026-05-04 to the current date; today is left
  deliberately partial so the live board and check-in have something to do.
