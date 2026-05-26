<?php
// user_actions.php — Proposal system + user relationship actions
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

// ── Auto-create proposals table ──
$pdo->exec("
    CREATE TABLE IF NOT EXISTS proposals (
        id INT AUTO_INCREMENT PRIMARY KEY,
        sender_id INT NOT NULL,
        receiver_id INT NOT NULL,
        status ENUM('pending','accepted','rejected','disconnected') DEFAULT 'pending',
        show_on_profile TINYINT(1) DEFAULT 1,
        is_read TINYINT(1) DEFAULT 0,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        UNIQUE KEY unique_pair (sender_id, receiver_id),
        INDEX idx_receiver (receiver_id, status),
        INDEX idx_sender (sender_id, status)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
");

// Match the rest of the backend, which uses user_blocks consistently.
$pdo->exec("
    CREATE TABLE IF NOT EXISTS user_blocks (
        id INT AUTO_INCREMENT PRIMARY KEY,
        blocker_id INT NOT NULL,
        blocked_id INT NOT NULL,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        UNIQUE KEY unique_block (blocker_id, blocked_id),
        INDEX idx_blocker (blocker_id),
        INDEX idx_blocked (blocked_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
");

// Helper: send FCM notification
function sendFcmNotification($pdo, $targetUserId, $title, $body, $data = [])
{
    $stmt = $pdo->prepare("SELECT fcm_token FROM users WHERE id = ? AND is_banned = 0");
    $stmt->execute([$targetUserId]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);
    if (!$row || empty($row['fcm_token']))
        return false;

    $serviceAccountPath = __DIR__ . '/service_account.json';
    if (!file_exists($serviceAccountPath))
        return false;

    require_once __DIR__ . '/fcm_v1.php';
    $jsonAccount = json_decode(file_get_contents($serviceAccountPath), true);
    $projectId = $jsonAccount['project_id'] ?? '';
    if (empty($projectId))
        return false;

    try {
        $fcmClient = new PushNotificationFCM($serviceAccountPath);
        $fcmClient->sendDataMessage($row['fcm_token'], $projectId, array_merge([
            'title' => $title,
            'body' => $body,
        ], $data), ['title' => $title, 'body' => $body]);
        return true;
    } catch (Throwable $e) {
        return false;
    }
}

// Insert notification row
function insertNotification($pdo, $userId, $fromUserId, $type, $message)
{
    try {
        $stmt = $pdo->prepare("
            INSERT INTO notifications (user_id, from_user_id, type, message, is_read, created_at)
            VALUES (?, ?, ?, ?, 0, NOW())
        ");
        $stmt->execute([$userId, $fromUserId, $type, $message]);
    } catch (Throwable $e) {
        // notifications table may not exist — ignore
    }
}

try {
    $viewer = requireUser($pdo);
    $userId = (int) $viewer['id'];
    $action = $_REQUEST['action'] ?? $_POST['action'] ?? '';

    // ── SEND PROPOSAL ──
    if ($action === 'send_proposal') {
        $targetId = (int) ($_POST['target_user_id'] ?? 0);
        if ($targetId <= 0 || $targetId === $userId) {
            echo json_encode(['status' => 'error', 'message' => 'Invalid target']);
            exit;
        }

        // Check if reverse proposal exists (mutual match)
        $reverseStmt = $pdo->prepare("SELECT id, status FROM proposals WHERE sender_id = ? AND receiver_id = ?");
        $reverseStmt->execute([$targetId, $userId]);
        $reverse = $reverseStmt->fetch(PDO::FETCH_ASSOC);

        if ($reverse && $reverse['status'] === 'pending') {
            // Mutual match — accept both
            $pdo->prepare("UPDATE proposals SET status='accepted', updated_at=NOW() WHERE id=?")->execute([$reverse['id']]);
            // Insert or update our side
            $pdo->prepare("
                INSERT INTO proposals (sender_id, receiver_id, status) VALUES (?, ?, 'accepted')
                ON DUPLICATE KEY UPDATE status='accepted', updated_at=NOW()
            ")->execute([$userId, $targetId]);

            // Sync total_proposals for both
            $pdo->prepare("UPDATE users SET total_proposals = (SELECT COUNT(*) FROM proposals WHERE (sender_id=users.id OR receiver_id=users.id) AND status='accepted') WHERE id IN (?,?)")->execute([$userId, $targetId]);

            // Get sender info for notification
            $senderStmt = $pdo->prepare("SELECT name, full_name FROM users WHERE id=?");
            $senderStmt->execute([$userId]);
            $senderInfo = $senderStmt->fetch(PDO::FETCH_ASSOC);
            $senderName = $senderInfo['full_name'] ?? $senderInfo['name'] ?? 'Someone';

            // Notify both users of mutual match
            insertNotification($pdo, $targetId, $userId, 'proposal_match', "$senderName accepted your proposal! 💕");
            insertNotification($pdo, $userId, $targetId, 'proposal_match', "It's a match! 💕");
            sendFcmNotification($pdo, $targetId, "It's a Match! 💕", "$senderName liked you back!", ['action' => 'proposal_match', 'user_id' => (string) $userId]);

            echo json_encode(['status' => 'success', 'matched' => true]);
            exit;
        }

        // Insert new proposal
        $stmt = $pdo->prepare("
            INSERT INTO proposals (sender_id, receiver_id, status) VALUES (?, ?, 'pending')
            ON DUPLICATE KEY UPDATE status='pending', is_read=0, updated_at=NOW()
        ");
        $stmt->execute([$userId, $targetId]);

        // Get sender info
        $senderStmt = $pdo->prepare("SELECT name, full_name FROM users WHERE id=?");
        $senderStmt->execute([$userId]);
        $senderInfo = $senderStmt->fetch(PDO::FETCH_ASSOC);
        $senderName = $senderInfo['full_name'] ?? $senderInfo['name'] ?? 'Someone';

        // Insert notification row
        insertNotification($pdo, $targetId, $userId, 'proposal', "$senderName sent you a proposal 🌹");

        // Send FCM push to receiver
        sendFcmNotification($pdo, $targetId, 'New Proposal 🌹', "$senderName sent you a proposal!", [
            'action' => 'new_proposal',
            'user_id' => (string) $userId,
        ]);

        echo json_encode(['status' => 'success', 'matched' => false]);
    }

    // ── ACCEPT PROPOSAL ──
    elseif ($action === 'accept_proposal') {
        $proposalId = (int) ($_POST['proposal_id'] ?? 0);
        $senderId = (int) ($_POST['sender_id'] ?? 0);

        if ($proposalId > 0) {
            $stmt = $pdo->prepare("UPDATE proposals SET status='accepted', updated_at=NOW() WHERE id=? AND receiver_id=?");
            $stmt->execute([$proposalId, $userId]);
        } elseif ($senderId > 0) {
            $stmt = $pdo->prepare("UPDATE proposals SET status='accepted', updated_at=NOW() WHERE sender_id=? AND receiver_id=?");
            $stmt->execute([$senderId, $userId]);
        } else {
            echo json_encode(['status' => 'error', 'message' => 'Missing proposal_id or sender_id']);
            exit;
        }

        // Sync total_proposals
        $pdo->prepare("UPDATE users SET total_proposals = (SELECT COUNT(*) FROM proposals WHERE (sender_id=users.id OR receiver_id=users.id) AND status='accepted') WHERE id IN (?,?)")->execute([$userId, $senderId ?: $userId]);

        // Notify the original sender
        if ($senderId > 0) {
            $acceptorStmt = $pdo->prepare("SELECT name, full_name FROM users WHERE id=?");
            $acceptorStmt->execute([$userId]);
            $acceptorInfo = $acceptorStmt->fetch(PDO::FETCH_ASSOC);
            $acceptorName = $acceptorInfo['full_name'] ?? $acceptorInfo['name'] ?? 'Someone';

            insertNotification($pdo, $senderId, $userId, 'proposal_accepted', "$acceptorName accepted your proposal! 💕");
            sendFcmNotification($pdo, $senderId, "Proposal Accepted! 💕", "$acceptorName accepted your proposal!", [
                'action' => 'proposal_accepted',
                'user_id' => (string) $userId,
            ]);
        }

        echo json_encode(['status' => 'success']);
    }

    // ── REJECT PROPOSAL ──
    elseif ($action === 'reject_proposal') {
        $proposalId = (int) ($_POST['proposal_id'] ?? 0);
        $senderId = (int) ($_POST['sender_id'] ?? 0);

        if ($proposalId > 0) {
            $pdo->prepare("UPDATE proposals SET status='rejected', updated_at=NOW() WHERE id=? AND receiver_id=?")->execute([$proposalId, $userId]);
        } elseif ($senderId > 0) {
            $pdo->prepare("UPDATE proposals SET status='rejected', updated_at=NOW() WHERE sender_id=? AND receiver_id=?")->execute([$senderId, $userId]);
        } else {
            echo json_encode(['status' => 'error', 'message' => 'Missing proposal_id or sender_id']);
            exit;
        }

        echo json_encode(['status' => 'success']);
    }

    // ── GET PROPOSALS ──
    elseif ($action === 'get_proposals') {
        $type = $_POST['type'] ?? 'received'; // 'received' or 'sent'

        if ($type === 'received') {
            $stmt = $pdo->prepare("
                SELECT p.id, p.sender_id, p.status, p.is_read, p.created_at,
                       u.name, u.full_name, u.profile_pic AS avatar, u.age, u.city
                FROM proposals p
                JOIN users u ON u.id = p.sender_id
                WHERE p.receiver_id = ? AND p.status IN ('pending','accepted')
                ORDER BY p.created_at DESC
                LIMIT 100
            ");
            $stmt->execute([$userId]);
        } else {
            $stmt = $pdo->prepare("
                SELECT p.id, p.receiver_id, p.status, p.is_read, p.created_at,
                       u.name, u.full_name, u.profile_pic AS avatar, u.age, u.city
                FROM proposals p
                JOIN users u ON u.id = p.receiver_id
                WHERE p.sender_id = ? AND p.status IN ('pending','accepted')
                ORDER BY p.created_at DESC
                LIMIT 100
            ");
            $stmt->execute([$userId]);
        }

        $proposals = $stmt->fetchAll(PDO::FETCH_ASSOC);
        echo json_encode(['status' => 'success', 'proposals' => $proposals]);
    }

    // ── GET PROPOSAL BADGE COUNT ──
    elseif ($action === 'get_proposal_badge_count') {
        $stmt = $pdo->prepare("SELECT COUNT(*) AS cnt FROM proposals WHERE receiver_id=? AND status='pending' AND is_read=0");
        $stmt->execute([$userId]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);
        echo json_encode(['status' => 'success', 'count' => (int) ($row['cnt'] ?? 0)]);
    }

    // ── GET ACCEPTED CONNECTIONS ──
    // Only show connections where BOTH sides have an accepted proposal row
    // (i.e. a true mutual match), and include gender for pronoun logic.
    elseif ($action === 'get_connections') {
        $stmt = $pdo->prepare("
            SELECT
                p.id AS proposal_id,
                p.show_on_profile,
                p.created_at,
                CASE WHEN p.sender_id = ? THEN p.receiver_id ELSE p.sender_id END AS connected_user_id,
                -- Aliases expected by the Flutter app
                COALESCE(u.full_name, u.name, 'User') AS partner_name,
                COALESCE(u.full_name, u.name, 'User') AS connected_user_name,
                u.profile_pic AS partner_avatar,
                u.profile_pic AS connected_user_avatar,
                u.gender AS partner_gender,
                u.gender,
                u.age,
                u.city,
                1 AS both_connected
            FROM proposals p
            JOIN users u
              ON u.id = CASE WHEN p.sender_id = ? THEN p.receiver_id ELSE p.sender_id END
            WHERE (p.sender_id = ? OR p.receiver_id = ?)
              AND p.status = 'accepted'
              AND EXISTS (
                  SELECT 1 FROM proposals p2
                  WHERE p2.sender_id = (CASE WHEN p.sender_id = ? THEN p.receiver_id ELSE p.sender_id END)
                    AND p2.receiver_id = ?
                    AND p2.status = 'accepted'
              )
            ORDER BY p.updated_at DESC, p.created_at DESC
            LIMIT 100
        ");
        $stmt->execute([$userId, $userId, $userId, $userId, $userId, $userId]);
        $connections = $stmt->fetchAll(PDO::FETCH_ASSOC);
        echo json_encode(['status' => 'success', 'connections' => $connections]);
    }

    // ── MARK PROPOSALS READ ──
    elseif ($action === 'mark_proposals_read') {
        $pdo->prepare("UPDATE proposals SET is_read=1 WHERE receiver_id=? AND is_read=0")->execute([$userId]);
        echo json_encode(['status' => 'success']);
    }

    // ── DISCONNECT PROPOSAL ──
    elseif ($action === 'disconnect_proposal') {
        $targetId = (int) ($_POST['target_user_id'] ?? 0);
        if ($targetId <= 0) {
            echo json_encode(['status' => 'error', 'message' => 'Invalid target']);
            exit;
        }

        $pdo->beginTransaction();
        $pdo->prepare("UPDATE proposals SET status='disconnected', show_on_profile=0 WHERE ((sender_id=? AND receiver_id=?) OR (sender_id=? AND receiver_id=?)) AND status IN ('accepted','pending')")->execute([$userId, $targetId, $targetId, $userId]);
        $pdo->prepare("UPDATE users SET total_proposals = (SELECT COUNT(*) FROM proposals WHERE (sender_id=users.id OR receiver_id=users.id) AND status IN ('pending','accepted')) WHERE id IN (?,?)")->execute([$userId, $targetId]);
        $pdo->commit();

        echo json_encode(['status' => 'success', 'message' => 'Disconnected']);
    }

    // ── TOGGLE PUBLIC PROPOSAL ──
    elseif ($action === 'toggle_public_proposal') {
        $proposalId = (int) ($_POST['proposal_id'] ?? 0);
        $isPublic = (int) ($_POST['is_public'] ?? 0);
        $pdo->prepare("UPDATE proposals SET show_on_profile=? WHERE id=? AND (sender_id=? OR receiver_id=?)")->execute([$isPublic, $proposalId, $userId, $userId]);
        echo json_encode(['status' => 'success']);
    }

    // ── GET USER ACTION STATUS ──
    elseif ($action === 'get_user_action_status') {
        $targetId = (int) ($_POST['target_user_id'] ?? $_GET['target_user_id'] ?? 0);
        if ($targetId <= 0) {
            echo json_encode(['status' => 'error', 'message' => 'Invalid target']);
            exit;
        }

        // Check block
        $blockStmt = $pdo->prepare("SELECT id FROM user_blocks WHERE (blocker_id=? AND blocked_id=?) OR (blocker_id=? AND blocked_id=?) LIMIT 1");
        $blockStmt->execute([$userId, $targetId, $targetId, $userId]);
        $isBlocked = (bool) $blockStmt->fetch();

        // Check mute
        $muteStmt = $pdo->prepare("SELECT id FROM mutes WHERE muter_id=? AND muted_id=? LIMIT 1");
        $muteStmt->execute([$userId, $targetId]);
        $isMuted = (bool) $muteStmt->fetch();

        // Check proposal connection
        $propStmt = $pdo->prepare("SELECT id FROM proposals WHERE ((sender_id=? AND receiver_id=?) OR (sender_id=? AND receiver_id=?)) AND status='accepted' LIMIT 1");
        $propStmt->execute([$userId, $targetId, $targetId, $userId]);
        $isConnected = (bool) $propStmt->fetch();

        // Get target name
        $nameStmt = $pdo->prepare("SELECT name, full_name FROM users WHERE id=?");
        $nameStmt->execute([$targetId]);
        $nameRow = $nameStmt->fetch(PDO::FETCH_ASSOC);

        echo json_encode([
            'status' => 'success',
            'is_blocked' => $isBlocked,
            'is_muted' => $isMuted,
            'is_proposal_connected' => $isConnected,
            'target_name' => $nameRow['full_name'] ?? $nameRow['name'] ?? '',
        ]);
    }

    // ── MUTE USER ──
    elseif ($action === 'mute_user') {
        $targetId = (int) ($_POST['target_user_id'] ?? 0);
        if ($targetId <= 0) {
            echo json_encode(['status' => 'error', 'message' => 'Invalid target']);
            exit;
        }
        try {
            $pdo->exec("CREATE TABLE IF NOT EXISTS mutes (id INT AUTO_INCREMENT PRIMARY KEY, muter_id INT NOT NULL, muted_id INT NOT NULL, created_at DATETIME DEFAULT CURRENT_TIMESTAMP, UNIQUE KEY unique_mute (muter_id, muted_id)) ENGINE=InnoDB");
            $pdo->prepare("INSERT IGNORE INTO mutes (muter_id, muted_id) VALUES (?,?)")->execute([$userId, $targetId]);
        } catch (Throwable $e) {
        }
        echo json_encode(['status' => 'success']);
    }

    // ── LEGACY DISCONNECT (kept for backward compat) ──
    elseif ($action === 'disconnect') {
        $senderId = (int) ($_POST['sender_id'] ?? 0);
        $targetId = (int) ($_POST['target_user_id'] ?? 0);
        if ($senderId <= 0 || $targetId <= 0) {
            echo json_encode(['status' => 'error', 'message' => 'Invalid user IDs']);
            exit;
        }
        $pdo->beginTransaction();
        $pdo->prepare("UPDATE proposals SET status='disconnected', show_on_profile=0 WHERE ((sender_id=? AND receiver_id=?) OR (sender_id=? AND receiver_id=?)) AND status IN ('accepted','pending')")->execute([$senderId, $targetId, $targetId, $senderId]);
        $pdo->prepare("UPDATE users SET total_proposals = (SELECT COUNT(*) FROM proposals WHERE (sender_id=users.id OR receiver_id=users.id) AND status IN ('pending','accepted')) WHERE id IN (?,?)")->execute([$senderId, $targetId]);
        $pdo->commit();
        echo json_encode(['status' => 'success', 'message' => 'Disconnected successfully']);

        // ── SUBMIT KYC (proxy to kyc.php logic) ──
    } elseif ($action === 'submit_kyc') {
        $level = strtolower(trim((string) ($_POST['level'] ?? 'basic')));
        if ($level !== 'basic' && $level !== 'full')
            $level = 'basic';
        $fullName = trim((string) ($_POST['full_name'] ?? ''));
        $taskId = (int) ($_POST['task_id'] ?? 0);

        // Ensure user_kyc row exists
        $pdo->prepare("INSERT IGNORE INTO user_kyc (user_id, basic_status, full_status) VALUES (?, 'none', 'none')")->execute([$userId]);

        // Handle video upload
        $videoUrl = null;
        if (!empty($_FILES['video']['tmp_name']) && is_uploaded_file($_FILES['video']['tmp_name'])) {
            $dir = __DIR__ . '/uploads/kyc/';
            if (!is_dir($dir))
                @mkdir($dir, 0777, true);
            $ext = pathinfo((string) $_FILES['video']['name'], PATHINFO_EXTENSION);
            $ext = $ext ? '.' . preg_replace('/[^a-zA-Z0-9]/', '', $ext) : '.mp4';
            $fname = uniqid('kyc_', true) . $ext;
            if (move_uploaded_file($_FILES['video']['tmp_name'], $dir . $fname)) {
                $videoUrl = '/api/v1/uploads/kyc/' . $fname;
            }
        }
        if (!$videoUrl) {
            echo json_encode(['status' => 'error', 'message' => 'video file required (field name: video)']);
            exit;
        }
        if ($taskId <= 0) {
            echo json_encode(['status' => 'error', 'message' => 'task_id required']);
            exit;
        }

        $pdo->prepare("INSERT INTO kyc_submissions (user_id, level, task_id, full_name, video_url, status) VALUES (?,?,?,?,?,'pending')")
            ->execute([$userId, $level, $taskId, $fullName, $videoUrl]);

        if ($level === 'basic') {
            $pdo->prepare("UPDATE user_kyc SET basic_status='pending', full_name=?, basic_video_url=?, basic_task_id=?, basic_submitted_at=NOW() WHERE user_id=?")
                ->execute([$fullName, $videoUrl, $taskId, $userId]);
        } else {
            $pdo->prepare("UPDATE user_kyc SET full_status='pending', full_video_url=?, full_task_id=?, full_submitted_at=NOW() WHERE user_id=?")
                ->execute([$videoUrl, $taskId, $userId]);
        }
        echo json_encode(['status' => 'success', 'message' => ucfirst($level) . ' KYC submitted', 'video_url' => $videoUrl]);

        // ── CANCEL KYC ──
    } elseif ($action === 'cancel_kyc') {
        $level = strtolower(trim((string) ($_POST['level'] ?? 'basic')));
        if ($level !== 'basic' && $level !== 'full')
            $level = 'basic';
        if ($level === 'basic') {
            $pdo->prepare("UPDATE user_kyc SET basic_status='none' WHERE user_id=? AND basic_status='pending'")->execute([$userId]);
        } else {
            $pdo->prepare("UPDATE user_kyc SET full_status='none' WHERE user_id=? AND full_status='pending'")->execute([$userId]);
        }
        echo json_encode(['status' => 'success', 'message' => 'KYC cancelled']);

    } else {
        echo json_encode(['status' => 'error', 'message' => 'Unknown action: ' . $action]);
    }

} catch (Throwable $e) {
    http_response_code(500);
    echo json_encode(['status' => 'error', 'message' => 'Server error', 'error' => $e->getMessage()]);
}
?>