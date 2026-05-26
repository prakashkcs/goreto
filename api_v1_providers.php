<?php
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Content-Type, Authorization');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    exit;
}

require_once __DIR__ . '/db_connect.php';
require_once __DIR__ . '/auth_middleware.php';

$action = $_GET['action'] ?? $_POST['action'] ?? '';

try {
    // 1. GET ACTIVE PROVIDER (for Flutter client) - NO AUTH REQUIRED for this one
    if ($action === 'get_active') {
        $stmt = $pdo->query("SELECT * FROM video_providers WHERE is_active = 1 LIMIT 1");
        $provider = $stmt->fetch(PDO::FETCH_ASSOC);

        if ($provider) {
            echo json_encode([
                'status' => 'success',
                'provider' => [
                    'name' => $provider['provider_name'],
                    'app_id' => $provider['app_id'],
                    'app_sign' => $provider['app_sign'] ?? '',
                    'server_secret' => $provider['server_secret'],
                    'config' => json_decode($provider['additional_config'] ?? '{}', true)
                ]
            ]);
        }
        else {
            echo json_encode(['status' => 'error', 'message' => 'No active video provider found']);
        }
        exit;
    }

    // All other actions require auth
    $viewer = requireUser($pdo);

    if ($action === 'list') {
        $stmt = $pdo->query("SELECT id, provider_name as name, is_active FROM video_providers");
        echo json_encode(['status' => 'success', 'providers' => $stmt->fetchAll(PDO::FETCH_ASSOC)]);
    }
    elseif ($action === 'activate') {
        $id = (int)$_POST['id'];
        $pdo->exec("UPDATE video_providers SET is_active = 0");
        $stmt = $pdo->prepare("UPDATE video_providers SET is_active = 1 WHERE id = ?");
        $stmt->execute([$id]);
        echo json_encode(['status' => 'success']);
    }
    else {
        echo json_encode(['status' => 'error', 'message' => 'Unknown action']);
    }
}
catch (Throwable $e) {
    http_response_code(500);
    echo json_encode(['status' => 'error', 'message' => $e->getMessage()]);
}
?>
