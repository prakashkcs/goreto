<?php
header('Content-Type: application/json');
require_once __DIR__ . '/db_connect.php';

try {
    $gifts = $pdo->query("SELECT id, name, coin_price FROM gifts WHERE is_active=1 LIMIT 5")->fetchAll(PDO::FETCH_ASSOC);
    $users = $pdo->query("SELECT id, name FROM users LIMIT 5")->fetchAll(PDO::FETCH_ASSOC);
    
    echo json_encode(['status' => 'success', 'gifts' => $gifts, 'users' => $users]);
} catch (Exception $e) {
    echo json_encode(['status' => 'error', 'message' => $e->getMessage()]);
}
