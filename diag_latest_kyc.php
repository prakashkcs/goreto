<?php
require_once __DIR__ . '/db_connect.php';

echo "--- LATEST KYC VERIFICATIONS ---\n\n";

$st = $pdo->query("SELECT * FROM kyc_verifications ORDER BY id DESC LIMIT 10");
$vers = $st->fetchAll(PDO::FETCH_ASSOC);
foreach ($vers as $v) {
    echo "ID: {$v['id']}, UID: {$v['user_id']}, Status: {$v['status']}, Name: {$v['first_name']} {$v['last_name']}\n";
}

echo "\n--- LATEST USERS WITH KYC STATUS ---\n\n";
$st2 = $pdo->query("SELECT id, username, name, kyc_status FROM users WHERE kyc_status != '' AND kyc_status != 'none' ORDER BY id DESC LIMIT 10");
$users = $st2->fetchAll(PDO::FETCH_ASSOC);
foreach ($users as $u) {
    echo "ID: {$u['id']}, Username: {$u['username']}, Name: {$u['name']}, Status: {$u['kyc_status']}\n";
}
?>
