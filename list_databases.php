<?php
require_once __DIR__ . '/db_connect.php';
header('Content-Type: text/plain');
try {
    $q = $pdo->query("SHOW DATABASES");
    echo "Accessible Databases:\n";
    while ($row = $q->fetch(PDO::FETCH_NUM)) {
        echo "  - " . $row[0] . "\n";
    }
} catch (Exception $e) {
    echo "Error: " . $e->getMessage();
}
