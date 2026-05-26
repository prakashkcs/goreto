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
    //  SUBMIT KYC
    // ════════════════════════════════════════════════════════
    if ($action === 'submit_kyc') {
        $firstName = $_POST['first_name'] ?? '';
        $lastName = $_POST['last_name'] ?? '';

        $uploadDir = __DIR__ . '/uploads/kyc/';
        if (!is_dir($uploadDir)) {
            @mkdir($uploadDir, 0777, true);
        }

        $baseUrl = 'https://coinzop.com/ekloadmin/api/v1/uploads/kyc/';

        $errors = [];
        function uploadFileInternal($fileKey, $prefix, $uploadDir, $baseUrl, &$errors)
        {
            if (!isset($_FILES[$fileKey])) {
                $errors[$fileKey] = "File not sent";
                return '';
            }
            if ($_FILES[$fileKey]['error'] != 0) {
                $errors[$fileKey] = "PHP Upload Error Code: " . $_FILES[$fileKey]['error'];
                return '';
            }
            
            $ext = pathinfo($_FILES[$fileKey]['name'], PATHINFO_EXTENSION);
            if (empty($ext)) $ext = 'jpg';
            $filename = uniqid($prefix) . '.' . $ext;
            if (move_uploaded_file($_FILES[$fileKey]['tmp_name'], $uploadDir . $filename)) {
                return $baseUrl . $filename;
            } else {
                $errors[$fileKey] = "Failed to move_uploaded_file to $uploadDir";
                return '';
            }
        }

        $idFrontUrl = uploadFileInternal('id_front', 'front_', $uploadDir, $baseUrl, $errors);
        $idBackUrl = uploadFileInternal('id_back', 'back_', $uploadDir, $baseUrl, $errors);
        $selfieUrl = uploadFileInternal('selfie', 'selfie_', $uploadDir, $baseUrl, $errors);
        $livenessUrl = uploadFileInternal('liveness_video', 'video_', $uploadDir, $baseUrl, $errors);

        if (!empty($errors)) {
            echo json_encode(['status' => 'error', 'message' => 'Failed to upload required files.', 'details' => $errors]);
            exit;
        }

        $checkStmt = $pdo->prepare('SELECT id FROM kyc_verifications WHERE user_id = ?');
        $checkStmt->execute([$userId]);
        $existing = $checkStmt->fetch(PDO::FETCH_ASSOC);

        if ($existing) {
            $updateStmt = $pdo->prepare('UPDATE kyc_verifications SET first_name=?, last_name=?, id_front=?, id_back=?, selfie_pic=?, liveness_video=?, status=?, submitted_at=NOW() WHERE user_id=?');
            $updateStmt->execute([$firstName, $lastName, $idFrontUrl, $idBackUrl, $selfieUrl, $livenessUrl, 'pending', $userId]);
        }
        else {
            $insertStmt = $pdo->prepare('INSERT INTO kyc_verifications (user_id, first_name, last_name, id_front, id_back, selfie_pic, liveness_video, status, submitted_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, NOW())');
            $insertStmt->execute([$userId, $firstName, $lastName, $idFrontUrl, $idBackUrl, $selfieUrl, $livenessUrl, 'pending']);
        }

        $pdo->prepare('UPDATE users SET full_name=?, kyc_status=? WHERE id=?')->execute([$firstName . ' ' . $lastName, 'pending', $userId]);

        echo json_encode(['status' => 'success', 'message' => 'KYC Submitted successfully']);
    }
    // ════════════════════════════════════════════════════════
    //  CANCEL KYC
    // ════════════════════════════════════════════════════════
    elseif ($action === 'cancel_kyc') {
        $pdo->prepare("DELETE FROM kyc_verifications WHERE user_id=? AND status='pending'")->execute([$userId]);
        $pdo->prepare("UPDATE users SET kyc_status='unverified' WHERE id=?")->execute([$userId]);
        echo json_encode(['status' => 'success', 'message' => 'KYC cancelled successfully']);
    }
    // ════════════════════════════════════════════════════════
    //  SEND PROPOSAL
    // ════════════════════════════════════════════════════════
    elseif ($action === 'send_proposal') {
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
            // Auto-accept: both want each other
            $pdo->prepare("UPDATE proposals SET status = 'accepted', updated_at = NOW() WHERE id = ?")->execute([$reverseProposal['id']]);
            
            // Also insert our proposal as accepted
            $pdo->prepare("INSERT INTO proposals (sender_id, receiver_id, status) VALUES (?, ?, 'accepted')")->execute([$userId, $targetUserId]);
            
            // Create chat connection (system message)
            $pdo->prepare("INSERT INTO messages (sender_id, receiver_id, type, content, status, created_at) VALUES (?, ?, 'system', '💕 You are now connected! Say hello.', 'sent', NOW())")->execute([$userId, $targetUserId]);

            // Increment proposals count
            $pdo->prepare("UPDATE users SET total_proposals = total_proposals + 1 WHERE id = ?")->execute([$targetUserId]);

            // Send notification to target: mutual match!
            require_once __DIR__ . '/notification_helper.php';
            $myQuery = $pdo->prepare("SELECT name FROM users WHERE id = ?");
            $myQuery->execute([$userId]);
            $myName = $myQuery->fetchColumn() ?: 'Someone';

            send_app_notification($pdo, $targetUserId, $userId, 'proposal_accepted', 'It\'s a Match! 💕', "$myName also likes you! Start chatting now.");
            send_app_notification($pdo, $userId, $targetUserId, 'proposal_accepted', 'It\'s a Match! 💕', "You and " . ($pdo->prepare("SELECT name FROM users WHERE id = ?")->execute([$targetUserId]) ? 'your match' : 'someone') . " both like each other!");

            echo json_encode(['status' => 'success', 'message' => 'It\'s a mutual match!', 'matched' => true]);
        } else {
            // Insert new proposal
            if ($existing) {
                // Re-propose (was rejected before)
                $pdo->prepare("UPDATE proposals SET status = 'pending', updated_at = NOW() WHERE id = ?")->execute([$existing['id']]);
            } else {
                $pdo->prepare("INSERT INTO proposals (sender_id, receiver_id, status) VALUES (?, ?, 'pending')")->execute([$userId, $targetUserId]);
            }

            // Increment proposals count
            $pdo->prepare("UPDATE users SET total_proposals = total_proposals + 1 WHERE id = ?")->execute([$targetUserId]);

            // Send Push Notification
            require_once __DIR__ . '/notification_helper.php';
            $myQuery = $pdo->prepare("SELECT name FROM users WHERE id = ?");
            $myQuery->execute([$userId]);
            $myName = $myQuery->fetchColumn() ?: 'Someone';

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

        // Find proposal
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

        // Accept
        $pdo->prepare("UPDATE proposals SET status = 'accepted', updated_at = NOW() WHERE id = ?")->execute([$proposal['id']]);

        // Create chat connection (system message)
        $sId = (int)$proposal['sender_id'];
        $pdo->prepare("INSERT INTO messages (sender_id, receiver_id, type, content, status, created_at) VALUES (?, ?, 'system', '💕 Proposal accepted! You are now connected.', 'sent', NOW())")->execute([$sId, $userId]);

        // Notify sender
        require_once __DIR__ . '/notification_helper.php';
        $myQuery = $pdo->prepare("SELECT name FROM users WHERE id = ?");
        $myQuery->execute([$userId]);
        $myName = $myQuery->fetchColumn() ?: 'Someone';

        send_app_notification($pdo, $sId, $userId, 'proposal_accepted', 'Proposal Accepted! 💕', "$myName accepted your proposal! Start chatting now.");

        echo json_encode(['status' => 'success', 'message' => 'Proposal accepted', 'chat_with' => $sId]);
    }
    // ════════════════════════════════════════════════════════
    //  REJECT PROPOSAL
    // ════════════════════════════════════════════════════════
    elseif ($action === 'reject_proposal') {
        $proposalId = (int)($_POST['proposal_id'] ?? 0);
        $senderId = (int)($_POST['sender_id'] ?? 0);
        
        if (!$proposalId && !$senderId) {
            echo json_encode(['status' => 'error', 'message' => 'Missing proposal_id or sender_id']);
            exit;
        }

        if ($proposalId) {
            $pdo->prepare("UPDATE proposals SET status = 'rejected', updated_at = NOW() WHERE id = ? AND receiver_id = ?")->execute([$proposalId, $userId]);
        } else {
            $pdo->prepare("UPDATE proposals SET status = 'rejected', updated_at = NOW() WHERE sender_id = ? AND receiver_id = ? AND status = 'pending'")->execute([$senderId, $userId]);
        }

        echo json_encode(['status' => 'success', 'message' => 'Proposal rejected']);
    }
    // ════════════════════════════════════════════════════════
    //  GET MY PROPOSALS (received, pending)
    // ════════════════════════════════════════════════════════
    elseif ($action === 'get_proposals') {
        $type = $_GET['type'] ?? $_POST['type'] ?? 'received'; // received or sent
        
        if ($type === 'received') {
            $stmt = $pdo->prepare("
                SELECT p.id as proposal_id, p.sender_id, p.status, p.created_at, p.show_on_profile,
                       u.name as sender_name, u.profile_pic as sender_avatar,
                       m.age, m.gender, m.bio
                FROM proposals p
                JOIN users u ON u.id = p.sender_id
                LEFT JOIN match_profiles m ON m.user_id = p.sender_id
                WHERE p.receiver_id = ? AND p.status IN ('pending', 'accepted')
                ORDER BY p.status DESC, p.created_at DESC
            ");
            $stmt->execute([$userId]);
        } else {
            $stmt = $pdo->prepare("
                SELECT p.id as proposal_id, p.receiver_id, p.status, p.created_at, p.show_on_profile,
                       u.name as receiver_name, u.profile_pic as receiver_avatar,
                       m.age, m.gender, m.bio
                FROM proposals p
                JOIN users u ON u.id = p.receiver_id
                LEFT JOIN match_profiles m ON m.user_id = p.receiver_id
                WHERE p.sender_id = ? AND p.status IN ('pending', 'accepted')
                ORDER BY p.status DESC, p.created_at DESC
            ");
            $stmt->execute([$userId]);
        }
        
        $proposals = $stmt->fetchAll(PDO::FETCH_ASSOC);
        echo json_encode(['status' => 'success', 'proposals' => $proposals]);
    }
    // ════════════════════════════════════════════════════════
    //  SET PROPOSAL PUBLIC
    // ════════════════════════════════════════════════════════
    elseif ($action === 'set_proposal_public') {
        $proposalId = (int)($_POST['proposal_id'] ?? 0);
        $isPublic = isset($_POST['is_public']) && ($_POST['is_public'] === 'true' || $_POST['is_public'] === '1' || $_POST['is_public'] === true) ? 1 : 0;
        
        if (!$proposalId) {
            echo json_encode(['status' => 'error', 'message' => 'Missing proposal_id']);
            exit;
        }

        // Must be part of the proposal and it must be accepted
        $stmt = $pdo->prepare("UPDATE proposals SET show_on_profile = ?, updated_at = NOW() WHERE id = ? AND (sender_id = ? OR receiver_id = ?) AND status = 'accepted'");
        $stmt->execute([$isPublic, $proposalId, $userId, $userId]);
        
        if ($stmt->rowCount() > 0) {
            echo json_encode(['status' => 'success', 'message' => 'Public visibility updated']);
        } else {
            echo json_encode(['status' => 'error', 'message' => 'Proposal not found or not accepted']);
        }
    }
    // ════════════════════════════════════════════════════════
    //  BLOCK USER
    // ════════════════════════════════════════════════════════
    elseif ($action === 'block_user') {
        $blockedId = (int)($_POST['blocked_id'] ?? 0);
        if (!$blockedId) {
            echo json_encode(['status' => 'error', 'message' => 'Missing blocked_id']);
            exit;
        }

        // Insert block (ignore duplicate)
        $pdo->prepare("INSERT IGNORE INTO user_blocks (blocker_id, blocked_id) VALUES (?, ?)")->execute([$userId, $blockedId]);

        // Also reject any pending proposals between them
        $pdo->prepare("UPDATE proposals SET status = 'rejected', updated_at = NOW() WHERE ((sender_id = ? AND receiver_id = ?) OR (sender_id = ? AND receiver_id = ?)) AND status = 'pending'")->execute([$userId, $blockedId, $blockedId, $userId]);

        echo json_encode(['status' => 'success', 'message' => 'User blocked']);
    }
    // ════════════════════════════════════════════════════════
    //  UNBLOCK USER
    // ════════════════════════════════════════════════════════
    elseif ($action === 'unblock_user') {
        $blockedId = (int)($_POST['blocked_id'] ?? 0);
        if (!$blockedId) {
            echo json_encode(['status' => 'error', 'message' => 'Missing blocked_id']);
            exit;
        }
        $pdo->prepare("DELETE FROM user_blocks WHERE blocker_id = ? AND blocked_id = ?")->execute([$userId, $blockedId]);
        echo json_encode(['status' => 'success', 'message' => 'User unblocked']);
    }
    // ════════════════════════════════════════════════════════
    //  GET CONNECTED MATCHES (accepted proposals)
    // ════════════════════════════════════════════════════════
    elseif ($action === 'get_connections') {
        $stmt = $pdo->prepare("
            SELECT 
                p.id as proposal_id,
                p.show_on_profile,
                CASE WHEN p.sender_id = ? THEN p.receiver_id ELSE p.sender_id END as connected_user_id,
                p.updated_at as connected_at,
                u.name, u.profile_pic,
                m.age, m.gender, m.bio
            FROM proposals p
            JOIN users u ON u.id = CASE WHEN p.sender_id = ? THEN p.receiver_id ELSE p.sender_id END
            LEFT JOIN match_profiles m ON m.user_id = u.id
            WHERE (p.sender_id = ? OR p.receiver_id = ?) AND p.status = 'accepted'
            ORDER BY p.updated_at DESC
        ");
        $stmt->execute([$userId, $userId, $userId, $userId]);
        $connections = $stmt->fetchAll(PDO::FETCH_ASSOC);
        echo json_encode(['status' => 'success', 'connections' => $connections]);
    }
    // ════════════════════════════════════════════════════════
    //  MUTE USER
    // ════════════════════════════════════════════════════════
    elseif ($action === 'mute_user') {
        $targetId = (int)($_POST['target_user_id'] ?? 0);
        if (!$targetId) {
            echo json_encode(['status' => 'error', 'message' => 'Missing target_user_id']);
            exit;
        }
        $pdo->prepare("INSERT IGNORE INTO user_mutes (muter_id, muted_id) VALUES (?, ?)")->execute([$userId, $targetId]);
        echo json_encode(['status' => 'success', 'message' => 'User muted']);
    }
    // ════════════════════════════════════════════════════════
    //  UNMUTE USER
    // ════════════════════════════════════════════════════════
    elseif ($action === 'unmute_user') {
        $targetId = (int)($_POST['target_user_id'] ?? 0);
        if (!$targetId) {
            echo json_encode(['status' => 'error', 'message' => 'Missing target_user_id']);
            exit;
        }
        $pdo->prepare("DELETE FROM user_mutes WHERE muter_id = ? AND muted_id = ?")->execute([$userId, $targetId]);
        echo json_encode(['status' => 'success', 'message' => 'User unmuted']);
    }
    // ════════════════════════════════════════════════════════
    //  REPORT USER
    // ════════════════════════════════════════════════════════
    elseif ($action === 'report_user') {
        $targetId = (int)($_POST['target_user_id'] ?? 0);
        $reason   = trim($_POST['reason'] ?? '');
        $details  = trim($_POST['details'] ?? '');

        if (!$targetId || !$reason) {
            echo json_encode(['status' => 'error', 'message' => 'Missing target_user_id or reason']);
            exit;
        }

        // Prevent duplicate reports within 24 hours
        $dupSt = $pdo->prepare("SELECT id FROM user_reports WHERE reporter_id = ? AND reported_id = ? AND created_at > DATE_SUB(NOW(), INTERVAL 24 HOUR)");
        $dupSt->execute([$userId, $targetId]);
        if ($dupSt->fetch()) {
            echo json_encode(['status' => 'error', 'message' => 'You have already reported this user recently']);
            exit;
        }

        $pdo->prepare("INSERT INTO user_reports (reporter_id, reported_id, reason, details) VALUES (?, ?, ?, ?)")
            ->execute([$userId, $targetId, $reason, $details]);

        echo json_encode(['status' => 'success', 'message' => 'Report submitted successfully']);
    }
    // ════════════════════════════════════════════════════════
    //  DISCONNECT PROPOSAL (break accepted connection)
    // ════════════════════════════════════════════════════════
    elseif ($action === 'disconnect_proposal') {
        $targetId = (int)($_POST['target_user_id'] ?? 0);
        if (!$targetId) {
            echo json_encode(['status' => 'error', 'message' => 'Missing target_user_id']);
            exit;
        }

        // Set all accepted proposals between the two users to 'disconnected'
        $stmt = $pdo->prepare("UPDATE proposals SET status = 'disconnected', updated_at = NOW() WHERE ((sender_id = ? AND receiver_id = ?) OR (sender_id = ? AND receiver_id = ?)) AND status = 'accepted'");
        $stmt->execute([$userId, $targetId, $targetId, $userId]);
        $affected = $stmt->rowCount();

        if ($affected > 0) {
            echo json_encode(['status' => 'success', 'message' => 'Proposal connection disconnected']);
        } else {
            echo json_encode(['status' => 'error', 'message' => 'No active proposal connection found']);
        }
    }
    // ════════════════════════════════════════════════════════
    //  GET USER STATUS (block, mute, proposal status)
    // ════════════════════════════════════════════════════════
    elseif ($action === 'get_user_status') {
        $targetId = (int)($_REQUEST['target_user_id'] ?? 0);
        if (!$targetId) {
            echo json_encode(['status' => 'error', 'message' => 'Missing target_user_id']);
            exit;
        }

        // Check block status
        $blockSt = $pdo->prepare("SELECT id FROM user_blocks WHERE blocker_id = ? AND blocked_id = ?");
        $blockSt->execute([$userId, $targetId]);
        $isBlocked = (bool)$blockSt->fetch();

        // Check mute status
        $muteSt = $pdo->prepare("SELECT id FROM user_mutes WHERE muter_id = ? AND muted_id = ?");
        $muteSt->execute([$userId, $targetId]);
        $isMuted = (bool)$muteSt->fetch();

        // Check proposal connection (accepted)
        $propSt = $pdo->prepare("SELECT id FROM proposals WHERE ((sender_id = ? AND receiver_id = ?) OR (sender_id = ? AND receiver_id = ?)) AND status = 'accepted' LIMIT 1");
        $propSt->execute([$userId, $targetId, $targetId, $userId]);
        $isProposalConnected = (bool)$propSt->fetch();

        // Get target user name
        $nameSt = $pdo->prepare("SELECT name FROM users WHERE id = ?");
        $nameSt->execute([$targetId]);
        $targetName = $nameSt->fetchColumn() ?: 'User';

        echo json_encode([
            'status' => 'success',
            'is_blocked' => $isBlocked,
            'is_muted' => $isMuted,
            'is_proposal_connected' => $isProposalConnected,
            'target_name' => $targetName,
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
