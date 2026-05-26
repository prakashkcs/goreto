<?php
header('Content-Type: application/json');
require_once __DIR__ . '/db_connect.php';

try {
    $st = $pdo->prepare("SELECT api_token FROM users WHERE id=9 LIMIT 1");
    $st->execute();
    $token = $st->fetchColumn();
    
    echo json_encode(['status' => 'success', 'token' => $token]);
} catch (Exception $e) {
    echo json_encode(['status' => 'error', 'message' => $e->getMessage()]);
}
