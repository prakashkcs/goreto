<?php
/**
 * security.php — Centralised Security Middleware
 *
 * Include this at the TOP of every API endpoint:
 *   require_once __DIR__ . '/security.php';
 *
 * Provides:
 *  - Security response headers (XSS, clickjacking, MIME sniffing, etc.)
 *  - IP-based rate limiting (file-based, no Redis required)
 *  - Fake engagement / view-farming detection
 *  - Input sanitisation helpers
 *  - Request signature validation (optional, for mobile app)
 *  - Suspicious pattern detection (SQLi, XSS probes)
 */

// ── Security headers ──────────────────────────────────────────────────────────
header('X-Content-Type-Options: nosniff');
header('X-Frame-Options: DENY');
header('X-XSS-Protection: 1; mode=block');
header('Referrer-Policy: strict-origin-when-cross-origin');
header('Permissions-Policy: camera=(), microphone=(), geolocation=()');
// Only send HSTS on HTTPS
if (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off') {
    header('Strict-Transport-Security: max-age=31536000; includeSubDomains');
}

// ── Config ────────────────────────────────────────────────────────────────────
define('SEC_RATE_DIR', sys_get_temp_dir() . '/eklo_rate/');
define('SEC_ENGAGE_DIR', sys_get_temp_dir() . '/eklo_engage/');

// Rate limits: [max_requests, window_seconds]
define('SEC_RATE_DEFAULT', [120, 60]);   // 120 req / 60 s  (general)
define('SEC_RATE_AUTH', [10, 60]);   // 10  req / 60 s  (login/register)
define('SEC_RATE_UPLOAD', [20, 60]);   // 20  req / 60 s  (file uploads)
define('SEC_RATE_LIKE', [60, 60]);   // 60  likes / 60 s
define('SEC_RATE_VIEW', [200, 60]);   // 200 views / 60 s
define('SEC_RATE_COMMENT', [30, 60]);   // 30  comments / 60 s

// Minimum seconds between two view events on the SAME post by the SAME user
define('SEC_VIEW_COOLDOWN', 30);

// ── Helpers ───────────────────────────────────────────────────────────────────

/**
 * Get the real client IP, respecting common proxy headers.
 * Never trust X-Forwarded-For blindly — only use it if you control the proxy.
 */
function sec_client_ip(): string
{
    // Prefer REMOTE_ADDR (most reliable); only fall back to forwarded headers
    // if you are behind a trusted reverse proxy (nginx/cloudflare).
    $ip = $_SERVER['REMOTE_ADDR'] ?? '0.0.0.0';

    // If behind a trusted proxy (e.g. Cloudflare), use CF-Connecting-IP
    if (!empty($_SERVER['HTTP_CF_CONNECTING_IP'])) {
        $candidate = trim($_SERVER['HTTP_CF_CONNECTING_IP']);
        if (filter_var($candidate, FILTER_VALIDATE_IP)) {
            return $candidate;
        }
    }

    return $ip;
}

/**
 * File-based rate limiter.
 * Returns true if the request is allowed, false if rate-limited.
 *
 * @param string $bucket  Unique key (e.g. "auth_1.2.3.4")
 * @param int    $max     Max requests in window
 * @param int    $window  Window in seconds
 */
function sec_rate_check(string $bucket, int $max, int $window): bool
{
    $dir = SEC_RATE_DIR;
    if (!is_dir($dir)) {
        @mkdir($dir, 0700, true);
    }

    $file = $dir . md5($bucket) . '.json';
    $now = time();
    $data = ['hits' => [], 'blocked_until' => 0];

    if (file_exists($file)) {
        $raw = @file_get_contents($file);
        if ($raw) {
            $decoded = json_decode($raw, true);
            if (is_array($decoded)) {
                $data = $decoded;
            }
        }
    }

    // If currently in a block period, reject immediately
    if ($data['blocked_until'] > $now) {
        return false;
    }

    // Prune hits outside the window
    $data['hits'] = array_values(array_filter(
        $data['hits'],
        fn($t) => ($now - $t) < $window
    ));

    $data['hits'][] = $now;

    if (count($data['hits']) > $max) {
        // Block for the remainder of the window
        $data['blocked_until'] = $now + $window;
        @file_put_contents($file, json_encode($data), LOCK_EX);
        return false;
    }

    @file_put_contents($file, json_encode($data), LOCK_EX);
    return true;
}

/**
 * Enforce rate limit — sends 429 and exits if exceeded.
 *
 * @param string $type   'default'|'auth'|'upload'|'like'|'view'|'comment'
 * @param string $extra  Extra key to append (e.g. user_id)
 */
function sec_rate_limit(string $type = 'default', string $extra = ''): void
{
    $ip = sec_client_ip();

    $limits = [
        'default' => SEC_RATE_DEFAULT,
        'auth' => SEC_RATE_AUTH,
        'upload' => SEC_RATE_UPLOAD,
        'like' => SEC_RATE_LIKE,
        'view' => SEC_RATE_VIEW,
        'comment' => SEC_RATE_COMMENT,
    ];

    [$max, $window] = $limits[$type] ?? SEC_RATE_DEFAULT;
    $bucket = $type . '_' . $ip . ($extra ? '_' . $extra : '');

    if (!sec_rate_check($bucket, $max, $window)) {
        http_response_code(429);
        header('Retry-After: ' . $window);
        echo json_encode([
            'status' => false,
            'message' => 'Too many requests. Please slow down.',
            'code' => 429,
        ]);
        exit;
    }
}

/**
 * Prevent fake view inflation.
 * A user (or IP) can only register a view on a specific post once per cooldown period.
 *
 * @param int    $postId
 * @param string $userId  User ID or IP if guest
 * @return bool  true = view is genuine, false = duplicate/fake
 */
function sec_check_view(int $postId, string $userId): bool
{
    $dir = SEC_ENGAGE_DIR;
    if (!is_dir($dir)) {
        @mkdir($dir, 0700, true);
    }

    $key = 'view_' . $postId . '_' . $userId;
    $file = $dir . md5($key) . '.ts';
    $now = time();

    if (file_exists($file)) {
        $last = (int) @file_get_contents($file);
        if (($now - $last) < SEC_VIEW_COOLDOWN) {
            return false; // too soon — fake/duplicate
        }
    }

    @file_put_contents($file, (string) $now, LOCK_EX);
    return true;
}

/**
 * Prevent fake like inflation.
 * A user can only like a post once (enforced by DB UNIQUE key ideally,
 * but this adds a fast pre-check layer).
 *
 * @param int    $postId
 * @param string $userId
 * @return bool  true = first like, false = already liked recently
 */
function sec_check_like(int $postId, string $userId): bool
{
    $dir = SEC_ENGAGE_DIR;
    if (!is_dir($dir)) {
        @mkdir($dir, 0700, true);
    }

    $key = 'like_' . $postId . '_' . $userId;
    $file = $dir . md5($key) . '.lk';

    if (file_exists($file)) {
        return false; // already liked
    }

    @file_put_contents($file, '1', LOCK_EX);
    return true;
}

/**
 * Remove the like lock (called when user unlikes).
 */
function sec_clear_like(int $postId, string $userId): void
{
    $key = 'like_' . $postId . '_' . $userId;
    $file = SEC_ENGAGE_DIR . md5($key) . '.lk';
    @unlink($file);
}

/**
 * Detect common SQL injection and XSS probe patterns in a string.
 * Returns true if the input looks malicious.
 */
function sec_is_malicious(string $input): bool
{
    $patterns = [
        // SQL injection
        '/(\bUNION\b.*\bSELECT\b|\bSELECT\b.*\bFROM\b|\bDROP\b.*\bTABLE\b)/i',
        '/(\bINSERT\b.*\bINTO\b|\bDELETE\b.*\bFROM\b|\bUPDATE\b.*\bSET\b)/i',
        '/(\bEXEC\b|\bEXECUTE\b|\bxp_cmdshell\b)/i',
        '/(\'|\")(\s*)(OR|AND)(\s+)(\'|\"|1|true)/i',
        '/--\s*$/',
        '/;\s*(DROP|DELETE|UPDATE|INSERT|CREATE|ALTER)/i',
        // XSS
        '/<script[\s>]/i',
        '/javascript\s*:/i',
        '/on(load|error|click|mouse|focus|blur|key|submit|change)\s*=/i',
        '/<\s*iframe/i',
        '/<\s*object/i',
        '/<\s*embed/i',
        // Path traversal
        '/\.\.[\/\\\\]/',
        // Null bytes
        '/\x00/',
    ];

    foreach ($patterns as $pattern) {
        if (preg_match($pattern, $input)) {
            return true;
        }
    }
    return false;
}

/**
 * Sanitise a string for safe use in responses (strip tags, trim).
 * Does NOT replace parameterised queries — always use PDO prepared statements.
 */
function sec_clean(string $input, int $maxLen = 2000): string
{
    $input = mb_substr(trim($input), 0, $maxLen);
    return htmlspecialchars($input, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
}

/**
 * Validate and sanitise an integer input.
 */
function sec_int(mixed $val, int $min = 0, int $max = PHP_INT_MAX): int
{
    $i = (int) $val;
    return max($min, min($max, $i));
}

/**
 * Check all GET/POST/COOKIE values for obvious injection probes.
 * Call once at the top of sensitive endpoints.
 */
function sec_scan_inputs(): void
{
    $sources = array_merge(
        array_values($_GET),
        array_values($_POST),
        array_values($_COOKIE)
    );

    foreach ($sources as $val) {
        if (is_string($val) && sec_is_malicious($val)) {
            http_response_code(400);
            echo json_encode([
                'status' => false,
                'message' => 'Invalid request.',
                'code' => 400,
            ]);
            exit;
        }
    }
}

/**
 * Validate that the request comes from the official app by checking
 * a shared secret header. Set APP_SECRET in config.php.
 * This is a lightweight check — not a replacement for proper auth.
 *
 * Usage: sec_verify_app_secret($config['app_secret'] ?? '');
 */
function sec_verify_app_secret(string $secret): void
{
    if (empty($secret)) {
        return; // not configured — skip
    }

    $header = $_SERVER['HTTP_X_APP_SECRET'] ?? '';
    if (!hash_equals($secret, $header)) {
        http_response_code(403);
        echo json_encode([
            'status' => false,
            'message' => 'Forbidden.',
            'code' => 403,
        ]);
        exit;
    }
}

/**
 * Log a security event to a dedicated file.
 */
function sec_log(string $event, array $context = []): void
{
    $logDir = sys_get_temp_dir() . '/eklo_security/';
    if (!is_dir($logDir)) {
        @mkdir($logDir, 0700, true);
    }

    $line = date('Y-m-d H:i:s') . ' | ' . sec_client_ip() . ' | ' . $event;
    if (!empty($context)) {
        $line .= ' | ' . json_encode($context);
    }
    $line .= PHP_EOL;

    @file_put_contents($logDir . 'security.log', $line, FILE_APPEND | LOCK_EX);
}

// ── Auto-scan inputs on every request ────────────────────────────────────────
// Scans GET/POST/COOKIE for obvious injection probes.
// JSON body is NOT scanned here (too expensive) — endpoints handle that via PDO.
sec_scan_inputs();
