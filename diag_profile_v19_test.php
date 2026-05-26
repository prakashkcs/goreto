<?php
// Mocking the profile_v19.php logic for UID 13
require_once __DIR__ . '/db_connect.php';
$userId = 13;

$st = $pdo->prepare("SELECT id, name, username, kyc_status FROM users WHERE id=? LIMIT 1");
$st->execute([$userId]);
$u = $st->fetch(PDO::FETCH_ASSOC);

if (!$u) {
    echo json_encode(['status' => 'error', 'message' => 'User not found']);
    exit;
}

// Add common fields
$u['kyc_status'] = $u['kyc_status'] ?? 'none';
$u['avatar'] = '';
$u['cover'] = '';

echo json_encode(['status' => 'success', 'user' => $u]);
?>
