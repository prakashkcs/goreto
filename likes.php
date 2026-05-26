<?php
// likes.php — Toggle like on a post (hardened with security middleware)
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Content-Type, Authorization');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
  http_response_code(200);
  echo json_encode(['status' => 'success']);
  exit;
}

require_once __DIR__ . '/security.php';
require_once __DIR__ . '/db_connect.php';
require_once __DIR__ . '/auth_middleware.php';

try {
  $viewer = requireUser($pdo);
  $userId = (int) $viewer['id'];

  $action = $_GET['action'] ?? $_POST['action'] ?? 'toggle';

  // Rate-limit likes per user (60 likes/min per IP+user combo)
  sec_rate_limit('like', (string) $userId);

  // Auto-create post_likes table if missing
  $pdo->exec("
        CREATE TABLE IF NOT EXISTS post_likes (
            id INT AUTO_INCREMENT PRIMARY KEY,
            post_id INT NOT NULL,
            user_id INT NOT NULL,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            UNIQUE KEY unique_like (post_id, user_id),
            INDEX idx_post (post_id),
            INDEX idx_user (user_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ");

  if ($action === 'toggle') {
    $postId = (int) ($_POST['post_id'] ?? $_GET['post_id'] ?? 0);
    if ($postId <= 0) {
      http_response_code(400);
      echo json_encode(['status' => 'error', 'message' => 'post_id required']);
      exit;
    }

    // Check if already liked in DB (source of truth)
    $check = $pdo->prepare("SELECT id FROM post_likes WHERE post_id = ? AND user_id = ? LIMIT 1");
    $check->execute([$postId, $userId]);
    $existing = $check->fetch(PDO::FETCH_ASSOC);

    if ($existing) {
      // Unlike — clear the security lock too
      $pdo->prepare("DELETE FROM post_likes WHERE post_id = ? AND user_id = ?")->execute([$postId, $userId]);
      sec_clear_like($postId, (string) $userId);
      $liked = false;
    } else {
      // Anti-fake-like check: reject if the file-lock says already liked
      // (catches rapid-fire duplicate requests before DB write completes)
      if (!sec_check_like($postId, (string) $userId)) {
        // Already liked recently — return current state without double-counting
        $countStmt = $pdo->prepare("SELECT COUNT(*) AS cnt FROM post_likes WHERE post_id = ?");
        $countStmt->execute([$postId]);
        $countRow = $countStmt->fetch(PDO::FETCH_ASSOC);
        echo json_encode([
          'status' => 'success',
          'liked' => true,
          'count' => (int) ($countRow['cnt'] ?? 0),
        ]);
        exit;
      }

      // Like
      $pdo->prepare("INSERT IGNORE INTO post_likes (post_id, user_id) VALUES (?, ?)")->execute([$postId, $userId]);
      $liked = true;

      // Send notification to post owner (fire-and-forget)
      try {
        $ownerStmt = $pdo->prepare("SELECT user_id FROM posts WHERE id = ? LIMIT 1");
        $ownerStmt->execute([$postId]);
        $ownerRow = $ownerStmt->fetch(PDO::FETCH_ASSOC);
        $ownerId = (int) ($ownerRow['user_id'] ?? 0);

        if ($ownerId > 0 && $ownerId !== $userId) {
          $likerStmt = $pdo->prepare("SELECT name, full_name FROM users WHERE id = ? LIMIT 1");
          $likerStmt->execute([$userId]);
          $likerRow = $likerStmt->fetch(PDO::FETCH_ASSOC);
          $likerName = $likerRow['full_name'] ?? $likerRow['name'] ?? 'Someone';

          $pdo->prepare("
                        INSERT INTO notifications (user_id, from_user_id, type, message, is_read, created_at)
                        VALUES (?, ?, 'like', ?, 0, NOW())
                    ")->execute([$ownerId, $userId, "$likerName liked your post"]);
        }
      } catch (Throwable $e) {
        // Notification failure must not break the like response
      }
    }

    // Get updated count
    $countStmt = $pdo->prepare("SELECT COUNT(*) AS cnt FROM post_likes WHERE post_id = ?");
    $countStmt->execute([$postId]);
    $countRow = $countStmt->fetch(PDO::FETCH_ASSOC);
    $count = (int) ($countRow['cnt'] ?? 0);

    echo json_encode([
      'status' => 'success',
      'liked' => $liked,
      'count' => $count,
    ]);

  } elseif ($action === 'count') {
    $postId = (int) ($_GET['post_id'] ?? $_POST['post_id'] ?? 0);
    if ($postId <= 0) {
      http_response_code(400);
      echo json_encode(['status' => 'error', 'message' => 'post_id required']);
      exit;
    }
    $countStmt = $pdo->prepare("SELECT COUNT(*) AS cnt FROM post_likes WHERE post_id = ?");
    $countStmt->execute([$postId]);
    $countRow = $countStmt->fetch(PDO::FETCH_ASSOC);
    $isLikedStmt = $pdo->prepare("SELECT id FROM post_likes WHERE post_id = ? AND user_id = ? LIMIT 1");
    $isLikedStmt->execute([$postId, $userId]);
    echo json_encode([
      'status' => 'success',
      'count' => (int) ($countRow['cnt'] ?? 0),
      'liked' => (bool) $isLikedStmt->fetch(),
    ]);

  } else {
    http_response_code(400);
    echo json_encode(['status' => 'error', 'message' => 'Unknown action']);
  }

} catch (Throwable $e) {
  error_log('likes.php error: ' . $e->getMessage());
  http_response_code(500);
  echo json_encode(['status' => 'error', 'message' => 'Server error']);
}
