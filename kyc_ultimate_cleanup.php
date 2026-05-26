<?php
require_once __DIR__ . '/db_connect.php';

echo "--- KYC ULTIMATE CLEANUP & SYNC ---\n\n";

try {
    // 1. Clean kyc_verifications: Keep only newest record per user
    echo "Cleaning kyc_verifications...\n";
    $q = $pdo->query("DELETE FROM kyc_verifications WHERE id NOT IN (
        SELECT id FROM (
            SELECT MAX(id) as id FROM kyc_verifications GROUP BY user_id
        ) as tmp
    )");
    echo "Deleted " . $q->rowCount() . " old verification records.\n";

    // 2. Clean kyc_submissions: Keep only newest record per user
    echo "Cleaning kyc_submissions...\n";
    try {
        $q = $pdo->query("DELETE FROM kyc_submissions WHERE id NOT IN (
            SELECT id FROM (
                SELECT MAX(id) as id FROM kyc_submissions GROUP BY user_id
            ) as tmp
        )");
        echo "Deleted " . $q->rowCount() . " old submission records.\n";
    } catch (Exception $e) { echo "kyc_submissions table error: " . $e->getMessage() . "\n"; }

    // 3. Sync statuses from kyc_verifications to users and user_kyc
    echo "Syncing statuses from kyc_verifications...\n";
    $st = $pdo->query("SELECT user_id, status FROM kyc_verifications");
    $vers = $st->fetchAll(PDO::FETCH_ASSOC);
    foreach ($vers as $v) {
        $uid = $v['user_id'];
        $status = $v['status'];
        if ($status === 'approved') $status = 'verified';

        // Update users
        $pdo->prepare("UPDATE users SET kyc_status=? WHERE id=?")->execute([$status, $uid]);
        
        // Update user_kyc
        try {
            $pdo->prepare("UPDATE user_kyc SET basic_status=?, full_status=? WHERE user_id=?")->execute([$status, $status, $uid]);
        } catch (Exception $e) {}
    }
    echo "Synced " . count($vers) . " users from verifications.\n";

    // 4. Force status label fix
    $pdo->query("UPDATE users SET kyc_status='verified' WHERE kyc_status='approved'");
    $pdo->query("UPDATE kyc_verifications SET status='verified' WHERE status='approved'");
    try {
        $pdo->query("UPDATE user_kyc SET basic_status='verified' WHERE basic_status='approved'");
        $pdo->query("UPDATE user_kyc SET full_status='verified' WHERE full_status='approved'");
    } catch (Exception $e) {}

    echo "\nCleanup Complete.\n";

} catch (Exception $e) {
    echo "FATAL ERROR: " . $e->getMessage() . "\n";
}
?>
