<?php
header('Content-Type: text/plain');
require_once __DIR__ . '/db_connect.php';

try {
    $result = $pdo->query("SHOW COLUMNS FROM users");
    $cols = $result->fetchAll(PDO::FETCH_ASSOC);
    foreach ($cols as $col) {
        echo $col['Field'] . " (" . $col['Type'] . ")\n";
    }
} catch (Throwable $e) {
    echo "Error: " . $e->getMessage() . "\n";
}

echo "\n--- proposals table ---\n";
try {
    $result = $pdo->query("SHOW COLUMNS FROM proposals");
    $cols = $result->fetchAll(PDO::FETCH_ASSOC);
    foreach ($cols as $col) {
        echo $col['Field'] . " (" . $col['Type'] . ")\n";
    }
} catch (Throwable $e) {
    echo "Error: " . $e->getMessage() . "\n";
}
?>
