<?php
header('Content-Type: application/json; charset=utf-8');
error_reporting(E_ALL);
ini_set('display_errors', 1);

echo json_encode(['stage' => 'start']);

try {
    echo json_encode(['stage' => 'before_db_connect']);
    require_once __DIR__ . '/db_connect.php';
    echo json_encode(['stage' => 'after_db_connect']);
    
    require_once __DIR__ . '/auth_middleware.php';
    echo json_encode(['stage' => 'after_auth_middleware']);
    
    $config = require __DIR__ . '/../config/config.php';
    echo json_encode(['stage' => 'after_config', 'config_path' => __DIR__ . '/../config/config.php']);
    
} catch (Throwable $e) {
    echo json_encode([
        'error' => $e->getMessage(),
        'file' => $e->getFile(),
        'line' => $e->getLine()
    ]);
}
