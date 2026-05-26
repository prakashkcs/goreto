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

// ── PARSE JSON BODY (Dio sends application/json) ──
$contentType = $_SERVER['CONTENT_TYPE'] ?? '';
if (stripos($contentType, 'application/json') !== false) {
    $jsonBody = json_decode(file_get_contents('php://input'), true);
    if (is_array($jsonBody)) {
        $_POST = array_merge($_POST, $jsonBody);
        $_REQUEST = array_merge($_REQUEST, $jsonBody);
    }
}

require_once __DIR__ . '/db_connect.php';
require_once __DIR__ . '/auth_middleware.php';

// ── SELF-HEALING TABLES ──
try {
    $pdo->exec("CREATE TABLE IF NOT EXISTS proposals (
        id INT AUTO_INCREMENT PRIMARY KEY,
        sender_id INT NOT NULL,
        receiver_id INT NOT NULL,
        status VARCHAR(20) DEFAULT 'pending',
        show_on_profile TINYINT(1) DEFAULT 0,
        is_read TINYINT(1) DEFAULT 0,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        INDEX (sender_id),
        INDEX (receiver_id),
        INDEX (status)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;");

    $pdo->exec("CREATE TABLE IF NOT EXISTS user_blocks (
        id INT AUTO_INCREMENT PRIMARY KEY,
        blocker_id INT NOT NULL,
        blocked_id INT NOT NULL,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        UNIQUE KEY unique_block (blocker_id, blocked_id),
        INDEX (blocker_id),
        INDEX (blocked_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;");

    $pdo->exec("CREATE TABLE IF NOT EXISTS user_mutes (
        id INT AUTO_INCREMENT PRIMARY KEY,
        muter_id INT NOT NULL,
        muted_id INT NOT NULL,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        UNIQUE KEY unique_mute (muter_id, muted_id),
        INDEX (muter_id),
        INDEX (muted_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;");

    $pdo->exec("CREATE TABLE IF NOT EXISTS user_reports (
        id INT AUTO_INCREMENT PRIMARY KEY,
        reporter_id INT NOT NULL,
        reported_id INT NOT NULL,
        reason VARCHAR(100) NOT NULL,
        details TEXT,
        status ENUM('pending','reviewed','resolved','dismissed') DEFAULT 'pending',
        admin_notes TEXT,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        INDEX (reporter_id),
        INDEX (reported_id),
        INDEX (status)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;");
} catch (PDOException $e) { /* ignore */ }

try {
    $viewer = requireUser($pdo);
    $userId = (int)$viewer['id'];
    $action = $_REQUEST['action'] ?? '';

    // ════════════════════════════════════════════════════════
    //  SEND PROPOSAL
    // ════════════════════════════════════════════════════════
    if ($action === 'send_proposal') {
        $targetUserId = (int)($_POST['target_user_id'] ?? 0);
        if (!$targetUserId) {
            echo json_encode(['status' => 'error', 'message' => 'Missing target user']);
            exit;
        }

        // Check if already proposed
        $chkSt = $pdo->prepare("SELECT id, status FROM proposals WHERE sender_id = ? AND receiver_id = ?");
        $chkSt->execute([$userId, $targetUserId]);
        $existing = $chkSt->fetch(PDO::FETCH_ASSOC);
        
        if ($existing && $existing['status'] === 'pending') {
            echo json_encode(['status' => 'error', 'message' => 'Proposal already sent']);
            exit;
        }
        if ($existing && $existing['status'] === 'accepted') {
            echo json_encode(['status' => 'error', 'message' => 'Already connected']);
            exit;
        }

        // Check if the OTHER user already proposed to us (auto-match!)
        $reverseSt = $pdo->prepare("SELECT id FROM proposals WHERE sender_id = ? AND receiver_id = ? AND status = 'pending'");
        $reverseSt->execute([$targetUserId, $userId]);
        $reverseProposal = $reverseSt->fetch(PDO::FETCH_ASSOC);

        if ($reverseProposal) {
            // Auto-accept
            $pdo->prepare("UPDATE proposals SET status = 'accepted', updated_at = NOW() WHERE id = ?")->execute([$reverseProposal['id']]);
            
            if ($existing) {
                $pdo->prepare("UPDATE proposals SET status = 'accepted', updated_at = NOW() WHERE id = ?")->execute([$existing['id']]);
            } else {
                $pdo->prepare("INSERT INTO proposals (sender_id, receiver_id, status) VALUES (?, ?, 'accepted')")->execute([$userId, $targetUserId]);
            }
            
            $pdo->prepare("INSERT INTO messages (sender_id, receiver_id, type, content, status, created_at) VALUES (?, ?, 'system', '💕 You are now connected! Say hello.', 'sent', NOW())")->execute([$userId, $targetUserId]);

            // Sync counts
            $pdo->prepare("UPDATE users SET total_proposals = (SELECT COUNT(*) FROM proposals WHERE (sender_id = id OR receiver_id = id) AND status IN ('pending', 'accepted')) WHERE id IN (?, ?)")->execute([$userId, $targetUserId]);

            require_once __DIR__ . '/notification_helper.php';
            $meSt = $pdo->prepare("SELECT name FROM users WHERE id = ?");
            $meSt->execute([$userId]);
            $myName = $meSt->fetchColumn() ?: 'Someone';
            
            $targetSt = $pdo->prepare("SELECT name FROM users WHERE id = ?");
            $targetSt->execute([$targetUserId]);
            $targetName = $targetSt->fetchColumn() ?: 'someone';

            send_app_notification($pdo, $targetUserId, $userId, 'proposal_accepted', 'It\'s a Match! 💕', "$myName also likes you! Start chatting now.");
            send_app_notification($pdo, $userId, $targetUserId, 'proposal_accepted', 'It\'s a Match! 💕', "You and $targetName both like each other!");

            echo json_encode(['status' => 'success', 'message' => 'It\'s a mutual match!', 'matched' => true]);
        } else {
            if ($existing) {
                $pdo->prepare("UPDATE proposals SET status = 'pending', updated_at = NOW(), is_read = 0 WHERE id = ?")->execute([$existing['id']]);
            } else {
                $pdo->prepare("INSERT INTO proposals (sender_id, receiver_id, status) VALUES (?, ?, 'pending')")->execute([$userId, $targetUserId]);
            }

            $pdo->prepare("UPDATE users SET total_proposals = (SELECT COUNT(*) FROM proposals WHERE (sender_id = id OR receiver_id = id) AND status IN ('pending', 'accepted')) WHERE id = ?")->execute([$targetUserId]);

            require_once __DIR__ . '/notification_helper.php';
            $meSt = $pdo->prepare("SELECT name FROM users WHERE id = ?");
            $meSt->execute([$userId]);
            $myName = $meSt->fetchColumn() ?: 'Someone';

            send_app_notification($pdo, $targetUserId, $userId, 'proposal', 'New Proposal', "$myName sent you a proposal ❤️");

            echo json_encode(['status' => 'success', 'message' => 'Proposal sent successfully', 'matched' => false]);
        }
    }
    // ════════════════════════════════════════════════════════
    //  ACCEPT PROPOSAL
    // ════════════════════════════════════════════════════════
    elseif ($action === 'accept_proposal') {
        $proposalId = (int)($_POST['proposal_id'] ?? 0);
        $senderId = (int)($_POST['sender_id'] ?? 0);
        
        if (!$proposalId && !$senderId) {
            echo json_encode(['status' => 'error', 'message' => 'Missing proposal_id or sender_id']);
            exit;
        }

        if ($proposalId) {
            $pSt = $pdo->prepare("SELECT * FROM proposals WHERE id = ? AND receiver_id = ? AND status = 'pending'");
            $pSt->execute([$proposalId, $userId]);
        } else {
            $pSt = $pdo->prepare("SELECT * FROM proposals WHERE sender_id = ? AND receiver_id = ? AND status = 'pending'");
            $pSt->execute([$senderId, $userId]);
        }
        $proposal = $pSt->fetch(PDO::FETCH_ASSOC);

        if (!$proposal) {
            echo json_encode(['status' => 'error', 'message' => 'Proposal not found or already handled']);
            exit;
        }

        $pdo->prepare("UPDATE proposals SET status = 'accepted', updated_at = NOW() WHERE id = ?")->execute([$proposal['id']]);
        $sId = (int)$proposal['sender_id'];
        $pdo->prepare("INSERT INTO messages (sender_id, receiver_id, type, content, status, created_at) VALUES (?, ?, 'system', '💕 Proposal accepted! You are now connected.', 'sent', NOW())")->execute([$sId, $userId]);

        require_once __DIR__ . '/notification_helper.php';
        $meSt = $pdo->prepare("SELECT name FROM users WHERE id = ?");
        $meSt->execute([$userId]);
        $myName = $meSt->fetchColumn() ?: 'Someone';

        send_app_notification($pdo, $sId, $userId, 'proposal_accepted', 'Proposal Accepted! 💕', "$myName accepted your proposal! Start chatting now.");

        echo json_encode(['status' => 'success', 'message' => 'Proposal accepted', 'chat_with' => $sId]);
    }
    // ════════════════════════════════════════════════════════
    //  REJECT PROPOSAL
    // ════════════════════════════════════════════════════════
    elseif ($action === 'reject_proposal') {
        $proposalId = (int)($_POST['proposal_id'] ?? 0);
        $senderId = (int)($_POST['sender_id'] ?? 0);
        
        if ($proposalId) {
            $pdo->prepare("UPDATE proposals SET status = 'rejected', updated_at = NOW() WHERE id = ? AND receiver_id = ?")->execute([$proposalId, $userId]);
        } elseif ($senderId) {
            $pdo->prepare("UPDATE proposals SET status = 'rejected', updated_at = NOW() WHERE sender_id = ? AND receiver_id = ? AND status = 'pending'")->execute([$senderId, $userId]);
        }

        echo json_encode(['status' => 'success', 'message' => 'Proposal rejected']);
    }
    // ════════════════════════════════════════════════════════
    //  GET MY PROPOSALS (received, pending)
    // ════════════════════════════════════════════════════════
    elseif ($action === 'get_proposals') {
        $type = $_REQUEST['type'] ?? 'received';
        
        if ($type === 'received') {
            $stmt = $pdo->prepare("
                SELECT p.id as proposal_id, p.sender_id, p.status, p.created_at, p.show_on_profile, p.is_read,
                       u.name as sender_name, u.profile_pic as sender_avatar
                FROM proposals p
                JOIN users u ON u.id = p.sender_id
                WHERE p.receiver_id = ? AND p.status IN ('pending', 'accepted')
                ORDER BY p.status DESC, p.created_at DESC
            ");
            $stmt->execute([$userId]);
        } else {
            $stmt = $pdo->prepare("
                SELECT p.id as proposal_id, p.receiver_id, p.status, p.created_at, p.show_on_profile, p.is_read,
                       u.name as receiver_name, u.profile_pic as receiver_avatar
                FROM proposals p
                JOIN users u ON u.id = p.receiver_id
                WHERE p.sender_id = ? AND p.status IN ('pending', 'accepted')
                ORDER BY p.status DESC, p.created_at DESC
            ");
            $stmt->execute([$userId]);
        }
        
        $proposals = $stmt->fetchAll(PDO::FETCH_ASSOC);
        echo json_encode(['status' => 'success', 'proposals' => $proposals]);
    }
    // ════════════════════════════════════════════════════════
    //  GET CONNECTIONS
    // ════════════════════════════════════════════════════════
    elseif ($action === 'get_connections') {
        $stmt = $pdo->prepare("
            SELECT 
                p.id as proposal_id,
                p.show_on_profile,
                CASE WHEN p.sender_id = ? THEN p.receiver_id ELSE p.sender_id END as connected_user_id,
                p.updated_at as connected_at,
                u.name, u.profile_pic
            FROM proposals p
            JOIN users u ON u.id = CASE WHEN p.sender_id = ? THEN p.receiver_id ELSE p.sender_id END
            WHERE (p.sender_id = ? OR p.receiver_id = ?) AND p.status = 'accepted'
            ORDER BY p.updated_at DESC
        ");
        $stmt->execute([$userId, $userId, $userId, $userId]);
        $connections = $stmt->fetchAll(PDO::FETCH_ASSOC);
        echo json_encode(['status' => 'success', 'connections' => $connections]);
    }
    // ════════════════════════════════════════════════════════
    //  TOGGLE PROPOSAL PUBLIC VISIBILITY
    // ════════════════════════════════════════════════════════
    elseif ($action === 'toggle_public_proposal') {
        $proposalId = (int)($_POST['proposal_id'] ?? 0);
        $isPublic = isset($_POST['is_public']) && ($_POST['is_public'] === 'true' || $_POST['is_public'] === '1' || $_POST['is_public'] === true) ? 1 : 0;
        
        $stmt = $pdo->prepare("UPDATE proposals SET show_on_profile = ?, updated_at = NOW() WHERE id = ? AND (sender_id = ? OR receiver_id = ?) AND status = 'accepted'");
        $stmt->execute([$isPublic, $proposalId, $userId, $userId]);
        
        if ($stmt->rowCount() > 0) {
            echo json_encode(['status' => 'success', 'message' => 'Public visibility updated']);
        } else {
            echo json_encode(['status' => 'error', 'message' => 'Proposal not found or not accepted']);
        }
    }
    // ════════════════════════════════════════════════════════
    //  DISCONNECT
    // ════════════════════════════════════════════════════════
    elseif ($action === 'disconnect_proposal') {
        $targetId = (int)($_POST['target_user_id'] ?? 0);
        if (!$targetId) {
            echo json_encode(['status' => 'error', 'message' => 'Missing target_user_id']);
            exit;
        }

        $stmt = $pdo->prepare("UPDATE proposals SET status = 'disconnected', updated_at = NOW() WHERE ((sender_id = ? AND receiver_id = ?) OR (sender_id = ? AND receiver_id = ?)) AND status = 'accepted'");
        $stmt->execute([$userId, $targetId, $targetId, $userId]);
        
        $pdo->prepare("UPDATE users SET total_proposals = (SELECT COUNT(*) FROM proposals WHERE (sender_id = id OR receiver_id = id) AND status IN ('pending', 'accepted')) WHERE id IN (?, ?)")->execute([$userId, $targetId]);

        echo json_encode(['status' => 'success', 'message' => 'Disconnected successfully']);
    }
    // ════════════════════════════════════════════════════════
    //  GET BADGE COUNT
    // ════════════════════════════════════════════════════════
    elseif ($action === 'get_proposal_badge_count') {
        $stmt = $pdo->prepare("SELECT COUNT(*) FROM proposals WHERE receiver_id = ? AND status = 'pending' AND is_read = 0");
        $stmt->execute([$userId]);
        $count = $stmt->fetchColumn();
        echo json_encode(['status' => 'success', 'unread_count' => (int)$count]);
    }
    // ════════════════════════════════════════════════════════
    //  MARK READ
    // ════════════════════════════════════════════════════════
    elseif ($action === 'mark_proposals_read') {
        $pdo->prepare("UPDATE proposals SET is_read = 1 WHERE receiver_id = ? AND status = 'pending'")->execute([$userId]);
        echo json_encode(['status' => 'success']);
    }
    // ════════════════════════════════════════════════════════
    //  BLOCK USER
    // ════════════════════════════════════════════════════════
    elseif ($action === 'block_user') {
        $blockedId = (int)($_POST['blocked_id'] ?? 0);
        if ($blockedId) {
            $pdo->prepare("INSERT IGNORE INTO user_blocks (blocker_id, blocked_id) VALUES (?, ?)")->execute([$userId, $blockedId]);
            $pdo->prepare("UPDATE proposals SET status = 'rejected', updated_at = NOW() WHERE ((sender_id = ? AND receiver_id = ?) OR (sender_id = ? AND receiver_id = ?)) AND status = 'pending'")->execute([$userId, $blockedId, $blockedId, $userId]);
            echo json_encode(['status' => 'success', 'message' => 'User blocked']);
        }
    }
    // ════════════════════════════════════════════════════════
    //  UNBLOCK USER
    // ════════════════════════════════════════════════════════
    elseif ($action === 'unblock_user') {
        $blockedId = (int)($_POST['blocked_id'] ?? 0);
        if ($blockedId) {
            $pdo->prepare("DELETE FROM user_blocks WHERE blocker_id = ? AND blocked_id = ?")->execute([$userId, $blockedId]);
            echo json_encode(['status' => 'success', 'message' => 'User unblocked']);
        }
    }
    // ════════════════════════════════════════════════════════
    //  REPORT USER
    // ════════════════════════════════════════════════════════
    elseif ($action === 'report_user') {
        $targetId = (int)($_POST['target_user_id'] ?? 0);
        $reason = $_POST['reason'] ?? '';
        $details = $_POST['details'] ?? '';
        if ($targetId && $reason) {
            $pdo->prepare("INSERT INTO user_reports (reporter_id, reported_id, reason, details) VALUES (?, ?, ?, ?)")->execute([$userId, $targetId, $reason, $details]);
            echo json_encode(['status' => 'success', 'message' => 'Report submitted']);
        }
    }
    // ════════════════════════════════════════════════════════
    //  GET USER STATUS
    // ════════════════════════════════════════════════════════
    elseif ($action === 'get_user_status') {
        $targetId = (int)($_REQUEST['target_user_id'] ?? 0);
        
        $blockSt = $pdo->prepare("SELECT id FROM user_blocks WHERE blocker_id = ? AND blocked_id = ?");
        $blockSt->execute([$userId, $targetId]);
        $isBlocked = (bool)$blockSt->fetch();

        $muteSt = $pdo->prepare("SELECT id FROM user_mutes WHERE muter_id = ? AND muted_id = ?");
        $muteSt->execute([$userId, $targetId]);
        $isMuted = (bool)$muteSt->fetch();

        $propSt = $pdo->prepare("SELECT status FROM proposals WHERE ((sender_id = ? AND receiver_id = ?) OR (sender_id = ? AND receiver_id = ?)) AND status IN ('pending', 'accepted') ORDER BY updated_at DESC LIMIT 1");
        $propSt->execute([$userId, $targetId, $targetId, $userId]);
        $pStatus = $propSt->fetchColumn();
        
        echo json_encode([
            'status' => 'success',
            'is_blocked' => $isBlocked,
            'is_muted' => $isMuted,
            'is_proposal_connected' => ($pStatus === 'accepted'),
            'proposal_status' => $pStatus ?: 'none'
        ]);
    }
    else {
        echo json_encode(['status' => 'error', 'message' => 'Unknown action: ' . $action]);
    }
}
catch (Throwable $e) {
    http_response_code(500);
    echo json_encode(['status' => 'error', 'message' => $e->getMessage()]);
}
?>
