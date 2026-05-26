<?php
require_once __DIR__ . '/db_connect.php';
header('Content-Type: application/json');

// Check FCM tokens
$stmt = $pdo->query("SELECT id, name, fcm_token FROM users WHERE fcm_token IS NOT NULL AND fcm_token != '' LIMIT 20");
$usersWithTokens = $stmt->fetchAll(PDO::FETCH_ASSOC);

// Check recent calls
$stmt2 = $pdo->query("SELECT * FROM calls ORDER BY id DESC LIMIT 5");
$recentCalls = $stmt2->fetchAll(PDO::FETCH_ASSOC);

// Check all users
$stmt3 = $pdo->query("SELECT id, name, CASE WHEN fcm_token IS NOT NULL AND fcm_token != '' THEN 'YES' ELSE 'NO' END as has_fcm FROM users LIMIT 20");
$allUsers = $stmt3->fetchAll(PDO::FETCH_ASSOC);

echo json_encode([
    'users_with_fcm_tokens' => $usersWithTokens,
    'recent_calls' => $recentCalls,
    'all_users_fcm_status' => $allUsers
], JSON_PRETTY_PRINT);
?>
