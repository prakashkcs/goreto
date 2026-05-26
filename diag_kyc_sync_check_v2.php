<?php
require_once __DIR__ . '/db_connect.php';

header('Content-Type: text/plain');

try {
    echo "--- Enhanced KYC Diagnostic ---\n\n";

    // 1. Database Info
    $q = $pdo->query("SELECT DATABASE() as db");
    echo "Current Database: " . $q->fetch(PDO::FETCH_ASSOC)['db'] . "\n\n";

    // 2. Status Counts
    $tables = [
        'users' => 'kyc_status',
        'user_kyc' => 'basic_status',
        'kyc_verifications' => 'status',
        'kyc_submissions' => 'status'
    ];

    foreach ($tables as $table => $col) {
        echo "Status counts for $table ($col):\n";
        try {
            $q = $pdo->query("SELECT $col, COUNT(*) as count FROM $table GROUP BY $col");
            while ($row = $q->fetch(PDO::FETCH_ASSOC)) {
                echo "  - " . ($row[$col] ?? 'NULL') . ": " . $row['count'] . "\n";
            }
        } catch (Exception $e) {
            echo "  Error: " . $e->getMessage() . "\n";
        }
        echo "\n";
    }

    // 3. Show all users with any non-verified/none status (Case Insensitive)
    echo "--- Non-Standard Status Details ---\n";
    $sql = "
        SELECT 
            u.id, 
            u.name, 
            u.kyc_status as users_status, 
            uk.basic_status as user_kyc_status, 
            kv.status as verifications_status
        FROM users u
        LEFT JOIN user_kyc uk ON u.id = uk.user_id
        LEFT JOIN kyc_verifications kv ON u.id = kv.user_id
        WHERE (u.kyc_status NOT IN ('verified', 'none', '') AND u.kyc_status IS NOT NULL)
           OR (uk.basic_status NOT IN ('verified', 'none', 'approved', '') AND uk.basic_status IS NOT NULL)
           OR (kv.status NOT IN ('verified', 'none', 'approved', '') AND kv.status IS NOT NULL)
        LIMIT 50
    ";
    $q = $pdo->query($sql);
    $rows = $q->fetchAll(PDO::FETCH_ASSOC);
    if ($rows) {
        printf("%-5s | %-20s | %-12s | %-12s | %-12s\n", "ID", "Name", "UsersTbl", "KYCTbl", "VerifTbl");
        echo str_repeat("-", 75) . "\n";
        foreach ($rows as $r) {
            printf("%-5d | %-20s | %-12s | %-12s | %-12s\n", 
                $r['id'], 
                substr($r['name'], 0, 20), 
                $r['users_status'], 
                $r['user_kyc_status'] ?? 'NULL', 
                $r['verifications_status'] ?? 'NULL'
            );
        }
    } else {
        echo "No non-standard status found.\n";
    }

    // 4. Detailed look at the most recent 5 verifications
    echo "\n--- Recent 10 KYC Verifications ---\n";
    try {
        $qV = $pdo->query("SELECT id, user_id, status, submitted_at FROM kyc_verifications ORDER BY id DESC LIMIT 10");
        while ($rv = $qV->fetch(PDO::FETCH_ASSOC)) {
            echo "  ID: {$rv['id']} | User: {$rv['user_id']} | Status: {$rv['status']} | At: {$rv['submitted_at']}\n";
        }
    } catch (Exception $e) {
        echo "  Error: " . $e->getMessage() . "\n";
    }

} catch (Exception $e) {
    echo "Error: " . $e->getMessage();
}
