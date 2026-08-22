<?php
/**
 * SCAS - Smart Classroom Attendance System
 * Application configuration.
 *
 * The credentials below are for the least-privilege application account
 * created by database/07_security_authorization.sql. That account cannot
 * INSERT, UPDATE or DELETE any business table directly; it can only execute
 * the stored procedures and read the views. Even if this file leaked, the
 * holder could not drop a table or rewrite an attendance record.
 */

declare(strict_types=1);

// ---------------------------------------------------------------------------
// Database connection
// ---------------------------------------------------------------------------
const DB_HOST = '127.0.0.1';
const DB_PORT = 3306;
const DB_NAME = 'scas_db';
const DB_USER = 'scas_app';
const DB_PASS = 'Scas#App2026!';
const DB_CHARSET = 'utf8mb4';

// ---------------------------------------------------------------------------
// Encryption key for sensitive personal data (national ID, bank account).
// Deliberately held HERE and not in the database: storing the key beside the
// ciphertext would mean anyone who can read the data can also read the key.
// Change this before any real deployment.
// ---------------------------------------------------------------------------
const SENSITIVE_DATA_KEY = 'scas-pilot-key-change-me-2026';
const JWT_SECRET         = 'scas-api-jwt-secret-key-change-in-prod-2026';

// ---------------------------------------------------------------------------
// Application
// ---------------------------------------------------------------------------
const APP_NAME     = 'Smart Classroom Attendance System';
const APP_SHORT    = 'SCAS';
const APP_BASE_URL = '/scas/';
const APP_VERSION  = '1.0';

// Idle session timeout in seconds. Mirrors system_setting
// 'security.session_timeout_minutes'; the database value wins when reachable.
const SESSION_IDLE_TIMEOUT = 1800;

// Statements slower than this (milliseconds) are written to
// query_performance_log for the DBA console. Mirrors 'report.slow_query_ms'.
const SLOW_QUERY_MS = 200;

// Privilege levels, matching user_role.privilege_level in the database.
const PRIV_TEACHER      = 10;
const PRIV_HEADTEACHER  = 50;
const PRIV_SCHOOL_ADMIN = 90;
const PRIV_SYS_ADMIN    = 99;

// Show database error detail on screen. MUST be false outside development:
// error text can disclose schema structure to an attacker.
const DEBUG_ERRORS = true;

date_default_timezone_set('Africa/Accra');
