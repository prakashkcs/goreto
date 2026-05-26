<?php
require_once __DIR__ . '/db_connect.php';
header('Content-Type: text/plain');

echo "--- DATA DUMP ---\n\n";

echo "TABLE: users (Top 20)\n";
$q = $pdo->query("SELECT id, username, kyc_status FROM users LIMIT 20");
while ($row = $q->fetch(PDO::FETCH_ASSOC)) {
    echo "ID: {$row['id']} | User: {$row['username']} | KYC: " . ($row['kyc_status'] ?? 'NULL') . "\n";
}

echo "\nTABLE: kyc_verifications (Top 20)\n";
try {
    $q = $pdo->query("SELECT id, user_id, status, submitted_at FROM kyc_verifications LIMIT 20");
    while ($row = $q->fetch(PDO::FETCH_ASSOC)) {
        echo "ID: {$row['id']} | UserID: {$row['user_id']} | Status: {$row['status']} | At: {$row['submitted_at']}\n";
    }
} catch (Exception $e) { echo "Error: " . $e->getMessage() . "\n"; }

echo "\nTABLE: kyc_submissions (Top 20)\n";
try {
    $q = $pdo->query("SELECT id, user_id, status, created_at FROM kyc_submissions LIMIT 20");
    while ($row = $q->fetch(PDO::FETCH_ASSOC)) {
        echo "ID: {$row['id']} | UserID: {$row['user_id']} | Status: {$row['status']} | At: {$row['created_at']}\n";
    }
} catch (Exception $e) { echo "Error: " . $e->getMessage() . "\n"; }

echo "\nTABLE: user_kyc (Top 20)\n";
try {
    $q = $pdo->query("SELECT user_id, basic_status, full_status FROM user_kyc LIMIT 20");
    while ($row = $q->fetch(PDO::FETCH_ASSOC)) {
        echo "UserID: {$row['user_id']} | Basic: {$row['basic_status']} | Full: {$row['full_status']}\n";
    }
} catch (Exception $e) { echo "Error: " . $e->getMessage() . "\n"; }
