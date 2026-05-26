<?php
require_once __DIR__ . '/db_connect.php';

echo "--- Debug Nearby Table ---\n";
$stmt = $pdo->query("SELECT * FROM debug_nearby ORDER BY id DESC LIMIT 20");
while($row = $stmt->fetch(PDO::FETCH_ASSOC)) {
    echo "[" . $row['ts'] . "] " . $row['msg'] . "\n";
}

echo "\n--- Nearby Notifications Log ---\n";
$stmt = $pdo->query("SELECT * FROM nearby_notifications_log ORDER BY last_notified_at DESC LIMIT 10");
while($row = $stmt->fetch(PDO::FETCH_ASSOC)) {
    echo "From " . $row['user_id'] . " to " . $row['nearby_user_id'] . " at " . $row['last_notified_at'] . "\n";
}

echo "\n--- Users With Location ---\n";
$stmt = $pdo->query("SELECT id, name, latitude, longitude, fcm_token FROM users WHERE latitude IS NOT NULL LIMIT 10");
while($row = $stmt->fetch(PDO::FETCH_ASSOC)) {
    $hasToken = !empty($row['fcm_token']) ? "YES" : "NO";
    echo "ID: " . $row['id'] . " | Name: " . $row['name'] . " | Lat: " . $row['latitude'] . " | Lng: " . $row['longitude'] . " | Token: " . $hasToken . "\n";
}
