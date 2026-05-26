<?php
// debug_probe.php — DEVELOPMENT DIAGNOSTICS ONLY.
// This file is also blocked by .htaccess.  Delete before production deployment.
$_allowed = ['127.0.0.1', '::1'];
if (!in_array($_SERVER['REMOTE_ADDR'] ?? '', $_allowed, true)) {
    http_response_code(404);
    exit;
}

error_reporting(E_ALL);
ini_set('display_errors', 1);

echo "=== PHP VERSION ===\n";
echo phpversion() . "\n\n";

echo "=== INCLUDE PATH TEST ===\n";
$files = [
    __DIR__ . '/config.php',
    __DIR__ . '/db_connect.php',
    __DIR__ . '/notification_helper.php',
    __DIR__ . '/fcm_v1.php',
];
foreach ($files as $f) {
    echo basename($f) . ': ' . (file_exists($f) ? 'EXISTS' : 'MISSING') . "\n";
}

echo "\n=== DB CONNECTION TEST ===\n";
try {
    require_once __DIR__ . '/config.php';
    require_once __DIR__ . '/db_connect.php';
    $stmt = $pdo->query("SELECT 1 AS ok");
    $row = $stmt->fetch(PDO::FETCH_ASSOC);
    echo "DB: " . ($row['ok'] == 1 ? 'OK' : 'FAIL') . "\n";
} catch (Throwable $e) {
    echo "DB ERROR: " . $e->getMessage() . "\n";
}

echo "\n=== DONE ===\n";
