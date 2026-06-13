<?php
// likes.php
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
  http_response_code(200);
  exit;
}

include_once 'db_connect.php';
include_once 'auth_middleware.php';

// Get PDO ($pdo) from db_connect.php
if (!isset($pdo)) {
  $database = new Database();
  $pdo = $database->connect();
}

// Auto-create post_likes table if missing
try {
  $pdo->exec("CREATE TABLE IF NOT EXISTS `post_likes` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `post_id` INT NOT NULL,
    `user_id` INT NOT NULL,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY `unique_like` (`post_id`, `user_id`)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;");
}
catch (Throwable $e) {
}

// Ensure created_at column exists
try {
  $pdo->exec("ALTER TABLE `post_likes` ADD COLUMN `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP");
}
catch (Throwable $e) {
}

$user = requireUser($pdo);
$userId = (int)$user["id"];

$action = $_GET['action'] ?? $_POST['action'] ?? '';
$raw = file_get_contents("php://input");
$data = json_decode($raw);
if (!$data)
  $data = (object)[];

$postIdRaw = $data->post_id ?? $_POST['post_id'] ?? $_GET['post_id'] ?? null;
if ($action === 'toggle' || $action === 'status') {
  if (!$postIdRaw) {
    echo json_encode(["status" => "error", "message" => "Missing post_id"]);
    exit;
  }
}

if ($action === 'toggle') {
  $postId = (int)$postIdRaw;

  // Check if already liked
  $check = $pdo->prepare("SELECT id FROM post_likes WHERE post_id = :p AND user_id = :u LIMIT 1");
  $check->execute([":p" => $postId, ":u" => $userId]);
  $existing = $check->fetch(PDO::FETCH_ASSOC);

  if ($existing) {
    // Unlike
    $del = $pdo->prepare("DELETE FROM post_likes WHERE post_id = :p AND user_id = :u");
    $del->execute([":p" => $postId, ":u" => $userId]);
    $liked = false;
  }
  else {
    // Like (unique constraint prevents duplicates)
    $ins = $pdo->prepare("INSERT IGNORE INTO post_likes (post_id, user_id) VALUES (:p, :u)");
    $ins->execute([":p" => $postId, ":u" => $userId]);
    $liked = true;

    // Send Push Notification
    try {
      require_once __DIR__ . '/notification_helper.php';
      $uSt = $pdo->prepare('SELECT name FROM users WHERE id = ?');
      $uSt->execute([$userId]);
      $uname = $uSt->fetchColumn() ?: 'Somebody';

      $ownerSt = $pdo->prepare('SELECT user_id FROM posts WHERE id = ?');
      $ownerSt->execute([$postId]);
      $ownerId = $ownerSt->fetchColumn();

      if ($ownerId && (int)$ownerId !== $userId) {
        send_app_notification($pdo, $ownerId, $userId, 'like', 'Post Liked', "$uname liked your post.", $postId);
      }
    } catch (Throwable $ignore) {}
  }

  // Count likes
  $cnt = $pdo->prepare("SELECT COUNT(*) AS c FROM post_likes WHERE post_id = :p");
  $cnt->execute([":p" => $postId]);
  $likesCount = (int)$cnt->fetch(PDO::FETCH_ASSOC)["c"];

  echo json_encode([
    "status" => "success",
    "data" => [
      "post_id" => $postId,
      "liked" => $liked,
      "likes_count" => $likesCount
    ]
  ]);
  exit;
}

if ($action === 'status') {
  $postId = (int)$postIdRaw;

  $check = $pdo->prepare("SELECT id FROM post_likes WHERE post_id = :p AND user_id = :u LIMIT 1");
  $check->execute([":p" => $postId, ":u" => $userId]);
  $liked = $check->fetch() ? true : false;

  $cnt = $pdo->prepare("SELECT COUNT(*) AS c FROM post_likes WHERE post_id = :p");
  $cnt->execute([":p" => $postId]);
  $likesCount = (int)$cnt->fetch(PDO::FETCH_ASSOC)["c"];

  echo json_encode([
    "status" => "success",
    "data" => [
      "post_id" => $postId,
      "liked" => $liked,
      "likes_count" => $likesCount
    ]
  ]);
  exit;
}

http_response_code(400);
echo json_encode(["status" => "error", "message" => "Invalid action"]);
