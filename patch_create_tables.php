<?php
header('Content-Type: application/json; charset=utf-8');

require_once __DIR__ . '/db_connect.php';

$results = [];

// 1. Create proposals table
try {
    $pdo->exec("CREATE TABLE IF NOT EXISTS proposals (
        id INT AUTO_INCREMENT PRIMARY KEY,
        sender_id INT NOT NULL,
        receiver_id INT NOT NULL,
        status VARCHAR(20) DEFAULT 'pending',
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        INDEX (sender_id),
        INDEX (receiver_id),
        INDEX (status)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;");
    $results['proposals'] = 'OK';
} catch (Throwable $e) {
    $results['proposals'] = 'ERROR: ' . $e->getMessage();
}

// 2. Create user_blocks table
try {
    $pdo->exec("CREATE TABLE IF NOT EXISTS user_blocks (
        id INT AUTO_INCREMENT PRIMARY KEY,
        blocker_id INT NOT NULL,
        blocked_id INT NOT NULL,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        UNIQUE KEY unique_block (blocker_id, blocked_id),
        INDEX (blocker_id),
        INDEX (blocked_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;");
    $results['user_blocks'] = 'OK';
} catch (Throwable $e) {
    $results['user_blocks'] = 'ERROR: ' . $e->getMessage();
}

// 3. Create match_profiles table (if missing)
try {
    $pdo->exec("CREATE TABLE IF NOT EXISTS match_profiles (
        id INT AUTO_INCREMENT PRIMARY KEY,
        user_id INT NOT NULL UNIQUE,
        age VARCHAR(10) NULL,
        gender VARCHAR(20) NULL,
        bio TEXT NULL,
        location VARCHAR(255) NULL,
        income VARCHAR(50) NULL,
        income_status VARCHAR(20) DEFAULT 'none',
        interests TEXT NULL,
        qualities TEXT NULL,
        looking_for TEXT NULL,
        is_visible TINYINT(1) DEFAULT 1,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        INDEX (user_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;");
    $results['match_profiles'] = 'OK';
} catch (Throwable $e) {
    $results['match_profiles'] = 'ERROR: ' . $e->getMessage();
}

// 4. Ensure total_proposals column exists on users
try {
    $pdo->exec("ALTER TABLE users ADD COLUMN total_proposals INT DEFAULT 0");
    $results['total_proposals_col'] = 'ADDED';
} catch (Throwable $e) {
    if (strpos($e->getMessage(), 'Duplicate column') !== false) {
        $results['total_proposals_col'] = 'Already exists';
    } else {
        $results['total_proposals_col'] = 'ERROR: ' . $e->getMessage();
    }
}

// 5. Ensure username_updated_at column exists on users
try {
    $pdo->exec("ALTER TABLE users ADD COLUMN username_updated_at DATETIME NULL");
    $results['username_updated_at_col'] = 'ADDED';
} catch (Throwable $e) {
    if (strpos($e->getMessage(), 'Duplicate column') !== false) {
        $results['username_updated_at_col'] = 'Already exists';
    } else {
        $results['username_updated_at_col'] = 'ERROR: ' . $e->getMessage();
    }
}

// Verify tables exist
$tables = ['proposals', 'user_blocks', 'match_profiles'];
$verify = [];
foreach ($tables as $t) {
    $st = $pdo->query("SHOW TABLES LIKE '$t'");
    $verify[$t] = $st->fetchColumn() ? 'EXISTS' : 'MISSING';
}

echo json_encode([
    'status' => 'success',
    'create_results' => $results,
    'verify' => $verify,
], JSON_PRETTY_PRINT);
