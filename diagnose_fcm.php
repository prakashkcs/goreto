<?php
ini_set('display_errors', 1);
error_reporting(E_ALL);

// Standalone test for FCM delivery
$fcm_v1_path = __DIR__ . '/fcm_v1.php';
$service_account_path = __DIR__ . '/service_account.json';

if (!file_exists($fcm_v1_path)) {
    die("fcm_v1.php not found at $fcm_v1_path");
}
if (!file_exists($service_account_path)) {
    die("service_account.json not found at $service_account_path");
}

require_once $fcm_v1_path;

// 1. Get user FCM token manually or from DB if possible
// For this test, let's try to find a token for user_id 9
require_once __DIR__ . '/db_connect.php';

// Note: db_connect is in api/v1, so this script should be run from there.

$userId = 9;
$stmt = $pdo->prepare("SELECT fcm_token FROM users WHERE id = ?");
$stmt->execute([$userId]);
$user = $stmt->fetch(PDO::FETCH_ASSOC);

if (!$user || empty($user['fcm_token'])) {
    die("No FCM token found for user $userId");
}

$token = $user['fcm_token'];
echo "Found token: " . substr($token, 0, 10) . "...<br>";

$jsonAccount = json_decode(file_get_contents($service_account_path), true);
$projectId = $jsonAccount['project_id'];

$fcmClient = new PushNotificationFCM($service_account_path);

$dataPayload = [
    'action' => 'notification',
    'type' => 'test',
    'diagnostic' => 'true'
];
$notificationPayload = [
    'title' => 'Diagnostic Push',
    'body' => 'Checking background tray delivery at ' . date('H:i:s')
];

echo "Sending to FCM...<br>";
$result = $fcmClient->sendDataMessage($token, $projectId, $dataPayload, $notificationPayload);

echo "FCM Result:<br>";
echo "<pre>";
print_r(json_decode($result, true));
echo "</pre>";
?>
