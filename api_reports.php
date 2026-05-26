<?php
/**
 * api_reports.php — User-submitted reports (bugs, abuse, content)
 *
 * POST  action=submit_report   → submit a new report (with optional image upload)
 * GET   action=check_reported  → check if current user already reported target
 */

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Content-Type, Authorization');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    echo json_encode(['status' => 'ok']);
    exit;
}

ini_set('display_errors', '0');
error_reporting(E_ALL);

// Resolve base dir whether file lives in root or api/v1/
$_base = __DIR__;
if (!file_exists($_base . '/db_connect.php') && file_exists($_base . '/../db_connect.php')) {
    $_base = realpath($_base . '/..');
}
require_once $_base . '/db_connect.php';
require_once $_base . '/auth_middleware.php';

function out(int $code, array $data): void
{
    http_response_code($code);
    echo json_encode($data);
    exit;
}

if (!isset($pdo) || !($pdo instanceof PDO)) {
    out(500, ['status' => 'error', 'message' => 'DB not connected']);
}

$config  = $config ?? [];
$baseUrl = rtrim($config['base_url'] ?? 'https://goreto.org/ekloadmin', '/');

// ── Ensure user_reports table exists with all required columns ────────────────

$pdo->exec("CREATE TABLE IF NOT EXISTS `user_reports` (
    `id`           INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `reporter_id`  INT UNSIGNED NOT NULL,
    `reported_id`  INT UNSIGNED NOT NULL DEFAULT 0,
    `report_type`  ENUM('user','post','system') NOT NULL DEFAULT 'user',
    `post_id`      INT UNSIGNED NULL DEFAULT NULL,
    `reason`       VARCHAR(255) NOT NULL DEFAULT '',
    `details`      TEXT NULL,
    `image_url`    VARCHAR(500) NULL DEFAULT NULL,
    `status`       ENUM('pending','reviewed','resolved','dismissed') NOT NULL DEFAULT 'pending',
    `admin_notes`  TEXT NULL,
    `created_at`   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at`   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX `idx_reporter`    (`reporter_id`),
    INDEX `idx_reported`    (`reported_id`),
    INDEX `idx_status`      (`status`),
    INDEX `idx_report_type` (`report_type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci");

// Ensure any missing columns are added to an existing table
$existingCols = [];
try {
    foreach ($pdo->query("SHOW COLUMNS FROM `user_reports`")->fetchAll(PDO::FETCH_ASSOC) as $c) {
        $existingCols[] = $c['Field'];
    }
} catch (Throwable $_) {
}

$colsToAdd = [
    'report_type' => "ENUM('user','post','system') NOT NULL DEFAULT 'user' AFTER `reported_id`",
    'post_id'     => "INT UNSIGNED NULL DEFAULT NULL AFTER `report_type`",
    'image_url'   => "VARCHAR(500) NULL DEFAULT NULL AFTER `details`",
];
foreach ($colsToAdd as $col => $def) {
    if (!in_array($col, $existingCols, true)) {
        try {
            $pdo->exec("ALTER TABLE `user_reports` ADD COLUMN `$col` $def");
        } catch (Throwable $_) {
        }
    }
}

// Add missing indexes (ignore errors if already exist)
$indexesToAdd = [
    'idx_reporter'    => 'reporter_id',
    'idx_reported'    => 'reported_id',
    'idx_status'      => 'status',
    'idx_report_type' => 'report_type',
];
foreach ($indexesToAdd as $idxName => $col) {
    try {
        $pdo->exec("ALTER TABLE `user_reports` ADD INDEX `$idxName` (`$col`)");
    } catch (Throwable $_) {
        // Index likely already exists — ignore
    }
}

// ── Route ─────────────────────────────────────────────────────────────────────

$method = $_SERVER['REQUEST_METHOD'];
$action = $_GET['action'] ?? $_POST['action'] ?? '';

// All actions require a valid authenticated user
$authUser = requireUser($pdo);
$reporterId = (int) $authUser['id'];

// ── GET: check_reported ───────────────────────────────────────────────────────

if ($method === 'GET' && $action === 'check_reported') {
    $reportedId  = (int) ($_GET['reported_id'] ?? 0);
    $reportType  = $_GET['report_type'] ?? 'user';
    if (!in_array($reportType, ['user', 'post', 'system'], true)) {
        $reportType = 'user';
    }

    if ($reportedId <= 0 && $reportType !== 'system') {
        out(400, ['status' => 'error', 'message' => 'reported_id is required']);
    }

    try {
        $stmt = $pdo->prepare("
            SELECT COUNT(*) FROM `user_reports`
            WHERE reporter_id = ? AND reported_id = ? AND report_type = ?
        ");
        $stmt->execute([$reporterId, $reportedId, $reportType]);
        $count = (int) $stmt->fetchColumn();
        out(200, [
            'status'       => 'success',
            'reported'     => $count > 0,
            'report_count' => $count,
        ]);
    } catch (Throwable $e) {
        out(500, ['status' => 'error', 'message' => 'Query failed']);
    }
}

// ── POST: submit_report ───────────────────────────────────────────────────────

if ($method === 'POST' && $action === 'submit_report') {

    // Accept JSON body or multipart/form-data
    $payload = [];
    $rawBody = file_get_contents('php://input');
    if ($rawBody) {
        $decoded = json_decode($rawBody, true);
        if (is_array($decoded)) {
            $payload = $decoded;
        }
    }
    // Merge $_POST (multipart) — POST wins over JSON body
    $payload = array_merge($payload, $_POST);

    $reportType = $payload['report_type'] ?? 'user';
    if (!in_array($reportType, ['user', 'post', 'system'], true)) {
        out(400, ['status' => 'error', 'message' => 'Invalid report_type. Must be user, post, or system.']);
    }

    $reportedId = (int) ($payload['reported_id'] ?? 0);
    $postId     = isset($payload['post_id']) && $payload['post_id'] !== '' ? (int) $payload['post_id'] : null;
    $reason     = trim((string) ($payload['reason'] ?? ''));
    $details    = trim((string) ($payload['details'] ?? ''));

    if ($reason === '') {
        out(400, ['status' => 'error', 'message' => 'reason is required']);
    }

    if ($reportType !== 'system' && $reportedId <= 0) {
        out(400, ['status' => 'error', 'message' => 'reported_id is required for user/post reports']);
    }

    // ── Rate limit: same reporter + reported + type within last 24 hours ──────
    try {
        $stmtRateCheck = $pdo->prepare("
            SELECT COUNT(*) FROM `user_reports`
            WHERE reporter_id = ?
              AND reported_id = ?
              AND report_type = ?
              AND created_at >= NOW() - INTERVAL 24 HOUR
        ");
        $stmtRateCheck->execute([$reporterId, $reportedId, $reportType]);
        if ((int) $stmtRateCheck->fetchColumn() > 0) {
            out(429, [
                'status'  => 'error',
                'message' => 'You already reported this recently. Please wait 24 hours.',
            ]);
        }
    } catch (Throwable $e) {
        out(500, ['status' => 'error', 'message' => 'Rate-limit check failed']);
    }

    // ── Image upload ──────────────────────────────────────────────────────────
    $imageUrl = null;

    if (!empty($_FILES['image']) && $_FILES['image']['error'] === UPLOAD_ERR_OK) {
        $uploadDir = '/var/www/html/ekloadmin/uploads/reports/';

        // Create directory if it doesn't exist
        if (!is_dir($uploadDir)) {
            if (!mkdir($uploadDir, 0755, true)) {
                out(500, ['status' => 'error', 'message' => 'Failed to create upload directory']);
            }
        }

        $tmpPath  = $_FILES['image']['tmp_name'];
        $origName = $_FILES['image']['name'];
        $ext      = strtolower(pathinfo($origName, PATHINFO_EXTENSION));

        $allowedExts = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'heic'];
        if (!in_array($ext, $allowedExts, true)) {
            out(400, ['status' => 'error', 'message' => 'Invalid image type. Allowed: jpg, jpeg, png, gif, webp, heic']);
        }

        // Validate MIME type
        $finfo = finfo_open(FILEINFO_MIME_TYPE);
        $mime  = finfo_file($finfo, $tmpPath);
        finfo_close($finfo);
        $allowedMimes = ['image/jpeg', 'image/png', 'image/gif', 'image/webp', 'image/heic'];
        if (!in_array($mime, $allowedMimes, true)) {
            out(400, ['status' => 'error', 'message' => 'Invalid image MIME type']);
        }

        // Max 10 MB
        if ($_FILES['image']['size'] > 10 * 1024 * 1024) {
            out(400, ['status' => 'error', 'message' => 'Image too large. Maximum size is 10 MB.']);
        }

        $fileName = 'report_' . $reporterId . '_' . time() . '_' . bin2hex(random_bytes(4)) . '.' . $ext;
        $destPath = $uploadDir . $fileName;

        if (!move_uploaded_file($tmpPath, $destPath)) {
            out(500, ['status' => 'error', 'message' => 'Failed to save uploaded image']);
        }

        $imageUrl = 'https://goreto.org/ekloadmin/uploads/reports/' . $fileName;
    }

    // ── Insert report ─────────────────────────────────────────────────────────
    try {
        $stmt = $pdo->prepare("
            INSERT INTO `user_reports`
                (reporter_id, reported_id, report_type, post_id, reason, details, image_url, status, created_at, updated_at)
            VALUES
                (?, ?, ?, ?, ?, ?, ?, 'pending', NOW(), NOW())
        ");
        $stmt->execute([
            $reporterId,
            $reportedId,
            $reportType,
            $postId,
            $reason,
            $details !== '' ? $details : null,
            $imageUrl,
        ]);

        out(200, [
            'status'  => 'success',
            'message' => 'Report submitted successfully',
        ]);
    } catch (Throwable $e) {
        out(500, ['status' => 'error', 'message' => 'Failed to save report']);
    }
}

// ── Fallback ──────────────────────────────────────────────────────────────────
out(400, ['status' => 'error', 'message' => 'Unknown action or method']);
