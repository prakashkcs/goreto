<?php
require_once __DIR__ . '/db_connect.php';

echo "--- DB FCM Token Check ---\n";
try {
    $stmt = $pdo->query("SELECT id, name, fcm_token FROM users WHERE fcm_token IS NOT NULL AND fcm_token != ''");
    $users = $stmt->fetchAll(PDO::FETCH_ASSOC);
    if (empty($users)) {
        echo "No users have FCM tokens in the DB.\n";
    }
    else {
        foreach ($users as $u) {
            echo "User ID: {$u['id']}, Name: {$u['username']}, Token: " . substr($u['fcm_token'], 0, 20) . "...\n";
        }
    }
}
catch (Exception $e) {
    echo "Error checking users: " . $e->getMessage() . "\n";
}

echo "\n--- Service Account Check ---\n";
$saPath = __DIR__ . '/service_account.json';
if (file_exists($saPath)) {
    echo "service_account.json found at: $saPath\n";
    $content = json_decode(file_get_contents($saPath), true);
    if ($content) {
        echo "Valid JSON. Project ID: " . ($content['project_id'] ?? 'MISSING') . "\n";
    }
    else {
        echo "Invalid JSON content.\n";
    }
}
else {
    echo "service_account.json NOT FOUND at: $saPath\n";
}

echo "\n--- signaling.php Check ---\n";
if (file_exists(__DIR__ . '/signaling.php')) {
    echo "signaling.php exists.\n";
}
else {
    echo "signaling.php NOT FOUND.\n";
}
?>
