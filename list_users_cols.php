<?php
require_once __DIR__ . '/db_connect.php';
try {
    $stmt = $pdo->query("SHOW COLUMNS FROM users");
    $cols = $stmt->fetchAll(PDO::FETCH_ASSOC);
    echo "COLUMNS IN users TABLE:\n";
    foreach ($cols as $c) {
        echo $c['Field'] . "\n";
    }
}
catch (Exception $e) {
    echo "Error: " . $e->getMessage();
}
?>
