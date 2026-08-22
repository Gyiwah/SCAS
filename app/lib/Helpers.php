<?php
/**
 * SCAS - view helpers.
 *
 * e() is the output-encoding boundary. Every value that came from the
 * database or from a request is passed through it before reaching HTML.
 * Escaping on output rather than on input is deliberate: the database stores
 * what the user actually typed, and each output context does its own
 * encoding, so the same value can be safely rendered as HTML here and as JSON
 * elsewhere.
 */

declare(strict_types=1);

/** HTML-escape. */
function e(?string $value): string
{
    return htmlspecialchars($value ?? '', ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
}

/** HTML-escape any scalar. */
function ev($value): string
{
    if ($value === null) {
        return '';
    }
    if (is_bool($value)) {
        return $value ? 'Yes' : 'No';
    }
    return e((string) $value);
}

function url(string $page, array $params = []): string
{
    $params = ['page' => $page] + $params;
    return APP_BASE_URL . 'index.php?' . http_build_query($params);
}

function fmtDate(?string $date, string $format = 'd M Y'): string
{
    if (!$date) {
        return '-';
    }
    $ts = strtotime($date);
    return $ts ? date($format, $ts) : e($date);
}

function fmtTime(?string $time): string
{
    if (!$time) {
        return '-';
    }
    $ts = strtotime($time);
    return $ts ? date('g:i a', $ts) : e($time);
}

function fmtDateTime(?string $dt): string
{
    if (!$dt) {
        return '-';
    }
    $ts = strtotime($dt);
    return $ts ? date('d M Y, g:i a', $ts) : e($dt);
}

/** Colour class for an attendance status. */
function statusClass(?string $status): string
{
    return match ($status) {
        'Present'  => 'ok',
        'Late'     => 'warn',
        'Absent'   => 'bad',
        'Excused'  => 'info',
        'On Leave' => 'info',
        'No Scan'  => 'muted',
        default    => 'muted',
    };
}

function rateClass(?float $rate): string
{
    if ($rate === null) {
        return 'muted';
    }
    if ($rate >= 95) return 'ok';
    if ($rate >= 85) return 'good';
    if ($rate >= 70) return 'warn';
    return 'bad';
}

/** Read an integer request parameter with a default and bounds. */
function intParam(string $name, int $default = 0, ?int $min = null, ?int $max = null): int
{
    $raw = $_GET[$name] ?? $_POST[$name] ?? null;
    if ($raw === null || $raw === '' || !is_numeric($raw)) {
        return $default;
    }
    $v = (int) $raw;
    if ($min !== null && $v < $min) return $default;
    if ($max !== null && $v > $max) return $default;
    return $v;
}

/** Read a string request parameter, trimmed and length-capped. */
function strParam(string $name, string $default = '', int $maxLen = 255): string
{
    $raw = $_GET[$name] ?? $_POST[$name] ?? null;
    if (!is_string($raw)) {
        return $default;
    }
    return mb_substr(trim($raw), 0, $maxLen);
}

/** Read a date parameter, validated as a real calendar date. */
function dateParam(string $name, ?string $default = null): ?string
{
    $raw = $_GET[$name] ?? $_POST[$name] ?? null;
    if (!is_string($raw) || $raw === '') {
        return $default;
    }
    $d = DateTime::createFromFormat('Y-m-d', $raw);
    return ($d && $d->format('Y-m-d') === $raw) ? $raw : $default;
}

/**
 * One-shot messages held in the session across a redirect.
 */
final class Flash
{
    public static function add(string $type, string $message): void
    {
        $_SESSION['flash'][] = ['type' => $type, 'message' => $message];
    }

    public static function drain(): array
    {
        $items = $_SESSION['flash'] ?? [];
        unset($_SESSION['flash']);
        return $items;
    }
}
