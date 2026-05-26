<?php
header('Content-Type: text/plain');
require_once __DIR__ . '/db_connect.php';
require_once __DIR__ . '/notification_helper.php';

$userId = 9;
$title = "Test System Tray " . time();
$body = "If you see this in the system tray, it works!";

echo "Attempting to send notification to User ID $userId...\n";
$ok = send_app_notification($pdo, $userId, 0, 'test_system_tray', $title, $body);

if ($ok) {
    echo "Notification sent (check fcm_v1_debug.log and system tray).\n";
} else {
    echo "Failed to initiate notification.\n";
}
