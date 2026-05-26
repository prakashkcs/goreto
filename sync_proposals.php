<?php
error_reporting(E_ALL);
ini_set('display_errors', 1);

require_once 'db_connect.php';

try {
    // Sync total_proposals for all users based on accepted proposals in proposals table where show_on_profile = 1
    $sql = "UPDATE users u 
            SET u.total_proposals = (
                SELECT COUNT(*) 
                FROM proposals p 
                WHERE (p.sender_id = u.id OR p.receiver_id = u.id) 
                AND p.status = 'accepted' 
                AND p.show_on_profile = 1
            )";

    $count = $pdo->exec($sql);
    echo "Successfully synchronized total_proposals for users. Rows affected: $count";
} catch (PDOException $e) {
    echo "Error synchronizing: " . $e->getMessage();
}
?>
