<?php
require_once __DIR__ . '/db_connect.php';
header('Content-Type: text/plain');

echo "--- income_proofs DUMP ---\n\n";
try {
    $q = $pdo->query("SELECT * FROM income_proofs LIMIT 10");
    while ($row = $q->fetch(PDO::FETCH_ASSOC)) {
        print_r($row);
    }
} catch (Exception $e) { echo "Error: " . $e->getMessage(); }
