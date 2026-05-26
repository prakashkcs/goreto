<?php
require_once __DIR__ . '/db_connect.php';
try {
    // Sync users with kyc_verifications
    $q = $pdo->query("SELECT user_id, status FROM kyc_verifications");
    $vers = $q->fetchAll(PDO::FETCH_ASSOC);
    $count = 0;
    foreach ($vers as $v) {
        $st = $pdo->prepare("UPDATE users SET kyc_status=? WHERE id=?");
        $st->execute([$v['status'], $v['user_id']]);
        $count += $st->rowCount();
    }
    echo "Synced $count users.\n";
    
    // Also fix any 'approved' to 'verified' just in case
    $q1 = $pdo->query("UPDATE kyc_verifications SET status='verified' WHERE status='approved'");
    echo "Converted " . $q1->rowCount() . " 'approved' to 'verified' in kyc_verifications.\n";
    
    $q2 = $pdo->query("UPDATE users SET kyc_status='verified' WHERE kyc_status='approved'");
    echo "Converted " . $q2->rowCount() . " 'approved' to 'verified' in users.\n";
    
} catch (Exception $e) {
    echo "Error: " . $e->getMessage();
}
?>
