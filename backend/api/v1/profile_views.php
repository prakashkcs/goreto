<?php
/**
 * profile_views.php
 * POST  body:{profile_id}  — record that the authenticated user viewed a profile
 * GET   ?page=N            — return list of users who viewed MY profile
 */
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Content-Type, Authorization');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); echo '{}'; exit; }

require_once __DIR__ . '/db_connect.php';
require_once __DIR__ . '/auth_middleware.php';

function jout(int $code, array $arr): void { http_response_code($code); echo json_encode($arr); exit; }

if (!isset($pdo) || !($pdo instanceof PDO)) jout(500, ['status' => 'error', 'message' => 'DB error']);

$viewer = requireUser($pdo);
$viewerId = (int)$viewer['id'];

// Ensure table exists
try {
    $pdo->exec("CREATE TABLE IF NOT EXISTS profile_views (
        id BIGINT AUTO_INCREMENT PRIMARY KEY,
        profile_id INT NOT NULL,
        viewer_id  INT NOT NULL,
        viewed_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        UNIQUE KEY uniq_pv (profile_id, viewer_id),
        KEY idx_profile (profile_id),
        KEY idx_viewer  (viewer_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
} catch (Throwable $_) {}

// ── POST: record a view ───────────────────────────────────────────────────────
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $body = json_decode(file_get_contents('php://input'), true) ?? $_POST;
    $profileId = (int)($body['profile_id'] ?? 0);

    if (!$profileId || $profileId === $viewerId) jout(400, ['status' => 'error', 'message' => 'Invalid profile_id']);

    // Only record if the profile owner has profile views enabled
    $privChk = $pdo->prepare('SELECT COALESCE(privacy_show_profile_views, 1) AS v FROM users WHERE id = ? LIMIT 1');
    $privChk->execute([$profileId]);
    if ((int)($privChk->fetchColumn() ?? 1) === 1) {
        $pdo->prepare("INSERT INTO profile_views (profile_id, viewer_id, viewed_at)
                       VALUES (?, ?, NOW())
                       ON DUPLICATE KEY UPDATE viewed_at = NOW()")
            ->execute([$profileId, $viewerId]);
    }

    jout(200, ['status' => 'success']);
}

// ── GET: list who viewed MY profile ──────────────────────────────────────────
if ($_SERVER['REQUEST_METHOD'] === 'GET') {
    $page   = max(1, (int)($_GET['page'] ?? 1));
    $limit  = 30;
    $offset = ($page - 1) * $limit;

    // LIMIT/OFFSET cannot be bound as parameters here: with emulated prepares
    // PDO quotes them, MySQL receives LIMIT '30' OFFSET '0' and rejects the
    // statement. Both values are integers we computed, so inlining is safe.
    $stmt = $pdo->prepare("
        SELECT pv.viewer_id, pv.viewed_at,
               u.name, u.username, u.profile_pic
        FROM profile_views pv
        JOIN users u ON u.id = pv.viewer_id
        WHERE pv.profile_id = ?
        ORDER BY pv.viewed_at DESC
        LIMIT " . (int)$limit . " OFFSET " . (int)$offset . "
    ");
    $stmt->execute([$viewerId]);
    $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

    $viewers = [];
    foreach ($rows as $r) {
        $pic = (string)($r['profile_pic'] ?? '');
        if ($pic !== '' && !preg_match('~^https?://~i', $pic)) {
            $pic = 'https://goreto.org/ekloadmin/' . ltrim($pic, '/');
        }
        $viewers[] = [
            'user_id'   => (string)$r['viewer_id'],
            'name'      => $r['name'] ?: $r['username'] ?: 'User',
            'username'  => (string)($r['username'] ?? ''),
            'avatar'    => $pic !== '' ? $pic : null,
            'viewed_at' => (string)$r['viewed_at'],
        ];
    }

    jout(200, ['status' => 'success', 'viewers' => $viewers, 'page' => $page]);
}

jout(405, ['status' => 'error', 'message' => 'Method not allowed']);
