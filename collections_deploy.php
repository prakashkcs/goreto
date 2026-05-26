<?php
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Content-Type, Authorization');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

require_once __DIR__ . '/db_connect.php';

function out($arr, $code = 200) {
    http_response_code($code);
    echo json_encode($arr);
    exit;
}

function auth_uid(PDO $pdo) {
    $headers = function_exists('getallheaders') ? getallheaders() : [];
    $auth = $headers['Authorization'] ?? $headers['authorization'] ?? '';
    if (empty($auth)) {
        $auth = $_SERVER['HTTP_AUTHORIZATION'] ?? $_SERVER['REDIRECT_HTTP_AUTHORIZATION'] ?? '';
    }
    // Also accept token in POST/GET params as fallback for clients that can't set headers
    if (empty($auth)) {
        $t = $_POST['token'] ?? $_GET['token'] ?? '';
        if ($t !== '') $auth = 'Bearer ' . $t;
    }
    $token = trim($auth);
    if (stripos($token, 'Bearer ') === 0) {
        $token = trim(substr($token, 7));
    }
    if ($token === '') return null;
    // Check legacy api_token column first
    $st = $pdo->prepare('SELECT id FROM users WHERE api_token = ? LIMIT 1');
    $st->execute([$token]);
    $id = $st->fetchColumn();
    if ($id) return (int)$id;
    // Fall back to user_auth_tokens table (multi-device sessions)
    $st2 = $pdo->prepare('SELECT user_id FROM user_auth_tokens WHERE token = ? AND revoked_at IS NULL LIMIT 1');
    $st2->execute([$token]);
    $uid = $st2->fetchColumn();
    return $uid ? (int)$uid : null;
}

// Create tables if not exist
try {
    $pdo->exec('CREATE TABLE IF NOT EXISTS collections (
        id INT AUTO_INCREMENT PRIMARY KEY,
        user_id INT NOT NULL,
        title VARCHAR(120) NOT NULL,
        cover_url VARCHAR(500) DEFAULT NULL,
        item_count INT DEFAULT 0,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_col_user (user_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4');

    $pdo->exec('CREATE TABLE IF NOT EXISTS collection_posts (
        id INT AUTO_INCREMENT PRIMARY KEY,
        collection_id INT NOT NULL,
        post_id INT NOT NULL,
        added_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        UNIQUE KEY uq_colpost (collection_id, post_id),
        INDEX idx_colpost_col (collection_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4');
} catch (Exception $e) {
    // Tables may already exist
}

// Add columns introduced after initial table creation (safe to fail if already present)
$existing = $pdo->query('SELECT COLUMN_NAME FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = \'collections\'')
    ->fetchAll(PDO::FETCH_COLUMN);
if (!in_array('item_count', $existing)) {
    try { $pdo->exec('ALTER TABLE collections ADD COLUMN item_count INT DEFAULT 0'); } catch (Exception $e) {}
}
if (!in_array('views_count', $existing)) {
    try { $pdo->exec('ALTER TABLE collections ADD COLUMN views_count INT DEFAULT 0'); } catch (Exception $e) {}
}

$action = $_GET['action'] ?? $_POST['action'] ?? '';
$method = $_SERVER['REQUEST_METHOD'];
$proto = (isset($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off') ? 'https' : 'http';
$base_url = $proto . '://' . $_SERVER['HTTP_HOST'] . '/ekloadmin/';

// GET ALL COLLECTIONS
if ($action === 'get_all') {
    $uid = intval($_GET['user_id'] ?? $_POST['user_id'] ?? 0);
    if (!$uid) {
        $uid = auth_uid($pdo);
        if (!$uid) out(['status' => 'error', 'message' => 'Unauthenticated'], 401);
    }
    $stmt = $pdo->prepare(
        'SELECT c.id, c.title, c.cover_url, c.item_count, c.created_at,
            (SELECT COALESCE(p.thumbnail_url, p.file_url)
             FROM collection_posts cp
             JOIN posts p ON p.id = cp.post_id
             WHERE cp.collection_id = c.id
             ORDER BY cp.id ASC
             LIMIT 1) AS first_post_thumb
        FROM collections c
        WHERE c.user_id = ?
        ORDER BY c.created_at DESC'
    );
    $stmt->execute([$uid]);
    $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);
    foreach ($rows as &$r) {
        $effective_cover = $r['cover_url'] ?: $r['first_post_thumb'];
        if (!empty($effective_cover) && strpos($effective_cover, 'http') !== 0) {
            $effective_cover = $base_url . ltrim($effective_cover, '/');
        }
        $r['cover_url'] = $effective_cover;
        $r['cover_thumb'] = $effective_cover;
        $r['item_count'] = (int)$r['item_count'];
        unset($r['first_post_thumb']);
    }
    unset($r);
    out(['status' => 'success', 'collections' => $rows]);
}

// CREATE COLLECTION
if ($action === 'create' && $method === 'POST') {
    $uid = auth_uid($pdo);
    if (!$uid) out(['status' => 'error', 'message' => 'Unauthenticated'], 401);

    $title = trim($_POST['title'] ?? '');
    if (!$title) out(['status' => 'error', 'message' => 'Title required'], 400);

    $cover_url = null;
    if (!empty($_FILES['cover']['tmp_name'])) {
        $ext = strtolower(pathinfo($_FILES['cover']['name'], PATHINFO_EXTENSION));
        if (!in_array($ext, ['jpg', 'jpeg', 'png', 'webp'])) {
            out(['status' => 'error', 'message' => 'Invalid image type'], 400);
        }
        // Store under /ekloadmin/uploads/ so URL matches $base_url
        $dir = dirname(dirname(__DIR__)) . '/uploads/collections/';
        if (!is_dir($dir)) mkdir($dir, 0755, true);
        $fname = 'col_' . uniqid() . '.' . $ext;
        if (move_uploaded_file($_FILES['cover']['tmp_name'], $dir . $fname)) {
            $cover_url = 'uploads/collections/' . $fname;
        }
    } elseif (!empty($_POST['cover_url'])) {
        $cover_url = $_POST['cover_url'];
    }

    $ins = $pdo->prepare('INSERT INTO collections (user_id, title, cover_url) VALUES (?, ?, ?)');
    $ins->execute([$uid, $title, $cover_url]);
    $new_id = (int)$pdo->lastInsertId();

    $full_cover = null;
    if ($cover_url) {
        $full_cover = (strpos($cover_url, 'http') === 0)
            ? $cover_url
            : $base_url . ltrim($cover_url, '/');
    }

    out([
        'status' => 'success',
        'collection' => [
            'id'          => $new_id,
            'title'       => $title,
            'cover_url'   => $full_cover,
            'cover_thumb' => $full_cover,
            'item_count'  => 0,
            'created_at'  => date('Y-m-d H:i:s'),
        ],
    ]);
}

// GET POSTS IN COLLECTION
if ($action === 'posts') {
    $cid = intval($_GET['collection_id'] ?? 0);
    if (!$cid) out(['status' => 'error', 'message' => 'collection_id required'], 400);
    $stmt = $pdo->prepare('SELECT p.id, p.caption, p.type,
        COALESCE(p.file_url, \'\') AS file_url,
        COALESCE(p.thumbnail_url, \'\') AS thumbnail_url,
        COALESCE(p.view_count, 0) AS view_count,
        COALESCE(p.like_count, 0) AS like_count,
        p.created_at
        FROM collection_posts cp
        JOIN posts p ON p.id = cp.post_id
        WHERE cp.collection_id = ?
        ORDER BY cp.added_at DESC');
    $stmt->execute([$cid]);
    $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);
    foreach ($rows as &$row) {
        // Normalize file_url to absolute
        if (!empty($row['file_url']) && strpos($row['file_url'], 'http') !== 0) {
            $row['file_url'] = $base_url . ltrim($row['file_url'], '/');
        }
        // Normalize thumbnail_url to absolute
        if (!empty($row['thumbnail_url']) && strpos($row['thumbnail_url'], 'http') !== 0) {
            $row['thumbnail_url'] = $base_url . ltrim($row['thumbnail_url'], '/');
        }
        // For photo posts with no thumbnail, use file_url as thumbnail
        $t = strtolower($row['type'] ?? '');
        if (empty($row['thumbnail_url']) && $t !== 'video' && $t !== 'reel') {
            $row['thumbnail_url'] = $row['file_url'];
        }
        $row['media_url'] = $row['file_url'];
    }
    unset($row);
    out(['status' => 'success', 'posts' => $rows]);
}

// RECORD VIEW
if ($action === 'view' && $method === 'POST') {
    $cid = intval($_GET['collection_id'] ?? $_POST['collection_id'] ?? 0);
    if ($cid) {
        $pdo->prepare('UPDATE collections SET views_count = views_count + 1 WHERE id = ?')
            ->execute([$cid]);
    }
    out(['status' => 'success']);
}

// ADD POST TO COLLECTION
if ($action === 'add_post' && $method === 'POST') {
    $uid = auth_uid($pdo);
    if (!$uid) out(['status' => 'error', 'message' => 'Unauthenticated'], 401);
    $cid = intval($_POST['collection_id'] ?? 0);
    $pid = intval($_POST['post_id'] ?? 0);
    if (!$cid || !$pid) out(['status' => 'error', 'message' => 'Missing params'], 400);
    try {
        $pdo->prepare('INSERT IGNORE INTO collection_posts (collection_id, post_id) VALUES (?, ?)')
            ->execute([$cid, $pid]);
        $pdo->prepare('UPDATE collections SET item_count =
            (SELECT COUNT(*) FROM collection_posts WHERE collection_id = ?)
            WHERE id = ?')->execute([$cid, $cid]);
        out(['status' => 'success']);
    } catch (Exception $e) {
        out(['status' => 'error', 'message' => $e->getMessage()], 500);
    }
}

// DELETE COLLECTION
if ($action === 'delete' && $method === 'POST') {
    $uid = auth_uid($pdo);
    if (!$uid) out(['status' => 'error', 'message' => 'Unauthenticated'], 401);
    $cid = intval($_POST['collection_id'] ?? 0);
    if (!$cid) out(['status' => 'error', 'message' => 'collection_id required'], 400);
    $check = $pdo->prepare('SELECT id FROM collections WHERE id = ? AND user_id = ? LIMIT 1');
    $check->execute([$cid, $uid]);
    if (!$check->fetchColumn()) out(['status' => 'error', 'message' => 'Not found'], 404);
    $pdo->prepare('DELETE FROM collection_posts WHERE collection_id = ?')->execute([$cid]);
    $pdo->prepare('DELETE FROM collections WHERE id = ? AND user_id = ?')->execute([$cid, $uid]);
    out(['status' => 'success']);
}

out(['status' => 'error', 'message' => 'Unknown action'], 400);
