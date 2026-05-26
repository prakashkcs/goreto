<?php
header('Content-Type: application/json; charset=utf-8');
error_reporting(E_ALL);
ini_set('display_errors', 1);

try {
    require_once __DIR__ . '/db_connect.php';
    require_once __DIR__ . '/auth_middleware.php';
    
    $user = requireUser($pdo);
    
    echo json_encode([
        'status' => 'success',
        'message' => 'Auth works',
        'user_id' => $user['id'],
        'user_name' => $user['name']
    ]);
} catch (Throwable $e) {
    http_response_code(500);
    echo json_encode([
        'status' => 'error',
        'message' => $e->getMessage(),
        'file' => basename($e->getFile()),
        'line' => $e->getLine()
    ]);
}
