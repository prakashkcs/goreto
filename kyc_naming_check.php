<?php
header('Content-Type: text/plain');
require_once __DIR__ . '/../../config.php';
try {
    \ = new PDO("mysql:host=".DB_HOST.";dbname=".DB_NAME.";charset=utf8mb4", DB_USER, DB_PASS, [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]);
    
    // Check latest 5 users
    echo "--- USERS KYC STATUS ---\n";
    \ = \->query("SELECT id, name, kyc_status FROM users ORDER BY id DESC LIMIT 5");
    print_r(\->fetchAll(PDO::FETCH_ASSOC));
    
    // Check latest 5 verifications
    echo "\n--- KYC VERIFICATIONS ---\n";
    \ = \->query("SELECT id, user_id, status FROM kyc_verifications ORDER BY id DESC LIMIT 5");
    print_r(\->fetchAll(PDO::FETCH_ASSOC));
    
} catch (Exception \) {
    echo "ERROR: " . \->getMessage() . "\n";
}
