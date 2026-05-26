<?php
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Content-Type, Authorization');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    echo json_encode(['status' => 'success']);
    exit;
}

require_once __DIR__ . '/db_connect.php';
require_once __DIR__ . '/auth_middleware.php';
$config = require __DIR__ . '/../../config/config.php';

// --- Utility Functions ---
function out_json(int $code, array $payload): void
{
    http_response_code($code);
    echo json_encode($payload);
    exit;
}

function norm_url(?string $url, string $baseUrl): ?string
{
    if ($url === null)
        return null;
    $url = trim((string)$url);
    if ($url === '')
        return '';

    // CDN Redirection for relative upload paths
    if (strpos($url, 'uploads/') !== false && !preg_match('~^https?://~i', $url)) {
        return 'https://goreto.org/ekloadmin/' . ltrim($url, '/');
    }

    if (preg_match('~^https?://~i', $url))
        return $url;
    $baseUrl = rtrim($baseUrl, '/');
    if ($url[0] === '/')
        return $baseUrl . $url;
    return $baseUrl . '/' . $url;
}

try {
    if (!isset($pdo) || !($pdo instanceof PDO)) {
        out_json(500, ['status' => 'error', 'message' => 'DB connection not available']);
    }

    // 🔧 Auto-migration: Ensure stories table exists
    // The bug report mentions "stories table", so we assume it should exist.
    $pdo->exec("CREATE TABLE IF NOT EXISTS `stories` (
        `id` INT AUTO_INCREMENT PRIMARY KEY,
        `user_id` INT NOT NULL,
        `media_url` TEXT NOT NULL,
        `type` ENUM('image', 'video') DEFAULT 'image',
        `music` VARCHAR(255) NULL,
        `tags` TEXT NULL,
        `filter_name` VARCHAR(32) NULL,
        `bg_color` VARCHAR(32) NULL,
        `text_overlays` TEXT NULL,
        `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        INDEX (`user_id`),
        INDEX (`created_at`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;");

    // Auto-migrate: add new columns to existing stories tables
    foreach (['filter_name VARCHAR(32) NULL', 'bg_color VARCHAR(32) NULL', 'text_overlays TEXT NULL'] as $colDef) {
        $col = explode(' ', $colDef)[0];
        try { $pdo->exec("ALTER TABLE `stories` ADD COLUMN `$col` $colDef"); } catch (Throwable $e) {}
    }

    $baseUrl = rtrim(($config['base_url'] ?? 'https://goreto.org/ekloadmin/api/v1'), '/');

    /* =========================================================
     ✅ POST: Upload Story
     ========================================================= */
    if ($_SERVER['REQUEST_METHOD'] === 'POST' && (!isset($_GET['action']) || $_GET['action'] === 'upload')) {
        // FIXED: requireUser correctly looks up in users table via api_token
        $viewer = requireUser($pdo);
        $userId = intval($viewer['id']);

        if (!isset($_FILES['file']) || !is_uploaded_file($_FILES['file']['tmp_name'])) {
            out_json(400, ['status' => 'error', 'message' => 'No file uploaded']);
        }

        $uploadDir = __DIR__ . '/uploads/stories/';
        if (!is_dir($uploadDir))
            @mkdir($uploadDir, 0777, true);

        $origName = basename($_FILES['file']['name']);
        $ext = pathinfo($origName, PATHINFO_EXTENSION);
        $fileName = uniqid('s_', true) . ($ext ? '.' . preg_replace('/[^a-zA-Z0-9]/', '', $ext) : '');
        $destPath = $uploadDir . $fileName;

        if (!move_uploaded_file($_FILES['file']['tmp_name'], $destPath)) {
            out_json(500, ['status' => 'error', 'message' => 'Failed to move uploaded file']);
        }

        // --- BunnyCDN Integration ---
        require_once __DIR__ . '/bunny_helper.php';
        $bunnyPath = 'uploads/stories/' . $fileName;
        $cdnUrl = uploadToBunny($destPath, $bunnyPath);
        if ($cdnUrl) {
            $mediaUrl = $cdnUrl;
        // @unlink($destPath);
        }
        else {
            $mediaUrl = rtrim(($config['base_url'] ?? 'https://goreto.org/ekloadmin'), '/') . "/api/v1/uploads/stories/" . $fileName;
        }
        // ---------------------------
        $type        = (isset($_POST['type']) && $_POST['type'] === 'video') ? 'video' : 'image';
        $music       = $_POST['music']       ?? null;
        $tags        = $_POST['tags']        ?? null;
        $filterName  = $_POST['filter_name'] ?? null;
        $bgColor     = $_POST['bg_color']    ?? null;
        $textOverlays= $_POST['text_overlays'] ?? null;

        $stmt = $pdo->prepare("INSERT INTO `stories`
            (user_id, media_url, type, music, tags, filter_name, bg_color, text_overlays)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)");
        $stmt->execute([$userId, $mediaUrl, $type, $music, $tags, $filterName, $bgColor, $textOverlays]);

        out_json(200, ['status' => 'success', 'message' => 'Story uploaded successfully', 'id' => $pdo->lastInsertId()]);
    }

    /* =========================================================
     ✅ GET: Active Stories
     ========================================================= */
    $action = $_GET['action'] ?? '';

    if ($action === 'active') {
        // Fetch stories from the last 24 hours
        // Join with users to fix "user name and profile pic are not showing"
        $sql = "SELECT s.*, u.name as user_name, u.profile_pic as user_avatar, u.username as user_handle
                FROM `stories` s
                JOIN `users` u ON u.id = s.user_id
                WHERE s.created_at >= DATE_SUB(NOW(), INTERVAL 24 HOUR)
                ORDER BY s.created_at DESC";

        $stmt = $pdo->query($sql);
        $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

        $stories = [];
        foreach ($rows as $r) {
            $stories[] = [
                'id' => (string)$r['id'],
                'user_id' => (string)$r['user_id'],
                'user_name' => (string)$r['user_name'],
                'user_avatar' => norm_url($r['user_avatar'], $baseUrl),
                'user_handle' => (string)$r['user_handle'],
                'media_url' => norm_url($r['media_url'], $baseUrl),
                'type'          => (string)$r['type'],
                'music'         => (string)($r['music'] ?? ''),
                'tags'          => (string)($r['tags'] ?? ''),
                'filter_name'   => (string)($r['filter_name'] ?? ''),
                'bg_color'      => (string)($r['bg_color'] ?? ''),
                'text_overlays' => (string)($r['text_overlays'] ?? ''),
                'created_at' => (string)$r['created_at']
            ];
        }

        out_json(200, ['status' => 'success', 'stories' => $stories]);
    }

    // Default response
    out_json(400, ['status' => 'error', 'message' => 'Invalid action']);

}
catch (Throwable $e) {
    out_json(500, ['status' => 'error', 'message' => $e->getMessage()]);
}
