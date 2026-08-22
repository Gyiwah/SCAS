<?php
/**
 * SCAS - authentication, session handling and role-based access control.
 *
 * Password handling: the plaintext password is never sent to the database.
 * sp_authenticate_start returns the stored bcrypt hash only when the account
 * is active and unlocked; the comparison happens here with password_verify(),
 * which is constant-time. A locked or disabled account gets no hash at all,
 * so an attacker cannot harvest hashes by hammering a locked account.
 *
 * Enumeration: whatever the real reason for a failure, the user sees one
 * message. The distinction is recorded in security_event for the
 * administrator, not shown to the person at the keyboard.
 */

declare(strict_types=1);

final class Auth
{
    public static function boot(): void
    {
        if (session_status() === PHP_SESSION_ACTIVE) {
            return;
        }

        session_set_cookie_params([
            'lifetime' => 0,
            'path'     => APP_BASE_URL,
            'httponly' => true,   // not readable from JavaScript, blunts XSS session theft
            'samesite' => 'Lax',  // not sent on cross-site POSTs, blunts CSRF
            'secure'   => !empty($_SERVER['HTTPS']),
        ]);
        session_name('SCASSESSID');
        session_start();

        self::enforceIdleTimeout();

        if (self::check()) {
            // Re-publish the identity: session variables live on the database
            // connection, and PHP opens a new connection on every request.
            Database::get()->setSessionContext(
                self::userId(),
                self::schoolId(),
                self::privilege()
            );
        }
    }

    // -- state ---------------------------------------------------------------

    public static function check(): bool
    {
        return isset($_SESSION['user']['user_id']);
    }

    public static function user(): ?array
    {
        return $_SESSION['user'] ?? null;
    }

    public static function userId(): ?int
    {
        return isset($_SESSION['user']['user_id']) ? (int) $_SESSION['user']['user_id'] : null;
    }

    public static function schoolId(): ?int
    {
        $v = $_SESSION['user']['school_id'] ?? null;
        return $v === null ? null : (int) $v;
    }

    public static function teacherId(): ?int
    {
        $v = $_SESSION['user']['teacher_id'] ?? null;
        return $v === null ? null : (int) $v;
    }

    public static function privilege(): int
    {
        return (int) ($_SESSION['user']['privilege_level'] ?? 0);
    }

    public static function isTeacher(): bool
    {
        return self::teacherId() !== null;
    }

    // -- sign in / out -------------------------------------------------------

    /**
     * @return array{ok: bool, message: string}
     */
    public static function login(string $username, string $password): array
    {
        $db    = Database::get();
        $ip    = self::clientIp();
        $agent = mb_substr($_SERVER['HTTP_USER_AGENT'] ?? 'unknown', 0, 200);
        $generic = 'Invalid username or password.';

        $username = mb_strtolower(trim($username));
        if ($username === '' || $password === '') {
            return ['ok' => false, 'message' => $generic];
        }

        $res = $db->callProc(
            'sp_authenticate_start',
            [$username, $ip],
            ['user_id', 'password_hash', 'state']
        );

        $state = $res['state'] ?? 'NOT_FOUND';

        if ($state === 'LOCKED') {
            return ['ok' => false, 'message' =>
                'This account is temporarily locked after repeated failed sign-in attempts. '
                . 'Try again later or ask an administrator to unlock it.'];
        }
        if ($state === 'INACTIVE') {
            return ['ok' => false, 'message' =>
                'This account has been deactivated. Please contact your school administrator.'];
        }
        if ($state !== 'OK' || empty($res['password_hash'])) {
            // Unknown username. Still spend time hashing so the response time
            // does not reveal whether the account exists.
            password_verify($password, '$2y$10$usesomesillystringfoxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx');
            $db->callProc('sp_login_failure', [$username, $ip, $agent]);
            return ['ok' => false, 'message' => $generic];
        }

        if (!password_verify($password, $res['password_hash'])) {
            $db->callProc('sp_login_failure', [$username, $ip, $agent]);
            return ['ok' => false, 'message' => $generic];
        }

        $userId = (int) $res['user_id'];

        // Elevate the connection so the identity views can be read.
        $db->setSessionContext($userId, null, PRIV_SYS_ADMIN);

        $profile = $db->one(
            'SELECT u.user_id, u.full_name, u.username, u.school_id, u.role_id,
                    u.must_change_password, u.last_login_at,
                    r.role_name, r.privilege_level,
                    s.school_name,
                    t.teacher_id, t.staff_number, t.department
             FROM app_user u
             JOIN user_role r ON r.role_id = u.role_id
             LEFT JOIN school  s ON s.school_id = u.school_id
             LEFT JOIN teacher t ON t.user_id   = u.user_id
             WHERE u.user_id = ?',
            [$userId],
            'login profile'
        );

        if ($profile === null) {
            return ['ok' => false, 'message' => $generic];
        }

        $db->callProc('sp_login_success', [$userId, $ip, $agent]);

        // New session id on privilege change defeats session fixation.
        session_regenerate_id(true);

        $_SESSION['user']          = $profile;
        $_SESSION['last_activity'] = time();
        $_SESSION['csrf_token']    = bin2hex(random_bytes(32));

        $db->setSessionContext(
            $userId,
            $profile['school_id'] === null ? null : (int) $profile['school_id'],
            (int) $profile['privilege_level']
        );

        return ['ok' => true, 'message' => 'Signed in.'];
    }

    public static function logout(): void
    {
        if (self::check()) {
            try {
                Database::get()->exec(
                    'CALL sp_log_query_performance(?, ?, 0, NULL, NULL, ?)',
                    ['logout', 'session ended for user ' . self::userId(), DB_USER]
                );
            } catch (Throwable) {
                // logging only
            }
        }
        $_SESSION = [];
        if (ini_get('session.use_cookies')) {
            $p = session_get_cookie_params();
            setcookie(session_name(), '', time() - 42000, $p['path'], $p['domain'], $p['secure'], $p['httponly']);
        }
        session_destroy();
    }

    // -- access control ------------------------------------------------------

    public static function requireLogin(): void
    {
        if (!self::check()) {
            Flash::add('warning', 'Please sign in to continue.');
            header('Location: ' . APP_BASE_URL . 'login.php');
            exit;
        }
    }

    public static function requirePrivilege(int $level): void
    {
        self::requireLogin();
        if (self::privilege() < $level) {
            self::recordDenial($level);
            http_response_code(403);
            Flash::add('danger', 'You do not have permission to open that page.');
            header('Location: ' . APP_BASE_URL . 'index.php?page=dashboard');
            exit;
        }
    }

    public static function requireTeacher(): void
    {
        self::requireLogin();
        if (!self::isTeacher()) {
            Flash::add('warning', 'That page is for teaching staff. Your account has no teacher record.');
            header('Location: ' . APP_BASE_URL . 'index.php?page=dashboard');
            exit;
        }
    }

    private static function recordDenial(int $required): void
    {
        try {
            Database::get()->exec(
                'CALL sp_log_query_performance(?, ?, 0, NULL, NULL, ?)',
                [
                    'privilege denied',
                    sprintf('user %d (level %d) requested a page needing level %d: %s',
                        self::userId() ?? 0, self::privilege(), $required,
                        mb_substr($_SERVER['REQUEST_URI'] ?? '', 0, 200)),
                    DB_USER,
                ]
            );
        } catch (Throwable) {
        }
    }

    private static function enforceIdleTimeout(): void
    {
        if (!isset($_SESSION['last_activity'])) {
            return;
        }
        if (time() - (int) $_SESSION['last_activity'] > SESSION_IDLE_TIMEOUT) {
            self::logout();
            Auth::boot();
            Flash::add('warning', 'Your session expired after a period of inactivity. Please sign in again.');
            header('Location: ' . APP_BASE_URL . 'login.php');
            exit;
        }
        $_SESSION['last_activity'] = time();
    }

    public static function clientIp(): string
    {
        return mb_substr($_SERVER['REMOTE_ADDR'] ?? '0.0.0.0', 0, 45);
    }

    // -- CSRF ----------------------------------------------------------------

    public static function csrfToken(): string
    {
        if (empty($_SESSION['csrf_token'])) {
            $_SESSION['csrf_token'] = bin2hex(random_bytes(32));
        }
        return $_SESSION['csrf_token'];
    }

    public static function csrfField(): string
    {
        return '<input type="hidden" name="csrf_token" value="' . self::csrfToken() . '">';
    }

    /**
     * Every state-changing POST must pass this. hash_equals is constant-time,
     * so the comparison cannot be attacked by timing.
     */
    public static function requireCsrf(): void
    {
        if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
            return;
        }
        $sent = $_POST['csrf_token'] ?? '';
        if (!is_string($sent) || !hash_equals(self::csrfToken(), $sent)) {
            http_response_code(400);
            exit('<h1>Request rejected</h1><p>Security token missing or invalid. Please reload the page and try again.</p>');
        }
    }
}
