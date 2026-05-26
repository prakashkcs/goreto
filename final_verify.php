<?php
require_once __DIR__ . '/db_connect.php';
$st = $pdo->prepare("SELECT basic_status, full_status FROM user_kyc WHERE user_id=?");
$st->execute([13]);
echo "user_kyc: " . json_encode($st->fetch()) . "\n";
?>
