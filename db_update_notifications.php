<?php
require_once __DIR__ . '/db_connect.php';

try {
    // ── Auto-create notifications table ──
    $pdo->exec("
        CREATE TABLE IF NOT EXISTS notifications (
            id INT AUTO_INCREMENT PRIMARY KEY,
            user_id INT NOT NULL,          -- Receiver
            sender_id INT DEFAULT 0,       -- 0 for System/Admin
            type VARCHAR(50) NOT NULL,     -- e.g., 'system', 'follow', 'gift', 'message', 'call', 'proposal'
            title VARCHAR(255) NOT NULL,
            message TEXT NOT NULL,
            reference_id INT DEFAULT NULL, -- ID of the related entity (e.g., post_id, message_id)
            is_read TINYINT DEFAULT 0,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            INDEX idx_user (user_id),
            INDEX idx_unread (user_id, is_read)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ");
    echo "Notifications table created successfully.\n";
}
catch (PDOException $e) {
    echo "Error creating table: " . $e->getMessage() . "\n";
}
?>
