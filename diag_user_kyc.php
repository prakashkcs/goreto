<?php
require_once __DIR__ . '/db_connect.php';
$uid = 13; // Focus on Nabina Rai who we know has issues

echo "--- CHECKING UID $uid ---\n";

// Table Users
$st = $pdo->prepare("SELECT id, kyc_status FROM users WHERE id=?");
$st->execute([$uid]);
echo "Users Table: " . json_encode($st->fetch()) . "\n";

// Table kyc_verifications
$st = $pdo->prepare("SELECT * FROM kyc_verifications WHERE user_id=?");
$st->execute([$uid]);
echo "kyc_verifications: " . json_encode($st->fetchAll()) . "\n";

// Table user_kyc
try {
    $st = $pdo->prepare("SELECT * FROM user_kyc WHERE user_id=?");
    $st->execute([$uid]);
    echo "user_kyc: " . json_encode($st->fetchAll()) . "\n";
} catch (Exception $e) { echo "user_kyc: TABLE NOT FOUND\n"; }

// Table kyc_submissions
try {
    $st = $pdo->prepare("SELECT * FROM kyc_submissions WHERE user_id=?");
    $st->execute([$uid]);
    echo "kyc_submissions: " . json_encode($st->fetchAll()) . "\n";
} catch (Exception $e) { echo "kyc_submissions: TABLE NOT FOUND\n"; }

?>
