<?php
require_once __DIR__ . '/db_connect.php';

$stmt = $pdo->prepare("SELECT id, name, email, fcm_token, api_token FROM users ORDER BY id DESC LIMIT 20");
$stmt->execute();
$users = $stmt->fetchAll(PDO::FETCH_ASSOC);

echo "Latest 20 users:<br>";
foreach ($users as $u) {
    echo "ID: {$u['id']} | Name: {$u['name']} | Email: {$u['email']} | FCM: " . (empty($u['fcm_token']) ? 'MISSING' : substr($u['fcm_token'], 0, 15) . '...') . "<br>";
}
?>
