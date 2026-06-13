<?php
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }

require_once __DIR__ . '/db_connect.php';
require_once __DIR__ . '/auth_middleware.php';

if (!isset($pdo) || !($pdo instanceof PDO)) {
  echo json_encode(["status"=>"error","message"=>"Database connection failed"]);
  exit;
}

function ensure_user_settings_schema(PDO $pdo): void {
  $pdo->exec("CREATE TABLE IF NOT EXISTS user_settings (
    user_id INT NOT NULL PRIMARY KEY,
    privacy_profile_visible TINYINT(1) NOT NULL DEFAULT 1,
    privacy_show_online TINYINT(1) NOT NULL DEFAULT 1,
    privacy_allow_nearby TINYINT(1) NOT NULL DEFAULT 1,
    notif_push_enabled TINYINT(1) NOT NULL DEFAULT 1,
    notif_like_enabled TINYINT(1) NOT NULL DEFAULT 1,
    notif_comment_enabled TINYINT(1) NOT NULL DEFAULT 1,
    notif_follow_enabled TINYINT(1) NOT NULL DEFAULT 1,
    discovery_enabled TINYINT(1) NOT NULL DEFAULT 1,
    privacy_allow_find_id TINYINT(1) NOT NULL DEFAULT 0,
    privacy_allow_random_video_call TINYINT(1) NOT NULL DEFAULT 0,
    privacy_allow_repost TINYINT(1) NOT NULL DEFAULT 0,
    privacy_allow_unknown_inbox TINYINT(1) NOT NULL DEFAULT 1,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci");
}

function out(array $payload, int $code = 200): void {
  http_response_code($code);
  echo json_encode($payload);
  exit;
}

$me = requireUser($pdo);
$meId = (int)$me['id'];
ensure_user_settings_schema($pdo);

$action = $_GET['action'] ?? $_POST['action'] ?? 'profile';
if ($action !== 'profile' && $action !== 'repost') {
  out(["status"=>"error","message"=>"Invalid action"], 400);
}

$raw = file_get_contents("php://input");
$data = json_decode($raw, true);
if (!is_array($data)) $data = $_POST;

$postId = (int)($data['post_id'] ?? 0);
$shareCaption = trim((string)($data['caption'] ?? $data['repost_caption'] ?? ''));

if ($postId <= 0) out(["status"=>"error","message"=>"Missing post_id"], 400);

$origStmt = $pdo->prepare("SELECT id, user_id, type, file_url, caption FROM posts WHERE id = :id LIMIT 1");
$origStmt->execute([":id" => $postId]);
$orig = $origStmt->fetch(PDO::FETCH_ASSOC);

if (!$orig) out(["status"=>"error","message"=>"Original post not found"], 404);

$ownerId = (int)($orig['user_id'] ?? 0);
if ($ownerId > 0 && function_exists('is_blocked_between') && is_blocked_between($pdo, $meId, $ownerId)) {
  out(["status"=>"error","message"=>"You cannot repost this user"], 403);
}

// ENFORCE: allow repost (default ON — uses users table, COALESCE to 1)
if ($ownerId > 0 && $ownerId !== $meId) {
  $st = $pdo->prepare("SELECT COALESCE(privacy_allow_repost, 1) AS v FROM users WHERE id = ? LIMIT 1");
  $st->execute([$ownerId]);
  $allow = (int)($st->fetchColumn() ?? 1);
  if ($allow === 0) {
    out(["status" => "error", "code" => "repost_disabled", "message" => "This user does not allow reposts of their content"], 403);
  }
}

$origType = strtolower((string)($orig['type'] ?? ''));
$origFile = (string)($orig['file_url'] ?? '');
$origCaption = (string)($orig['caption'] ?? '');

if ($origType === 'photo') $origType = 'image'; // photo == image for reposts
if ($origType !== 'image' && $origType !== 'video') {
  out(["status"=>"error","message"=>"This post type cannot be shared"], 400);
}
if (trim($origFile) === '') {
  out(["status"=>"error","message"=>"Original post has no media"], 400);
}

$finalCaption = ($shareCaption !== '') ? $shareCaption : $origCaption;

$ins = $pdo->prepare("
  INSERT INTO posts (user_id, type, file_url, caption, created_at, repost_of, repost_caption)
  VALUES (:uid, :type, :file_url, :caption, NOW(), :repost_of, :repost_caption)
");
$ins->execute([
  ":uid" => $meId,
  ":type" => $origType,
  ":file_url" => $origFile,
  ":caption" => $finalCaption,
  ":repost_of" => $postId,
  ":repost_caption" => $shareCaption
]);

$newPostId = (int)$pdo->lastInsertId();

out([
  "status" => "success",
  "message" => "Shared successfully",
  "data" => [
    "new_post_id" => $newPostId,
    "repost_of" => $postId,
    "caption" => $finalCaption,
    "repost_caption" => $shareCaption
  ]
]);