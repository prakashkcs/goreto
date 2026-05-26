<?php
header('Content-Type: application/json');
require_once __DIR__ . '/db_connect.php';

$res = [
    'fcm_v1_exists' => file_exists(__DIR__ . '/fcm_v1.php'),
    'service_account_exists' => file_exists(__DIR__ . '/service_account.json'),
    'notifications_table_exists' => false
];

try {
    $st = $pdo->query("SHOW TABLES LIKE 'notifications'");
    $res['notifications_table_exists'] = $st->rowCount() > 0;
} catch (Exception $e) {
    $res['notifications_error'] = $e->getMessage();
}

if (!$res['notifications_table_exists']) {
    try {
        $pdo->exec("
            CREATE TABLE IF NOT EXISTS notifications (
                id BIGINT AUTO_INCREMENT PRIMARY KEY,
                user_id INT NOT NULL,
                sender_id INT NOT NULL DEFAULT 0,
                type VARCHAR(50) NOT NULL,
                title VARCHAR(191) NOT NULL,
                message TEXT NOT NULL,
                reference_id VARCHAR(100) NULL,
                is_read TINYINT(1) DEFAULT 0,
                created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                INDEX(user_id),
                INDEX(sender_id),
                INDEX(type),
                INDEX(is_read)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        ");
        $res['notifications_table_created'] = true;
    } catch (Exception $e) {
        $res['notifications_create_error'] = $e->getMessage();
    }
}

echo json_encode(['status' => 'success', 'data' => $res]);
