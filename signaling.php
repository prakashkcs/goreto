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

// ── Helper: push a call_cancelled data message to one user ──────────────────
function _sendCallCancelledFCM(PDO $pdo, int $recipientId, int $callId): void {
    if ($recipientId <= 0) return;
    $s = $pdo->prepare("SELECT fcm_token FROM users WHERE id=? AND is_banned=0");
    $s->execute([$recipientId]);
    $row = $s->fetch(PDO::FETCH_ASSOC);
    if (empty($row['fcm_token'])) return;

    $serviceAccountPath = __DIR__ . '/service_account.json';
    if (!file_exists($serviceAccountPath)) return;
    require_once __DIR__ . '/fcm_v1.php';
    $jsonAccount = json_decode(file_get_contents($serviceAccountPath), true);
    $projectId = $jsonAccount['project_id'] ?? '';
    if (empty($projectId)) return;

    $fcmClient = new PushNotificationFCM($serviceAccountPath);
    $fcmClient->sendDataMessage($row['fcm_token'], $projectId, [
        'type'    => 'call_cancelled',
        'action'  => 'call_cancelled',
        'call_id' => (string)$callId,
    ], null, true);
}

try {
    $viewer = requireUser($pdo);
    $userId = (int) $viewer['id'];
    $action = $_REQUEST['action'] ?? '';

    // ── 1. INITIATE CALL ──
    if ($action === 'initiate_call') {
        $receiverId = (int) ($_REQUEST['receiver_id'] ?? 0);
        $type = in_array($_REQUEST['type'] ?? '', ['audio', 'video']) ? $_REQUEST['type'] : 'audio';
        $callUuid = $_REQUEST['call_uuid'] ?? bin2hex(random_bytes(16));

        if ($receiverId <= 0) {
            echo json_encode(['status' => 'error', 'message' => 'Invalid receiver_id']);
            exit;
        }

        // Only friends (mutual follows) or users with an accepted message request can call
        $mfA = $pdo->prepare("SELECT COUNT(*) FROM follows WHERE follower_id=? AND following_id=?");
        $mfA->execute([$userId, $receiverId]); $af = (int)$mfA->fetchColumn();
        $mfA->execute([$receiverId, $userId]); $bf = (int)$mfA->fetchColumn();
        $isFriend = $af > 0 && $bf > 0;
        if (!$isFriend) {
            $rSt = $pdo->prepare("SELECT accepted FROM message_requests WHERE ((requester_id=? AND receiver_id=?) OR (requester_id=? AND receiver_id=?)) AND accepted=1 LIMIT 1");
            $rSt->execute([$userId, $receiverId, $receiverId, $userId]);
            if (!$rSt->fetchColumn()) {
                echo json_encode(['status' => 'error', 'message' => 'You can only call friends or people who accepted your message request', 'error_code' => 'not_allowed_to_call']);
                exit;
            }
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

        // Send FCM Notification to the receiver
        $fcmSent = false;
        $stmtFCM = $pdo->prepare("SELECT fcm_token FROM users WHERE id = ? AND is_banned = 0");
        $stmtFCM->execute([$receiverId]);
        $receiver = $stmtFCM->fetch(PDO::FETCH_ASSOC);

        if ($receiver && !empty($receiver['fcm_token'])) {
            $serviceAccountPath = __DIR__ . '/service_account.json';
            if (file_exists($serviceAccountPath)) {
                require_once __DIR__ . '/fcm_v1.php';
                $jsonAccount = json_decode(file_get_contents($serviceAccountPath), true);
                $projectId = $jsonAccount['project_id'] ?? '';
                if (!empty($projectId)) {
                    $fcmClient = new PushNotificationFCM($serviceAccountPath);
                    $fcmClient->sendCallNotification($receiver['fcm_token'], $projectId, $callerInfo['name'] ?? 'Someone', $userId, $callUuid, $callId, $type);
                    $fcmSent = true;
                }
            }
        }

        echo json_encode([
            'status' => 'success',
            'call_id' => (int) $callId,
            'call_uuid' => $callUuid,
            'caller' => $callerInfo,
            'fcm_sent' => $fcmSent
        ]);
    }

    // ── 2. POLL INCOMING ── (receiver polls for ringing calls targeting them)
    elseif ($action === 'poll_incoming') {
        $stmt = $pdo->prepare("
            SELECT c.id AS call_id, c.call_uuid, c.type, c.status, c.created_at,
                   u.id AS caller_id, u.name AS caller_name, u.full_name AS caller_full_name, u.profile_pic AS caller_avatar
            FROM calls c
            JOIN users u ON u.id = c.caller_id
            WHERE (c.receiver_id = ? OR (c.receiver_id = 0 AND c.caller_id != ?))
              AND c.status = 'ringing'
              AND (UNIX_TIMESTAMP() - UNIX_TIMESTAMP(c.created_at)) < 60
            ORDER BY c.created_at DESC LIMIT 1
        ");
        $stmt->execute([$userId, $userId]);
        $call = $stmt->fetch(PDO::FETCH_ASSOC);

        if ($call) {
            echo json_encode(['status' => 'success', 'has_call' => true, 'call' => $call]);
        } else {
            echo json_encode(['status' => 'success', 'has_call' => false]);
        }
    }

    // ── 3. ACCEPT CALL ──
    elseif ($action === 'accept_call') {
        $callId = (int) ($_REQUEST['call_id'] ?? 0);
        // Support broadcast calls (receiver_id = 0) — first user to accept claims it
        $stmt = $pdo->prepare("SELECT id, receiver_id, status FROM calls WHERE id = ?");
        $stmt->execute([$callId]);
        $call = $stmt->fetch(PDO::FETCH_ASSOC);

        if ($call && $call['status'] === 'ringing') {
            if ((int) $call['receiver_id'] === 0) {
                // Broadcast call — claim it for this user
                $upd = $pdo->prepare("UPDATE calls SET status='accepted', receiver_id=? WHERE id=? AND status='ringing' AND receiver_id=0");
                $upd->execute([$userId, $callId]);
                echo json_encode(['status' => 'success']);
            } else if ((int) $call['receiver_id'] === $userId) {
                // Normal direct call
                $upd = $pdo->prepare("UPDATE calls SET status='accepted' WHERE id=? AND receiver_id=? AND status='ringing'");
                $upd->execute([$callId, $userId]);

                // Notify the caller that call was picked up
                $stmtCaller = $pdo->prepare("SELECT u.fcm_token, r.name as receiver_name FROM calls c JOIN users u ON u.id = c.caller_id JOIN users r ON r.id = c.receiver_id WHERE c.id = ?");
                $stmtCaller->execute([$callId]);
                $caller = $stmtCaller->fetch(PDO::FETCH_ASSOC);

                if ($caller && !empty($caller['fcm_token'])) {
                    $serviceAccountPath = __DIR__ . '/service_account.json';
                    if (file_exists($serviceAccountPath)) {
                        require_once __DIR__ . '/fcm_v1.php';
                        $jsonAccount = json_decode(file_get_contents($serviceAccountPath), true);
                        $projectId = $jsonAccount['project_id'] ?? '';
                        if (!empty($projectId)) {
                            $fcmClient = new PushNotificationFCM($serviceAccountPath);
                            $fcmClient->sendCallPickupNotification($caller['fcm_token'], $projectId, $caller['receiver_name'] ?? 'User');
                        }
                    }
                }

                echo json_encode(['status' => 'success']);
            } else {
                echo json_encode(['status' => 'error', 'message' => 'Not your call']);
            }
        } else {
            echo json_encode(['status' => 'error', 'message' => 'Call not available']);
        }
    }

    // ── 4. DECLINE CALL ──
    elseif ($action === 'decline_call') {
        $callId = (int) ($_REQUEST['call_id'] ?? 0);

        // Read the call before updating so we can notify the other party
        $callRow = null;
        $preStmt = $pdo->prepare("SELECT caller_id, receiver_id FROM calls WHERE id=?");
        $preStmt->execute([$callId]);
        $callRow = $preStmt->fetch(PDO::FETCH_ASSOC);

        $stmt = $pdo->prepare("UPDATE calls SET status='declined' WHERE id=? AND (receiver_id=? OR caller_id=?)");
        $stmt->execute([$callId, $userId, $userId]);

        // Notify the other party that the call was declined
        if ($callRow) {
            $otherId = ((int)$callRow['caller_id'] === $userId) ? (int)$callRow['receiver_id'] : (int)$callRow['caller_id'];
            _sendCallCancelledFCM($pdo, $otherId, $callId);
        }

        echo json_encode(['status' => 'success']);
    }

    // ── 5. END CALL ──
    elseif ($action === 'end_call') {
        $callId = (int) ($_REQUEST['call_id'] ?? 0);

        // Read the call before updating so we can notify the other party
        $preStmt = $pdo->prepare("SELECT caller_id, receiver_id FROM calls WHERE id=?");
        $preStmt->execute([$callId]);
        $callRow = $preStmt->fetch(PDO::FETCH_ASSOC);

        $stmt = $pdo->prepare("UPDATE calls SET status='ended' WHERE id=? AND (caller_id=? OR receiver_id=?)");
        $stmt->execute([$callId, $userId, $userId]);

        // Notify the other party so they can dismiss the incoming-call UI immediately
        if ($callRow) {
            $otherId = ((int)$callRow['caller_id'] === $userId) ? (int)$callRow['receiver_id'] : (int)$callRow['caller_id'];
            _sendCallCancelledFCM($pdo, $otherId, $callId);
        }

        echo json_encode(['status' => 'success']);
    }

    // ── 6. SEND SIGNAL ── (SDP offer, answer, or ICE candidate)
    elseif ($action === 'send_signal') {
        $callId = (int) ($_REQUEST['call_id'] ?? 0);
        $signalType = $_REQUEST['signal_type'] ?? '';
        $payload = $_REQUEST['payload'] ?? '';

        if (!in_array($signalType, ['offer', 'answer', 'ice'])) {
            echo json_encode(['status' => 'error', 'message' => 'Invalid signal_type']);
            exit;
        }

        $stmt = $pdo->prepare("INSERT INTO call_signals (call_id, sender_id, signal_type, payload) VALUES (?, ?, ?, ?)");
        $stmt->execute([$callId, $userId, $signalType, $payload]);
        echo json_encode(['status' => 'success', 'signal_id' => (int) $pdo->lastInsertId()]);
    }

    // ── 7. POLL SIGNALS ── (get signals from the other party)
    elseif ($action === 'poll_signals') {
        $callId = (int) ($_REQUEST['call_id'] ?? 0);
        $afterId = (int) ($_REQUEST['after_id'] ?? 0);

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
        $callId = (int) ($_REQUEST['call_id'] ?? 0);
        $stmt = $pdo->prepare("SELECT id, call_uuid, caller_id, receiver_id, type, status FROM calls WHERE id=?");
        $stmt->execute([$callId]);
        $call = $stmt->fetch(PDO::FETCH_ASSOC);

        if ($call) {
            echo json_encode(['status' => 'success', 'call' => $call]);
        } else {
            echo json_encode(['status' => 'error', 'message' => 'Call not found']);
        }
    }

    // ── 9. RANDOM CALL MATCH ── Queue-based matchmaking + incoming call broadcast
    elseif ($action === 'random_call_match') {
        $type = in_array($_REQUEST['type'] ?? '', ['audio', 'video']) ? $_REQUEST['type'] : 'video';

        // Auto-create random_call_queue table
        $pdo->exec("
            CREATE TABLE IF NOT EXISTS random_call_queue (
                id INT AUTO_INCREMENT PRIMARY KEY,
                user_id INT NOT NULL UNIQUE,
                type ENUM('audio','video') DEFAULT 'video',
                call_id INT DEFAULT NULL,
                broadcast_call_id INT DEFAULT NULL,
                matched_user_id INT DEFAULT NULL,
                created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
                INDEX idx_user (user_id),
                INDEX idx_waiting (call_id, created_at)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        ");
        // Add broadcast_call_id column if table already existed without it
        try {
            $pdo->exec("ALTER TABLE random_call_queue ADD COLUMN broadcast_call_id INT DEFAULT NULL");
        } catch (Throwable $e) {
        }

        // Clean up stale queue entries (older than 60 seconds)
        $pdo->exec("DELETE FROM random_call_queue WHERE call_id IS NULL AND (UNIX_TIMESTAMP() - UNIX_TIMESTAMP(created_at)) > 60");
        // Also expire old broadcast calls from stale queue entries
        $pdo->exec("UPDATE calls SET status='missed' WHERE receiver_id=0 AND status='ringing' AND (UNIX_TIMESTAMP() - UNIX_TIMESTAMP(created_at)) > 60");

        // Check current user allows random calls
        $myPrivSt = $pdo->prepare("SELECT COALESCE(privacy_allow_random_video_call, 1) AS allow_rv FROM users WHERE id = ? LIMIT 1");
        $myPrivSt->execute([$userId]);
        $myPriv = $myPrivSt->fetch(PDO::FETCH_ASSOC);
        if ($myPriv && (int)$myPriv['allow_rv'] === 0) {
            echo json_encode(['status' => 'error', 'message' => 'You have disabled random video calls in privacy settings.']);
            exit;
        }

        // STEP 1: Check if another user is already waiting in the queue (must also allow random calls)
        $findWaiting = $pdo->prepare("
            SELECT q.id, q.user_id, q.broadcast_call_id, u.name, u.full_name, u.profile_pic AS avatar
            FROM random_call_queue q
            JOIN users u ON u.id = q.user_id
            WHERE q.user_id != ?
              AND q.call_id IS NULL
              AND (UNIX_TIMESTAMP() - UNIX_TIMESTAMP(q.created_at)) < 60
              AND COALESCE(u.privacy_allow_random_video_call, 1) = 1
            ORDER BY q.created_at ASC
            LIMIT 1
            FOR UPDATE
        ");
        $findWaiting->execute([$userId]);
        $waitingUser = $findWaiting->fetch(PDO::FETCH_ASSOC);

        if ($waitingUser) {
            // MATCH FOUND! Create a call between the two users
            $callUuid = bin2hex(random_bytes(16));
            $insertStmt = $pdo->prepare("INSERT INTO calls (call_uuid, caller_id, receiver_id, type, status) VALUES (?, ?, ?, ?, 'accepted')");
            $insertStmt->execute([$callUuid, $userId, (int) $waitingUser['user_id'], $type]);
            $callId = $pdo->lastInsertId();

            // End the waiting user's old broadcast call (so FCM recipients can't accept it anymore)
            if (!empty($waitingUser['broadcast_call_id'])) {
                $pdo->prepare("UPDATE calls SET status='ended' WHERE id=? AND status='ringing'")->execute([$waitingUser['broadcast_call_id']]);
            }

            // Update the waiting user's queue entry so they know they got matched
            $updateQueue = $pdo->prepare("UPDATE random_call_queue SET call_id = ?, matched_user_id = ? WHERE id = ?");
            $updateQueue->execute([$callId, $userId, $waitingUser['id']]);

            // Remove current user from queue if they were in it
            $pdo->prepare("DELETE FROM random_call_queue WHERE user_id = ?")->execute([$userId]);

            echo json_encode([
                'status' => 'success',
                'matched' => true,
                'call_id' => (int) $callId,
                'call_uuid' => $callUuid,
                'matched_user' => [
                    'id' => $waitingUser['user_id'],
                    'name' => $waitingUser['name'],
                    'full_name' => $waitingUser['full_name'],
                    'avatar' => $waitingUser['avatar'],
                ],
            ]);
            exit;
        }

        // STEP 2: No one waiting — add to queue + create broadcast call + send FCM
        $pdo->prepare("DELETE FROM random_call_queue WHERE user_id = ?")->execute([$userId]);

        // Create a broadcast call (receiver_id=0 = available to anyone)
        $broadcastUuid = bin2hex(random_bytes(16));
        $pdo->prepare("INSERT INTO calls (call_uuid, caller_id, receiver_id, type, status) VALUES (?, ?, 0, ?, 'ringing')")
            ->execute([$broadcastUuid, $userId, $type]);
        $broadcastCallId = $pdo->lastInsertId();

        // Add to queue with broadcast_call_id reference
        $pdo->prepare("INSERT INTO random_call_queue (user_id, type, broadcast_call_id) VALUES (?, ?, ?)")
            ->execute([$userId, $type, $broadcastCallId]);

        // STEP 3: Send incoming_call FCM to users with direct call enabled
        $notifiedCount = 0;
        $fcmStmt = $pdo->prepare("
            SELECT u.id, u.fcm_token
            FROM users u
            WHERE u.id != ?
              AND u.is_banned = 0
              AND u.fcm_token IS NOT NULL AND u.fcm_token != ''
              AND u.id NOT IN (
                  SELECT blocked_id FROM blocks WHERE blocker_id = ?
                  UNION
                  SELECT blocker_id FROM blocks WHERE blocked_id = ?
              )
            LIMIT 50
        ");
        $fcmStmt->execute([$userId, $userId, $userId]);
        $fcmUsers = $fcmStmt->fetchAll(PDO::FETCH_ASSOC);

        if (!empty($fcmUsers)) {
            $serviceAccountPath = __DIR__ . '/service_account.json';
            if (file_exists($serviceAccountPath)) {
                require_once __DIR__ . '/fcm_v1.php';
                $jsonAccount = json_decode(file_get_contents($serviceAccountPath), true);
                $projectId = $jsonAccount['project_id'] ?? '';

                if (!empty($projectId)) {
                    $fcmClient = new PushNotificationFCM($serviceAccountPath);
                    $callerStmt = $pdo->prepare("SELECT id, name, full_name, profile_pic FROM users WHERE id=?");
                    $callerStmt->execute([$userId]);
                    $callerInfo = $callerStmt->fetch(PDO::FETCH_ASSOC);

                    foreach ($fcmUsers as $fu) {
                        $fcmPayload = [
                            'action' => 'incoming_call',
                            'call_id' => (string) $broadcastCallId,
                            'call_uuid' => (string) $broadcastUuid,
                            'caller_id' => (string) $userId,
                            'caller_name' => 'Random User',
                            'caller_avatar' => $callerInfo['profile_pic'] ?? '',
                            'type' => $type,
                            'is_random' => 'true'
                        ];

                        try {
                            // Data-only message to ensure background tray shows buttons/ringtone
                            $fcmClient->sendDataMessage($fu['fcm_token'], $projectId, $fcmPayload, null, true);
                            $notifiedCount++;
                        } catch (Throwable $ignore) {
                        }
                    }
                }
            }
        }

        echo json_encode([
            'status' => 'success',
            'matched' => false,
            'call_id' => (int) $broadcastCallId,
            'call_uuid' => $broadcastUuid,
            'message' => 'Added to queue. Waiting for a match...',
            'notified_count' => $notifiedCount,
        ]);
    }

    // ── 10. POLL RANDOM MATCH ── Check if current user got matched while waiting
    elseif ($action === 'poll_random_match') {
        $stmt = $pdo->prepare("
            SELECT q.call_id, q.broadcast_call_id, q.matched_user_id
            FROM random_call_queue q
            WHERE q.user_id = ?
        ");
        $stmt->execute([$userId]);
        $entry = $stmt->fetch(PDO::FETCH_ASSOC);

        if (!$entry) {
            echo json_encode(['status' => 'success', 'matched' => false, 'expired' => true]);
            exit;
        }

        // Check 1: Queue match (another user searching matched us)
        if ($entry['call_id']) {
            $callStmt = $pdo->prepare("SELECT call_uuid FROM calls WHERE id=?");
            $callStmt->execute([$entry['call_id']]);
            $callData = $callStmt->fetch(PDO::FETCH_ASSOC);

            $userStmt = $pdo->prepare("SELECT id, name, full_name, profile_pic AS avatar FROM users WHERE id=?");
            $userStmt->execute([$entry['matched_user_id']]);
            $matchUser = $userStmt->fetch(PDO::FETCH_ASSOC);

            $pdo->prepare("DELETE FROM random_call_queue WHERE user_id = ?")->execute([$userId]);
            echo json_encode([
                'status' => 'success',
                'matched' => true,
                'call_id' => (int) $entry['call_id'],
                'call_uuid' => $callData['call_uuid'] ?? '',
                'matched_user' => $matchUser,
            ]);
            exit;
        }

        // Check 2: Broadcast call accepted (someone accepted our incoming_call notification)
        if ($entry['broadcast_call_id']) {
            $bcStmt = $pdo->prepare("SELECT id, call_uuid, receiver_id, status FROM calls WHERE id=?");
            $bcStmt->execute([$entry['broadcast_call_id']]);
            $bcCall = $bcStmt->fetch(PDO::FETCH_ASSOC);

            if ($bcCall && $bcCall['status'] === 'accepted' && (int) $bcCall['receiver_id'] > 0) {
                // Someone accepted our broadcast call!
                $userStmt = $pdo->prepare("SELECT id, name, full_name, profile_pic AS avatar FROM users WHERE id=?");
                $userStmt->execute([$bcCall['receiver_id']]);
                $matchUser = $userStmt->fetch(PDO::FETCH_ASSOC);

                $pdo->prepare("DELETE FROM random_call_queue WHERE user_id = ?")->execute([$userId]);
                echo json_encode([
                    'status' => 'success',
                    'matched' => true,
                    'call_id' => (int) $bcCall['id'],
                    'call_uuid' => $bcCall['call_uuid'],
                    'matched_user' => $matchUser,
                ]);
                exit;
            }
        }

        echo json_encode(['status' => 'success', 'matched' => false]);
    }

    // ── 11. CANCEL RANDOM MATCH ── Leave the queue + end broadcast call
    elseif ($action === 'cancel_random_match') {
        // End the broadcast call if any
        $qStmt = $pdo->prepare("SELECT broadcast_call_id FROM random_call_queue WHERE user_id = ?");
        $qStmt->execute([$userId]);
        $qEntry = $qStmt->fetch(PDO::FETCH_ASSOC);
        if ($qEntry && !empty($qEntry['broadcast_call_id'])) {
            $pdo->prepare("UPDATE calls SET status='ended' WHERE id=? AND status='ringing'")->execute([$qEntry['broadcast_call_id']]);
        }
        $pdo->prepare("DELETE FROM random_call_queue WHERE user_id = ?")->execute([$userId]);
        echo json_encode(['status' => 'success']);
    } else {
        echo json_encode(['status' => 'error', 'message' => 'Unknown action']);
    }
} catch (Throwable $e) {
    http_response_code(500);
    echo json_encode(['status' => 'error', 'message' => 'Server error', 'error' => $e->getMessage()]);
}
?>