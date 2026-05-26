<?php
// debug_nearby_v2.php — Check FCM tokens, notification delivery, and match_profiles state
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');

require_once __DIR__ . '/db_connect.php';

$action = $_GET['action'] ?? 'check';

if ($action === 'check') {
    // Check FCM tokens for both users
    $stmt = $pdo->query("SELECT id, name, fcm_token, 
        CASE WHEN fcm_token IS NULL OR fcm_token = '' THEN 'MISSING' ELSE 'PRESENT' END as token_status,
        LENGTH(fcm_token) as token_length
        FROM users WHERE id IN (9, 13)");
    $users_fcm = $stmt->fetchAll(PDO::FETCH_ASSOC);
    
    // Redact tokens for security (show first/last 10 chars)
    foreach ($users_fcm as &$u) {
        if (!empty($u['fcm_token'])) {
            $tk = $u['fcm_token'];
            $u['fcm_token_preview'] = substr($tk, 0, 15) . '...' . substr($tk, -15);
            unset($u['fcm_token']);
        }
    }

    // Check match_profiles with location data
    $stmt2 = $pdo->query("SELECT mp.user_id, mp.lat, mp.lng, mp.is_visible, 
        mp.last_location_update, mp.last_nearby_notif
        FROM match_profiles mp WHERE mp.user_id IN (9, 13)");
    $profiles = $stmt2->fetchAll(PDO::FETCH_ASSOC);

    // Check most recent nearby notifications
    $stmt3 = $pdo->query("SELECT id, user_id, sender_id, type, title, message, created_at
        FROM notifications WHERE type = 'nearby' ORDER BY created_at DESC LIMIT 5");
    $notifs = $stmt3->fetchAll(PDO::FETCH_ASSOC);

    // Check PHP error log for FCM failures
    $errorLog = '';
    $logFile = __DIR__ . '/../../error_log';
    if (file_exists($logFile)) {
        $lines = file($logFile);
        $lastLines = array_slice($lines, -20);
        $errorLog = implode('', $lastLines);
    }
    
    // Check match_debug.log
    $matchDebug = '';
    $debugFile = __DIR__ . '/match_debug.log';
    if (file_exists($debugFile)) {
        $lines = file($debugFile);
        $lastLines = array_slice($lines, -30);
        $matchDebug = implode('', $lastLines);
    }

    // Check server time
    $serverTime = date('Y-m-d H:i:s');

    echo json_encode([
        'status' => 'success',
        'server_time' => $serverTime,
        'users_fcm_status' => $users_fcm,
        'match_profiles' => $profiles,
        'recent_nearby_notifs' => $notifs,
        'php_error_log_last20' => $errorLog,
        'match_debug_log_last30' => $matchDebug,
    ], JSON_PRETTY_PRINT);
}

elseif ($action === 'test_fcm') {
    // Try sending a test nearby notification from user 13 to user 9
    require_once __DIR__ . '/notification_helper.php';
    
    $targetUserId = (int)($_GET['to'] ?? 9);
    $senderId = (int)($_GET['from'] ?? 13);
    
    $result = send_app_notification(
        $pdo, 
        $targetUserId, 
        $senderId, 
        'nearby', 
        '📍 Someone is nearby!', 
        'Test nearby notification - triggered manually'
    );
    
    echo json_encode([
        'status' => 'success',
        'message' => 'Test notification sent',
        'send_result' => $result,
        'to_user' => $targetUserId,
        'from_user' => $senderId,
    ], JSON_PRETTY_PRINT);
}

else {
    echo json_encode(['status' => 'error', 'message' => 'Use action=check or action=test_fcm']);
}
