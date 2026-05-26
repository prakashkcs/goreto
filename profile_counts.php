<?php
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Content-Type, Authorization');
header('Access-Control-Allow-Methods: GET, OPTIONS');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }

require_once __DIR__ . '/db_connect.php';

function out_json(int $code, array $payload): void {
  http_response_code($code);
  echo json_encode($payload);
  exit;
}

$userId = (int)($_GET['user_id'] ?? 0);
if ($userId <= 0) out_json(400, ['status' => false, 'message' => 'user_id required']);

// Count followers (others following this user)
$followersCount = 0;
$followingCount = 0;
try {
  $cols = array_column($pdo->query("SHOW COLUMNS FROM follows")->fetchAll(PDO::FETCH_ASSOC), 'Field');
  $followerId  = in_array('follower_id', $cols) ? 'follower_id' : (in_array('user_id', $cols) ? 'user_id' : null);
  $followingId = in_array('following_id', $cols) ? 'following_id' : (in_array('target_id', $cols) ? 'target_id' : null);

  if ($followerId && $followingId) {
    $st = $pdo->prepare("SELECT COUNT(*) FROM follows WHERE $followingId = ?");
    $st->execute([$userId]);
    $followersCount = (int)$st->fetchColumn();

    $st = $pdo->prepare("SELECT COUNT(*) FROM follows WHERE $followerId = ?");
    $st->execute([$userId]);
    $followingCount = (int)$st->fetchColumn();
  }
} catch (Throwable $_) {}

// Count posts
$postsCount = 0;
try {
  $postsCols = array_column($pdo->query("SHOW COLUMNS FROM posts")->fetchAll(PDO::FETCH_ASSOC), 'Field');
  $userCol   = in_array('user_id', $postsCols) ? 'user_id' : (in_array('author_id', $postsCols) ? 'author_id' : null);
  if ($userCol) {
    $st = $pdo->prepare("SELECT COUNT(*) FROM posts WHERE $userCol = ?");
    $st->execute([$userId]);
    $postsCount = (int)$st->fetchColumn();
  }
} catch (Throwable $_) {}

out_json(200, [
  'status'          => true,
  'followers_count' => $followersCount,
  'following_count' => $followingCount,
  'posts_count'     => $postsCount,
]);
