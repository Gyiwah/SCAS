# SCAS Mobile Application & REST API Implementation Plan

This plan details the step-by-step process to build a **REST API** backend in PHP (consuming existing SCAS MariaDB stored procedures and views) and a **React Native (Expo)** mobile application featuring a real-time QR code camera scanner for teacher attendance check-in.

---

## Technical Overview

```
┌────────────────────────────────┐         HTTPS JSON          ┌────────────────────────────────┐
│   React Native (Expo) App      │ ◄─────────────────────────► │      PHP REST API Layer        │
│   • Camera Scanner (expo-camera)│   Authorization: Bearer     │      (app/api/*.php)           │
│   • Auth State (SecureStore)   │                             │  • JWT Auth & Token Verification│
│   • Timetable & Attendance UI  │                             └───────────────┬────────────────┘
└────────────────────────────────┘                                             │ PDO (Session Context)
                                                                               ▼
                                                               ┌────────────────────────────────┐
                                                               │  MariaDB Database (scas_db)     │
                                                               │  • sp_authenticate_*           │
                                                               │  • sp_record_attendance        │
                                                               │  • RLS Views (v_my_timetable) │
                                                               └────────────────────────────────┘
```

---

## User Review Required

> [!IMPORTANT]
> **Database Grants & API Security**: The PHP application user (`scas_app`) executes procedures and queries views. All API endpoints will maintain this design by issuing `Database::get()->setSessionContext($userId, $schoolId, $privilege)` on every request before calling stored procedures or views.

> [!NOTE]
> **Mobile App Setup**: The mobile application will be built inside a new directory `scas-mobile` using **Expo SDK 51+** (TypeScript) with `expo-camera` for QR scanning and `expo-secure-store` for token storage.

---

## Proposed Implementation Steps

### Phase 1: PHP REST API Backend (`app/api/`)

#### 1. [NEW] [`app/api/jwt.php`](file:///d:/SCAS/app/api/jwt.php)
- Implement lightweight JWT / HMAC SHA-256 token helper (encode/decode) using a secret key defined in [`app/config/config.php`](file:///d:/SCAS/app/config/config.php).
- Provide middleware function `requireApiAuth()` that parses `Authorization: Bearer <token>`, verifies signature/expiration, sets `Database::get()->setSessionContext()`, and returns user payload (`user_id`, `school_id`, `privilege`, `role_name`).

#### 2. [NEW] [`app/api/login.php`](file:///d:/SCAS/app/api/login.php)
- **Method**: `POST`
- **Payload**: `{ "username": "...", "password": "..." }`
- **Execution Flow**:
  1. Call stored procedure `sp_authenticate_start(username, client_ip, ...)` to retrieve `user_id`, `password_hash`, and lockout `state`.
  2. If locked/inactive/not_found, return HTTP 401 with descriptive JSON error.
  3. Verify password via `password_verify($password, $hash)`.
  4. On failure: call `sp_authenticate_failure(username, client_ip)` and return HTTP 401.
  5. On success: call `sp_authenticate_success(user_id, client_ip)`, fetch teacher/school details, issue JWT token, and return JSON payload.

#### 3. [NEW] [`app/api/checkin.php`](file:///d:/SCAS/app/api/checkin.php)
- **Method**: `POST` (Requires API Auth)
- **Payload**: `{ "code": "32_CHAR_HEX_OR_URL" }`
- **Execution Flow**:
  1. Parse `code` (extract `code` query parameter if raw scan string is a full URL).
  2. Call stored procedure `sp_record_attendance(user_id, code, ip, user_agent)`.
  3. Return result JSON:
     ```json
     {
       "status": "success",
       "data": {
         "result": "OK",
         "attendance_status": "Present",
         "message": "Checked in successfully"
       }
     }
     ```

#### 4. [NEW] [`app/api/timetable.php`](file:///d:/SCAS/app/api/timetable.php)
- **Method**: `GET` (Requires API Auth)
- **Execution Flow**:
  1. Query `v_my_timetable` for the current teacher for today's date.
  2. Return JSON list of sessions with subject, room, start/end times, and current session state (`Upcoming`, `In Progress`, `Ended`).

#### 5. [NEW] [`app/api/attendance.php`](file:///d:/SCAS/app/api/attendance.php)
- **Method**: `GET` (Requires API Auth)
- **Execution Flow**:
  1. Fetch recent attendance logs and summary counts (`Present`, `Late`, `Excused`, `Absent`) for the logged-in teacher.

---

### Phase 2: React Native / Expo Mobile Application (`scas-mobile/`)

#### 1. Project Initialization & Dependencies
- Create Expo app: `npx create-expo-app@latest scas-mobile --template blank-typescript`
- Install dependencies:
  - Navigation: `@react-navigation/native`, `@react-navigation/bottom-tabs`, `@react-navigation/native-stack`
  - Camera & Haptics: `expo-camera`, `expo-haptics`
  - Storage & Utilities: `expo-secure-store`, `axios`
  - Icons & Styling: `@expo/vector-icons`, `react-native-safe-area-context`

#### 2. App Structure (`scas-mobile/src/`)
```
scas-mobile/src/
├── api/                  # Axios HTTP client with JWT interceptor
│   └── client.ts
├── context/              # AuthContext (login, logout, token state)
│   └── AuthContext.tsx
├── navigation/           # Tab & Stack Navigation
│   └── RootNavigator.tsx
├── screens/
│   ├── LoginScreen.tsx   # Sign in form with validation
│   ├── TimetableScreen.tsx # Today's sessions & live indicators
│   ├── ScanQrScreen.tsx  # Camera scanner & overlay UI
│   └── HistoryScreen.tsx # Attendance history & status badges
└── components/           # Reusable cards, buttons, badges
```

#### 3. Core Screens & Logic Details

##### `ScanQrScreen.tsx` (Camera & QR Scanner Feature)
- Utilize `CameraView` from `expo-camera`:
  ```tsx
  <CameraView
    style={StyleSheet.absoluteFillObject}
    facing="back"
    barcodeScannerSettings={{ barcodeTypes: ["qr"] }}
    onBarcodeScanned={scanned ? undefined : handleBarCodeScanned}
  />
  ```
- **Handling Scanned Data**:
  1. Trigger immediate haptic feedback (`Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success)`).
  2. Send barcode data string to `POST /api/checkin.php`.
  3. Display animated visual alert card on screen with DB response message.
  4. Provide a "Scan Next Code" reset button.

##### `AuthContext.tsx`
- Persist JWT token using `expo-secure-store`.
- Automatically attach `Authorization: Bearer <token>` header to all Axios API requests.
- Handle session expiration and auto-logout on HTTP 401.

##### `TimetableScreen.tsx`
- Pull-to-refresh control for today's timetable.
- Visual badges for session state: `In Progress` (Green pulsing dot), `Upcoming` (Blue), `Ended` (Gray).

---

## Verification & Testing Plan

### 1. API Verification (Backend)
- Execute cURL / HTTP tests against local Apache server (`http://localhost/scas/api/`):
  - **Auth Test**: Post valid credentials (`k.mensah` / `Teach@2026`) -> Verify JWT token return.
  - **Lockout Test**: Send 5 invalid logins -> Verify HTTP 401 account locked status.
  - **Check-in Test**: Post valid QR code to `/api/checkin.php` -> Verify attendance record in MariaDB via `12_verification_tests.sql`.

### 2. Mobile App Verification (Expo)
- **Camera Permission**: Test requesting and granting camera access on physical Android & iOS devices via Expo Go.
- **QR Scanner Speed**: Scan live QR codes generated on the web frontend (`http://localhost/scas/index.php?page=codes`).
- **Network Resilience**: Test error handling when backend server is unreachable or when scanning expired/invalid QR codes.
