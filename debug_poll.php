<?php
require_once __DIR__ . '/db_connect.php';
header('Content-Type: application/json');

// Check what poll_incoming would return for user 13
$userId = 13;
$stmt = $pdo->prepare("
    SELECT c.id AS call_id, c.call_uuid, c.type, c.status, c.created_at,
           c.receiver_id, c.caller_id,
           UNIX_TIMESTAMP() AS now_ts,
           UNIX_TIMESTAMP(c.created_at) AS created_ts,
           (UNIX_TIMESTAMP() - UNIX_TIMESTAMP(c.created_at)) AS age_seconds,
           u.id AS caller_user_id, u.name AS caller_name
    FROM calls c
    JOIN users u ON u.id = c.caller_id
    WHERE c.receiver_id = ? AND c.status = 'ringing'
    ORDER BY c.created_at DESC LIMIT 5
");
$stmt->execute([$userId]);
$calls = $stmt->fetchAll(PDO::FETCH_ASSOC);

// Check auth_middleware - what user does token 48225d... resolve to?
$token = '48225d8559e6379de804d70095c08343ac319f8f328cc0bdf195b644b0d95403';
$stmt2 = $pdo->prepare("SELECT id, name FROM users WHERE api_token = ?");
$stmt2->execute([$token]);
$tokenUser = $stmt2->fetch(PDO::FETCH_ASSOC);

// Also check user_auth_tokens table
$stmt3 = $pdo->prepare("SELECT user_id FROM user_auth_tokens WHERE token = ? AND revoked_at IS NULL ORDER BY id DESC LIMIT 1");
$stmt3->execute([$token]);
$authTokenUser = $stmt3->fetch(PDO::FETCH_ASSOC);

echo json_encode([
    'ringing_calls_for_user_13' => $calls,
    'token_resolves_to_legacy' => $tokenUser,
    'token_resolves_to_multi_device' => $authTokenUser,
    'server_time' => date('Y-m-d H:i:s'),
    'server_timestamp' => time()
], JSON_PRETTY_PRINT);
?>
