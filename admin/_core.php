<?php
// ekloadmin/admin/_core.php
ini_set('display_errors', 0);
error_reporting(E_ALL);

// Find config — works from admin/ or root
$config = null;
foreach ([
    __DIR__ . '/../config/config.php',
    __DIR__ . '/../config.php',
    __DIR__ . '/config.php',
] as $_cp) {
    if (file_exists($_cp)) {
        $config = require $_cp;
        break;
    }
}
if (!$config || empty($config['db'])) {
    die('<h2 style="font-family:sans-serif;padding:40px">Admin config not found. Check server setup.</h2>');
}

// ── Secure session configuration ─────────────────────────────────────────────
$_isHttps = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off')
    || ($_SERVER['HTTP_X_FORWARDED_PROTO'] ?? '') === 'https';
$_sessLifetime = (int) ($config['admin']['session_lifetime'] ?? 7200);
session_name($config['admin']['session_name'] ?? 'eklo_admin_sess');
session_set_cookie_params([
    'lifetime' => 0,             // Session cookie (no persistent expiry in browser)
    'path'     => '/',
    'domain'   => '',
    'secure'   => $_isHttps,     // HTTPS-only cookie
    'httponly' => true,          // Inaccessible to JavaScript
    'samesite' => 'Strict',      // Blocks cross-site form submissions (CSRF)
]);
ini_set('session.gc_maxlifetime', $_sessLifetime);
ini_set('session.use_strict_mode', 1);
ini_set('session.cookie_httponly', 1);
ini_set('session.cookie_samesite', 'Strict');
session_start();

// Enforce idle timeout
if (!empty($_SESSION['admin_id'])) {
    $lastActive = $_SESSION['_last_active'] ?? 0;
    if (time() - $lastActive > $_sessLifetime) {
        session_destroy();
        header('Location: login.php?timeout=1');
        exit;
    }
    $_SESSION['_last_active'] = time();
}

try {
    $db = $config['db'];
    $pdo = new PDO(
        "mysql:host={$db['host']};dbname={$db['name']};charset=" . ($db['charset'] ?? 'utf8mb4'),
        $db['user'],
        $db['pass'],
        [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION, PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC]
    );
} catch (PDOException $e) {
    die('<h2 style="font-family:sans-serif;padding:40px">DB connection failed: ' . htmlspecialchars($e->getMessage()) . '</h2>');
}

// Bootstrap admin_users table
$pdo->exec("CREATE TABLE IF NOT EXISTS admin_users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(100) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

$c = (int) ($pdo->query("SELECT COUNT(*) FROM admin_users")->fetchColumn() ?? 0);
if ($c === 0) {
    $u = $config['admin']['bootstrap_username'] ?? 'admin';
    $p = $config['admin']['bootstrap_password'] ?? 'admin123';
    $pdo->prepare("INSERT INTO admin_users (username, password_hash) VALUES (?, ?)")
        ->execute([$u, password_hash($p, PASSWORD_DEFAULT)]);
}

// ── CSRF helpers ─────────────────────────────────────────────────────────────

function admin_csrf_token(): string
{
    if (empty($_SESSION['csrf_token'])) {
        $_SESSION['csrf_token'] = bin2hex(random_bytes(32));
    }
    return (string) $_SESSION['csrf_token'];
}

function admin_verify_csrf(): void
{
    if ($_SERVER['REQUEST_METHOD'] !== 'POST') return;
    $token    = trim((string) ($_POST['csrf_token'] ?? ''));
    $expected = (string) ($_SESSION['csrf_token'] ?? '');
    if ($token === '' || $expected === '' || !hash_equals($expected, $token)) {
        http_response_code(403);
        die('<h2 style="font-family:sans-serif;padding:40px">Invalid request (CSRF). Go back and try again.</h2>');
    }
}

// ── Brute-force protection ────────────────────────────────────────────────────

function _admin_ensure_attempts_table(PDO $pdo): void
{
    $pdo->exec("CREATE TABLE IF NOT EXISTS admin_login_attempts (
        ip          VARCHAR(45)  NOT NULL PRIMARY KEY,
        attempts    INT          NOT NULL DEFAULT 0,
        last_try    DATETIME     NULL,
        locked_until DATETIME    NULL
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
}

function admin_check_ip_allowed(PDO $pdo, string $ip): bool
{
    try {
        _admin_ensure_attempts_table($pdo);
        $st = $pdo->prepare("SELECT attempts, locked_until FROM admin_login_attempts WHERE ip = ?");
        $st->execute([$ip]);
        $row = $st->fetch();
        if (!$row) return true;
        if ($row['locked_until'] && new DateTime($row['locked_until']) > new DateTime()) {
            return false; // Still locked
        }
        return true;
    } catch (Throwable $_) {
        return true; // Fail-open: don't block on DB error
    }
}

function admin_record_failed_login(PDO $pdo, string $ip): void
{
    try {
        _admin_ensure_attempts_table($pdo);
        $pdo->prepare(
            "INSERT INTO admin_login_attempts (ip, attempts, last_try, locked_until)
             VALUES (?, 1, NOW(), NULL)
             ON DUPLICATE KEY UPDATE
               attempts    = IF(locked_until IS NOT NULL AND locked_until < NOW(), 1, attempts + 1),
               last_try    = NOW(),
               locked_until = IF(
                 IF(locked_until IS NOT NULL AND locked_until < NOW(), 1, attempts + 1) >= 5,
                 DATE_ADD(NOW(), INTERVAL 15 MINUTE),
                 NULL
               )"
        )->execute([$ip]);
    } catch (Throwable $_) {}
}

function admin_clear_login_attempts(PDO $pdo, string $ip): void
{
    try {
        $pdo->prepare("DELETE FROM admin_login_attempts WHERE ip = ?")
            ->execute([$ip]);
    } catch (Throwable $_) {}
}

// ── Session / auth helpers ────────────────────────────────────────────────────

function admin_require_login()
{
    if (empty($_SESSION['admin_id'])) {
        header('Location: login.php');
        exit;
    }
}
function admin_logout()
{
    session_destroy();
    header('Location: login.php');
    exit;
}
function table_count(PDO $pdo, string $table): int
{
    try {
        return (int) $pdo->query("SELECT COUNT(*) FROM `$table`")->fetchColumn();
    } catch (Throwable $_) {
        return 0;
    }
}
function notif_path(): string
{
    // Find notification_helper.php from admin/ context
    foreach ([
        __DIR__ . '/../notification_helper.php',
        __DIR__ . '/notification_helper.php',
        __DIR__ . '/../api/v1/notification_helper.php',
    ] as $p) {
        if (file_exists($p))
            return $p;
    }
    return '';
}
function send_notif(PDO $pdo, int $uid, string $type, string $title, string $body): void
{
    $p = notif_path();
    if (!$p)
        return;
    try {
        require_once $p;
        if (function_exists('send_app_notification'))
            send_app_notification($pdo, $uid, 0, $type, $title, $body);
    } catch (Throwable $_) {
    }
}

function admin_get_settings(PDO $pdo, string $table, array $defaults = []): array
{
    $settings = [];
    try {
        foreach ($pdo->query("SELECT setting_key, setting_value FROM `$table`")->fetchAll() as $row) {
            $settings[$row['setting_key']] = $row['setting_value'];
        }
    } catch (Throwable $_) {
    }
    foreach ($defaults as $k => $v) {
        if (!array_key_exists($k, $settings))
            $settings[$k] = $v;
    }
    return $settings;
}

function admin_upsert_settings(PDO $pdo, string $table, array $values): void
{
    foreach ($values as $key => $value) {
        $pdo->prepare("INSERT INTO `$table` (setting_key, setting_value) VALUES (?, ?) ON DUPLICATE KEY UPDATE setting_value = VALUES(setting_value), updated_at = NOW()")
            ->execute([$key, (string) $value]);
    }
}

function admin_alert_counts(PDO $pdo): array
{
    $counts = [
        'wallet_requests' => 0,
        'withdrawals' => 0,
        'kyc_review' => 0,
        'reports' => 0,
        'sound_reports' => 0,
        'notifications' => 0,
        'important_total' => 0,
    ];

    $queries = [
        'wallet_requests' => "SELECT COUNT(*) FROM wallet_requests WHERE status='pending' AND (req_type='deposit' OR req_type IS NULL)",
        'withdrawals' => "SELECT COUNT(*) FROM wallet_requests WHERE status='pending' AND req_type='withdraw'",
        'kyc_review' => "SELECT COUNT(*) FROM kyc_submissions WHERE status='pending'",
        'reports' => "SELECT COUNT(*) FROM user_reports WHERE status='pending'",
        'sound_reports' => "SELECT COUNT(*) FROM sound_reports WHERE status='pending'",
    ];

    foreach ($queries as $key => $sql) {
        try {
            $counts[$key] = (int) ($pdo->query($sql)->fetchColumn() ?: 0);
        } catch (Throwable $_) {
        }
    }

    // Also count QR deposits awaiting review (stored in wallet_deposits, not wallet_requests)
    try {
        $counts['wallet_requests'] += (int) ($pdo->query("SELECT COUNT(*) FROM wallet_deposits WHERE status='reviewing'")->fetchColumn() ?: 0);
    } catch (Throwable $_) {
    }

    $counts['notifications'] = $counts['wallet_requests'] + $counts['withdrawals'] + $counts['kyc_review'] + $counts['reports'] + $counts['sound_reports'];
    $counts['important_total'] = $counts['notifications'];
    return $counts;
}

function admin_badge_html(int $count, string $class = ''): string
{
    if ($count <= 0)
        return '';
    $safeClass = trim($class);
    return '<span class="nav-badge ' . htmlspecialchars($safeClass) . '">' . number_format($count) . '</span>';
}

function admin_send_push_via_onesignal(array $settings, string $title, string $body, array $includePlayerIds = [], array $data = []): array
{
    $appId = trim($settings['onesignal_app_id'] ?? '');
    $apiKey = trim($settings['onesignal_api_key'] ?? '');
    if ($appId === '' || $apiKey === '') {
        throw new Exception('OneSignal App ID / API Key not configured.');
    }

    $payload = [
        'app_id' => $appId,
        'headings' => ['en' => $title],
        'contents' => ['en' => $body],
        'data' => $data,
    ];

    if (!empty($includePlayerIds)) {
        $payload['include_player_ids'] = array_values($includePlayerIds);
    } else {
        $payload['included_segments'] = ['All'];
    }

    $ch = curl_init('https://onesignal.com/api/v1/notifications');
    curl_setopt_array($ch, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_POST => true,
        CURLOPT_HTTPHEADER => [
            'Content-Type: application/json; charset=utf-8',
            'Authorization: Basic ' . $apiKey,
        ],
        CURLOPT_POSTFIELDS => json_encode($payload),
        CURLOPT_TIMEOUT => 25,
    ]);
    $response = curl_exec($ch);
    $httpCode = (int) curl_getinfo($ch, CURLINFO_HTTP_CODE);
    $curlError = curl_error($ch);
    curl_close($ch);

    if ($response === false || $curlError) {
        throw new Exception('OneSignal request failed: ' . $curlError);
    }

    $decoded = json_decode($response, true);
    if ($httpCode >= 400) {
        $msg = is_array($decoded) ? json_encode($decoded) : $response;
        throw new Exception('OneSignal error: ' . $msg);
    }

    return is_array($decoded) ? $decoded : ['raw' => $response];
}

function admin_send_notification(PDO $pdo, array $options): array
{
    $pdo->exec("CREATE TABLE IF NOT EXISTS notification_settings (
        id INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
        setting_key VARCHAR(80) NOT NULL UNIQUE,
        setting_value TEXT NULL,
        updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

    $hasOneSignalPlayerId = false;
    try {
        $col = $pdo->query("SHOW COLUMNS FROM users LIKE 'onesignal_player_id'")->fetch();
        $hasOneSignalPlayerId = !empty($col);
    } catch (Throwable $_) {
    }

    $settings = admin_get_settings($pdo, 'notification_settings', [
        'default_provider' => 'in_app',
        'fcm_push_enabled' => '1',
        'onesignal_enabled' => '0',
        'onesignal_app_id' => '',
        'onesignal_api_key' => '',
        'onesignal_target_mode' => 'segments',
    ]);

    $provider = $options['provider'] ?? ($settings['default_provider'] ?? 'in_app');
    $target = $options['target'] ?? 'all';
    $title = trim((string) ($options['title'] ?? ''));
    $body = trim((string) ($options['body'] ?? ''));
    $userId = (int) ($options['user_id'] ?? 0);
    $type = trim((string) ($options['type'] ?? 'admin')) ?: 'admin';
    $important = !empty($options['important']);

    if ($title === '' || $body === '')
        throw new Exception('Title and message are required.');

    $sent = 0;
    $failed = 0;
    $pushSent = 0;
    $notifPath = notif_path();
    if (($provider === 'in_app' || $provider === 'server_push') && !$notifPath) {
        throw new Exception('Notification helper not found on server.');
    }
    if ($notifPath)
        require_once $notifPath;

    $users = [];
    $userSelect = $hasOneSignalPlayerId ? 'id, onesignal_player_id' : 'id, NULL AS onesignal_player_id';
    if ($target === 'user' && $userId > 0) {
        try {
            $st = $pdo->prepare("SELECT {$userSelect} FROM users WHERE id = ? LIMIT 1");
            $st->execute([$userId]);
            $row = $st->fetch();
            if ($row)
                $users[] = $row;
        } catch (Throwable $_) {
            $users[] = ['id' => $userId, 'onesignal_player_id' => null];
        }
        if (!$users)
            throw new Exception('User not found.');
    } else {
        $users = $pdo->query("SELECT {$userSelect} FROM users WHERE is_banned = 0 OR is_banned IS NULL ORDER BY id DESC LIMIT 5000")->fetchAll();
    }

    $forceDataOnly = !$important;

    if ($provider === 'onesignal') {
        $playerIds = [];
        foreach ($users as $u) {
            if (!empty($u['onesignal_player_id']))
                $playerIds[] = $u['onesignal_player_id'];
        }
        $resp = admin_send_push_via_onesignal($settings, $title, $body, $target === 'user' ? $playerIds : [], [
            'type' => $type,
            'important' => $important ? '1' : '0',
            'action' => 'notification',
        ]);
        return ['sent' => count($users), 'failed' => 0, 'push_sent' => count($playerIds), 'provider' => 'onesignal', 'response' => $resp];
    }

    foreach ($users as $u) {
        try {
            if (function_exists('send_app_notification')) {
                send_app_notification($pdo, (int) $u['id'], 0, $type, $title, $body, null, $forceDataOnly);
                $sent++;
                if ($provider === 'server_push' && !empty($settings['fcm_push_enabled']))
                    $pushSent++;
            }
        } catch (Throwable $_) {
            $failed++;
        }
    }

    return ['sent' => $sent, 'failed' => $failed, 'push_sent' => $pushSent, 'provider' => $provider, 'response' => null];
}
