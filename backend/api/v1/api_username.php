<?php
/**
 * api_username.php
 * Handles unique username: check availability, get current, update (once per 30 days).
 */
require_once __DIR__ . '/db_connect.php';
require_once __DIR__ . '/auth_middleware.php';

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Content-Type, Authorization');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    echo json_encode(['success' => true]);
    exit;
}

if (!isset($pdo) || !($pdo instanceof PDO)) {
    http_response_code(500);
    echo json_encode(['success' => false, 'msg' => 'DB connection not available']);
    exit;
}

$authUser = requireUser($pdo);
$userId = (int) ($authUser['id'] ?? 0);
if (!$userId) {
    http_response_code(401);
    echo json_encode(['success' => false, 'msg' => 'Unauthorized']);
    exit;
}

$method = $_SERVER['REQUEST_METHOD'];

// ── Ensure columns exist ──────────────────────────────────────────────────────
try {
    $pdo->exec("ALTER TABLE users ADD COLUMN username VARCHAR(30) NULL UNIQUE");
} catch (Exception $e) {
}
try {
    $pdo->exec("ALTER TABLE users ADD COLUMN username_changed_at DATETIME NULL");
} catch (Exception $e) {
}

// ── GET: return current username + next-change date ──────────────────────────
if ($method === 'GET') {
    $row = $pdo->prepare("SELECT username, username_changed_at FROM users WHERE id=?");
    $row->execute([$userId]);
    $data = $row->fetch(PDO::FETCH_ASSOC);

    $changedAt = $data['username_changed_at'] ?? null;
    $canChangeAt = null;
    $canChange = true;
    $timeRemaining = null; // human-readable string e.g. "27 days, 3 hours"

    if ($changedAt) {
        $next = strtotime($changedAt . ' UTC') + (30 * 86400);
        if (time() < $next) {
            $canChange = false;
            $canChangeAt = gmdate('Y-m-d\TH:i:s\Z', $next);
            $secsLeft = $next - time();
            $daysLeft = (int) floor($secsLeft / 86400);
            $hoursLeft = (int) floor(($secsLeft % 86400) / 3600);
            if ($daysLeft > 0) {
                $timeRemaining = $daysLeft . ' day' . ($daysLeft !== 1 ? 's' : '')
                    . ($hoursLeft > 0 ? ', ' . $hoursLeft . ' hour' . ($hoursLeft !== 1 ? 's' : '') : '');
            } else {
                $minsLeft = (int) ceil($secsLeft / 60);
                $timeRemaining = $minsLeft . ' minute' . ($minsLeft !== 1 ? 's' : '');
            }
        }
    }

    echo json_encode([
        'success' => true,
        'username' => $data['username'] ?? null,
        'can_change' => $canChange,
        'can_change_at' => $canChangeAt,
        'time_remaining' => $timeRemaining, // null when can change freely
    ]);
    exit;
}

// ── POST: check availability or update ───────────────────────────────────────
if ($method === 'POST') {
    $in = json_decode(file_get_contents('php://input'), true) ?? [];
    if (!is_array($in)) {
        $in = [];
    }
    $in = array_merge($_POST, $in);

    $action = trim((string) ($in['action'] ?? ''));
    $username = strtolower(trim((string) ($in['username'] ?? '')));

    if ($action !== 'check' && $action !== 'update') {
        echo json_encode(['success' => false, 'msg' => 'Unknown action.']);
        exit;
    }

    // Validate format: 3-30 chars, letters/numbers/underscores only
    if (!preg_match('/^[a-z0-9_]{3,30}$/', $username)) {
        echo json_encode(['success' => false, 'msg' => 'Username must be 3–30 characters: letters, numbers, underscores only.']);
        exit;
    }

    // Reserved words
    $reserved = ['admin', 'support', 'help', 'goreto', 'system', 'mod', 'moderator', 'staff', 'official'];
    if (in_array($username, $reserved)) {
        echo json_encode(['success' => false, 'msg' => 'That username is reserved.']);
        exit;
    }

    // Check availability
    $chk = $pdo->prepare("SELECT id FROM users WHERE username=? AND id!=?");
    $chk->execute([$username, $userId]);
    $taken = $chk->fetch();

    if ($action === 'check') {
        echo json_encode(['success' => true, 'available' => !$taken]);
        exit;
    }

    if ($action === 'update') {
        if ($taken) {
            echo json_encode(['success' => false, 'msg' => 'Username already taken.']);
            exit;
        }

        // Enforce 30-day cooldown
        $cur = $pdo->prepare("SELECT username, username_changed_at FROM users WHERE id=?");
        $cur->execute([$userId]);
        $curData = $cur->fetch(PDO::FETCH_ASSOC);

        if ($curData['username_changed_at']) {
            $next = strtotime($curData['username_changed_at'] . ' UTC') + (30 * 86400);
            if (time() < $next) {
                $daysLeft = ceil(($next - time()) / 86400);
                echo json_encode(['success' => false, 'msg' => "You can change your username again in $daysLeft day(s)."]);
                exit;
            }
        }

        // Same username — no-op
        if ($curData['username'] === $username) {
            echo json_encode(['success' => true, 'msg' => 'Username unchanged.', 'username' => $username]);
            exit;
        }

        $upd = $pdo->prepare("UPDATE users SET username=?, username_changed_at=UTC_TIMESTAMP() WHERE id=?");
        $upd->execute([$username, $userId]);

        echo json_encode(['success' => true, 'msg' => 'Username updated!', 'username' => $username]);
        exit;
    }

    echo json_encode(['success' => false, 'msg' => 'Unknown action.']);
    exit;
}

echo json_encode(['success' => false, 'msg' => 'Method not allowed.']);
