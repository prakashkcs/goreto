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

// Ensure app_sign and error columns exist (safe migration)
try {
    $pdo->exec("ALTER TABLE video_providers ADD COLUMN app_sign VARCHAR(255) DEFAULT '' AFTER app_id");
} catch (Throwable $_) {}
try {
    $pdo->exec("ALTER TABLE video_providers ADD COLUMN last_error_message TEXT NULL AFTER last_error_time");
} catch (Throwable $_) {}
try {
    $pdo->exec("ALTER TABLE video_providers ADD COLUMN error_count INT DEFAULT 0 AFTER last_error_message");
} catch (Throwable $_) {}

$action = $_GET['action'] ?? $_POST['action'] ?? '';

try {
    // ── 1. GET ACTIVE PROVIDER ── (no auth, called by Flutter client)
    if ($action === 'get_active') {
        $stmt = $pdo->query("SELECT * FROM video_providers WHERE is_active = 1 LIMIT 1");
        $provider = $stmt->fetch(PDO::FETCH_ASSOC);

        if ($provider) {
            echo json_encode([
                'status'   => 'success',
                'provider' => [
                    'name'          => $provider['provider_name'],
                    'app_id'        => $provider['app_id'],
                    'app_sign'      => $provider['app_sign'] ?? '',
                    'server_secret' => $provider['server_secret'] ?? '',
                    'config'        => json_decode($provider['additional_config'] ?? '{}', true),
                ]
            ]);
        } else {
            echo json_encode(['status' => 'error', 'message' => 'No active video provider configured']);
        }
        exit;
    }

    // ── 2. REPORT ERROR ── (called by Flutter when SDK login/connect fails, no strict auth needed)
    if ($action === 'report_error') {
        $provider   = trim($_REQUEST['provider']    ?? '');
        $errorMsg   = trim($_REQUEST['error']       ?? 'Unknown error');
        $autoRotate = (int)($_REQUEST['auto_rotate'] ?? 0);
        $rotated    = false;
        $nextProviderData = null;

        if ($provider !== '') {
            $stmt = $pdo->prepare("
                UPDATE video_providers
                SET last_error_time    = NOW(),
                    last_error_message = ?,
                    error_count        = COALESCE(error_count, 0) + 1
                WHERE provider_name = ?
            ");
            $stmt->execute([$errorMsg, $provider]);

            if ($autoRotate) {
                // Find next best provider: different name, has app_id set, fewest errors
                $nxt = $pdo->prepare("
                    SELECT id, provider_name, app_id, app_sign, server_secret, additional_config
                    FROM video_providers
                    WHERE provider_name != ?
                      AND app_id IS NOT NULL AND app_id != ''
                    ORDER BY COALESCE(error_count, 0) ASC, id ASC
                    LIMIT 1
                ");
                $nxt->execute([$provider]);
                $row = $nxt->fetch(PDO::FETCH_ASSOC);

                if ($row) {
                    $pdo->exec("UPDATE video_providers SET is_active = 0");
                    $pdo->prepare("UPDATE video_providers SET is_active = 1 WHERE id = ?")->execute([$row['id']]);
                    $rotated = true;
                    $nextProviderData = [
                        'name'          => $row['provider_name'],
                        'app_id'        => $row['app_id'],
                        'app_sign'      => $row['app_sign'] ?? '',
                        'server_secret' => $row['server_secret'] ?? '',
                        'config'        => json_decode($row['additional_config'] ?? '{}', true),
                    ];
                }
            }
        }

        echo json_encode([
            'status'   => 'ok',
            'rotated'  => $rotated,
            'provider' => $nextProviderData,
        ]);
        exit;
    }

    // All other actions require admin auth
    $viewer = requireUser($pdo);

    if ($action === 'list') {
        $stmt = $pdo->query("SELECT id, provider_name AS name, is_active, last_error_time, last_error_message, error_count FROM video_providers");
        echo json_encode(['status' => 'success', 'providers' => $stmt->fetchAll(PDO::FETCH_ASSOC)]);
    } elseif ($action === 'activate') {
        $id = (int)($_POST['id'] ?? 0);
        $pdo->exec("UPDATE video_providers SET is_active = 0");
        $stmt = $pdo->prepare("UPDATE video_providers SET is_active = 1 WHERE id = ?");
        $stmt->execute([$id]);
        echo json_encode(['status' => 'success']);
    } elseif ($action === 'clear_error') {
        $provider = trim($_POST['provider'] ?? '');
        if ($provider !== '') {
            $stmt = $pdo->prepare("UPDATE video_providers SET last_error_time=NULL, last_error_message=NULL, error_count=0 WHERE provider_name=?");
            $stmt->execute([$provider]);
        }
        echo json_encode(['status' => 'ok']);
    } else {
        echo json_encode(['status' => 'error', 'message' => 'Unknown action']);
    }
} catch (Throwable $e) {
    http_response_code(500);
    echo json_encode(['status' => 'error', 'message' => $e->getMessage()]);
}
?>
