<?php
header('Content-Type: text/plain');
require_once __DIR__ . '/../../config.php';
try {
    \ = new PDO("mysql:host=".DB_HOST.";dbname=".DB_NAME.";charset=utf8mb4", DB_USER, DB_PASS, [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]);
    \ = \->query("SHOW COLUMNS FROM users LIKE 'kyc_status'")->fetchAll(PDO::FETCH_ASSOC);
    echo "kyc_status column: " . (empty(\) ? "DOES NOT EXIST" : "EXISTS") . "\n";
    
    \ = \->query("SELECT id, name, kyc_status FROM users ORDER BY id DESC LIMIT 10")->fetchAll(PDO::FETCH_ASSOC);
    echo "\nLatest 10 users:\n";
    foreach(\ as \) {
        echo "  id=" . \['id'] . " name=" . \['name'] . " kyc_status=" . \['kyc_status'] . "\n";
    }

    \ = \->query("SELECT user_id, status FROM kyc_verifications ORDER BY id DESC LIMIT 10")->fetchAll(PDO::FETCH_ASSOC);
    echo "\nLatest 10 kyc_verifications:\n";
    foreach(\ as \) {
        echo "  user_id=" . \['user_id'] . " status=" . \['status'] . "\n";
    }
} catch (Exception \) {
    echo "Error: " . \->getMessage();
}
