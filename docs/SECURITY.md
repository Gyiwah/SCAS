# SCAS — Security and Authorization

Companion to [`database/07_security_authorization.sql`](../database/07_security_authorization.sql).

The threat this system is actually built against is not an anonymous attacker on
the internet. It is **an insider with a legitimate account** — a teacher who
wants a colleague to sign them in, or who wants last Tuesday to look different.
Every design choice below follows from that.

---

## 1. Five layers

| Layer | Mechanism | Answers |
|-------|-----------|---------|
| Authentication | bcrypt (`PASSWORD_DEFAULT`, cost 10), lockout after 5 failures for 15 minutes | Who are you? |
| Authorization | MariaDB roles, per-purpose accounts, procedure-only writes | What may you invoke? |
| Row-level | Security views keyed on `SESSION_USER()` / application context | Which rows may you see? |
| Integrity | 22 CHECKs, 19 FKs, 26 triggers | Is this state even legal? |
| Accountability | `audit_log` and `security_event`, append-only by privilege | What happened, and who did it? |

No single layer is trusted alone. The application checks role before rendering a
page; the procedure checks role again before acting; the trigger checks the facts
regardless of who is asking. A bug in the first two is contained by the third.

---

## 2. Accounts and roles

Five roles, five accounts, each with the narrowest grant that lets it do its job:

```
scas_app_role       EXECUTE on procedures + SELECT on views.  One write grant:
                    notification.is_read.  Cannot read password_hash.
scas_readonly_role  SELECT on reporting views only.  MAX_UPDATES_PER_HOUR 0 —
                    a hard stop at the server, not a promise in the grant table.
scas_auditor_role   audit_log, security_event and the audit views.  Explicitly
                    NOT granted password_hash or teacher_sensitive: an auditor
                    needs to see that a change happened, not the personal data
                    inside it.
scas_backup_role    SELECT, LOCK TABLES, SHOW VIEW, EVENT, TRIGGER — exactly
                    what mysqldump requires and nothing more.
scas_dba_role       ALL PRIVILEGES on scas_db.*, and nothing on *.*.  A DBA for
                    this database is not an administrator of the server.
```

Resource limits are part of the security posture, not an afterthought:
`MAX_USER_CONNECTIONS` caps a runaway report from exhausting the connection
pool, and `MAX_UPDATES_PER_HOUR 0` on the reporting account means a compromised
BI credential cannot write even if every other control failed.

---

## 3. Why the application cannot write

This is the decision the whole design rests on, so it is worth stating the
alternative. The conventional arrangement gives the web application
`INSERT, UPDATE, DELETE` on the tables and enforces the rules in PHP. Under that
arrangement, one SQL-injection flaw, one missed authorization check, or one
developer running an ad-hoc `UPDATE` is enough to rewrite the attendance record —
and nothing in the database would object, because the database was never told
what the rules were.

Here, `scas_app` can invoke `sp_record_attendance` and 41 other named
procedures. That is its entire vocabulary. An attacker holding the application's
credentials in full can do exactly what the application can do — no more. They
cannot:

- write an attendance row that no QR scan produced (no INSERT on `attendance`)
- change who was present, when, or under which code (no UPDATE grant, and
  `trg_attendance_bu` rejects those columns for every account including `root`)
- delete the evidence (no DELETE grant, and `trg_attendance_bd` rejects it)
- read a password hash (not in the column grants)
- read a Ghana Card number in the clear (encrypted, key not in the database)

The cost is real and worth naming: 42 procedures is more code than 42 inline
queries, and adding a feature means adding a procedure rather than a line of PHP.
That cost buys a system where the security properties are provable from
`SHOW GRANTS` rather than by reading every line of the application.

---

## 4. Row-level security

A headteacher must see their own school and no other. Rather than appending
`AND school_id = ?` to every query and hoping none is ever forgotten, the
filtering lives in views:

```sql
CREATE VIEW v_my_school_attendance AS
SELECT ...
FROM   attendance a
JOIN   teacher t ON t.teacher_id = a.teacher_id
WHERE  t.school_id = fn_current_school_id();
```

The application is granted the **view**, never the base table, for these paths.
A forgotten predicate is then not a data leak, because the predicate is not the
application's responsibility. `v_my_attendance` does the same for a teacher's own
rows, and `v_teacher_directory` exposes staff contact details with the encrypted
columns absent rather than merely unselected.

---

## 5. Encryption at rest

`teacher_sensitive` holds Ghana Card number, bank account and next-of-kin
details under `AES_ENCRYPT` with a 256-bit key. Two properties matter:

**The key is not in the database.** It is supplied per-session from application
configuration. A stolen `mysqldump` file therefore yields ciphertext. Storing
the key in a table beside the ciphertext — a common shortcut — would make the
encryption decorative.

**The plaintext has no view.** Decryption happens only inside
`sp_read_sensitive`, which checks the caller's role first and writes an
`audit_log` row before returning. Reading a bank account is an auditable event,
not an ordinary `SELECT`.

Passwords are not in this scheme, because passwords must not be decryptable at
all: they are bcrypt hashes, verified by `password_verify()`, never compared in
SQL.

---

## 6. Accountability

`audit_log` is written by triggers on every table that matters, recording the
table, row, old values, new values, database user, application user and
timestamp.

It is append-only **by privilege**: no account in the system is granted
`UPDATE` or `DELETE` on it. The application holds `SELECT` and nothing else, so
no route through the web tier can alter the trail. Precision matters here —
this is a grant, not a trigger, so `scas_dba` and `root` *can* still modify it.
Making it immutable even to the DBA requires the binary log (§8) or shipping
the trail to a separate server; both are noted as gaps rather than claimed as
present.

The ledger itself has stronger protection, enforced by triggers that apply to
every account including `root`:

- `trg_attendance_bu` rejects any change to `teacher_id`, `timetable_id`,
  `session_date`, `scan_datetime` or `qr_code_id`. Only `status`, `minutes_late`
  and `remarks` may be corrected — which is exactly what an approved leave needs
  in order to reclassify an `Absent` row to `Excused`.
- `trg_attendance_au` writes every such correction to `audit_log`, so the verdict
  can change but the change cannot be silent.
- `trg_attendance_bd` refuses deletes outright. The single exception is
  `sp_archive_old_attendance`, which sets a session variable only after it has
  proved the rows are already in `attendance_archive`. Nothing else in the system
  sets that variable.

`security_event` records sign-ins and failures, lockouts, permission denials, and
every rejected QR scan with its reason. The rejected scans are the interesting
ones operationally — a teacher repeatedly scanning an expired code is usually a
timetable problem, while a teacher scanning a colleague's code is not.

---

## 7. Application-layer controls

The database is the last line, not the only one. In `app/`:

- **Every statement is a prepared statement.** No string concatenation reaches
  SQL anywhere in the application.
- **CSRF tokens** on every state-changing form, verified centrally in
  `index.php` before any page code runs, so a new page cannot forget.
- **Output escaping** through a single `h()` helper; the templates never echo a
  raw variable.
- **Session hardening**: `httponly`, `samesite=Strict`, regeneration on
  privilege change, idle timeout.
- **Authorization checked in the front controller**, by page and by role, before
  the page is included — and then again in the procedure.

---

## 8. Known gaps

Stated plainly, because a security document that claims completeness is not
credible:

- **The XAMPP `root` account has no password.** Acceptable on an isolated
  development machine, nowhere else. It was left alone deliberately: this
  machine hosts other project databases, and changing it would break them. The
  hardening steps are in `07_security_authorization.sql`, Part 7.
- **The encryption key lives in `config.php`**, so it is protected only by the
  file system. A production deployment should take it from an environment
  variable or a key management service.
- **Transport is plain HTTP** on localhost. Anything beyond a single machine
  needs TLS, or the session cookie and every password crosses the network in the
  clear.
- **No rate limiting on QR scanning.** Lockout covers sign-in, but a valid user
  can scan as fast as they like. Single-use enforcement makes this mostly moot;
  a per-teacher throttle would still be an improvement.
- **`log_bin` is off**, so the audit trail is the only record of *when* something
  changed. Enabling it (see [RECOVERY.md](RECOVERY.md)) also gives a
  server-level, independently verifiable record.

### The REST API (`app/api/`)

The mobile API is a separate front door onto the same database, so it inherits
the procedure-only design — but it has its own exposures:

- **`Access-Control-Allow-Origin: *`** on every response. Because the API
  authenticates with a bearer token rather than a cookie, this is not a CSRF
  hole: a browser will not attach the token automatically. It does, however, let
  any web page call `login.php` from a visitor's browser and read the reply,
  which turns the API into a credential-testing oracle from arbitrary origins.
  The database lockout still applies per account. A deployment should name the
  permitted origins explicitly rather than using `*`.
- **The JWT secret is a project default** in `config.php`, and it signs every
  token. Anyone who reads that file can mint a valid token for any user, which
  makes it equivalent to a master password. It must be changed and moved out of
  version-controlled configuration.
- **Tokens last 7 days and cannot be revoked.** Deactivating an account stops
  new sign-ins but does not invalidate a token already issued, so a compromised
  token stays valid until it expires. Short-lived tokens with a refresh step, or
  a server-side blocklist, would close the gap.
- **Plain HTTP.** The token is sent in a header on every request, so without TLS
  it is readable by anyone on the same network.
