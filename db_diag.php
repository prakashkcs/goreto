<?php
header('Content-Type: application/json');
require_once 'db_connect.php';

$tables = ['users', 'match_profiles', 'income_proofs'];
$results = [];

foreach ($tables as $table) {
    try {
        $stmt = $pdo->query("DESCRIBE $table");
        $results[$table] = $stmt->fetchAll(PDO::FETCH_ASSOC);
    } catch (Exception $e) {
        $results[$table] = "Error: " . $e->getMessage();
    }
}

echo json_encode(['status' => 'success', 'schema' => $results], JSON_PRETTY_PRINT);
