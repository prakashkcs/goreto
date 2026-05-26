<?php
// Public endpoint — returns notification provider config for the Flutter app.
// No auth required (only non-sensitive keys are exposed).
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');

include_once 'db_connect.php';

try {
    $database = new Database();
    $db = $database->connect();

    $rows = $db->query("SELECT setting_key, setting_value FROM notification_settings")->fetchAll(PDO::FETCH_ASSOC);
    $settings = [];
    foreach ($rows as $r) {
        $settings[$r['setting_key']] = $r['setting_value'];
    }

    echo json_encode([
        'status' => 'success',
        // Only expose the App ID — never the REST API key
        'onesignal_app_id' => $settings['onesignal_app_id'] ?? '',
        'onesignal_enabled' => ($settings['onesignal_enabled'] ?? '0') === '1',
        'default_provider' => $settings['default_provider'] ?? 'in_app',
        'fcm_push_enabled' => ($settings['fcm_push_enabled'] ?? '1') === '1',
    ]);
} catch (Throwable $e) {
    echo json_encode([
        'status' => 'error',
        'onesignal_app_id' => '',
        'onesignal_enabled' => false,
        'default_provider' => 'in_app',
        'fcm_push_enabled' => true,
    ]);
}
