<?php
require_once __DIR__ . '/db_connect.php';
header('Content-Type: text/plain');

echo "--- TABLE ROW COUNTS ---\n\n";

try {
    $q = $pdo->query("SHOW TABLES");
    while ($row = $q->fetch(PDO::FETCH_NUM)) {
        $table = $row[0];
        $cq = $pdo->query("SELECT COUNT(*) FROM `$table` ");
        $count = $cq->fetchColumn();
        echo "TABLE: $table | ROWS: $count\n";
    }
} catch (Exception $e) {
    echo "Error: " . $e->getMessage();
}
