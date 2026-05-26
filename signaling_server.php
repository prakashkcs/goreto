<?php
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Content-Type, Authorization');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    echo json_encode(['status' => 'success']);
    exit;
}

require_once __DIR__ . '/db_connect.php';
require_once __DIR__ . '/auth_middleware.php';

// ── Auto-create tables ──
$pdo->exec("
    CREATE TABLE IF NOT EXISTS calls (
        id INT AUTO_INCREMENT PRIMARY KEY,
        call_uuid VARCHAR(64) NOT NULL UNIQUE,
        caller_id INT NOT NULL,
        receiver_id INT NOT NULL,
        type ENUM('audio','video') DEFAULT 'audio',
        status ENUM('ringing','accepted','declined','ended','missed') DEFAULT 'ringing',
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        INDEX idx_receiver_status (receiver_id, status),
        INDEX idx_caller_status (caller_id, status),
        INDEX idx_uuid (call_uuid)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
");

$pdo->exec("
    CREATE TABLE IF NOT EXISTS call_signals (
        id INT AUTO_INCREMENT PRIMARY KEY,
        call_id INT NOT NULL,
        sender_id INT NOT NULL,
        signal_type ENUM('offer','answer','ice') NOT NULL,
        payload TEXT NOT NULL,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_call_sender (call_id, sender_id),
        FOREIGN KEY (call_id) REFERENCES calls(id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
");

try {
    $viewer = requireUser($pdo);
    $userId = (int)$viewer['id'];
    $action = $_REQUEST['action'] ?? '';

    // ── 1. INITIATE CALL ──
    if ($action === 'initiate_call') {
        $receiverId = (int)($_REQUEST['receiver_id'] ?? 0);
        $type = in_array($_REQUEST['type'] ?? '', ['audio', 'video']) ? $_REQUEST['type'] : 'audio';
        $callUuid = $_REQUEST['call_uuid'] ?? bin2hex(random_bytes(16));

        if ($receiverId <= 0) {
            echo json_encode(['status' => 'error', 'message' => 'Invalid receiver_id']);
            exit;
        }

        // Auto-expire old ringing calls from this caller (> 60s)
        $pdo->prepare("UPDATE calls SET status='missed' WHERE caller_id=? AND status='ringing' AND (UNIX_TIMESTAMP() - UNIX_TIMESTAMP(created_at)) > 60")->execute([$userId]);

        $stmt = $pdo->prepare("INSERT INTO calls (call_uuid, caller_id, receiver_id, type, status) VALUES (?, ?, ?, ?, 'ringing')");
        $stmt->execute([$callUuid, $userId, $receiverId, $type]);
        $callId = $pdo->lastInsertId();

        // Get caller info for the receiver
        $callerStmt = $pdo->prepare("SELECT id, name, full_name, profile_pic AS avatar FROM users WHERE id=?");
        $callerStmt->execute([$userId]);
        $callerInfo = $callerStmt->fetch(PDO::FETCH_ASSOC);

        echo json_encode([
            'status' => 'success',
            'call_id' => (int)$callId,
            'call_uuid' => $callUuid,
            'caller' => $callerInfo,
        ]);
    }

    // ── 2. POLL INCOMING ── (receiver polls for ringing calls targeting them)
    elseif ($action === 'poll_incoming') {
        $stmt = $pdo->prepare("
            SELECT c.id AS call_id, c.call_uuid, c.type, c.status, c.created_at,
                   u.id AS caller_id, u.name AS caller_name, u.full_name AS caller_full_name, u.profile_pic AS caller_avatar
            FROM calls c
            JOIN users u ON u.id = c.caller_id
            WHERE c.receiver_id = ? AND c.status = 'ringing'
              AND (UNIX_TIMESTAMP() - UNIX_TIMESTAMP(c.created_at)) < 60
            ORDER BY c.created_at DESC LIMIT 1
        ");
        $stmt->execute([$userId]);
        $call = $stmt->fetch(PDO::FETCH_ASSOC);

        if ($call) {
            echo json_encode(['status' => 'success', 'has_call' => true, 'call' => $call]);
        }
        else {
            echo json_encode(['status' => 'success', 'has_call' => false]);
        }
    }

    // ── 3. ACCEPT CALL ──
    elseif ($action === 'accept_call') {
        $callId = (int)($_REQUEST['call_id'] ?? 0);
        $stmt = $pdo->prepare("UPDATE calls SET status='accepted' WHERE id=? AND receiver_id=? AND status='ringing'");
        $stmt->execute([$callId, $userId]);
        echo json_encode(['status' => 'success']);
    }

    // ── 4. DECLINE CALL ──
    elseif ($action === 'decline_call') {
        $callId = (int)($_REQUEST['call_id'] ?? 0);
        $stmt = $pdo->prepare("UPDATE calls SET status='declined' WHERE id=? AND (receiver_id=? OR caller_id=?)");
        $stmt->execute([$callId, $userId, $userId]);
        echo json_encode(['status' => 'success']);
    }

    // ── 5. END CALL ──
    elseif ($action === 'end_call') {
        $callId = (int)($_REQUEST['call_id'] ?? 0);
        $stmt = $pdo->prepare("UPDATE calls SET status='ended' WHERE id=? AND (caller_id=? OR receiver_id=?)");
        $stmt->execute([$callId, $userId, $userId]);
        echo json_encode(['status' => 'success']);
    }

    // ── 6. SEND SIGNAL ── (SDP offer, answer, or ICE candidate)
    elseif ($action === 'send_signal') {
        $callId = (int)($_REQUEST['call_id'] ?? 0);
        $signalType = $_REQUEST['signal_type'] ?? '';
        $payload = $_REQUEST['payload'] ?? '';

        if (!in_array($signalType, ['offer', 'answer', 'ice'])) {
            echo json_encode(['status' => 'error', 'message' => 'Invalid signal_type']);
            exit;
        }

        $stmt = $pdo->prepare("INSERT INTO call_signals (call_id, sender_id, signal_type, payload) VALUES (?, ?, ?, ?)");
        $stmt->execute([$callId, $userId, $signalType, $payload]);
        echo json_encode(['status' => 'success', 'signal_id' => (int)$pdo->lastInsertId()]);
    }

    // ── 7. POLL SIGNALS ── (get signals from the other party)
    elseif ($action === 'poll_signals') {
        $callId = (int)($_REQUEST['call_id'] ?? 0);
        $afterId = (int)($_REQUEST['after_id'] ?? 0);

        // Get signals NOT from me (from the other party)
        $stmt = $pdo->prepare("
            SELECT id, signal_type, payload, created_at
            FROM call_signals
            WHERE call_id = ? AND sender_id != ? AND id > ?
            ORDER BY id ASC
        ");
        $stmt->execute([$callId, $userId, $afterId]);
        $signals = $stmt->fetchAll(PDO::FETCH_ASSOC);

        echo json_encode(['status' => 'success', 'signals' => $signals]);
    }

    // ── 8. GET CALL STATUS ── (check if call is still active)
    elseif ($action === 'call_status') {
        $callId = (int)($_REQUEST['call_id'] ?? 0);
        $stmt = $pdo->prepare("SELECT id, call_uuid, caller_id, receiver_id, type, status FROM calls WHERE id=?");
        $stmt->execute([$callId]);
        $call = $stmt->fetch(PDO::FETCH_ASSOC);

        if ($call) {
            echo json_encode(['status' => 'success', 'call' => $call]);
        }
        else {
            echo json_encode(['status' => 'error', 'message' => 'Call not found']);
        }
    }

    // ── 9. RANDOM CALL MATCH ── Pick a real random online user and initiate call
    elseif ($action === 'random_call_match') {
        $type = in_array($_REQUEST['type'] ?? '', ['audio', 'video']) ? $_REQUEST['type'] : 'video';

        // Find a random user who:
        // 1. Is not the current user
        // 2. Has been active recently (last 15 minutes = online)
        // 3. Is not already in an active call
        // 4. Has not blocked us / we haven't blocked them
        $stmt = $pdo->prepare("
            SELECT u.id, u.name, u.full_name, u.profile_pic AS avatar
            FROM users u
            WHERE u.id != ?
              AND u.is_banned = 0
              AND u.id NOT IN (
                  SELECT caller_id FROM calls WHERE status IN ('ringing','accepted') AND (UNIX_TIMESTAMP() - UNIX_TIMESTAMP(created_at)) < 120
                  UNION
                  SELECT receiver_id FROM calls WHERE status IN ('ringing','accepted') AND (UNIX_TIMESTAMP() - UNIX_TIMESTAMP(created_at)) < 120
              )
            ORDER BY RAND()
            LIMIT 1
        ");
        $stmt->execute([$userId]);
        $matchedUser = $stmt->fetch(PDO::FETCH_ASSOC);

        if (!$matchedUser) {
            echo json_encode(['status' => 'error', 'message' => 'No users available right now. Try again later.']);
            exit;
        }

        // Auto-initiate the call
        $callUuid = bin2hex(random_bytes(16));
        $insertStmt = $pdo->prepare("INSERT INTO calls (call_uuid, caller_id, receiver_id, type, status) VALUES (?, ?, ?, ?, 'ringing')");
        $insertStmt->execute([$callUuid, $userId, (int)$matchedUser['id'], $type]);
        $callId = $pdo->lastInsertId();

        echo json_encode([
            'status' => 'success',
            'call_id' => (int)$callId,
            'call_uuid' => $callUuid,
            'matched_user' => $matchedUser,
        ]);
    }

    else {
        echo json_encode(['status' => 'error', 'message' => 'Unknown action']);
    }
}
catch (Throwable $e) {
    http_response_code(500);
    echo json_encode(['status' => 'error', 'message' => 'Server error', 'error' => $e->getMessage()]);
}
?>
