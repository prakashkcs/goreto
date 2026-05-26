<?php
// user_actions.php
// Modified to ensure robust disconnection logic and total_proposals synchronization using PDO

require_once 'db_connect.php';

function handleDisconnect($senderId, $targetUserId) {
    global $pdo;
    
    try {
        $pdo->beginTransaction();

        // 1. Mark existing accepted/pending proposals as 'disconnected' and hide from profile
        $stmt = $pdo->prepare("UPDATE proposals SET status = 'disconnected', show_on_profile = 0 WHERE ((sender_id = ? AND receiver_id = ?) OR (sender_id = ? AND receiver_id = ?)) AND status IN ('accepted', 'pending')");
        $stmt->execute([$senderId, $targetUserId, $targetUserId, $senderId]);

        // 2. Synchronize total_proposals for BOTH users
        // Use a subquery to count ACTUAL accepted/pending connections for each user
        $syncSql = "UPDATE users SET total_proposals = (SELECT COUNT(*) FROM proposals WHERE (sender_id = users.id OR receiver_id = users.id) AND status IN ('pending', 'accepted')) WHERE id IN (?, ?)";
        $syncStmt = $pdo->prepare($syncSql);
        $syncStmt->execute([$senderId, $targetUserId]);

        $pdo->commit();
        return ["status" => "success", "message" => "Disconnected successfully and counts synchronized"];
    } catch (Exception $e) {
        if ($pdo->inTransaction()) {
            $pdo->rollBack();
        }
        return ["status" => "error", "message" => "Database error: " . $e->getMessage()];
    }
}

// Check if this script is being called directly for an action
if (basename($_SERVER['PHP_SELF']) == 'user_actions.php') {
    $action = $_POST['action'] ?? $_GET['action'] ?? '';
    
    if ($action == 'disconnect') {
        $senderId = (int)($_POST['sender_id'] ?? 0);
        $targetUserId = (int)($_POST['target_user_id'] ?? 0);
        
        if ($senderId > 0 && $targetUserId > 0) {
            $result = handleDisconnect($senderId, $targetUserId);
            echo json_encode($result);
        } else {
            echo json_encode(["status" => "error", "message" => "Invalid user IDs"]);
        }
    } else {
        echo json_encode(["status" => "error", "message" => "Unknown action"]);
    }
}
?>
