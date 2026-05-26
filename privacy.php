<?php
/**
 * privacy.php — User Privacy Settings API
 *
 * GET  /api/v1/privacy.php  → return current user's privacy settings
 * POST /api/v1/privacy.php  → update one or more privacy settings (JSON body)
 */

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Content-Type, Authorization');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    echo json_encode(['status' => 'success']);
    exit;
}

ini_set('display_errors', '0');
error_reporting(E_ALL);

function json_out(int $code, array $data): void
{
    http_response_code($code);
    echo json_encode($data);
    exit;
}

// Resolve db_connect and auth_middleware regardless of whether this file
// lives in the root or inside api/v1/
$_base = __DIR__;
if (!file_exists($_base . '/db_connect.php') && file_exists($_base . '/../db_connect.php')) {
    $_base = realpath($_base . '/..');
}
require_once $_base . '/db_connect.php';
require_once $_base . '/auth_middleware.php';

if (!isset($pdo) || !($pdo instanceof PDO)) {
    json_out(500, ['status' => false, 'message' => 'DB not connected']);
}

// ── Allowed privacy columns (whitelist) ──────────────────────────────────────
$PRIVACY_COLS = [
    'privacy_allow_find_id',
    'privacy_allow_random_video_call',
    'privacy_allow_direct_call',
    'privacy_allow_repost',
    'privacy_allow_unknown_inbox',
    'privacy_show_online',
    'privacy_show_last_seen',
    'privacy_show_profile_views',
    'privacy_share_distance',
    'privacy_nearby_visible',
    'privacy_feed_action_subscribe',
];

// ── Ensure columns exist in users table ──────────────────────────────────────
// Pass $PRIVACY_COLS explicitly to avoid global scope issues
function ensure_privacy_columns(PDO $pdo, array $privacyCols): void
{
    static $done = false;
    if ($done)
        return;
    $done = true;

    try {
        $existing = [];
        $st = $pdo->query("SHOW COLUMNS FROM users");
        foreach ($st->fetchAll(PDO::FETCH_ASSOC) as $row) {
            $existing[] = $row['Field'];
        }

        $defaults = [
            'privacy_allow_find_id' => 1,
            'privacy_allow_random_video_call' => 1,
            'privacy_allow_direct_call' => 0,
            'privacy_allow_repost' => 1,
            'privacy_allow_unknown_inbox' => 1,
            'privacy_show_online' => 1,
            'privacy_show_last_seen' => 1,
            'privacy_show_profile_views' => 1,
            'privacy_share_distance' => 1,
            'privacy_nearby_visible' => 1,
            'privacy_feed_action_subscribe' => 0,
        ];

        foreach ($privacyCols as $col) {
            if (!in_array($col, $existing, true)) {
                $default = $defaults[$col] ?? 0;
                try {
                    $pdo->exec("ALTER TABLE users ADD COLUMN `$col` TINYINT(1) NOT NULL DEFAULT $default");
                } catch (Throwable $_) {
                    // Column may already exist in a race condition — safe to ignore
                }
            }
        }
    } catch (Throwable $e) {
        // Non-fatal: if SHOW COLUMNS fails we continue and let the query fail naturally
    }
}

try {
    $user = requireUser($pdo);
    $userId = (int) $user['id'];

    ensure_privacy_columns($pdo, $PRIVACY_COLS);

    // ── GET: return current settings ─────────────────────────────────────────
    if ($_SERVER['REQUEST_METHOD'] === 'GET') {
        $cols = implode(', ', array_map(fn($c) => "`$c`", $PRIVACY_COLS));
        $st = $pdo->prepare("SELECT $cols FROM users WHERE id = ? LIMIT 1");
        $st->execute([$userId]);
        $row = $st->fetch(PDO::FETCH_ASSOC);

        if (!$row) {
            json_out(404, ['status' => false, 'message' => 'User not found']);
        }

        // Cast to int so Flutter _asBool() works correctly
        $settings = [];
        foreach ($row as $k => $v) {
            $settings[$k] = (int) $v;
        }

        json_out(200, ['status' => true, 'user' => $settings]);
    }

    // ── POST: update settings ────────────────────────────────────────────────
    if ($_SERVER['REQUEST_METHOD'] === 'POST') {
        // Accept JSON body (Flutter sends Content-Type: application/json)
        $input = file_get_contents('php://input');
        $body = [];
        if (!empty($input)) {
            $decoded = json_decode($input, true);
            if (is_array($decoded)) {
                $body = $decoded;
            }
        }
        // Also accept form-encoded fallback
        if (!empty($_POST)) {
            $body = array_merge($body, $_POST);
        }

        $setClauses = [];
        $params = [];

        foreach ($PRIVACY_COLS as $col) {
            if (array_key_exists($col, $body)) {
                $val = $body[$col];
                // Normalise: bool true/false, int 1/0, string "1"/"0"/"true"/"false"
                if (is_bool($val)) {
                    $intVal = $val ? 1 : 0;
                } elseif (is_numeric($val)) {
                    $intVal = ((int) $val) ? 1 : 0;
                } else {
                    $s = strtolower(trim((string) $val));
                    $intVal = ($s === '1' || $s === 'true' || $s === 'yes' || $s === 'on') ? 1 : 0;
                }
                $setClauses[] = "`$col` = ?";
                $params[] = $intVal;
            }
        }

        if (empty($setClauses)) {
            json_out(400, ['status' => false, 'message' => 'No valid privacy fields provided']);
        }

        $params[] = $userId;
        $sql = "UPDATE users SET " . implode(', ', $setClauses) . " WHERE id = ?";
        $stmt = $pdo->prepare($sql);
        $stmt->execute($params);

        // Return fresh values
        $cols = implode(', ', array_map(fn($c) => "`$c`", $PRIVACY_COLS));
        $st = $pdo->prepare("SELECT $cols FROM users WHERE id = ? LIMIT 1");
        $st->execute([$userId]);
        $row = $st->fetch(PDO::FETCH_ASSOC);

        $settings = [];
        foreach (($row ?: []) as $k => $v) {
            $settings[$k] = (int) $v;
        }

        json_out(200, ['status' => true, 'message' => 'Privacy settings updated', 'user' => $settings]);
    }

    json_out(405, ['status' => false, 'message' => 'Method not allowed']);

} catch (Throwable $e) {
    // Log internally but don't expose raw exception messages to clients
    error_log('privacy.php error: ' . $e->getMessage());
    json_out(500, ['status' => false, 'message' => 'Server error: ' . $e->getMessage()]);
}
