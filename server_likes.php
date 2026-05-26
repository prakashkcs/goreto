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

if ($action === 'toggle') {
  if (!isset($data->post_id)) {
    echo json_encode(["status" => "error", "message" => "Missing post_id"]);
    exit;
  }

  $postId = (int)$data->post_id;

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
  // optional: return is_liked for a post
  if (!isset($_GET["post_id"])) {
    echo json_encode(["status" => "error", "message" => "Missing post_id"]);
    exit;
  }
  $postId = (int)$_GET["post_id"];

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
