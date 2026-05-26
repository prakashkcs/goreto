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

try {
    $viewer = requireUser($pdo);
    $userId = (int)$viewer['id'];
    $action = $_REQUEST['action'] ?? '';

    if ($action === 'get_conversations') {
        $stmt = $pdo->prepare('
            SELECT 
                CASE WHEN sender_id = ? THEN receiver_id ELSE sender_id END as other_user_id,
                MAX(created_at) as last_interaction
            FROM messages 
            WHERE sender_id = ? OR receiver_id = ?
            GROUP BY other_user_id
            ORDER BY last_interaction DESC
        ');
        $stmt->execute([$userId, $userId, $userId]);
        $convs = $stmt->fetchAll(PDO::FETCH_ASSOC);

        $res = [];
        foreach ($convs as $c) {
            $otherId = $c['other_user_id'];
            $uSt = $pdo->prepare('SELECT name, profile_pic FROM users WHERE id = ?');
            $uSt->execute([$otherId]);
            $other = $uSt->fetch(PDO::FETCH_ASSOC);

            $mSt = $pdo->prepare('SELECT * FROM messages WHERE (sender_id = ? AND receiver_id = ?) OR (sender_id = ? AND receiver_id = ?) ORDER BY created_at DESC LIMIT 1');
            $mSt->execute([$userId, $otherId, $otherId, $userId]);
            $lastMsg = $mSt->fetch(PDO::FETCH_ASSOC);

            $urSt = $pdo->prepare('SELECT COUNT(*) FROM messages WHERE receiver_id = ? AND sender_id = ? AND status != \'read\'');
            $urSt->execute([$userId, $otherId]);
            $unread = $urSt->fetchColumn();

            $rawPic = $other ? ($other['profile_pic'] ?? '') : '';
            $avatarUrl = $rawPic
                ? (preg_match('~^https?://~i', $rawPic) ? $rawPic : 'https://goreto.org/ekloadmin/' . ltrim($rawPic, '/'))
                : '';
            $res[] = [
                'other_user_id' => $otherId,
                'other_user_name' => $other ? $other['name'] : 'User',
                'other_user_avatar' => $avatarUrl,
                'last_message' => $lastMsg,
                'unread_count' => $unread,
                'updated_at' => $c['last_interaction']
            ];
        }
        echo json_encode(['status' => 'success', 'conversations' => $res]);
    }
    elseif ($action === 'get_messages') {
        $withUserId = $_GET['with_user_id'] ?? 0;

        $bSt = $pdo->prepare('SELECT blocker_id, blocked_id FROM user_blocks WHERE (blocker_id = ? AND blocked_id = ?) OR (blocker_id = ? AND blocked_id = ?)');
        $bSt->execute([$userId, $withUserId, $withUserId, $userId]);
        $blocks = $bSt->fetchAll(PDO::FETCH_ASSOC);
        $isBlockedByMe = false;
        $isBlockedByThem = false;
        foreach ($blocks as $b) {
            if ($b['blocker_id'] == $userId) $isBlockedByMe = true;
            if ($b['blocker_id'] == $withUserId) $isBlockedByThem = true;
        }

        $rSt = $pdo->prepare('UPDATE messages SET status=\'read\', read_at=NOW() WHERE receiver_id=? AND sender_id=? AND status!=\'read\'');
        $rSt->execute([$userId, $withUserId]);
        $stmt = $pdo->prepare('SELECT * FROM messages WHERE (sender_id = ? AND receiver_id = ?) OR (sender_id = ? AND receiver_id = ?) ORDER BY created_at ASC LIMIT 200');
        $stmt->execute([$userId, $withUserId, $withUserId, $userId]);
        $msgs = $stmt->fetchAll(PDO::FETCH_ASSOC);
        
        echo json_encode([
            'status' => 'success', 
            'messages' => $msgs,
            'is_blocked_by_me' => $isBlockedByMe,
            'is_blocked_by_them' => $isBlockedByThem
        ]);
    }
    elseif ($action === 'get_new_messages') {
        $withUserId = (int)($_GET['with_user_id'] ?? 0);
        $lastId = (int)($_GET['last_id'] ?? 0);
        $rSt = $pdo->prepare('UPDATE messages SET status=\'read\', read_at=NOW() WHERE receiver_id=? AND sender_id=? AND id > ? AND status!=\'read\'');
        $rSt->execute([$userId, $withUserId, $lastId]);
        $stmt = $pdo->prepare('SELECT * FROM messages WHERE id > ? AND ((sender_id = ? AND receiver_id = ?) OR (sender_id = ? AND receiver_id = ?)) ORDER BY created_at ASC');
        $stmt->execute([$lastId, $userId, $withUserId, $withUserId, $userId]);
        $msgs = $stmt->fetchAll(PDO::FETCH_ASSOC);

        // Fetch updated statuses for messages the user sent
        $stmt2 = $pdo->prepare('SELECT id, status, read_at FROM messages WHERE sender_id = ? AND receiver_id = ? AND status IN (\'delivered\', \'read\')');
        $stmt2->execute([$userId, $withUserId]);
        $statusUpdates = $stmt2->fetchAll(PDO::FETCH_ASSOC);

        echo json_encode(['status' => 'success', 'messages' => $msgs, 'status_updates' => $statusUpdates]);
    }
    elseif ($action === 'send_message') {
        $receiverId = (int)($_POST['receiver_id'] ?? 0);
        $type = $_POST['type'] ?? 'text';
        $content = $_POST['content'] ?? '';
        $voiceDur = $_POST['voice_duration'] ?? 0;

        // --- Block Check ---
        $bSt = $pdo->prepare('SELECT blocker_id, blocked_id FROM user_blocks WHERE (blocker_id = ? AND blocked_id = ?) OR (blocker_id = ? AND blocked_id = ?) LIMIT 1');
        $bSt->execute([$userId, $receiverId, $receiverId, $userId]);
        $block = $bSt->fetch(PDO::FETCH_ASSOC);
        if ($block) {
            echo json_encode(['status' => 'error', 'message' => $block['blocker_id'] == $userId ? 'You have blocked this user' : 'User unavailable']);
            exit;
        }

        // --- Stranger message restriction ---
        // Check if receiver has privacy_allow_unknown_inbox = 0
        $privSt = $pdo->prepare('SELECT COALESCE(privacy_allow_unknown_inbox, 1) AS allow_inbox FROM users WHERE id = ?');
        $privSt->execute([$receiverId]);
        $allowInbox = (int)($privSt->fetchColumn() ?? 1);
        if ($allowInbox === 0) {
            // Allow only if they are mutual followers (friends)
            $friendSt = $pdo->prepare('SELECT COUNT(*) FROM follows WHERE follower_id = ? AND following_id = ?');
            $friendSt->execute([$userId, $receiverId]);
            $iFollow = (int)$friendSt->fetchColumn();
            $friendSt->execute([$receiverId, $userId]);
            $theyFollow = (int)$friendSt->fetchColumn();
            if (!($iFollow && $theyFollow)) {
                echo json_encode(['status' => 'error', 'message' => 'This user only accepts messages from friends (mutual followers)']);
                exit;
            }
        }

        $mediaUrl = '';
        if (isset($_FILES['file']) && $_FILES['file']['error'] == 0) {
            $ext = pathinfo($_FILES['file']['name'], PATHINFO_EXTENSION);
            $filename = uniqid('chat_') . '.' . $ext;
            $dest = __DIR__ . '/../../uploads/' . $filename;
            if (move_uploaded_file($_FILES['file']['tmp_name'], $dest)) {
                $proto = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off') ? 'https' : 'http';
                $host  = $_SERVER['HTTP_HOST'] ?? 'goreto.org';
                $mediaUrl = $proto . '://' . $host . '/ekloadmin/uploads/' . $filename;
            }
        }

        $stmt = $pdo->prepare('INSERT INTO messages (sender_id, receiver_id, type, content, media_url, voice_duration, status, created_at) VALUES (?, ?, ?, ?, ?, ?, \'sent\', NOW())');
        $stmt->execute([$userId, $receiverId, $type, $content, $mediaUrl, $voiceDur]);
        $msgId = $pdo->lastInsertId();

        require_once __DIR__ . '/notification_helper.php';
        $uname = 'Someone';
        try {
            $uSt = $pdo->prepare('SELECT name FROM users WHERE id=?');
            $uSt->execute([$userId]);
            $uname = $uSt->fetchColumn() ?: 'Someone';
        }
        catch (Exception $e) {
        }

        $msgText = $type === 'text' ? substr($content, 0, 40) : "Sent a $type message";
        send_app_notification($pdo, $receiverId, $userId, 'chat', "Message from $uname", $msgText);

        $fSt = $pdo->prepare('SELECT * FROM messages WHERE id = ?');
        $fSt->execute([$msgId]);
        $newMsg = $fSt->fetch(PDO::FETCH_ASSOC);
        echo json_encode(['status' => 'success', 'message' => $newMsg]);
    }
    elseif ($action === 'get_unread_count') {
        $stmt = $pdo->prepare('SELECT COUNT(*) FROM messages WHERE receiver_id = ? AND status != \'read\'');
        $stmt->execute([$userId]);
        $count = $stmt->fetchColumn();
        echo json_encode(['status' => 'success', 'unread_count' => $count]);
    }
    elseif ($action === 'mark_read') {
        $senderId = $_POST['sender_id'] ?? 0;
        $stmt = $pdo->prepare('UPDATE messages SET status=\'read\', read_at=NOW() WHERE receiver_id=? AND sender_id=? AND status!=\'read\'');
        $stmt->execute([$userId, $senderId]);
        echo json_encode(['status' => 'success']);
    }
    elseif ($action === 'mark_delivered') {
        $senderId = $_POST['sender_id'] ?? 0;
        $stmt = $pdo->prepare('UPDATE messages SET status=\'delivered\' WHERE receiver_id=? AND sender_id=? AND status=\'sent\'');
        $stmt->execute([$userId, $senderId]);
        echo json_encode(['status' => 'success']);
    }
    elseif ($action === 'delete_conversation') {
        $otherUserId = (int)($_POST['other_user_id'] ?? 0);
        if ($otherUserId <= 0) {
            echo json_encode(['status' => 'error', 'message' => 'Invalid user ID']);
            exit;
        }
        $stmt = $pdo->prepare('DELETE FROM messages WHERE (sender_id = ? AND receiver_id = ?) OR (sender_id = ? AND receiver_id = ?)');
        $stmt->execute([$userId, $otherUserId, $otherUserId, $userId]);
        $deleted = $stmt->rowCount();
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
