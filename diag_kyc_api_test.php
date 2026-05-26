<?php
require_once __DIR__ . '/db_connect.php';
$userId = 13; // nabina rai

$st = $pdo->prepare("SELECT kyc_status FROM users WHERE id=? LIMIT 1");
$st->execute([$userId]);
$user = $st->fetch(PDO::FETCH_ASSOC);
$status = $user ? $user['kyc_status'] : 'none';

$st2 = $pdo->prepare("SELECT admin_note FROM kyc_verifications WHERE user_id=? ORDER BY id DESC LIMIT 1");
$st2->execute([$userId]);
$sub = $st2->fetch(PDO::FETCH_ASSOC);
$note = $sub ? $sub['admin_note'] : '';

$row = [
    'user_id' => $userId,
    'basic_status' => $status,
    'full_status' => $status,
    'admin_note' => $note
];

header('Content-Type: application/json');
echo json_encode(['status'=>'success','kyc'=>$row]);
?>
