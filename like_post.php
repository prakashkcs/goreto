<?php
// Legacy endpoint — forward to likes.php toggle action
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Content-Type, Authorization');
header('Access-Control-Allow-Methods: POST, OPTIONS');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }

require_once __DIR__ . '/db_connect.php';
require_once __DIR__ . '/auth_middleware.php';

function out_json(int $code, array $payload): void {
  http_response_code($code);
  echo json_encode($payload);
  exit;
}

$viewer = requireUser($pdo);
$userId = (int)$viewer['id'];

$in = json_decode(file_get_contents('php://input'), true) ?: [];
$postId = (int)($in['post_id'] ?? $_POST['post_id'] ?? 0);

if ($postId <= 0) out_json(400, ['status' => false, 'message' => 'post_id required']);

// Upsert like using INSERT IGNORE (toggle not needed for legacy caller)
try {
  $pdo->exec("CREATE TABLE IF NOT EXISTS post_likes (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    post_id BIGINT NOT NULL,
    user_id INT NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_like (post_id, user_id),
    KEY idx_post (post_id)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

  $pdo->prepare("INSERT IGNORE INTO post_likes (post_id, user_id) VALUES (?, ?)")
      ->execute([$postId, $userId]);

  // Update likes count on posts table
  try {
    $pdo->prepare("UPDATE posts SET likes_count = (SELECT COUNT(*) FROM post_likes WHERE post_id = ?) WHERE id = ?")
        ->execute([$postId, $postId]);
  } catch (Throwable $_) {}

  out_json(200, ['status' => true, 'message' => 'Liked']);
} catch (Throwable $e) {
  out_json(500, ['status' => false, 'message' => $e->getMessage()]);
}
