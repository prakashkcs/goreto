<?php
header('Content-Type: application/json');

$deps = [
    'db_connect.php' => file_exists(__DIR__ . '/db_connect.php'),
    'auth_middleware.php' => file_exists(__DIR__ . '/auth_middleware.php'),
    'notification_helper.php' => file_exists(__DIR__ . '/notification_helper.php'),
];

$functions = [];
if ($deps['notification_helper.php']) {
    try {
        require_once __DIR__ . '/notification_helper.php';
        $functions['send_app_notification'] = function_exists('send_app_notification');
    } catch (Throwable $e) {
        $functions['send_app_notification_error'] = $e->getMessage();
    }
}

echo json_encode([
    'status' => 'success',
    'dependencies' => $deps,
    'functions' => $functions
]);
