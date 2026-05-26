<?php
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Content-Type, Authorization');
header('Access-Control-Allow-Methods: GET, POST, DELETE, OPTIONS');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
  http_response_code(200);
  echo json_encode(['status' => 'success']);
  exit;
}

require_once __DIR__ . '/db_connect.php';
require_once __DIR__ . '/auth_middleware.php';
$config = require __DIR__ . '/../../config/config.php';

function out_json(int $code, array $payload): void
{
  http_response_code($code);
  echo json_encode($payload);
  exit;
}

function get_columns(PDO $pdo, string $table): array
{
  $cols = [];
  try {
    $stmt = $pdo->query("SHOW COLUMNS FROM `{$table}`");
    while ($r = $stmt->fetch(PDO::FETCH_ASSOC))
      $cols[] = $r['Field'];
  }
  catch (Exception $e) {
  }
  return $cols;
}

function pick_from(array $cols, array $cands): ?string
{
  foreach ($cands as $c)
    if (in_array($c, $cols, true))
      return $c;
  return null;
}

function norm_url(?string $url, string $baseUrl): ?string
{
  if ($url === null)
    return null;
  $url = trim((string)$url);
  if ($url === '')
    return '';
  if (preg_match('~^https?://~i', $url))
    return $url;
  $baseUrl = rtrim($baseUrl, '/');
  if ($url[0] === '/')
    return $baseUrl . $url;
  return $baseUrl . '/' . $url;
}

try {
  if (!isset($pdo) || !($pdo instanceof PDO)) {
    out_json(500, ['status' => 'error', 'message' => 'DB connection not available']);
  }

  // 🔧 Auto-migration: Ensure table exists
  $pdo->exec("CREATE TABLE IF NOT EXISTS `post_views` (
        `id` INT AUTO_INCREMENT PRIMARY KEY,
        `post_id` INT NOT NULL,
        `user_id` INT NULL,
        `ip_address` VARCHAR(45) NULL,
        `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        UNIQUE KEY `unique_post_view` (`post_id`, `user_id`, `ip_address`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;");

  // 🔒 Subscriber-only column
  try {
    $pdo->exec("ALTER TABLE posts ADD COLUMN subscriber_only TINYINT(1) NOT NULL DEFAULT 0");
  }
  catch (Throwable $e) {
  }

  $baseUrl = rtrim(($config['base_url'] ?? 'https://coinzop.com/ekloadmin/api/v1'), '/');

  $postsTbl = 'posts';
  $usersTbl = 'users';
  $likesTbl = 'post_likes';
  $commentsTbl = 'post_comments';
  $viewsTbl = 'post_views';

  // Check if user_subscriptions table exists
  $hasSubscriptionsTbl = false;
  try {
    $pdo->query("SELECT 1 FROM user_subscriptions LIMIT 1");
    $hasSubscriptionsTbl = true;
  }
  catch (Throwable $e) {
  }


  // columns
  $postsCols = get_columns($pdo, $postsTbl);
  $usersCols = get_columns($pdo, $usersTbl);

  $hasLikesTbl = false;
  $likesCols = [];
  try {
    $likesCols = get_columns($pdo, $likesTbl);
    $hasLikesTbl = true;
  }
  catch (Throwable $e) {
  }

  $hasCommentsTbl = false;
  try {
    get_columns($pdo, $commentsTbl);
    $hasCommentsTbl = true;
  }
  catch (Throwable $e) {
  }

  // posts schema
  $pId = pick_from($postsCols, ['id', 'post_id']);
  $pUserId = pick_from($postsCols, ['user_id', 'uid']);
  $pCaption = pick_from($postsCols, ['caption', 'text', 'content', 'description', 'body']);
  $pMedia = pick_from($postsCols, ['file_url', 'media_url', 'image', 'image_url', 'photo', 'file', 'video', 'url', 'media', 'path']);
  $pType = pick_from($postsCols, ['type', 'post_type', 'media_type']);
  $pCreated = pick_from($postsCols, ['created_at', 'created', 'date_created']);
  $pRepostOf = pick_from($postsCols, ['repost_of']);
  $pRepostCaption = pick_from($postsCols, ['repost_caption']);

  if (!$pId || !$pUserId || !$pMedia) {
    out_json(500, ['status' => 'error', 'message' => 'posts table missing required columns']);
  }

  $uId = pick_from($usersCols, ['id', 'user_id']);
  $uName = pick_from($usersCols, ['name', 'full_name', 'display_name']);
  $uUsername = pick_from($usersCols, ['username', 'user_name', 'handle']);
  $uAvatar = pick_from($usersCols, ['profile_pic', 'avatar', 'avatar_url', 'photo', 'image']);

  $lPostId = $hasLikesTbl ? pick_from($likesCols, ['post_id', 'pid']) : null;
  $lUserId = $hasLikesTbl ? pick_from($likesCols, ['user_id', 'uid']) : null;

  $reqPayload = json_decode(file_get_contents('php://input'), true) ?? [];

  /* =========================================================
   🗑️ DELETE: Remove a post
   ========================================================= */
  if ($_SERVER['REQUEST_METHOD'] === 'DELETE') {
    $viewer = requireUser($pdo);
    $postId = intval($_GET['id'] ?? $reqPayload['id'] ?? $reqPayload['post_id'] ?? 0);
    if ($postId <= 0)
      out_json(400, ['status' => 'error', 'message' => 'Post ID required']);

    // Check ownership
    $chk = $pdo->prepare("SELECT $pUserId FROM $postsTbl WHERE $pId = ? LIMIT 1");
    $chk->execute([$postId]);
    $p = $chk->fetch(PDO::FETCH_ASSOC);
    if (!$p)
      out_json(404, ['status' => 'error', 'message' => 'Post not found']);
    if (intval($p[$pUserId]) !== intval($viewer['id']))
      out_json(403, ['status' => 'error', 'message' => 'Unauthorized']);

    $pdo->prepare("DELETE FROM $postsTbl WHERE $pId = ?")->execute([$postId]);
    out_json(200, ['status' => 'success', 'message' => 'Post deleted']);
  }

  /* =========================================================
   ✅ POST: upload / view / etc
   ========================================================= */
  if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $action = $_POST['action'] ?? $reqPayload['action'] ?? 'upload';

    /* --- Action: Record View --- */
    if ($action === 'view') {
      $postId = intval($_POST['post_id'] ?? $reqPayload['post_id'] ?? 0);
      if ($postId <= 0)
        out_json(400, ['status' => 'error', 'message' => 'post_id required']);

      $viewerId = 0;
      try {
        $v = requireUser($pdo);
        $viewerId = intval($v['id']);
      }
      catch (Exception $e) {
      }
      $ip = $_SERVER['REMOTE_ADDR'] ?? null;

      // record unique view
      $stmt = $pdo->prepare("INSERT IGNORE INTO `post_views` (post_id, user_id, ip_address) VALUES (?, ?, ?)");
      $stmt->execute([$postId, $viewerId ?: null, $ip]);

      out_json(200, ['status' => 'success', 'message' => 'View recorded']);
    }

    /* --- Action: Upload --- */
    $viewer = requireUser($pdo);
    $userId = (int)$viewer['id'];

    $caption = trim((string)($_POST['caption'] ?? $reqPayload['caption'] ?? ''));
    $type = strtolower(trim((string)($_POST['type'] ?? $reqPayload['type'] ?? 'image')));
    if ($type === '')
      $type = 'image';

    $isTextPost = ($type === 'text');
    $hasFile = isset($_FILES['file']) && is_uploaded_file($_FILES['file']['tmp_name'] ?? '');

    if (!$hasFile && !$isTextPost) {
      out_json(400, ['status' => 'error', 'message' => 'No file uploaded.']);
    }

    $fileUrl = '';
    if ($hasFile) {
      $uploadDir = __DIR__ . '/uploads/';
      if (!is_dir($uploadDir))
        @mkdir($uploadDir, 0777, true);
      $origName = basename((string)$_FILES['file']['name']);
      $ext = pathinfo($origName, PATHINFO_EXTENSION);
      $fileName = uniqid('p_', true) . ($ext ? '.' . preg_replace('/[^a-zA-Z0-9]/', '', $ext) : '');
      if (move_uploaded_file($_FILES['file']['tmp_name'], $uploadDir . $fileName)) {
        $fileUrl = rtrim(($config['base_url'] ?? 'https://coinzop.com/ekloadmin'), '/') . "/api/v1/uploads/" . $fileName;
      }
    }

    $subscriberOnly = intval($_POST['subscriber_only'] ?? $reqPayload['subscriber_only'] ?? 0);

    $sql = "INSERT INTO $postsTbl ($pUserId, $pType, $pMedia, $pCaption, subscriber_only" . ($pCreated ? ", $pCreated" : "") . ") 
                VALUES (?, ?, ?, ?, ?" . ($pCreated ? ", NOW()" : "") . ")";
    $pdo->prepare($sql)->execute([$userId, $type, $fileUrl, $caption, $subscriberOnly]);
    $newId = $pdo->lastInsertId();

    out_json(200, ['status' => 'success', 'post_id' => $newId]);
  }

  /* =========================================================
   ✅ GET: Fetch Feed
   ========================================================= */
  $viewerId = intval($_GET['viewer_id'] ?? $_POST['viewer_id'] ?? $_GET['user_id'] ?? 0);
  $scope = strtolower(trim((string)($_GET['scope'] ?? $_POST['scope'] ?? '')));
  $filterUserId = intval($_GET['filter_user_id'] ?? $_POST['filter_user_id'] ?? 0);
  if ($filterUserId <= 0 && $scope === 'profile') {
    $filterUserId = intval($_GET['user_id'] ?? $_POST['user_id'] ?? 0);
  }
  $type = strtolower(trim((string)($_GET['type'] ?? $_POST['type'] ?? '')));
  $limit = max(1, min(500, intval($_GET['limit'] ?? $_POST['limit'] ?? 200)));
  $offset = max(0, intval($_GET['offset'] ?? $_POST['offset'] ?? 0));

  // Resolve viewer from token for subscription check
  $authViewerId = 0;
  try {
    $authViewer = requireUser($pdo);
    $authViewerId = (int)$authViewer['id'];
    if ($viewerId <= 0)
      $viewerId = $authViewerId;
  }
  catch (Throwable $e) {
  }

  // Columns
  $select = [
    "p.$pId AS id", "p.$pUserId AS user_id", ($pCaption ? "p.$pCaption AS caption" : "'' AS caption"),
    "p.$pMedia AS media", ($pType ? "p.$pType AS type" : "'' AS type"), ($pCreated ? "p.$pCreated AS created_at" : "'' AS created_at"),
    "COALESCE(lc.likes_count, 0) AS likes_count", "COALESCE(cc.comments_count, 0) AS comments_count",
    "COALESCE(vc.total_views, 0) AS views_total", "COALESCE(vcu.unique_views, 0) AS views_unique",
    "COALESCE(p.subscriber_only, 0) AS subscriber_only"
  ];

  // Add subscription check for gating (only if table exists)
  if ($authViewerId > 0 && $hasSubscriptionsTbl) {
    $select[] = "CASE WHEN p.subscriber_only = 1 AND p.$pUserId != $authViewerId AND sub_chk.id IS NULL THEN 1 ELSE 0 END AS is_locked";
    $select[] = "CASE WHEN sub_chk.id IS NOT NULL THEN 1 ELSE 0 END AS is_subscribed";
  }
  else {
    $select[] = "CASE WHEN p.subscriber_only = 1 THEN 1 ELSE 0 END AS is_locked";
    $select[] = "0 AS is_subscribed";
  }

  if ($pRepostOf) {
    $select[] = "p.$pRepostOf AS repost_of";
    $select[] = "op.$pUserId AS original_user_id";
    $select[] = ($uName ? "ou.$uName AS original_user_name" : "'' AS original_user_name");
    $select[] = ($uAvatar ? "ou.$uAvatar AS original_user_profile_pic" : "'' AS original_user_profile_pic");
  }
  if ($pRepostCaption)
    $select[] = "p.$pRepostCaption AS repost_caption";
  if ($uId) {
    $select[] = ($uName ? "u.$uName AS author_name" : "'' AS author_name");
    $select[] = ($uUsername ? "u.$uUsername AS author_username" : "'' AS author_username");
    $select[] = ($uAvatar ? "u.$uAvatar AS author_avatar" : "'' AS author_avatar");
  }
  $select[] = ($viewerId > 0) ? "CASE WHEN ul.user_id IS NULL THEN 0 ELSE 1 END AS is_liked" : "0 AS is_liked";
  if ($viewerId > 0) {
    $select[] = "CASE WHEN fl.follower_id IS NOT NULL THEN 1 ELSE 0 END AS is_following";
  }
  else {
    $select[] = "0 AS is_following";
  }

  $joins = [];
  if ($viewerId > 0) {
    $joins[] = "LEFT JOIN follows fl ON fl.follower_id = $viewerId AND fl.following_id = p.$pUserId";
  }
  if ($uId)
    $joins[] = "LEFT JOIN $usersTbl u ON u.$uId = p.$pUserId";
  if ($pRepostOf) {
    $joins[] = "LEFT JOIN $postsTbl op ON op.$pId = p.$pRepostOf";
    $joins[] = "LEFT JOIN $usersTbl ou ON ou.$uId = op.$pUserId";
  }
  if ($hasLikesTbl && $lPostId) {
    $joins[] = "LEFT JOIN (SELECT $lPostId AS post_id, COUNT(*) AS likes_count FROM $likesTbl GROUP BY $lPostId) lc ON lc.post_id = p.$pId";
  }
  if ($hasLikesTbl && $lPostId && $lUserId && $viewerId > 0) {
    $joins[] = "LEFT JOIN (SELECT $lPostId AS post_id, $lUserId AS user_id FROM $likesTbl WHERE $lUserId = $viewerId GROUP BY $lPostId) ul ON ul.post_id = p.$pId";
  }
  if ($hasCommentsTbl) {
    $joins[] = "LEFT JOIN (SELECT post_id, COUNT(*) AS comments_count FROM $commentsTbl GROUP BY post_id) cc ON cc.post_id = p.$pId";
  }

  // View Counts Joins
  $joins[] = "LEFT JOIN (SELECT post_id, COUNT(*) AS total_views FROM $viewsTbl GROUP BY post_id) vc ON vc.post_id = p.$pId";
  $joins[] = "LEFT JOIN (SELECT post_id, COUNT(DISTINCT COALESCE(CAST(ip_address AS CHAR), ''), COALESCE(CAST(user_id AS CHAR), '')) AS unique_views FROM $viewsTbl GROUP BY post_id) vcu ON vcu.post_id = p.$pId";

  // Subscription check join (only if table exists)
  if ($authViewerId > 0 && $hasSubscriptionsTbl) {
    $joins[] = "LEFT JOIN user_subscriptions sub_chk ON sub_chk.subscriber_id = $authViewerId AND sub_chk.creator_id = p.$pUserId AND sub_chk.status = 'active' AND sub_chk.expires_at > NOW()";
  }

  // WHERE
  $where = [];
  $params = [];
  if ($action === 'following_reels' && $viewerId > 0) {
    $where[] = "p.$pUserId IN (SELECT following_id FROM follows WHERE follower_id = ?)";
    $params[] = $viewerId;
  }
  if ($filterUserId > 0) {
    $where[] = "p.$pUserId = ?";
    $params[] = $filterUserId;
  }
  if ($type !== '' && $pType) {
    $t = strtolower($type);
    if ($t === 'photos' || $t === 'images')
      $t = 'image';
    if ($t === 'videos')
      $t = 'video';
    if (in_array($t, ['image', 'video', 'reel', 'text'])) {
      $where[] = "LOWER(p.$pType) = ?";
      $params[] = $t;
    }
  }

  $sql = "SELECT " . implode(", ", $select) . " FROM $postsTbl p " . implode(" ", $joins);
  if (!empty($where))
    $sql .= " WHERE " . implode(" AND ", $where);
  $sql .= " ORDER BY p.$pId DESC LIMIT $limit OFFSET $offset";

  $stmt = $pdo->prepare($sql);
  $stmt->execute($params);
  $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

  $posts = [];
  foreach ($rows as $r) {
    $id = (string)$r['id'];
    $media = norm_url($r['media'] ?? '', $baseUrl);
    $avatar = norm_url($r['author_avatar'] ?? '', $baseUrl);
    $oAvatar = norm_url($r['original_user_profile_pic'] ?? '', $baseUrl);
    $isLocked = intval($r['is_locked'] ?? 0);
    $subscriberOnly = intval($r['subscriber_only'] ?? 0);
    $isSubscribed = intval($r['is_subscribed'] ?? 0);

    // Strip media for locked posts
    $displayMedia = $isLocked ? '' : $media;

    $posts[] = [
      'id' => $id, 'post_id' => $id, 'user_id' => (string)$r['user_id'], 'uid' => (string)$r['user_id'],
      'caption' => (string)$r['caption'], 'text' => (string)$r['caption'], 'content' => (string)$r['caption'],
      'file_url' => $displayMedia, 'media_url' => $displayMedia, 'image_url' => $displayMedia, 'video' => $displayMedia,
      'type' => (string)$r['type'], 'post_type' => (string)$r['type'],
      'created_at' => (string)$r['created_at'],
      'likes_count' => intval($r['likes_count']), 'is_liked' => intval($r['is_liked']),
      'comments_count' => intval($r['comments_count']),
      'views_total' => intval($r['views_total']), 'views_unique' => intval($r['views_unique']),
      'view_count' => intval($r['views_total']),
      'author_name' => (string)($r['author_name'] ?? ''), 'author_username' => (string)($r['author_username'] ?? ''), 'author_avatar' => $avatar,
      'repost_of' => intval($r['repost_of'] ?? 0), 'is_repost' => (intval($r['repost_of'] ?? 0) > 0 ? 1 : 0),
      'original_user_id' => (string)($r['original_user_id'] ?? ''), 'original_user_name' => (string)($r['original_user_name'] ?? ''), 'original_avatar' => $oAvatar,
      'subscriber_only' => $subscriberOnly, 'is_locked' => $isLocked, 'is_subscribed' => $isSubscribed,
      'is_following' => intval($r['is_following'] ?? 0)
    ];
  }

  out_json(200, ['status' => 'success', 'posts' => $posts]);

}
catch (Throwable $e) {
  out_json(500, ['status' => 'error', 'message' => $e->getMessage()]);
}
