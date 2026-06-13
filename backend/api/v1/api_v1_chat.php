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

            $res[] = [
                'other_user_id' => $otherId,
                'other_user_name' => $other ? $other['name'] : 'User',
                'other_user_avatar' => $other ? $other['profile_pic'] : '',
                'last_message' => $lastMsg,
                'unread_count' => $unread,
                'updated_at' => $c['last_interaction']
            ];
        }
        echo json_encode(['status' => 'success', 'conversations' => $res]);
    }
    elseif ($action === 'get_messages') {
        $withUserId = $_GET['with_user_id'] ?? 0;
        $rSt = $pdo->prepare('UPDATE messages SET status=\'read\', read_at=NOW() WHERE receiver_id=? AND sender_id=? AND status!=\'read\'');
        $rSt->execute([$userId, $withUserId]);
        $stmt = $pdo->prepare('SELECT * FROM messages WHERE (sender_id = ? AND receiver_id = ?) OR (sender_id = ? AND receiver_id = ?) ORDER BY created_at ASC LIMIT 200');
        $stmt->execute([$userId, $withUserId, $withUserId, $userId]);
        $msgs = $stmt->fetchAll(PDO::FETCH_ASSOC);
        echo json_encode(['status' => 'success', 'messages' => $msgs]);
    }
    elseif ($action === 'get_new_messages') {
        $withUserId = (int)($_GET['with_user_id'] ?? 0);
        $lastId = (int)($_GET['last_id'] ?? 0);
        $rSt = $pdo->prepare('UPDATE messages SET status=\'read\', read_at=NOW() WHERE receiver_id=? AND sender_id=? AND id > ? AND status!=\'read\'');
        $rSt->execute([$userId, $withUserId, $lastId]);
        $stmt = $pdo->prepare('SELECT * FROM messages WHERE id > ? AND ((sender_id = ? AND receiver_id = ?) OR (sender_id = ? AND receiver_id = ?)) ORDER BY created_at ASC');
        $stmt->execute([$lastId, $userId, $withUserId, $withUserId, $userId]);
        $msgs = $stmt->fetchAll(PDO::FETCH_ASSOC);
        echo json_encode(['status' => 'success', 'messages' => $msgs]);
    }
    elseif ($action === 'send_message') {
        $receiverId = (int)($_POST['receiver_id'] ?? 0);
        $type = $_POST['type'] ?? 'text';
        $content = $_POST['content'] ?? '';
        $voiceDur = $_POST['voice_duration'] ?? 0;

        // Privacy: check if receiver allows messages from non-followers
        if ($receiverId > 0 && $receiverId !== $userId) {
            $privSt = $pdo->prepare("SELECT COALESCE(privacy_allow_unknown_inbox, 1) AS allow_inbox FROM users WHERE id = ? LIMIT 1");
            $privSt->execute([$receiverId]);
            $privRow = $privSt->fetch(PDO::FETCH_ASSOC);
            if ($privRow && (int)$privRow['allow_inbox'] === 0) {
                // Check if sender follows receiver
                $followSt = $pdo->prepare("SELECT 1 FROM follows WHERE follower_id = ? AND following_id = ? LIMIT 1");
                $followSt->execute([$userId, $receiverId]);
                if (!$followSt->fetchColumn()) {
                    echo json_encode(['status' => 'error', 'message' => 'This user only accepts messages from people they follow.']);
                    exit;
                }
            }
        }

        $mediaUrl = '';
        if (isset($_FILES['file']) && $_FILES['file']['error'] == 0) {
            $ext = pathinfo($_FILES['file']['name'], PATHINFO_EXTENSION);
            $filename = uniqid('chat_') . '.' . $ext;
            // Use parent directory's uploads folder if we are in api/v1/
            $dest = __DIR__ . '/../../uploads/' . $filename;
            if (move_uploaded_file($_FILES['file']['tmp_name'], $dest)) {
                $mediaUrl = 'https://goreto.org/ekloadmin/uploads/' . $filename;
            }
        }

        $stmt = $pdo->prepare('INSERT INTO messages (sender_id, receiver_id, type, content, media_url, voice_duration, status, created_at) VALUES (?, ?, ?, ?, ?, ?, \'sent\', NOW())');
        $stmt->execute([$userId, $receiverId, $type, $content, $mediaUrl, $voiceDur]);
        $msgId = $pdo->lastInsertId();

        // Send Push Notification
        try {
            require_once __DIR__ . '/notification_helper.php';
            $uSt = $pdo->prepare('SELECT name FROM users WHERE id = ?');
            $uSt->execute([$userId]);
            $uname = $uSt->fetchColumn() ?: 'Somebody';
            send_app_notification($pdo, $receiverId, $userId, 'chat', "Message from $uname", $content, $msgId);
        } catch (Throwable $ignore) {}

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
    else {
        echo json_encode(['status' => 'error', 'message' => 'Unknown action']);
    }
}
catch (Throwable $e) {
    http_response_code(500);
    echo json_encode(['status' => 'error', 'message' => $e->getMessage()]);
}
?>
