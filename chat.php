<?php
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Content-Type, Authorization');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

file_put_contents(__DIR__ . '/chat_trace.txt', "[" . date('Y-m-d H:i:s') . "] Req: " . $_SERVER['REQUEST_METHOD'] . " Body: " . file_get_contents('php://input') . "\n", FILE_APPEND);

// Handle JSON input
$jsonInput = json_decode(file_get_contents('php://input'), true);
if (is_array($jsonInput)) {
    $_REQUEST = array_merge($_REQUEST, $jsonInput);
    $_POST = array_merge($_POST, $jsonInput);
}

require_once __DIR__ . '/db_connect.php';
require_once __DIR__ . '/auth_middleware.php';

// Auto-create message_requests table
$pdo->exec("
    CREATE TABLE IF NOT EXISTS message_requests (
        requester_id INT NOT NULL,
        receiver_id  INT NOT NULL,
        accepted     TINYINT(1) DEFAULT 0,
        created_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (requester_id, receiver_id),
        INDEX idx_receiver_pending (receiver_id, accepted)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
");

// ── helpers ──────────────────────────────────────────────────────────────────

function isMutualFriend(PDO $pdo, int $a, int $b): bool {
    $s = $pdo->prepare("SELECT COUNT(*) FROM follows WHERE follower_id=? AND following_id=?");
    $s->execute([$a, $b]); $aFollowsB = (int)$s->fetchColumn();
    $s->execute([$b, $a]); $bFollowsA = (int)$s->fetchColumn();
    return $aFollowsB > 0 && $bFollowsA > 0;
}

// Returns ['exists'=>bool, 'accepted'=>bool, 'i_am_requester'=>bool]
function getRequestStatus(PDO $pdo, int $userId, int $otherId): array {
    $s = $pdo->prepare("SELECT requester_id, accepted FROM message_requests
                        WHERE (requester_id=? AND receiver_id=?)
                           OR (requester_id=? AND receiver_id=?) LIMIT 1");
    $s->execute([$userId, $otherId, $otherId, $userId]);
    $row = $s->fetch(PDO::FETCH_ASSOC);
    if (!$row) return ['exists' => false, 'accepted' => false, 'i_am_requester' => false];
    return [
        'exists'        => true,
        'accepted'      => (bool)$row['accepted'],
        'i_am_requester'=> (int)$row['requester_id'] === $userId,
    ];
}

// 'none' | 'pending_sent' | 'pending_received' | 'accepted'
function requestStatusLabel(array $rs, bool $isFriend): string {
    if ($isFriend) return 'none';
    if (!$rs['exists']) return 'none';
    if ($rs['accepted']) return 'accepted';
    return $rs['i_am_requester'] ? 'pending_sent' : 'pending_received';
}

function buildAvatarUrl(string $rawPic): string {
    if ($rawPic === '') return '';
    if (preg_match('~^https?://~i', $rawPic)) return $rawPic;
    return 'https://goreto.org/ekloadmin/' . ltrim($rawPic, '/');
}

try {
    $viewer = requireUser($pdo);
    $userId = (int)$viewer['id'];
    $action = $_REQUEST['action'] ?? '';

    // ── get_conversations ─────────────────────────────────────────────────────
    if ($action === 'get_conversations') {
        $stmt = $pdo->prepare('
            SELECT
                CASE WHEN sender_id = ? THEN receiver_id ELSE sender_id END AS other_user_id,
                MAX(created_at) AS last_interaction
            FROM messages
            WHERE sender_id = ? OR receiver_id = ?
            GROUP BY other_user_id
            ORDER BY last_interaction DESC
        ');
        $stmt->execute([$userId, $userId, $userId]);
        $convs = $stmt->fetchAll(PDO::FETCH_ASSOC);

        $res = [];
        foreach ($convs as $c) {
            $otherId = (int)$c['other_user_id'];

            $uSt = $pdo->prepare('SELECT name, profile_pic FROM users WHERE id = ?');
            $uSt->execute([$otherId]);
            $other = $uSt->fetch(PDO::FETCH_ASSOC);

            $mSt = $pdo->prepare('SELECT * FROM messages WHERE (sender_id = ? AND receiver_id = ?) OR (sender_id = ? AND receiver_id = ?) ORDER BY created_at DESC LIMIT 1');
            $mSt->execute([$userId, $otherId, $otherId, $userId]);
            $lastMsg = $mSt->fetch(PDO::FETCH_ASSOC);

            $urSt = $pdo->prepare("SELECT COUNT(*) FROM messages WHERE receiver_id = ? AND sender_id = ? AND status != 'read'");
            $urSt->execute([$userId, $otherId]);
            $unread = $urSt->fetchColumn();

            $isFriend = isMutualFriend($pdo, $userId, $otherId);
            $rs       = getRequestStatus($pdo, $userId, $otherId);
            $rsLabel  = requestStatusLabel($rs, $isFriend);

            $res[] = [
                'other_user_id'    => $otherId,
                'other_user_name'  => $other ? $other['name'] : 'User',
                'other_user_avatar'=> buildAvatarUrl($other ? ($other['profile_pic'] ?? '') : ''),
                'last_message'     => $lastMsg,
                'unread_count'     => $unread,
                'updated_at'       => $c['last_interaction'],
                'is_friend'        => $isFriend,
                'request_status'   => $rsLabel,
            ];
        }
        echo json_encode(['status' => 'success', 'conversations' => $res]);
    }

    // ── get_messages ──────────────────────────────────────────────────────────
    elseif ($action === 'get_messages') {
        $withUserId = (int)($_GET['with_user_id'] ?? 0);

        $bSt = $pdo->prepare('SELECT blocker_id, blocked_id FROM user_blocks WHERE (blocker_id = ? AND blocked_id = ?) OR (blocker_id = ? AND blocked_id = ?)');
        $bSt->execute([$userId, $withUserId, $withUserId, $userId]);
        $blocks = $bSt->fetchAll(PDO::FETCH_ASSOC);
        $isBlockedByMe = false;
        $isBlockedByThem = false;
        foreach ($blocks as $b) {
            if ($b['blocker_id'] == $userId)      $isBlockedByMe = true;
            if ($b['blocker_id'] == $withUserId)  $isBlockedByThem = true;
        }

        $rSt = $pdo->prepare("UPDATE messages SET status='read', read_at=NOW() WHERE receiver_id=? AND sender_id=? AND status!='read'");
        $rSt->execute([$userId, $withUserId]);

        $stmt = $pdo->prepare('SELECT * FROM messages WHERE (sender_id = ? AND receiver_id = ?) OR (sender_id = ? AND receiver_id = ?) ORDER BY created_at ASC LIMIT 200');
        $stmt->execute([$userId, $withUserId, $withUserId, $userId]);
        $msgs = $stmt->fetchAll(PDO::FETCH_ASSOC);

        $isFriend = isMutualFriend($pdo, $userId, $withUserId);
        $rs       = getRequestStatus($pdo, $userId, $withUserId);
        $rsLabel  = requestStatusLabel($rs, $isFriend);

        echo json_encode([
            'status'           => 'success',
            'messages'         => $msgs,
            'is_blocked_by_me' => $isBlockedByMe,
            'is_blocked_by_them'=> $isBlockedByThem,
            'is_friend'        => $isFriend,
            'request_status'   => $rsLabel,
        ]);
    }

    // ── get_new_messages ──────────────────────────────────────────────────────
    elseif ($action === 'get_new_messages') {
        $withUserId = (int)($_GET['with_user_id'] ?? 0);
        $lastId     = (int)($_GET['last_id'] ?? 0);

        $rSt = $pdo->prepare("UPDATE messages SET status='read', read_at=NOW() WHERE receiver_id=? AND sender_id=? AND id > ? AND status!='read'");
        $rSt->execute([$userId, $withUserId, $lastId]);

        $stmt = $pdo->prepare('SELECT * FROM messages WHERE id > ? AND ((sender_id = ? AND receiver_id = ?) OR (sender_id = ? AND receiver_id = ?)) ORDER BY created_at ASC');
        $stmt->execute([$lastId, $userId, $withUserId, $withUserId, $userId]);
        $msgs = $stmt->fetchAll(PDO::FETCH_ASSOC);

        $stmt2 = $pdo->prepare("SELECT id, status, read_at FROM messages WHERE sender_id = ? AND receiver_id = ? AND status IN ('delivered', 'read')");
        $stmt2->execute([$userId, $withUserId]);
        $statusUpdates = $stmt2->fetchAll(PDO::FETCH_ASSOC);

        echo json_encode(['status' => 'success', 'messages' => $msgs, 'status_updates' => $statusUpdates]);
    }

    // ── send_message ──────────────────────────────────────────────────────────
    elseif ($action === 'send_message') {
        $receiverId = (int)($_POST['receiver_id'] ?? 0);
        $type       = $_POST['type'] ?? 'text';
        $content    = $_POST['content'] ?? '';
        $voiceDur   = $_POST['voice_duration'] ?? 0;

        // Block check
        $bSt = $pdo->prepare('SELECT blocker_id, blocked_id FROM user_blocks WHERE (blocker_id = ? AND blocked_id = ?) OR (blocker_id = ? AND blocked_id = ?) LIMIT 1');
        $bSt->execute([$userId, $receiverId, $receiverId, $userId]);
        $block = $bSt->fetch(PDO::FETCH_ASSOC);
        if ($block) {
            echo json_encode(['status' => 'error', 'message' => $block['blocker_id'] == $userId ? 'You have blocked this user' : 'User unavailable']);
            exit;
        }

        $isFriend = isMutualFriend($pdo, $userId, $receiverId);
        $rs       = getRequestStatus($pdo, $userId, $receiverId);

        if (!$isFriend) {
            if ($rs['exists'] && $rs['accepted']) {
                // Accepted request — full messaging allowed, fall through
            } elseif ($rs['exists'] && !$rs['i_am_requester']) {
                // I am the receiver of a pending request — must accept before replying
                echo json_encode(['status' => 'error', 'message' => 'Accept the message request to reply', 'error_code' => 'request_pending_received']);
                exit;
            } elseif (!$rs['exists']) {
                // First message from a non-friend — create the request
                $ins = $pdo->prepare("INSERT IGNORE INTO message_requests (requester_id, receiver_id, accepted) VALUES (?, ?, 0)");
                $ins->execute([$userId, $receiverId]);
            }
            // If $rs['exists'] && $rs['i_am_requester'] && !$rs['accepted'] → requester can keep sending
        }

        // Handle media upload
        $mediaUrl = '';
        if (isset($_FILES['file']) && $_FILES['file']['error'] == 0) {
            $ext      = pathinfo($_FILES['file']['name'], PATHINFO_EXTENSION);
            $filename = uniqid('chat_') . '.' . $ext;
            $dest     = __DIR__ . '/../../uploads/' . $filename;
            if (move_uploaded_file($_FILES['file']['tmp_name'], $dest)) {
                $proto    = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off') ? 'https' : 'http';
                $host     = $_SERVER['HTTP_HOST'] ?? 'goreto.org';
                $mediaUrl = $proto . '://' . $host . '/ekloadmin/uploads/' . $filename;
            }
        }

        $stmt = $pdo->prepare("INSERT INTO messages (sender_id, receiver_id, type, content, media_url, voice_duration, status, created_at) VALUES (?, ?, ?, ?, ?, ?, 'sent', NOW())");
        $stmt->execute([$userId, $receiverId, $type, $content, $mediaUrl, $voiceDur]);
        $msgId = $pdo->lastInsertId();

        require_once __DIR__ . '/notification_helper.php';
        $uname = 'Someone';
        try {
            $uSt = $pdo->prepare('SELECT name FROM users WHERE id=?');
            $uSt->execute([$userId]);
            $uname = $uSt->fetchColumn() ?: 'Someone';
        } catch (Exception $e) {}

        $msgText = $type === 'text' ? substr($content, 0, 40) : "Sent a $type message";
        send_app_notification($pdo, $receiverId, $userId, 'chat', "Message from $uname", $msgText);

        $fSt = $pdo->prepare('SELECT * FROM messages WHERE id = ?');
        $fSt->execute([$msgId]);
        $newMsg = $fSt->fetch(PDO::FETCH_ASSOC);

        $rsLabel = requestStatusLabel(
            $rs['exists'] ? $rs : ['exists' => true, 'accepted' => false, 'i_am_requester' => true],
            $isFriend
        );

        echo json_encode(['status' => 'success', 'message' => $newMsg, 'request_status' => $rsLabel, 'is_friend' => $isFriend]);
    }

    // ── accept_request ────────────────────────────────────────────────────────
    elseif ($action === 'accept_request') {
        $requesterId = (int)($_POST['requester_id'] ?? 0);
        if ($requesterId <= 0) {
            echo json_encode(['status' => 'error', 'message' => 'Missing requester_id']);
            exit;
        }
        $upd = $pdo->prepare("UPDATE message_requests SET accepted=1 WHERE requester_id=? AND receiver_id=?");
        $upd->execute([$requesterId, $userId]);
        if ($upd->rowCount() === 0) {
            // Row may not exist yet (edge case: both followed each other before first message)
            $ins = $pdo->prepare("INSERT IGNORE INTO message_requests (requester_id, receiver_id, accepted) VALUES (?, ?, 1)");
            $ins->execute([$requesterId, $userId]);
        }
        echo json_encode(['status' => 'success']);
    }

    // ── decline_request ───────────────────────────────────────────────────────
    elseif ($action === 'decline_request') {
        $requesterId = (int)($_POST['requester_id'] ?? 0);
        if ($requesterId <= 0) {
            echo json_encode(['status' => 'error', 'message' => 'Missing requester_id']);
            exit;
        }
        // Delete the request record
        $pdo->prepare("DELETE FROM message_requests WHERE requester_id=? AND receiver_id=?")->execute([$requesterId, $userId]);
        // Delete all messages between them
        $pdo->prepare("DELETE FROM messages WHERE (sender_id=? AND receiver_id=?) OR (sender_id=? AND receiver_id=?)")->execute([$requesterId, $userId, $userId, $requesterId]);
        echo json_encode(['status' => 'success']);
    }

    // ── get_unread_count ──────────────────────────────────────────────────────
    elseif ($action === 'get_unread_count') {
        $stmt = $pdo->prepare("SELECT COUNT(*) FROM messages WHERE receiver_id = ? AND status != 'read'");
        $stmt->execute([$userId]);
        $count = $stmt->fetchColumn();
        echo json_encode(['status' => 'success', 'unread_count' => $count]);
    }

    // ── mark_read ─────────────────────────────────────────────────────────────
    elseif ($action === 'mark_read') {
        $senderId = $_POST['sender_id'] ?? 0;
        $stmt = $pdo->prepare("UPDATE messages SET status='read', read_at=NOW() WHERE receiver_id=? AND sender_id=? AND status!='read'");
        $stmt->execute([$userId, $senderId]);
        echo json_encode(['status' => 'success']);
    }

    // ── mark_delivered ────────────────────────────────────────────────────────
    elseif ($action === 'mark_delivered') {
        $senderId = $_POST['sender_id'] ?? 0;
        $stmt = $pdo->prepare("UPDATE messages SET status='delivered' WHERE receiver_id=? AND sender_id=? AND status='sent'");
        $stmt->execute([$userId, $senderId]);
        echo json_encode(['status' => 'success']);
    }

    // ── delete_conversation ───────────────────────────────────────────────────
    elseif ($action === 'delete_conversation') {
        $otherUserId = (int)($_POST['other_user_id'] ?? 0);
        if ($otherUserId <= 0) {
            echo json_encode(['status' => 'error', 'message' => 'Invalid user ID']);
            exit;
        }
        $stmt = $pdo->prepare('DELETE FROM messages WHERE (sender_id = ? AND receiver_id = ?) OR (sender_id = ? AND receiver_id = ?)');
        $stmt->execute([$userId, $otherUserId, $otherUserId, $userId]);
        $deleted = $stmt->rowCount();
        // Also clean up any request record
        $pdo->prepare("DELETE FROM message_requests WHERE (requester_id=? AND receiver_id=?) OR (requester_id=? AND receiver_id=?)")->execute([$userId, $otherUserId, $otherUserId, $userId]);
        echo json_encode(['status' => 'success', 'deleted_count' => $deleted]);
    }

    else {
        echo json_encode(['status' => 'error', 'message' => 'Unknown action']);
    }
}
catch (Throwable $e) {
    http_response_code(500);
    echo json_encode(['status' => 'error', 'message' => $e->getMessage()]);
}
?>
