<?php
require_once __DIR__ . '/db_connect.php';

try {
    $stmt = $pdo->prepare("
        INSERT INTO live_streams (user_id, is_live, last_ping, started_at)
        VALUES (?, 1, NOW(), NOW())
        ON DUPLICATE KEY UPDATE is_live = 1, last_ping = NOW(), started_at = NOW()
    ");
    if (!$stmt->execute([1])) {
        echo "Error INSERT: ";
        print_r($stmt->errorInfo());
    } else {
        echo "Insert success.\n";
    }

    $stmt2 = $pdo->prepare("
        SELECT u.id as user_id, u.name, u.username, u.profile_pic as avatar, u.followers_count as viewers
        FROM live_streams l
        JOIN users u ON u.id = l.user_id
        WHERE l.is_live = 1
    ");
    if (!$stmt2->execute()) {
        echo "Error SELECT: ";
        print_r($stmt2->errorInfo());
    } else {
        echo "Select success.\n";
        print_r($stmt2->fetchAll(PDO::FETCH_ASSOC));
    }
} catch (Exception $e) {
    echo "Exception: " . $e->getMessage();
}
