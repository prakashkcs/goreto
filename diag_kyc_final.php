<?php
header('Content-Type: text/plain');
require_once __DIR__ . '/db_connect.php';

echo "--- KYC DIAGNOSTIC ---\n\n";

try {
    // 1. Check users table schema for kyc_status
    echo "Checking 'users' table columns:\n";
    $st = $pdo->query("SHOW COLUMNS FROM users LIKE 'kyc_status'");
    $col = $st->fetch(PDO::FETCH_ASSOC);
    if ($col) {
        print_r($col);
    } else {
        echo "COLUMN 'kyc_status' DOES NOT EXIST IN 'users' TABLE!\n";
    }
    echo "\n";

    // 2. Check kyc_verifications table status ENUM
    echo "Checking 'kyc_verifications' table status column:\n";
    $st = $pdo->query("SHOW COLUMNS FROM kyc_verifications LIKE 'status'");
    $col = $st->fetch(PDO::FETCH_ASSOC);
    print_r($col);
    echo "\n";

    // 3. Get latest 5 users and their kyc_status
    echo "Latest 5 User KYC Statuses:\n";
    $st = $pdo->query("SELECT id, name, username, kyc_status FROM users ORDER BY id DESC LIMIT 5");
    $users = $st->fetchAll(PDO::FETCH_ASSOC);
    foreach ($users as $u) {
        echo "ID: {$u['id']}, Name: {$u['name']}, User: {$u['username']}, Status: '{$u['kyc_status']}'\n";
    }
    echo "\n";

    // 4. Get latest 5 KYC verifications
    echo "Latest 5 KYC Verifications:\n";
    $st = $pdo->query("SELECT id, user_id, status, submitted_at FROM kyc_verifications ORDER BY id DESC LIMIT 5");
    $kv = $st->fetchAll(PDO::FETCH_ASSOC);
    foreach ($kv as $k) {
        echo "ID: {$k['id']}, UID: {$k['user_id']}, Status: '{$k['status']}', At: {$k['submitted_at']}\n";
    }
    echo "\n";

    // 5. Test Update
    /*
    echo "Testing Update for latest pending user...\n";
    $st = $pdo->query("SELECT user_id FROM kyc_verifications WHERE status='pending' ORDER BY id DESC LIMIT 1");
    $row = $st->fetch();
    if ($row) {
        $uid = $row['user_id'];
        echo "Found pending UID: $uid. Attempting to set to 'rejected'...\n";
        $ret = $pdo->prepare("UPDATE users SET kyc_status='rejected' WHERE id=?")->execute([$uid]);
        echo "Update result: " . ($ret ? "SUCCESS" : "FAIL") . "\n";
        $st = $pdo->prepare("SELECT kyc_status FROM users WHERE id=?");
        $st->execute([$uid]);
        echo "New status in DB: '" . $st->fetchColumn() . "'\n";
    }
    */

} catch (Exception $e) {
    echo "ERROR: " . $e->getMessage() . "\n";
}
?>
