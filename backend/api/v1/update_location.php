<?php
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Content-Type, Authorization');
header('Access-Control-Allow-Methods: POST, OPTIONS');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    echo json_encode(['status' => true]);
    exit;
}

require_once __DIR__ . '/db_connect.php';
require_once __DIR__ . '/auth_middleware.php';

try {
    $viewer = requireUser($pdo);
    $userId = (int)$viewer['id'];

    if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
        http_response_code(405);
        echo json_encode(['status' => false, 'message' => 'POST required']);
        exit;
    }

    $raw = file_get_contents('php://input');
    $body = json_decode($raw, true) ?? $_POST;

    $lat = isset($body['lat']) ? floatval($body['lat']) : null;
    $lng = isset($body['lng']) ? floatval($body['lng']) : null;

    if ($lat === null || $lng === null) {
        echo json_encode(['status' => false, 'message' => 'lat and lng required']);
        exit;
    }

    // Ensure columns exist
    try {
        $pdo->query("SELECT latitude, longitude, location_updated_at FROM users LIMIT 1");
    }
    catch (Throwable $e) {
        try {
            // First check what columns exist
            $stmt = $pdo->query("SHOW COLUMNS FROM users");
            $uCols = [];
            while ($row = $stmt->fetch(PDO::FETCH_ASSOC)) {
                $uCols[] = $row['Field'];
            }
            if (!in_array('latitude', $uCols)) {
                $pdo->exec("ALTER TABLE users ADD COLUMN latitude DOUBLE NULL");
            }
            if (!in_array('longitude', $uCols)) {
                $pdo->exec("ALTER TABLE users ADD COLUMN longitude DOUBLE NULL");
            }
            if (!in_array('location_updated_at', $uCols)) {
                $pdo->exec("ALTER TABLE users ADD COLUMN location_updated_at DATETIME NULL");
            }
        }
        catch (Throwable $e2) {
            error_log("Failed to alter location columns: " . $e2->getMessage());
        }
    }

    $pdo->prepare("UPDATE users SET latitude = ?, longitude = ?, location_updated_at = NOW() WHERE id = ?")
        ->execute([$lat, $lng, $userId]);

    echo json_encode(['status' => true, 'message' => 'Location updated']);

}
catch (Throwable $e) {
    http_response_code(500);
    echo json_encode(['status' => false, 'message' => 'Server error', 'error' => $e->getMessage()]);
}
