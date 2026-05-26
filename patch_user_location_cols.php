<?php
ini_set('display_errors', '1');
error_reporting(E_ALL);
require_once __DIR__ . '/db_connect.php';

echo "Checking columns in 'users' table...\n";
try {
    $stmt = $pdo->query("SHOW COLUMNS FROM users");
    $uCols = [];
    while ($row = $stmt->fetch(PDO::FETCH_ASSOC)) {
        $uCols[] = $row['Field'];
    }

    if (!in_array('latitude', $uCols)) {
        echo "- Adding latitude...\n";
        $pdo->exec("ALTER TABLE users ADD COLUMN latitude DOUBLE NULL");
    } else {
        echo "- latitude exists.\n";
    }

    if (!in_array('longitude', $uCols)) {
        echo "- Adding longitude...\n";
        $pdo->exec("ALTER TABLE users ADD COLUMN longitude DOUBLE NULL");
    } else {
        echo "- longitude exists.\n";
    }

    if (!in_array('location_updated_at', $uCols)) {
        echo "- Adding location_updated_at...\n";
        $pdo->exec("ALTER TABLE users ADD COLUMN location_updated_at DATETIME NULL");
    } else {
        echo "- location_updated_at exists.\n";
    }

    echo "\nAll required location columns are now present.\n";

    // Verify
    $stmt2 = $pdo->query("SHOW COLUMNS FROM users");
    while ($row = $stmt2->fetch(PDO::FETCH_ASSOC)) {
        if (in_array($row['Field'], ['latitude', 'longitude', 'location_updated_at'])) {
            print_r($row);
        }
    }

} catch (PDOException $e) {
    echo "ERROR: " . $e->getMessage() . "\n";
}
