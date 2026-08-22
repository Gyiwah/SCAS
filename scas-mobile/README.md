# SCAS Mobile

React Native (Expo) app for teachers: see today's sessions, scan the classroom
QR code to check in, and review your own attendance history.

It talks to the PHP REST API in [`../app/api/`](../app/api), which in turn calls
the same MariaDB stored procedures the web application uses. **No attendance
rule is implemented in this app.** Whether a scan counts — is the code expired,
revoked, already used, does it belong to this teacher — is decided by
`sp_record_attendance` in the database. The app reads a code and reports the
answer.

---

## Setup

### 1. The backend must be reachable from the phone

This is the step that usually goes wrong, so do it first.

Apache and MySQL must be running in XAMPP, and `app/` must be served at
`/scas` (see the root [README](../README.md) for the directory junction).

The app cannot use `localhost` — on a phone that means the phone itself. Find
your PC's LAN address:

```bash
ipconfig
```

Take the **IPv4 Address** of your Wi-Fi adapter and put it in
[`src/config.ts`](src/config.ts):

```ts
export const API_BASE_URL = 'http://10.135.198.183/scas/api';
```

Then confirm from the **phone's browser** that this URL answers:

```
http://<your-ip>/scas/api/timetable.php
```

A `401` with `"Missing or invalid Authorization header"` is the **correct**
response — it proves the phone can reach the API. A timeout means the phone and
PC are not on the same network, or Windows Firewall is blocking Apache.

> If it times out, allow Apache through the firewall for **private networks**:
> Windows Security → Firewall & network protection → Allow an app → `httpd.exe`.

### 2. Install and run

```bash
npm install
```

```bash
npx expo start
```

Scan the Expo QR code with **Expo Go** (Android) or the Camera app (iOS). The
phone must be on the same Wi-Fi as the PC.

### 3. Sign in

Any teacher account from the seed data, for example:

| Username | Password |
|----------|----------|
| `k.mensah` | `Teach@2026` |
| `a.boateng` | `Teach@2026` |

Five failed attempts lock the account for 15 minutes — that rule lives in the
database, so it applies here exactly as it does on the web.

---

## Using it

**Today** — your sessions for today, each showing whether it is `Upcoming`,
`In Progress` or `Ended`, and whether you have checked in. Pull down to refresh.

**Scan** — the camera scanner. Point it at the QR code displayed for your class.
The screen is live only while the tab is focused, so it does not hold the camera
open in the background.

**History** — your attendance rate and recent sessions. The counts come from
your row-level-security view, so they match what the headteacher's report shows.

### Generating a code to test against

Sign in to the web app as a headteacher (`head.winneba` / `Head@2026`) and open
**QR Codes**:

```
http://localhost/scas/index.php?page=qrcodes
```

Generate codes for today, click one to display it, and scan it with the app.

Each code is single-use, so a second scan of the same code is refused — that is
the system working, not a bug.

---

## Structure

```
scas-mobile/
├── App.tsx                     providers + navigator
├── app.json                    Expo config, camera permission strings
└── src/
    ├── config.ts               API base URL and storage keys
    ├── theme.ts                colours, spacing, type; status colour mapping
    ├── api/client.ts           axios instance, JWT interceptor, API types
    ├── context/AuthContext.tsx sign in/out, token in SecureStore
    ├── navigation/RootNavigator.tsx
    ├── components/ui.tsx       Card, Badge, Button, EmptyState, ErrorBanner
    └── screens/
        ├── LoginScreen.tsx
        ├── TimetableScreen.tsx
        ├── ScanQrScreen.tsx
        └── HistoryScreen.tsx
```

---

## Notes on a few decisions

**The token lives in `expo-secure-store`, not AsyncStorage.** A JWT is a bearer
credential: whoever holds it can check in as that teacher until it expires. It
belongs in the keychain/keystore, with the passwords.

**The scanner latches after the first detection.** `CameraView` fires
`onBarcodeScanned` many times a second while a code is in frame. Without a latch
one physical scan would fire a burst of check-ins; the database would reject the
duplicates as reused codes, and the teacher would see "already used" for their
own first scan. The latch clears when they tap *Scan next code*.

**Any 401 signs the user out.** Rather than leaving them tapping a screen that
will never load, the session is cleared and the login screen explains why.

**Errors show the database's own words.** When a scan is refused, the message
the teacher sees ("This code has already been used.") comes from
`sp_record_attendance`. Axios's default "Request failed with status code 400"
would tell them nothing.

---

## Limitations

- **Plain HTTP.** Fine on a lab network; anything wider needs TLS, or the token
  crosses the network in the clear. `expo-build-properties` is configured with
  `usesCleartextTraffic` so Android standalone builds permit it — that setting
  should be removed once the API is served over HTTPS.
- **The JWT secret is a project default** in `app/config/config.php` and must be
  changed before any real deployment.
- **Tokens last 7 days and cannot be revoked** server-side. Deactivating a user
  stops new sign-ins but does not invalidate a token already issued. A token
  blocklist, or short-lived tokens with refresh, would close that.
- **No offline queue.** A scan made with no connectivity is lost rather than
  retried. Given codes expire within the session window, queueing would need
  care to avoid recording a check-in after the fact.
