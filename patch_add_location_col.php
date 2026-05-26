<?php
header('Content-Type: application/json; charset=utf-8');

require_once __DIR__ . '/db_connect.php';

$results = [];

// Add 'location' text column to users table
try {
    $pdo->exec("ALTER TABLE users ADD COLUMN location VARCHAR(255) NULL AFTER bio");
    $results['location_column'] = 'ADDED';
} catch (Throwable $e) {
    if (strpos($e->getMessage(), 'Duplicate column') !== false) {
        $results['location_column'] = 'Already exists';
    } else {
        $results['location_column'] = 'ERROR: ' . $e->getMessage();
    }
}

// Verify
$cols = [];
$stmt = $pdo->query("SHOW COLUMNS FROM users");
while ($r = $stmt->fetch(PDO::FETCH_ASSOC)) {
    $cols[] = $r['Field'];
}
$results['has_location'] = in_array('location', $cols);
$results['all_columns'] = $cols;

echo json_encode($results, JSON_PRETTY_PRINT);
