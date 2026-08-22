# SCAS — Backup and Recovery

Companion to [`database/08_transactions_recovery.sql`](../database/08_transactions_recovery.sql),
[`tools/backup.bat`](../tools/backup.bat) and [`tools/restore.bat`](../tools/restore.bat).

---

## 1. What is protected, and what is not

| Failure | Covered by | Recovery point | Recovery time |
|---------|-----------|----------------|---------------|
| Transaction fails mid-way | InnoDB rollback + procedure handlers | instant | instant |
| Process or power loss | InnoDB redo log, crash recovery on restart | last committed transaction | seconds |
| Wrong value in a setting | `system_setting` temporal table | any past instant | one query |
| A bad approval or correction | Compensating procedure + `audit_log` | the specific row | one call |
| Table dropped, data corrupted | `mysqldump` logical backup | **last backup** | minutes |
| Disk or machine lost | Backup file held off the machine | last off-machine copy | minutes to hours |
| Any of the above, to a chosen second | Binary log replay | **not available — see §5** | — |

The honest summary: **recovery granularity today is the last backup.** Binary
logging is off, as XAMPP ships it, so there is no way to replay the interval
between the last backup and a failure. Section 5 is the fix, and it takes about
five minutes.

---

## 2. Taking a backup

```bash
D:\SCAS\tools\backup.bat
```

The flags are chosen, not copied:

**`--single-transaction`** takes the dump inside one consistent InnoDB snapshot.
Without it, `mysqldump` locks every table for the duration and the school cannot
check in while the backup runs. With it, a teacher scanning a code at 02:00
succeeds, and the dump still sees one coherent instant.

**`--routines --triggers --events`** because in this system the business rules
*are* database objects. A dump with the tables but not the triggers restores a
database in which a teacher can sign in for a colleague — the data would be
intact and the rules gone. This is the flag most often forgotten, and here it
would be the most damaging.

**`--master-data=2`** records the binary-log coordinates in the dump as a
comment. Those coordinates are where a point-in-time replay begins. The script
adds this flag only when binary logging is on, and says which case applies.

The script then verifies the artefact rather than trusting the exit code, since
redirection hides it: the file must exceed 10 KB and must contain
`CREATE TABLE \`attendance\``. A dump that exists but is empty is the classic
silent backup failure. Success and failure are both recorded in `backup_log`,
which drives the Recovery tab of the DBA console.

---

## 3. Restoring — and the drill

```bash
D:\SCAS\tools\restore.bat ..\backups\scas_db_20260819_050144.sql
```

The script takes a **pre-restore snapshot before touching anything**. Restoring
the wrong file is one of the commonest ways a small incident becomes a large
one, and the snapshot makes that mistake reversible.

It then drops and recreates the schema, loads the dump, and **verifies**:
`sp_run_integrity_check()` must report **0 violations on all 7 rules**, and the
row counts are printed for a sanity check.

This drill has been run against this system. Result:

```
| Attendance rows whose session_date disagrees with its QR code |  0 |
| Attendance rows whose teacher does not own the session        |  0 |
| Scanned rows with no QR code                                  |  0 |
| QR codes whose scan_count exceeds max_scans                   |  0 |
| Teachers with no user account (orphans)                       |  0 |
| Approved leave still counted as Absent                        |  0 |
| Active sessions outside the current term                      |  0 |

attendance_rows 1093    users 20
triggers 26   procedures 42   events 4
```

The application reconnected and served pages immediately afterwards. **A backup
that has never been restored is a hope, not a backup** — the point of the drill
is that this one is now neither.

### The trap the script warns about

Database users and grants live in the `mysql` system database, **not** in a
`scas_db` dump. Restore onto a rebuilt server and the schema returns while
`scas_app` does not exist — the application cannot connect, and the failure looks
like a broken restore rather than a missing account. Re-run
`database/07_security_authorization.sql` to recreate roles and accounts.

---

## 4. Recovering without a backup

Two mechanisms handle the common cases without a restore at all.

**A changed setting.** `system_setting` is system-versioned, so every superseded
value is still there:

```sql
-- what was the lateness threshold before someone changed it?
SELECT setting_key, setting_value, row_start, row_end
FROM   system_setting FOR SYSTEM_TIME ALL
WHERE  setting_key = 'late_threshold_minutes'
ORDER  BY row_start;

-- the whole configuration as it stood that morning
SELECT * FROM system_setting
FOR SYSTEM_TIME AS OF TIMESTAMP '2026-08-01 08:00:00';
```

No backup file, no downtime, and it answers *when* it changed as well as *what*
it was.

**A wrong attendance decision.** The evidence columns are frozen by
`trg_attendance_bu`, so nothing can rewrite who was present or when. The verdict
is correctable: `sp_action_leave_request` reclassifies `Absent` rows to
`Excused` across the leave period inside a `SAVEPOINT`, so a failure in that
step cannot leave the approval half-applied. Every status change is written to
`audit_log` by `trg_attendance_au`, giving the before value, the after value and
the user responsible. Deletes are refused outright.

That means "undo" here is always a forward correction with a trace, never an
erasure — which is the property you actually want when the register is evidence
in a payroll or disciplinary dispute.

---

## 5. Enabling point-in-time recovery

This is the one material gap, and closing it is straightforward.

1. Stop MySQL in the XAMPP Control Panel.
2. Edit `C:\xampp\mysql\bin\my.ini`, and under `[mysqld]` add:

   ```ini
   log_bin                 = mysql-bin
   binlog_format           = ROW
   expire_logs_days        = 14
   sync_binlog             = 1
   innodb_flush_log_at_trx_commit = 1
   ```

3. Start MySQL. Confirm with `SELECT @@log_bin;` — it must return `1`.
4. Take a fresh backup. `backup.bat` will now add `--master-data=2` on its own
   and say so.

`ROW` format is the right choice here because the system is full of triggers and
procedures; `STATEMENT` format replays the *call* and can produce a different
result on replay, which is precisely the failure mode you cannot afford during a
recovery.

Recovery then becomes: restore the last full backup, then replay the binary log
from the recorded coordinate up to the instant before the damage:

```bash
C:\xampp\mysql\bin\mysqlbinlog.exe ^
    --start-position=<position from the dump header> ^
    --stop-datetime="2026-08-19 14:29:00" ^
    C:\xampp\mysql\data\mysql-bin.000007 | C:\xampp\mysql\bin\mysql.exe -u root scas_db
```

`--stop-datetime` is what turns "we lost today" into "we lost the ninety seconds
before someone ran the wrong statement".

---

## 6. What a real deployment still needs

- **Off-machine copies.** Backups currently sit in `D:\SCAS\backups`, on the same
  disk as the database. A disk failure takes both. Copy them elsewhere.
- **A schedule.** `backup.bat` is run by hand. Windows Task Scheduler, nightly.
- **Retention.** Nothing prunes old dumps; they accumulate.
- **A periodic drill.** The restore has been proven once. It should be proven on
  a schedule, because backups fail silently and the discovery should not happen
  during an incident.
