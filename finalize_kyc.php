<?php
require_once __DIR__ . '/db_connect.php';

try {
    echo "Altering kyc_submissions table...\n";
    $pdo->query("ALTER TABLE kyc_submissions MODIFY COLUMN status ENUM('pending','approved','rejected','verified') NOT NULL DEFAULT 'pending'");
    echo "kyc_submissions altered successfully.\n";

    echo "Re-running ultimate sync...\n";
    // Clean verifications
    $pdo->query("DELETE FROM kyc_verifications WHERE id NOT IN (SELECT id FROM (SELECT MAX(id) as id FROM kyc_verifications GROUP BY user_id) as tmp)");
    
    // Clean submissions
    $pdo->query("DELETE FROM kyc_submissions WHERE id NOT IN (SELECT id FROM (SELECT MAX(id) as id FROM kyc_submissions GROUP BY user_id) as tmp)");

    // Sync
    $st = $pdo->query("SELECT user_id, status FROM kyc_verifications");
    $vers = $st->fetchAll(PDO::FETCH_ASSOC);
    foreach ($vers as $v) {
        $uid = $v['user_id'];
        $status = $v['status'];
        if ($status === 'approved') $status = 'verified';

        $pdo->prepare("UPDATE users SET kyc_status=? WHERE id=?")->execute([$status, $uid]);
        $pdo->prepare("UPDATE user_kyc SET basic_status=?, full_status=? WHERE user_id=?")->execute([$status, $status, $uid]);
        try {
            $pdo->prepare("UPDATE kyc_submissions SET status=? WHERE user_id=?")->execute([$status, $uid]);
        } catch (Exception $e) {}
    }
    echo "Synced " . count($vers) . " users finalized.\n";
    
    // Final check for UID 13
    $st = $pdo->prepare("SELECT basic_status FROM user_kyc WHERE user_id=13");
    $st->execute();
    echo "UID 13 final user_kyc status: " . $st->fetchColumn() . "\n";

} catch (Exception $e) {
    echo "Error: " . $e->getMessage() . "\n";
}
?>
