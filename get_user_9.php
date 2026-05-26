<?php
header('Content-Type: application/json');
require_once __DIR__ . '/db_connect.php';

$stmt = $pdo->prepare("SELECT id, name, fcm_token FROM users WHERE id = 9");
$stmt->execute();
$u = $stmt->fetch(PDO::FETCH_ASSOC);

echo json_encode($u, JSON_PRETTY_PRINT);
