<?php
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    echo json_encode(['status' => true]);
    exit;
}

require_once __DIR__ . '/db_connect.php';
require_once __DIR__ . '/auth_middleware.php';

function ensure_notifications_table(PDO $pdo): void
{
    try {
        $pdo->query("SELECT 1 FROM app_notifications LIMIT 1");
    }
    catch (Throwable $e) {
        $pdo->exec("
            CREATE TABLE IF NOT EXISTS app_notifications (
                id INT AUTO_INCREMENT PRIMARY KEY,
                user_id INT NULL, -- NULL means ALL users
                title VARCHAR(255) NOT NULL,
                body TEXT NOT NULL,
                is_read TINYINT(1) DEFAULT 0,
                created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                INDEX(user_id),
                INDEX(is_read)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        ");
    }
}

try {
    ensure_notifications_table($pdo);
    $viewer = requireUser($pdo);
    $user_id = (int)$viewer['id'];

    if ($_SERVER['REQUEST_METHOD'] === 'GET') {
        // Fetch unread notifications for this user OR 'all users' that haven't been marked read in a tracking table
        // For simplicity, we just fetch the last 5 notifications for this user or global, created in the last 24 hours.
        $st = $pdo->prepare("
            SELECT id, title, body, created_at 
            FROM app_notifications 
            WHERE (user_id = ? OR user_id = 0 OR user_id IS NULL) 
            AND is_read = 0
            ORDER BY created_at DESC 
            LIMIT 5
        ");
        $st->execute([$user_id]);
        $notifs = $st->fetchAll(PDO::FETCH_ASSOC);

        echo json_encode(['status' => true, 'data' => $notifs]);
    }

    // Action to mark read
    if ($_SERVER['REQUEST_METHOD'] === 'POST') {
        $raw = file_get_contents('php://input');
        $body = json_decode($raw, true) ?? $_POST;
        if (isset($body['action']) && $body['action'] == 'mark_read') {
            $notif_id = (int)($body['notification_id'] ?? 0);
            if ($notif_id > 0) {
                // Fix: Allow marking as read even if the notification was global (user_id IS NULL or 0)
                $pdo->prepare("UPDATE app_notifications SET is_read=1 WHERE id=? AND (user_id=? OR user_id IS NULL OR user_id=0)")->execute([$notif_id, $user_id]);
            }
        }
        echo json_encode(['status' => true]);
    }

}
catch (Throwable $e) {
    echo json_encode(['status' => false, 'message' => $e->getMessage()]);
}
?>
