<?php
header('Content-Type: text/plain');
require_once __DIR__ . '/db_connect.php';

// Check if kyc_status column exists in users table
try {
    \ = \->query("SHOW COLUMNS FROM users LIKE 'kyc_status'")->fetchAll(PDO::FETCH_ASSOC);
    echo "kyc_status column: " . (empty(\) ? "DOES NOT EXIST" : "EXISTS") . "\n";
    
    \ = \->query("SELECT id, name, kyc_status FROM users ORDER BY id DESC LIMIT 10")->fetchAll(PDO::FETCH_ASSOC);
    echo "\nLatest 10 users (id, name, kyc_status):\n";
    foreach(\ as \) {
        echo "  id=" . \['id'] . " name=" . \['name'] . " kyc_status=" . \['kyc_status'] . "\n";
    }

    \ = \->query("SELECT user_id, status, submitted_at FROM kyc_verifications ORDER BY id DESC LIMIT 10")->fetchAll(PDO::FETCH_ASSOC);
    echo "\nLatest 10 kyc_verifications:\n";
    foreach(\ as \) {
        echo "  user_id=" . \['user_id'] . " status=" . \['status'] . " at=" . \['submitted_at'] . "\n";
    }
} catch (Exception \) {
    echo "Error: " . \->getMessage();
}
