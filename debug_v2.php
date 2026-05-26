<?php
header('Content-Type: text/plain');
error_reporting(E_ALL);
ini_set('display_errors', 1);

echo "=== STEP 1: START ===\n";

try {
    echo "=== STEP 2: Loading db_connect.php ===\n";
    require_once __DIR__ . '/db_connect.php';
    echo "SUCCESS: db_connect.php loaded\n";
    echo "PDO exists: " . (isset($pdo) ? "YES" : "NO") . "\n";
} catch (Throwable $e) {
    echo "FAILED: " . $e->getMessage() . " in " . $e->getFile() . " line " . $e->getLine() . "\n";
    exit(1);
}

echo "=== STEP 3: Loading auth_middleware.php ===\n";
try {
    require_once __DIR__ . '/auth_middleware.php';
    echo "SUCCESS: auth_middleware.php loaded\n";
} catch (Throwable $e) {
    echo "FAILED: " . $e->getMessage() . " in " . $e->getFile() . " line " . $e->getLine() . "\n";
    exit(1);
}

echo "=== STEP 4: Loading config ===\n";
try {
    $config = require __DIR__ . '/../config/config.php';
    echo "SUCCESS: config.php loaded\n";
} catch (Throwable $e) {
    echo "FAILED: " . $e->getMessage() . " in " . $e->getFile() . " line " . $e->getLine() . "\n";
    exit(1);
}

echo "=== STEP 5: Testing DB connection ===\n";
try {
    $test = $pdo->query("SELECT 1")->fetch();
    echo "SUCCESS: DB query works\n";
} catch (Throwable $e) {
    echo "FAILED: " . $e->getMessage() . "\n";
    exit(1);
}

echo "=== STEP 6: Testing table creation ===\n";
try {
    $pdo->exec("CREATE TABLE IF NOT EXISTS test_group_chat_debug (id INT PRIMARY KEY)");
    echo "SUCCESS: Table creation works\n";
    $pdo->exec("DROP TABLE IF EXISTS test_group_chat_debug");
} catch (Throwable $e) {
    echo "FAILED: " . $e->getMessage() . "\n";
    exit(1);
}

echo "=== ALL STEPS COMPLETE ===\n";
