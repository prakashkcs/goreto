<?php
header('Content-Type: application/json');
require_once __DIR__ . '/db_connect.php';

$tables = ['gifts', 'gift_transactions', 'user_wallets', 'wallet_transactions', 'user_gifts', 'gift_sales', 'gifts_received', 'users'];
$results = [];

foreach ($tables as $table) {
    try {
        $st = $pdo->query("SHOW TABLES LIKE '$table'");
        $exists = $st->rowCount() > 0;
        
        $schema = [];
        if ($exists) {
            $st = $pdo->query("DESCRIBE $table");
            $schema = $st->fetchAll(PDO::FETCH_ASSOC);
        }
        
        $results[$table] = [
            'exists' => $exists,
            'schema' => $schema
        ];
    } catch (Exception $e) {
        $results[$table] = [
            'exists' => false,
            'error' => $e->getMessage()
        ];
    }
}

echo json_encode([
    'status' => 'success',
    'results' => $results
], JSON_PRETTY_PRINT);
