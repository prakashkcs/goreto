<?php
/**
 * collections.php — Collections API
 *
 * GET  /api/v1/collections.php?action=list&user_id=X        → list user's collections
 * GET  /api/v1/collections.php?action=posts&collection_id=X → posts in a collection
 * POST /api/v1/collections.php?action=view&collection_id=X  → record collection view (unique)
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

function json_out($code, $arr)
{
    http_response_code($code);
    echo json_encode($arr);
    exit;
}

require_once __DIR__ . '/db_connect.php';
require_once __DIR__ . '/auth_middleware.php';

if (!isset($pdo) || !($pdo instanceof PDO)) {
    json_out(500, ['status' => false, 'message' => 'DB not connected']);
}

$action = strtolower(trim((string) ($_GET['action'] ?? 'list')));

// ─── Helper: ensure collection_views table ────────────────────────────────
function ensure_collection_views(PDO $pdo): void
{
    $pdo->exec("CREATE TABLE IF NOT EXISTS collection_views (
    id          BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    collection_id INT NOT NULL,
    viewer_id   INT NULL,
    viewer_ip   VARCHAR(64) NOT NULL DEFAULT '',
    viewed_at   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_cid (collection_id),
    UNIQUE KEY uq_view (collection_id, viewer_id, viewer_ip)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
}

// ─── ACTION: view (record unique collection view) ─────────────────────────
if ($action === 'view') {
    $collectionId = (int) ($_GET['collection_id'] ?? 0);
    if ($collectionId <= 0)
        json_out(400, ['status' => false, 'message' => 'collection_id required']);

    ensure_collection_views($pdo);

    $viewerId = null;
    try {
        $u = requireUser($pdo);
        $viewerId = (int) $u['id'];
    } catch (Throwable $e) {
    }

    $ip = $_SERVER['HTTP_X_FORWARDED_FOR'] ?? $_SERVER['REMOTE_ADDR'] ?? '';
    $ip = trim(explode(',', $ip)[0]);

    // Insert ignore = only count once per (collection, viewer/ip)
    $pdo->prepare("INSERT IGNORE INTO collection_views (collection_id, viewer_id, viewer_ip) VALUES (?, ?, ?)")
        ->execute([$collectionId, $viewerId, $viewerId ? '' : $ip]);

    json_out(200, ['status' => true]);
}

// ─── ACTION: posts (posts in a collection) ───────────────────────────────
if ($action === 'posts') {
    $collectionId = (int) ($_GET['collection_id'] ?? 0);
    if ($collectionId <= 0)
        json_out(400, ['status' => false, 'message' => 'collection_id required']);

    // Resolve table/column names
    $postTable = 'posts';
    $idCol = 'id';

    // Fetch via pivot table if it exists, else return empty
    try {
        $hasPivot = false;
        $st = $pdo->query("SHOW TABLES LIKE 'collection_posts'");
        if ($st->fetchColumn())
            $hasPivot = true;

        if ($hasPivot) {
            $st2 = $pdo->prepare("
        SELECT p.*, 
          COALESCE(p.views_total, p.view_count, p.views, 0) AS views_total,
          COALESCE(p.views_unique, 0) AS views_unique
        FROM $postTable p
        INNER JOIN collection_posts cp ON cp.post_id = p.$idCol
        WHERE cp.collection_id = ?
        ORDER BY cp.sort_order ASC, p.created_at DESC
        LIMIT 200
      ");
            $st2->execute([$collectionId]);
            $posts = $st2->fetchAll(PDO::FETCH_ASSOC);
        } else {
            $posts = [];
        }

        json_out(200, ['status' => true, 'posts' => $posts]);
    } catch (Throwable $e) {
        json_out(200, ['status' => true, 'posts' => [], 'debug' => $e->getMessage()]);
    }
}

// ─── ACTION: list (list user's collections with counts) ──────────────────
if ($action === 'list') {
    $targetUserId = (int) ($_GET['user_id'] ?? 0);
    if ($targetUserId <= 0)
        json_out(400, ['status' => false, 'message' => 'user_id required']);

    try {
        $hasColl = false;
        $st = $pdo->query("SHOW TABLES LIKE 'collections'");
        if ($st->fetchColumn())
            $hasColl = true;

        if (!$hasColl) {
            json_out(200, ['status' => true, 'collections' => []]);
        }

        $st2 = $pdo->prepare("
      SELECT c.id, c.title, c.cover_thumb, c.created_at,
        COALESCE((SELECT COUNT(*) FROM collection_posts cp WHERE cp.collection_id = c.id), 0) AS item_count,
        COALESCE((SELECT COUNT(*) FROM collection_views cv WHERE cv.collection_id = c.id), 0) AS views
      FROM collections c
      WHERE c.user_id = ?
      ORDER BY c.created_at DESC
    ");
        $st2->execute([$targetUserId]);
        $rows = $st2->fetchAll(PDO::FETCH_ASSOC);

        json_out(200, ['status' => true, 'collections' => $rows]);
    } catch (Throwable $e) {
        json_out(500, ['status' => false, 'message' => $e->getMessage()]);
    }
}

// ─── ACTION: create (create a new collection) ────────────────────────────
if ($action === 'create') {
    try {
        $user = requireUser($pdo);
        $userId = (int) $user['id'];
    } catch (Throwable $e) {
        json_out(401, ['status' => false, 'message' => 'Unauthorized']);
    }

    // Support both form-data and JSON body
    $jsonBody = [];
    $rawInput = file_get_contents('php://input');
    if (!empty($rawInput)) {
        $decoded = json_decode($rawInput, true);
        if (is_array($decoded))
            $jsonBody = $decoded;
    }

    $title = trim((string) ($_POST['title'] ?? $jsonBody['title'] ?? ''));
    if ($title === '')
        json_out(400, ['status' => false, 'message' => 'title required']);

    // Ensure collections table exists
    $pdo->exec("CREATE TABLE IF NOT EXISTS collections (
        id          INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
        user_id     INT NOT NULL,
        title       VARCHAR(255) NOT NULL,
        cover_thumb VARCHAR(512) DEFAULT NULL,
        created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_user (user_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

    $coverThumb = null;
    if (!empty($_FILES['cover']['tmp_name']) && is_uploaded_file($_FILES['cover']['tmp_name'])) {
        $dir = __DIR__ . '/uploads/collections/';
        if (!is_dir($dir))
            @mkdir($dir, 0777, true);
        $ext = pathinfo((string) $_FILES['cover']['name'], PATHINFO_EXTENSION);
        $ext = $ext ? '.' . preg_replace('/[^a-zA-Z0-9]/', '', $ext) : '.jpg';
        $fname = uniqid('col_', true) . $ext;
        if (move_uploaded_file($_FILES['cover']['tmp_name'], $dir . $fname)) {
            $coverThumb = '/api/v1/uploads/collections/' . $fname;
        }
    } elseif (!empty($_POST['cover_url'])) {
        $coverThumb = trim((string) $_POST['cover_url']);
    }

    $st = $pdo->prepare("INSERT INTO collections (user_id, title, cover_thumb) VALUES (?, ?, ?)");
    $st->execute([$userId, $title, $coverThumb]);
    $newId = (int) $pdo->lastInsertId();

    json_out(200, [
        'status' => 'success',
        'collection' => [
            'id' => $newId,
            'title' => $title,
            'cover_thumb' => $coverThumb,
            'item_count' => 0,
            'views' => 0,
            'created_at' => date('Y-m-d H:i:s'),
        ],
    ]);
}

json_out(400, ['status' => false, 'message' => 'Unknown action']);
