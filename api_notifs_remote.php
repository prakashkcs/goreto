<?php
// api_notifications.php
header('Content-Type: application/json; charset=utf-8');

require_once __DIR__ . '/db_connect.php';
require_once __DIR__ . '/auth_middleware.php';

try {
    // Read JSON payload if available (used by Flutter Dio)
    $input = file_get_contents('php://input');
    if (!empty($input)) {
        $json = json_decode($input, true);
        if (is_array($json)) {
            $_REQUEST = array_merge($_REQUEST, $json);
            $_POST = array_merge($_POST, $json);
        }
    }

    $user = requireUser($pdo);
    $userId = $user['id'];
    $action = $_REQUEST['action'] ?? 'list';

    if ($action === 'list') {
        $page = isset($_GET['page']) ? (int)$_GET['page'] : 1;
        $limit = 20;
        $offset = ($page - 1) * $limit;

        // Fetch notifications and join sender info
        $stmt = $pdo->prepare("
            SELECT n.id, n.sender_id, n.type, n.title, n.message, n.reference_id, n.is_read, n.created_at,
                   u.name AS sender_name, u.full_name AS sender_full_name, u.profile_pic AS sender_avatar
            FROM notifications n
            LEFT JOIN users u ON u.id = n.sender_id AND n.sender_id > 0
            WHERE n.user_id = ?
            ORDER BY n.created_at DESC
            LIMIT ? OFFSET ?
        ");
        $stmt->bindValue(1, $userId, PDO::PARAM_INT);
        $stmt->bindValue(2, $limit, PDO::PARAM_INT);
        $stmt->bindValue(3, $offset, PDO::PARAM_INT);
        $stmt->execute();
        $notifications = $stmt->fetchAll(PDO::FETCH_ASSOC);

        // Format dates relative (or pass raw and format in Flutter)
        foreach ($notifications as &$notif) {
            $notif['is_read'] = (bool)$notif['is_read'];
            $notif['id'] = (int)$notif['id'];
        }

        echo json_encode(['status' => true, 'data' => $notifications]);
    }
    elseif ($action === 'unread_count') {
        $stmt = $pdo->prepare("SELECT COUNT(*) FROM notifications WHERE user_id = ? AND is_read = 0");
        $stmt->execute([$userId]);
        $count = $stmt->fetchColumn();
        echo json_encode(['status' => true, 'count' => (int)$count]);
    }
    elseif ($action === 'mark_read') {
        // Can mark a specific one or all
        $notifId = $_POST['id'] ?? $_POST['notification_id'] ?? null;
        if ($notifId) {
            $stmt = $pdo->prepare("UPDATE notifications SET is_read = 1 WHERE user_id = ? AND id = ?");
            $stmt->execute([$userId, $notifId]);
        }
        else {
            $stmt = $pdo->prepare("UPDATE notifications SET is_read = 1 WHERE user_id = ?");
            $stmt->execute([$userId]);
        }
        echo json_encode(['status' => true]);
    }
    else {
        http_response_code(400);
        echo json_encode(['status' => false, 'message' => 'Invalid action']);
    }
}
catch (Exception $e) {
    http_response_code(500);
    echo json_encode(['status' => false, 'message' => $e->getMessage()]);
}
?>
