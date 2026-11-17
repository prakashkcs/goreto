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
try {
    $pdo->exec("ALTER TABLE video_providers ADD COLUMN service_type VARCHAR(10) NOT NULL DEFAULT 'call' AFTER provider_name");
} catch (Throwable $_) {}

$action = $_GET['action'] ?? $_POST['action'] ?? '';
// 'call' (1:1 / random voice+video calls) or 'live' (Go Live broadcast) --
// each has its own independently-configured active provider.
$serviceType = $_GET['service_type'] ?? $_POST['service_type'] ?? 'call';
if (!in_array($serviceType, ['call', 'live'], true)) {
    $serviceType = 'call';
}

try {
    // ── 1. GET ACTIVE PROVIDER ── (no auth, called by Flutter client)
    if ($action === 'get_active') {
        $stmt = $pdo->prepare("SELECT * FROM video_providers WHERE is_active = 1 AND service_type = ? LIMIT 1");
        $stmt->execute([$serviceType]);
        $provider = $stmt->fetch(PDO::FETCH_ASSOC);

        if ($provider) {
            echo json_encode([
                'status'   => 'success',
                'provider' => [
                    'name'          => $provider['provider_name'],
                    'app_id'        => $provider['app_id'],
                    'app_sign'      => $provider['app_sign'] ?? '',
                    'server_secret' => $provider['server_secret'] ?? '',
                    // Echo which service this row is for. agora_token.php looks
                    // the credentials up by service_type, so a client that
                    // cannot tell call from live asks for the wrong row.
                    'service_type'  => $provider['service_type'] ?? $serviceType,
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
        // The client's own auto_rotate hint is NOT trusted as the deciding
        // factor -- it previously was, which meant a per-provider "auto_rotate
        // off" set in the admin panel had no effect at all, since the app
        // always sent auto_rotate=1 on every error report regardless. The
        // database's per-(provider, service_type) flag is the real switch now.
        $rotated    = false;
        $nextProviderData = null;

        if ($provider !== '') {
            $stmt = $pdo->prepare("
                UPDATE video_providers
                SET last_error_time    = NOW(),
                    last_error_message = ?,
                    error_count        = COALESCE(error_count, 0) + 1
                WHERE provider_name = ? AND service_type = ?
            ");
            $stmt->execute([$errorMsg, $provider, $serviceType]);

            $curRow = $pdo->prepare("SELECT auto_rotate FROM video_providers WHERE provider_name = ? AND service_type = ? LIMIT 1");
            $curRow->execute([$provider, $serviceType]);
            $autoRotate = (int) $curRow->fetchColumn();

            if ($autoRotate) {
                // Find next best provider WITHIN THE SAME service_type: different
                // name, has app_id set, fewest errors. Never rotate a live-streaming
                // failure into a calls-only provider or vice versa.
                $nxt = $pdo->prepare("
                    SELECT id, provider_name, app_id, app_sign, server_secret, additional_config
                    FROM video_providers
                    WHERE provider_name != ? AND service_type = ?
                      AND app_id IS NOT NULL AND app_id != ''
                    ORDER BY COALESCE(error_count, 0) ASC, id ASC
                    LIMIT 1
                ");
                $nxt->execute([$provider, $serviceType]);
                $row = $nxt->fetch(PDO::FETCH_ASSOC);

                if ($row) {
                    $pdo->prepare("UPDATE video_providers SET is_active = 0 WHERE service_type = ?")->execute([$serviceType]);
                    $pdo->prepare("UPDATE video_providers SET is_active = 1 WHERE id = ?")->execute([$row['id']]);
                    $rotated = true;
                    $nextProviderData = [
                        'name'          => $row['provider_name'],
                        'app_id'        => $row['app_id'],
                        'app_sign'      => $row['app_sign'] ?? '',
                        'server_secret' => $row['server_secret'] ?? '',
                        'service_type'  => $row['service_type'] ?? $serviceType,
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
        $stmt = $pdo->query("SELECT id, provider_name AS name, service_type, is_active, last_error_time, last_error_message, error_count FROM video_providers");
        echo json_encode(['status' => 'success', 'providers' => $stmt->fetchAll(PDO::FETCH_ASSOC)]);
    } elseif ($action === 'activate') {
        $id = (int)($_POST['id'] ?? 0);
        // Only deactivate other providers of the SAME service_type as the one
        // being activated, so activating a live-streaming provider never
        // touches which provider is active for calls.
        $row = $pdo->prepare("SELECT service_type FROM video_providers WHERE id = ?");
        $row->execute([$id]);
        $svc = $row->fetchColumn();
        if ($svc !== false) {
            $pdo->prepare("UPDATE video_providers SET is_active = 0 WHERE service_type = ?")->execute([$svc]);
            $pdo->prepare("UPDATE video_providers SET is_active = 1 WHERE id = ?")->execute([$id]);
        }
        echo json_encode(['status' => 'success']);
    } elseif ($action === 'clear_error') {
        $provider = trim($_POST['provider'] ?? '');
        if ($provider !== '') {
            $stmt = $pdo->prepare("UPDATE video_providers SET last_error_time=NULL, last_error_message=NULL, error_count=0 WHERE provider_name=? AND service_type=?");
            $stmt->execute([$provider, $serviceType]);
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
