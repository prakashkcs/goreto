<?php
require_once __DIR__ . '/db_connect.php';

try {
    $sql = "CREATE TABLE IF NOT EXISTS follows (
        id INT AUTO_INCREMENT PRIMARY KEY,
        follower_id INT NOT NULL,
        following_id INT NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        UNIQUE KEY unique_follow (follower_id, following_id)
    )";
    $pdo->exec($sql);
    echo json_encode(["status" => true, "message" => "Table 'follows' created or already exists."]);
} catch (PDOException $e) {
    http_response_code(500);
    echo json_encode(["status" => false, "message" => "DB Error: " . $e->getMessage()]);
}
