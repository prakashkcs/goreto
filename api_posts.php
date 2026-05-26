<?php
/**
 * api_posts.php — Create / list posts and reels
 *
 * POST  action=create   → upload a new post/reel
 * GET   action=feed     → paginated feed
 * GET   action=reels    → paginated reels
 * POST  action=delete   → delete own post
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
if (file_exists($_base . '/security.php')) {
  require_once $_base . '/security.php';
} else {
  // Stub sec_rate_limit if security.php is missing
  if (!function_exists('sec_rate_limit')) {
    function sec_rate_limit(string $action, string $key): void
    {
    }
  }
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
  out(500, ['status' => false, 'message' => 'DB not connected']);
}

$config = $config ?? [];
$baseUrl = rtrim($config['base_url'] ?? 'https://goreto.org/ekloadmin', '/');

// ── Ensure posts table has all required columns ───────────────────────────────
$existingCols = [];
foreach ($pdo->query("SHOW COLUMNS FROM posts")->fetchAll(PDO::FETCH_ASSOC) as $c) {
  $existingCols[] = $c['Field'];
}
$neededCols = [
  'sound_name' => "VARCHAR(255) NULL",
  'sound_id' => "INT NULL",
  'subscriber_only' => "TINYINT(1) NOT NULL DEFAULT 0",
  'hashtags' => "TEXT NULL",
  'mute_audio' => "TINYINT(1) NOT NULL DEFAULT 0",
];
foreach ($neededCols as $col => $def) {
  if (!in_array($col, $existingCols, true)) {
    try {
      $pdo->exec("ALTER TABLE posts ADD COLUMN `$col` $def");
    } catch (Throwable $_) {
    }
  }
}

$method = $_SERVER['REQUEST_METHOD'];
$payload = json_decode(file_get_contents('php://input'), true) ?? [];
$action = $_GET['action'] ?? $_POST['action'] ?? $payload['action'] ?? 'feed';

// ── GET: feed / reels ─────────────────────────────────────────────────────────
if ($method === 'GET') {
  $viewer = null;
  try {
    $viewer = requireUser($pdo);
  } catch (Throwable $_) {
  }
  $viewerId = $viewer ? (int) $viewer['id'] : 0;

  $limit = max(1, min(50, (int) ($_GET['limit'] ?? 20)));
  $offset = max(0, (int) ($_GET['offset'] ?? 0));
  $type = $_GET['type'] ?? 'feed';

  if ($action === 'reels' || $type === 'reels') {
    $stmt = $pdo->prepare("
            SELECT p.*, u.username, u.profile_pic, u.name AS display_name,
                   u.gender,
                   (SELECT COUNT(*) FROM likes l WHERE l.post_id = p.id) AS likes_count,
                   (SELECT COUNT(*) FROM comments c WHERE c.post_id = p.id) AS comments_count,
                   IF(? > 0, (SELECT COUNT(*) FROM likes l2 WHERE l2.post_id = p.id AND l2.user_id = ?), 0) AS is_liked
            FROM posts p
            JOIN users u ON u.id = p.user_id
            WHERE p.type IN ('reel','video')
              AND (p.subscriber_only = 0 OR p.user_id = ?)
            ORDER BY p.created_at DESC
            LIMIT $limit OFFSET $offset
        ");
    $stmt->execute([$viewerId, $viewerId, $viewerId]);
  } else {
    $stmt = $pdo->prepare("
            SELECT p.*, u.username, u.profile_pic, u.name AS display_name,
                   u.gender,
                   (SELECT COUNT(*) FROM likes l WHERE l.post_id = p.id) AS likes_count,
                   (SELECT COUNT(*) FROM comments c WHERE c.post_id = p.id) AS comments_count,
                   IF(? > 0, (SELECT COUNT(*) FROM likes l2 WHERE l2.post_id = p.id AND l2.user_id = ?), 0) AS is_liked
            FROM posts p
            JOIN users u ON u.id = p.user_id
            WHERE (p.subscriber_only = 0 OR p.user_id = ?)
            ORDER BY p.created_at DESC
            LIMIT $limit OFFSET $offset
        ");
    $stmt->execute([$viewerId, $viewerId, $viewerId]);
  }

  $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);
  $posts = array_map(fn($r) => format_post($r, $baseUrl), $rows);
  out(200, ['status' => true, 'posts' => $posts]);
}

// ── POST: create / delete ─────────────────────────────────────────────────────
if ($method === 'POST') {
  $viewer = requireUser($pdo);
  $userId = (int) $viewer['id'];

  // ── delete ────────────────────────────────────────────────────────────────
  if ($action === 'delete') {
    $postId = (int) ($payload['post_id'] ?? $_POST['post_id'] ?? 0);
    if ($postId <= 0)
      out(400, ['status' => false, 'message' => 'post_id required']);

    $chk = $pdo->prepare("SELECT id, file_url FROM posts WHERE id = ? AND user_id = ? LIMIT 1");
    $chk->execute([$postId, $userId]);
    $post = $chk->fetch(PDO::FETCH_ASSOC);
    if (!$post)
      out(403, ['status' => false, 'message' => 'Post not found or not yours']);

    // Delete physical file
    if (!empty($post['file_url'])) {
      $rel = str_replace($baseUrl . '/', '', $post['file_url']);
      $path = __DIR__ . '/' . ltrim($rel, '/');
      if (file_exists($path))
        @unlink($path);
    }

    $pdo->prepare("DELETE FROM posts WHERE id = ?")->execute([$postId]);
    out(200, ['status' => true, 'message' => 'Post deleted']);
  }

  // ── create ────────────────────────────────────────────────────────────────
  if ($action === 'create' || $action === 'upload' || !isset($_GET['action'])) {
    // Rate-limit uploads: 20 per minute per user
    sec_rate_limit('upload', (string) $userId);

    $caption = trim((string) ($_POST['caption'] ?? $payload['caption'] ?? ''));
    $type = strtolower(trim((string) ($_POST['type'] ?? $payload['type'] ?? 'photo')));
    // Normalize aliases to canonical DB values
    if ($type === 'reel')
      $type = 'video';
    if ($type === 'image')
      $type = 'photo';

    $hashtags = trim((string) ($_POST['hashtags'] ?? $payload['hashtags'] ?? ''));
    $soundName = trim((string) ($_POST['sound_name'] ?? $payload['sound_name'] ?? ''));
    $soundId = (int) ($_POST['sound_id'] ?? $payload['sound_id'] ?? 0);
    $subscriberOnly = (int) ($_POST['subscriber_only'] ?? $payload['subscriber_only'] ?? 0);
    $muteAudio = (int) ($_POST['mute_audio'] ?? $payload['mute_audio'] ?? 0);
    $bgStyle = trim((string) ($_POST['bg_style'] ?? $payload['bg_style'] ?? ''));

    // Validate type (after normalization)
    $allowedTypes = ['photo', 'video', 'text', 'audio'];
    if (!in_array($type, $allowedTypes, true)) {
      out(400, ['status' => false, 'message' => 'Invalid post type: ' . $type]);
    }

    $fileUrl = null;
    $thumbnailUrl = null;

    // Use web root for uploads so files are accessible via URL
    $webRoot = realpath(__DIR__);
    // If we're in api/v1/, go up two levels to web root
    if (basename(dirname($webRoot)) === 'api' || basename($webRoot) === 'v1') {
      $webRoot = dirname(dirname($webRoot));
    } elseif (basename($webRoot) === 'api') {
      $webRoot = dirname($webRoot);
    }
    $uploadDir = $webRoot . '/uploads/posts/';
    if (!is_dir($uploadDir)) {
      @mkdir($uploadDir, 0775, true);
      @chown($uploadDir, 'www-data');
    }

    // ── Helper: upload a single $_FILES slot ─────────────────────────────────
    $uploadSlot = function (string $slot, array $allowedExts) use ($uploadDir, $baseUrl, $userId): ?string {
      if (!isset($_FILES[$slot]) || $_FILES[$slot]['error'] === UPLOAD_ERR_NO_FILE) {
        return null;
      }
      if ($_FILES[$slot]['error'] !== UPLOAD_ERR_OK) {
        $uploadErrors = [
          UPLOAD_ERR_INI_SIZE => 'File exceeds server upload limit',
          UPLOAD_ERR_FORM_SIZE => 'File exceeds form upload limit',
          UPLOAD_ERR_PARTIAL => 'File was only partially uploaded',
          UPLOAD_ERR_NO_TMP_DIR => 'Missing temporary folder on server',
          UPLOAD_ERR_CANT_WRITE => 'Failed to write file to disk',
          UPLOAD_ERR_EXTENSION => 'Upload blocked by server extension',
        ];
        $code = $_FILES[$slot]['error'];
        out(500, ['status' => false, 'message' => $uploadErrors[$code] ?? "Upload error code $code"]);
      }
      $origName = basename($_FILES[$slot]['name']);
      $ext = strtolower(pathinfo($origName, PATHINFO_EXTENSION));
      if (!in_array($ext, $allowedExts, true)) {
        out(415, ['status' => false, 'message' => "File type not allowed for $slot: $ext"]);
      }
      $filename = $slot . '_' . $userId . '_' . uniqid('', true) . '.' . $ext;
      $destPath = $uploadDir . $filename;
      if (!move_uploaded_file($_FILES[$slot]['tmp_name'], $destPath)) {
        out(500, ['status' => false, 'message' => "Failed to save $slot file"]);
      }
      return $baseUrl . '/uploads/posts/' . $filename;
    };

    // Main media file
    $fileUrl = $uploadSlot('file', ['jpg', 'jpeg', 'png', 'gif', 'webp', 'mp4', 'mov', 'avi', 'webm', 'm4v', 'mp3', 'm4a', 'aac', 'wav']);

    // Optional thumbnail (for reels/videos — a JPEG/PNG cover frame)
    $thumbnailUrl = $uploadSlot('thumbnail', ['jpg', 'jpeg', 'png', 'webp']);

    // Text posts don't need a file
    if ($type !== 'text' && $fileUrl === null) {
      out(400, ['status' => false, 'message' => 'No file uploaded for post type: ' . $type]);
    }

    // Use UTC time so all timestamps are consistent
    $now = gmdate('Y-m-d H:i:s');

    // Ensure optional columns exist (safe migration — ignore if already present)
    foreach ([
      "ALTER TABLE posts ADD COLUMN updated_at DATETIME NULL",
      "ALTER TABLE posts ADD COLUMN thumbnail_url VARCHAR(512) NULL",
      "ALTER TABLE posts ADD COLUMN bg_style VARCHAR(50) NULL",
    ] as $_sql) {
      try {
        $pdo->exec($_sql);
      } catch (Throwable $_) {
      }
    }

    $ins = $pdo->prepare("
            INSERT INTO posts
                (user_id, caption, type, file_url, thumbnail_url, hashtags, sound_name, sound_id,
                 subscriber_only, mute_audio, bg_style, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ");
    $ins->execute([
      $userId,
      $caption,
      $type,
      $fileUrl,
      $thumbnailUrl,
      $hashtags,
      $soundName ?: null,
      $soundId > 0 ? $soundId : null,
      $subscriberOnly ? 1 : 0,
      $muteAudio ? 1 : 0,
      $bgStyle !== '' ? $bgStyle : null,
      $now,
      $now,
    ]);
    $postId = (int) $pdo->lastInsertId();

    // Record sound use if a sound was selected
    if ($soundId > 0) {
      try {
        $pdo->prepare("INSERT IGNORE INTO sound_uses (sound_id, post_id, user_id) VALUES (?, ?, ?)")
          ->execute([$soundId, $postId, $userId]);
        $pdo->prepare("UPDATE sounds SET use_count = use_count + 1 WHERE id = ?")
          ->execute([$soundId]);
      } catch (Throwable $_) {
      }
    }

    // Fetch the created post
    $s = $pdo->prepare("
            SELECT p.*, u.username, u.profile_pic, u.name AS display_name, u.gender
            FROM posts p JOIN users u ON u.id = p.user_id
            WHERE p.id = ?
        ");
    $s->execute([$postId]);
    $row = $s->fetch(PDO::FETCH_ASSOC);

    out(200, ['status' => true, 'message' => 'Post created', 'post' => format_post($row, $baseUrl)]);
  }

  out(400, ['status' => false, 'message' => 'Unknown action']);
}

out(405, ['status' => false, 'message' => 'Method not allowed']);

// ── Helpers ───────────────────────────────────────────────────────────────────

function format_post(array $r, string $baseUrl): array
{
  $pic = $r['profile_pic'] ?? '';
  if ($pic && !preg_match('~^https?://~i', $pic)) {
    $pic = $baseUrl . '/' . ltrim($pic, '/');
  }
  $fileUrl = $r['file_url'] ?? '';
  if ($fileUrl && !preg_match('~^https?://~i', $fileUrl)) {
    $fileUrl = $baseUrl . '/' . ltrim($fileUrl, '/');
  }
  return [
    'id' => (int) $r['id'],
    'user_id' => (int) $r['user_id'],
    'username' => (string) ($r['username'] ?? ''),
    'display_name' => (string) ($r['display_name'] ?? ''),
    'profile_pic' => $pic,
    'gender' => (string) ($r['gender'] ?? ''),
    'caption' => (string) ($r['caption'] ?? ''),
    'type' => (string) ($r['type'] ?? 'photo'),
    'file_url' => $fileUrl,
    'thumbnail_url' => isset($r['thumbnail_url']) && $r['thumbnail_url']
      ? (preg_match('~^https?://~i', $r['thumbnail_url'])
        ? $r['thumbnail_url']
        : $baseUrl . '/' . ltrim($r['thumbnail_url'], '/'))
      : '',
    'hashtags' => (string) ($r['hashtags'] ?? ''),
    'sound_name' => (string) ($r['sound_name'] ?? ''),
    'sound_id' => (int) ($r['sound_id'] ?? 0),
    'subscriber_only' => (int) ($r['subscriber_only'] ?? 0),
    'mute_audio' => (int) ($r['mute_audio'] ?? 0),
    'likes_count' => (int) ($r['likes_count'] ?? 0),
    'comments_count' => (int) ($r['comments_count'] ?? 0),
    'is_liked' => (int) ($r['is_liked'] ?? 0) === 1,
    // Return UTC ISO-8601 with Z suffix so Flutter DateTime.parse() treats it as UTC
    'created_at' => isset($r['created_at']) && $r['created_at']
      ? str_replace(' ', 'T', $r['created_at']) . 'Z'
      : '',
  ];

}
