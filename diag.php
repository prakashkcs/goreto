<?php
error_reporting(E_ALL);
ini_set('display_errors', 1);
ini_set('display_startup_errors', 1);

echo "PHP OK\n";
echo "DIR: " . __DIR__ . "\n";

// Check config file
$cfg = __DIR__ . '/config/config.php';
echo "Config path: $cfg\n";
echo "Config exists: " . (file_exists($cfg) ? 'YES' : 'NO') . "\n";

if (file_exists($cfg)) {
    $config = require $cfg;
    echo "Config loaded OK\n";
    echo "DB host: " . $config['db']['host'] . "\n";
    echo "DB name: " . $config['db']['name'] . "\n";

    // Test DB connection
    try {
        $dsn = "mysql:host={$config['db']['host']};dbname={$config['db']['name']};charset=utf8mb4";
        $pdo = new PDO($dsn, $config['db']['user'], $config['db']['pass'], [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        ]);
        echo "DB connection: OK\n";
        $r = $pdo->query("SELECT COUNT(*) as cnt FROM users")->fetch();
        echo "Users count: " . $r['cnt'] . "\n";
    } catch (Exception $e) {
        echo "DB ERROR: " . $e->getMessage() . "\n";
    }
} else {
    echo "ERROR: config file not found!\n";
    echo "Files in __DIR__:\n";
    foreach (scandir(__DIR__) as $f)
        echo "  $f\n";
    echo "Files in config/:\n";
    $cd = __DIR__ . '/config';
    if (is_dir($cd)) {
        foreach (scandir($cd) as $f)
            echo "  $f\n";
    } else {
        echo "  (config dir missing)\n";
    }
}
