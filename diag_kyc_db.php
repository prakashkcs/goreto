<?php
header('Content-Type: text/plain');
require_once __DIR__ . '/db_connect.php';

echo "--- KYC DB CHECK ---\n\n";

try {
    // 1. Check latest users
    echo "Latest 10 Users and KYC Status:\n";
    $st = $pdo->query("SELECT id, name, username, kyc_status FROM users ORDER BY id DESC LIMIT 10");
    $users = $st->fetchAll(PDO::FETCH_ASSOC);
    foreach ($users as $u) {
        $name = $u['name'] ?: 'No Name';
        echo "ID: {$u['id']}, Name: {$name}, Status: '{$u['kyc_status']}'\n";
    }
    echo "\n";

    // 2. Check latest verifications
    echo "Latest 10 Verifications:\n";
    $st = $pdo->query("SELECT id, user_id, status FROM kyc_verifications ORDER BY id DESC LIMIT 10");
    $kv = $st->fetchAll(PDO::FETCH_ASSOC);
    foreach ($kv as $k) {
        echo "ID: {$k['id']}, UID: {$k['user_id']}, Status: '{$k['status']}'\n";
    }
    
} catch (Exception $e) {
    echo "ERROR: " . $e->getMessage() . "\n";
}
?>
