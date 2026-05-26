<?php
require_once __DIR__ . '/db_connect.php';
$uid = 13;

echo "--- KYC FULL DIAGNOSTIC FOR UID $uid ---\n\n";

// 1. Users table
$st = $pdo->prepare("SELECT id, kyc_status, full_name FROM users WHERE id=?");
$st->execute([$uid]);
echo "Users table: " . json_encode($st->fetch()) . "\n";

// 2. kyc_verifications
$st = $pdo->prepare("SELECT * FROM kyc_verifications WHERE user_id=? ORDER BY id DESC LIMIT 5");
$st->execute([$uid]);
echo "kyc_verifications: " . json_encode($st->fetchAll()) . "\n";

// 3. user_kyc
try {
    $st = $pdo->prepare("SELECT * FROM user_kyc WHERE user_id=?");
    $st->execute([$uid]);
    echo "user_kyc: " . json_encode($st->fetchAll()) . "\n";
} catch (Exception $e) { echo "user_kyc error: " . $e->getMessage() . "\n"; }

// 4. kyc_submissions
try {
    $st = $pdo->prepare("SELECT * FROM kyc_submissions WHERE user_id=? ORDER BY id DESC LIMIT 5");
    $st->execute([$uid]);
    echo "kyc_submissions: " . json_encode($st->fetchAll()) . "\n";
} catch (Exception $e) { echo "kyc_submissions error: " . $e->getMessage() . "\n"; }

echo "\n--- END ---\n";
?>
