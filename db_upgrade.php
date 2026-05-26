<?php
header('Content-Type: application/json; charset=utf-8');
require_once __DIR__ . '/db_connect.php';

try {
    // ─── messages table for chat ───
    $pdo->exec("CREATE TABLE IF NOT EXISTS messages (
        id INT AUTO_INCREMENT PRIMARY KEY,
        sender_id INT NOT NULL,
        receiver_id INT NOT NULL,
        type VARCHAR(20) DEFAULT 'text',
        content TEXT,
        media_url VARCHAR(500) DEFAULT '',
        media_thumbnail VARCHAR(500) DEFAULT '',
        voice_duration INT DEFAULT 0,
        status VARCHAR(20) DEFAULT 'sent',
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        read_at DATETIME DEFAULT NULL,
        INDEX idx_sender (sender_id),
        INDEX idx_receiver (receiver_id),
        INDEX idx_created (created_at)
    )");

    // kyc_verifications table for names & selfie
    $pdo->exec("CREATE TABLE IF NOT EXISTS kyc_verifications (
        id INT AUTO_INCREMENT PRIMARY KEY,
        user_id INT NOT NULL,
        first_name VARCHAR(100) DEFAULT NULL,
        last_name VARCHAR(100) DEFAULT NULL,
        id_front VARCHAR(255) DEFAULT NULL,
        id_back VARCHAR(255) DEFAULT NULL,
        selfie_pic VARCHAR(255) DEFAULT NULL,
        liveness_video VARCHAR(255) DEFAULT NULL,
        status VARCHAR(50) DEFAULT 'pending',
        submitted_at DATETIME DEFAULT NULL
    )");

    try {
        $pdo->exec("ALTER TABLE kyc_verifications ADD COLUMN first_name VARCHAR(100) DEFAULT NULL");
    }
    catch (Exception $e) {
    }
    try {
        $pdo->exec("ALTER TABLE kyc_verifications ADD COLUMN last_name VARCHAR(100) DEFAULT NULL");
    }
    catch (Exception $e) {
    }
    try {
        $pdo->exec("ALTER TABLE kyc_verifications ADD COLUMN selfie_pic VARCHAR(255) DEFAULT NULL");
    }
    catch (Exception $e) {
    }
    try {
        $pdo->exec("ALTER TABLE kyc_verifications ADD COLUMN id_front VARCHAR(255) DEFAULT NULL");
    }
    catch (Exception $e) {
    }
    try {
        $pdo->exec("ALTER TABLE kyc_verifications ADD COLUMN id_back VARCHAR(255) DEFAULT NULL");
    }
    catch (Exception $e) {
    }
    try {
        $pdo->exec("ALTER TABLE kyc_verifications ADD COLUMN liveness_video VARCHAR(255) DEFAULT NULL");
    }
    catch (Exception $e) {
    }

    // Add activity counter for women checks (5x a week)
    try {
        $pdo->exec("ALTER TABLE users ADD COLUMN last_kyc_check_date DATE DEFAULT NULL");
    }
    catch (Exception $e) {
    }
    try {
        $pdo->exec("ALTER TABLE users ADD COLUMN kyc_checks_this_week INT DEFAULT 0");
    }
    catch (Exception $e) {
    }

    // Additional columns for admin
    try {
        $pdo->exec("ALTER TABLE users ADD COLUMN full_name VARCHAR(200) DEFAULT NULL");
    }
    catch (Exception $e) {
    }
    try {
        $pdo->exec("ALTER TABLE users ADD COLUMN kyc_status VARCHAR(50) DEFAULT 'unverified'");
    }
    catch (Exception $e) {
    }
    try {
        $pdo->exec("ALTER TABLE users ADD COLUMN subscription_status ENUM('active', 'inactive', 'disabled') DEFAULT 'active'");
    }
    catch (Exception $e) {
    }

    // Add proof_url for deposit flow
    try {
        $pdo->exec("ALTER TABLE wallet_deposits ADD COLUMN proof_url VARCHAR(255) DEFAULT NULL");
    }
    catch (Exception $e) {
    }

    echo json_encode(['status' => 'success', 'message' => 'Database altered successfully']);
}
catch (Exception $e) {
    echo json_encode(['status' => 'error', 'message' => $e->getMessage()]);
}
?>
