<?php
require_once __DIR__ . '/db_connect.php';

echo "--- START FCM DEBUG ---\n";
try {
    $stmt = $pdo->query("SELECT id, name, fcm_token FROM users WHERE fcm_token IS NOT NULL AND fcm_token != ''");
    $users = $stmt->fetchAll(PDO::FETCH_ASSOC);
    echo "COUNT: " . count($users) . "\n";
    foreach ($users as $u) {
        echo "ID: " . $u['id'] . " | NAME: " . $u['name'] . " | TOKEN: " . substr($u['fcm_token'], 0, 15) . "...\n";
    }
}
catch (Exception $e) {
    echo "ERROR: " . $e->getMessage() . "\n";
}
echo "--- END FCM DEBUG ---\n";
?>
