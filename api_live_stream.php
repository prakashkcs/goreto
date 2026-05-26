<?php
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Content-Type, Authorization');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    echo json_encode(['status' => 'ok']);
    exit;
}

require_once __DIR__ . '/db_connect.php';
require_once __DIR__ . '/auth_middleware.php';

// Ensure live_streams table and all required columns exist
try {
    $pdo->exec("
        CREATE TABLE IF NOT EXISTS live_streams (
            user_id        INT NOT NULL PRIMARY KEY,
            user_name      VARCHAR(100) DEFAULT '',
            avatar         VARCHAR(255) DEFAULT '',
            started_at     DATETIME NOT NULL,
            last_heartbeat DATETIME NOT NULL,
            viewer_count   INT DEFAULT 0
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ");
} catch (Throwable $e) {
}

// Add any columns that may be missing in older schema
foreach ([
    "ALTER TABLE live_streams ADD COLUMN user_name      VARCHAR(100) DEFAULT ''",
    "ALTER TABLE live_streams ADD COLUMN avatar         VARCHAR(255) DEFAULT ''",
    "ALTER TABLE live_streams ADD COLUMN started_at     DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP",
    "ALTER TABLE live_streams ADD COLUMN last_heartbeat DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP",
    "ALTER TABLE live_streams ADD COLUMN viewer_count   INT          DEFAULT 0",
] as $_sql) {
    try {
        $pdo->exec($_sql);
    } catch (Throwable $e) {
    }
}

// Auto-cleanup stale streams
try {
    $pdo->exec("DELETE FROM live_streams WHERE last_heartbeat < DATE_SUB(NOW(), INTERVAL 60 SECOND)");
} catch (Throwable $e) {
}

// Parse JSON body (Flutter Dio sends application/json)
$_rawBody = file_get_contents('php://input');
if (!empty($_rawBody)) {
    $_jsonBody = json_decode($_rawBody, true);
    if (is_array($_jsonBody)) {
        $_REQUEST = array_merge($_REQUEST, $_jsonBody);
        $_POST = array_merge($_POST, $_jsonBody);
    }
}

try {
    $action = $_REQUEST['action'] ?? '';

    // ── GET LIVE USERS (no auth required) ──────────────────────────────────
    if ($action === 'get_live_users') {
        $proto = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off') ? 'https' : 'http';
        $host = $_SERVER['HTTP_HOST'] ?? 'coinzop.com';
        $siteUrl = $proto . '://' . $host;

        // Detect which display-name column exists in users table (name vs username)
        $nameCol = 'ls.user_name';
        try {
            $colCheck = $pdo->query("SHOW COLUMNS FROM users LIKE 'name'");
            if ($colCheck && $colCheck->rowCount() > 0) {
                $nameCol = "COALESCE(u.name, u.username, ls.user_name)";
            } else {
                $nameCol = "COALESCE(u.username, ls.user_name)";
            }
        } catch (Throwable $_e) {
        }

        $rows = [];
        try {
            $stmt = $pdo->query("
                SELECT ls.user_id, ls.user_name, ls.viewer_count, ls.started_at,
                       COALESCE(u.profile_pic, ls.avatar, '') AS avatar,
                       $nameCol AS display_name
                FROM   live_streams ls
                LEFT   JOIN users u ON u.id = ls.user_id
                WHERE  ls.last_heartbeat > DATE_SUB(NOW(), INTERVAL 45 SECOND)
                ORDER  BY ls.viewer_count DESC, ls.started_at ASC
            ");
            $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);
        } catch (Throwable $_e) {
            // Table may not exist yet — return empty list gracefully
            echo json_encode(['status' => 'success', 'profiles' => []]);
            exit;
        }

        $profiles = [];
        foreach ($rows as $r) {
            $av = (string) ($r['avatar'] ?? '');
            if ($av !== '' && strpos($av, 'http') !== 0) {
                $av = $siteUrl . '/' . ltrim($av, '/');
            }
            $profiles[] = [
                'user_id' => (string) $r['user_id'],
                'name' => (string) ($r['display_name'] ?: $r['user_name'] ?: 'User'),
                'avatar' => $av,
                'viewers' => (int) $r['viewer_count'],
                'started_at' => $r['started_at'],
            ];
        }

        echo json_encode(['status' => 'success', 'profiles' => $profiles]);
        exit;
    }

    // All mutating actions require auth
    $user = requireUser($pdo);
    $userId = (int) $user['id'];
    $name = $user['name'] ?? $user['username'] ?? 'User';
    $avatar = $user['profile_pic'] ?? $user['avatar'] ?? '';

    // ── START LIVE ──────────────────────────────────────────────────────────
    if ($action === 'start_live') {
        $stmt = $pdo->prepare("
            INSERT INTO live_streams (user_id, user_name, avatar, started_at, last_heartbeat, viewer_count)
            VALUES (?, ?, ?, NOW(), NOW(), 0)
            ON DUPLICATE KEY UPDATE
                user_name      = VALUES(user_name),
                avatar         = VALUES(avatar),
                last_heartbeat = NOW(),
                started_at     = IF(last_heartbeat < DATE_SUB(NOW(), INTERVAL 60 SECOND), NOW(), started_at)
        ");
        $stmt->execute([$userId, $name, $avatar]);

        // Notify followers that this user is now live
        try {
            require_once __DIR__ . '/notification_helper.php';
            $fStmt = $pdo->prepare(
                "SELECT follower_id FROM follows WHERE following_id = ? LIMIT 500"
            );
            $fStmt->execute([$userId]);
            foreach ($fStmt->fetchAll(PDO::FETCH_COLUMN) as $fid) {
                $fid = (int) $fid;
                if ($fid > 0 && $fid !== $userId) {
                    send_app_notification(
                        $pdo,
                        $fid,
                        $userId,
                        'live_start',
                        "$name is Live Now! 🔴",
                        "Tap to join the live stream.",
                        $userId
                    );
                }
            }
        } catch (Throwable $e) { /* non-fatal */
        }

        echo json_encode(['status' => 'success', 'live_id' => 'live_' . $userId]);
        exit;
    }

    // ── END LIVE ────────────────────────────────────────────────────────────
    if ($action === 'end_live') {
        $stmt = $pdo->prepare("DELETE FROM live_streams WHERE user_id = ?");
        $stmt->execute([$userId]);
        echo json_encode(['status' => 'success']);
        exit;
    }

    // ── HEARTBEAT ───────────────────────────────────────────────────────────
    if ($action === 'heartbeat') {
        $stmt = $pdo->prepare("UPDATE live_streams SET last_heartbeat = NOW() WHERE user_id = ?");
        $stmt->execute([$userId]);
        if ($stmt->rowCount() === 0) {
            // Race condition: auto-register
            $ins = $pdo->prepare("
                INSERT IGNORE INTO live_streams (user_id, user_name, avatar, started_at, last_heartbeat)
                VALUES (?, ?, ?, NOW(), NOW())
            ");
            $ins->execute([$userId, $name, $avatar]);
        }
        echo json_encode(['status' => 'success']);
        exit;
    }

    // ── UPDATE VIEWER COUNT ─────────────────────────────────────────────────
    if ($action === 'update_viewers') {
        $count = max(0, (int) ($_REQUEST['count'] ?? 0));
        $stmt = $pdo->prepare("UPDATE live_streams SET viewer_count = ? WHERE user_id = ?");
        $stmt->execute([$count, $userId]);
        echo json_encode(['status' => 'success']);
        exit;
    }

    echo json_encode(['status' => 'error', 'message' => 'Unknown action']);

} catch (Throwable $e) {
    http_response_code(500);
    echo json_encode(['status' => 'error', 'message' => $e->getMessage()]);
}
?>