<?php
error_reporting(E_ALL);
ini_set('display_errors', 1);
ini_set('display_startup_errors', 1);

// Clear opcache for db_connect and profile_v19
if (function_exists('opcache_invalidate')) {
    opcache_invalidate(__DIR__ . '/db_connect.php', true);
    opcache_invalidate(__DIR__ . '/profile_v19.php', true);
    echo "opcache cleared\n";
}

echo "=== Testing db_connect.php ===\n";
echo "db_connect path: " . __DIR__ . "/db_connect.php\n";
echo "config path: " . __DIR__ . "/config/config.php\n";
echo "config exists: " . (file_exists(__DIR__ . '/config/config.php') ? 'YES' : 'NO') . "\n";

try {
    require_once __DIR__ . '/db_connect.php';
    echo "db_connect loaded OK\n";
    echo "pdo is: " . get_class($pdo) . "\n";
} catch (Throwable $e) {
    echo "db_connect ERROR: " . $e->getMessage() . " in " . $e->getFile() . ":" . $e->getLine() . "\n";
    exit;
}

echo "\n=== Testing profile query ===\n";
try {
    $colsStmt = $pdo->query("SHOW COLUMNS FROM users");
    $cols = array_column($colsStmt->fetchAll(PDO::FETCH_ASSOC), 'Field');
    echo "users columns: " . implode(', ', $cols) . "\n";
} catch (Throwable $e) {
    echo "SHOW COLUMNS ERROR: " . $e->getMessage() . "\n";
}

echo "\n=== Testing proposals table ===\n";
try {
    $r = $pdo->query("SHOW COLUMNS FROM proposals")->fetchAll(PDO::FETCH_ASSOC);
    $pcols = array_column($r, 'Field');
    echo "proposals columns: " . implode(', ', $pcols) . "\n";
    echo "show_on_profile exists: " . (in_array('show_on_profile', $pcols) ? 'YES' : 'NO') . "\n";
} catch (Throwable $e) {
    echo "proposals ERROR: " . $e->getMessage() . "\n";
}

echo "\n=== Testing follows table ===\n";
try {
    $pdo->query("SELECT 1 FROM follows LIMIT 1");
    echo "follows table: OK\n";
} catch (Throwable $e) {
    echo "follows ERROR: " . $e->getMessage() . "\n";
}

echo "\n=== Testing user_blocks table ===\n";
try {
    $pdo->query("SELECT 1 FROM user_blocks LIMIT 1");
    echo "user_blocks table: OK\n";
} catch (Throwable $e) {
    echo "user_blocks ERROR: " . $e->getMessage() . "\n";
}

echo "\nDone.\n";
