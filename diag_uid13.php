<?php
require_once __DIR__ . '/db_connect.php';
$uid = 13;

echo "--- USERS TABLE ---\n";
$st = $pdo->prepare("SELECT id, name, username, kyc_status FROM users WHERE id=?");
$st->execute([$uid]);
print_r($st->fetch(PDO::FETCH_ASSOC));

echo "\n--- USER_KYC TABLE ---\n";
$st = $pdo->prepare("SELECT * FROM user_kyc WHERE user_id=?");
$st->execute([$uid]);
print_r($st->fetch(PDO::FETCH_ASSOC));

echo "\n--- KYC_VERIFICATIONS TABLE ---\n";
$st = $pdo->prepare("SELECT id, user_id, status, submitted_at FROM kyc_verifications WHERE user_id=? ORDER BY id DESC");
$st->execute([$uid]);
print_r($st->fetchAll(PDO::FETCH_ASSOC));

echo "\n--- KYC_SUBMISSIONS TABLE ---\n";
$st = $pdo->prepare("SELECT id, user_id, status, created_at FROM kyc_submissions WHERE user_id=? ORDER BY id DESC");
$st->execute([$uid]);
print_r($st->fetchAll(PDO::FETCH_ASSOC));

echo "\n--- PENDING CHECKS ---\n";
$st = $pdo->query("SELECT id, name FROM users WHERE kyc_status='pending' OR kyc_status='Pending'");
echo "Users with kyc_status=pending: " . json_encode($st->fetchAll(PDO::FETCH_ASSOC)) . "\n";

?>
