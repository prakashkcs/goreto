<?php
// sync_all.php - One-time script to fix total_proposals and hide disconnected proposals
require_once 'db_connect.php';

echo "Starting synchronization...\n";

try {
    // 1. Hide all disconnected, rejected, or canceled proposals from profiles
    $stmt = $pdo->prepare("UPDATE proposals SET show_on_profile = 0 WHERE status NOT IN ('accepted', 'pending')");
    $stmt->execute();
    echo "Hidden non-active proposals: " . $stmt->rowCount() . " rows updated.\n";

    // 2. Synchronize total_proposals for all users
    $syncSql = "UPDATE users SET total_proposals = (SELECT COUNT(*) FROM proposals WHERE (sender_id = users.id OR receiver_id = users.id) AND status IN ('pending', 'accepted'))";
    $stmt = $pdo->prepare($syncSql);
    $stmt->execute();
    echo "Synchronized total_proposals for all users: " . $stmt->rowCount() . " rows updated.\n";

    echo "Synchronization complete.\n";
} catch (Exception $e) {
    echo "Error: " . $e->getMessage() . "\n";
}
?>
