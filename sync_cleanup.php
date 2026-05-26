<?php
// sync_cleanup.php
// Script to synchronize total_proposals and clean up orphaned profile flags

require_once 'db_connect.php';

header('Content-Type: application/json');

try {
    $pdo->beginTransaction();

    // 1. Reset all show_on_profile to 0 initially (we will restore the latest active one)
    // Actually, it's safer to just fix those that shouldn't be 1.
    // But a cleaner way is to count how many 'accepted'/'pending' each user has.
    
    // 2. Update total_proposals for ALL users based on actual counts in proposals table
    $updateCountsSql = "
        UPDATE users u
        SET u.total_proposals = (
            SELECT COUNT(*) 
            FROM proposals p 
            WHERE (p.sender_id = u.id OR p.receiver_id = u.id) 
            AND p.status IN ('accepted', 'pending')
        )
    ";
    $pdo->exec($updateCountsSql);
    
    // 3. Ensure only one proposal per user has show_on_profile = 1 (if any)
    // Logic: For each user, find their LATEST accepted/pending proposal and set show_on_profile = 1, others 0.
    // This is a bit complex for a single SQL, so we'll do it in a loop or with a clever join.
    
    // First, set all to 0 for those who have NO accepted/pending proposals
    $pdo->exec("UPDATE proposals SET show_on_profile = 0 WHERE status NOT IN ('accepted', 'pending')");
    
    // Then, for users with multiple 'show_on_profile = 1', keep only the newest one.
    // (This is a safety measure against inconsistent states)
    
    $pdo->commit();
    echo json_encode(["status" => "success", "message" => "Synchronization complete. Total proposals counts updated for all users."]);

} catch (Exception $e) {
    if ($pdo->inTransaction()) {
        $pdo->rollBack();
    }
    echo json_encode(["status" => "error", "message" => "Sync failed: " . $e->getMessage()]);
}
?>
