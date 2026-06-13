<?php
// Increase upload limits for video/reel uploads
ini_set('upload_max_filesize', '500M');
ini_set('post_max_size', '500M');
ini_set('max_execution_time', '300');
ini_set('max_input_time', '300');
ini_set('memory_limit', '512M');

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
  } catch (Exception $e) {
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
  $url = trim((string) $url);
  if ($url === '')
    return '';

  // CDN Redirection for relative upload paths
  if (strpos($url, 'uploads/') !== false && !preg_match('~^https?://~i', $url)) {
    return 'https://goreto.org/ekloadmin/' . ltrim($url, '/');
  }

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
  } catch (Throwable $e) {
  }

  $baseUrl = rtrim(($config['base_url'] ?? 'https://goreto.org/ekloadmin/api/v1'), '/');

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
  } catch (Throwable $e) {
  }


  // columns
  $postsCols = get_columns($pdo, $postsTbl);
  $usersCols = get_columns($pdo, $usersTbl);

  $hasLikesTbl = false;
  $likesCols = [];
  try {
    $likesCols = get_columns($pdo, $likesTbl);
    $hasLikesTbl = true;
  } catch (Throwable $e) {
  }

  $hasCommentsTbl = false;
  try {
    get_columns($pdo, $commentsTbl);
    $hasCommentsTbl = true;
  } catch (Throwable $e) {
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
  $pThumbnail = in_array('thumbnail_url', $postsCols) ? 'thumbnail_url' : null;
  $pSoundName = in_array('sound_name', $postsCols) ? 'sound_name' : null;

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
    $action = $_POST['action'] ?? $_GET['action'] ?? $reqPayload['action'] ?? 'upload';

    /* --- Action: Record View --- */
    if ($action === 'view') {
      $postId = intval($_POST['post_id'] ?? $reqPayload['post_id'] ?? 0);
      if ($postId <= 0)
        out_json(400, ['status' => 'error', 'message' => 'post_id required']);

      $viewerId = 0;
      try {
        $v = requireUser($pdo);
        $viewerId = intval($v['id']);
      } catch (Exception $e) {
      }
      $ip = $_SERVER['REMOTE_ADDR'] ?? null;

      // record unique view
      $stmt = $pdo->prepare("INSERT IGNORE INTO `post_views` (post_id, user_id, ip_address) VALUES (?, ?, ?)");
      $stmt->execute([$postId, $viewerId ?: null, $ip]);

      out_json(200, ['status' => 'success', 'message' => 'View recorded']);
    }


    /* --- Action: Edit Caption --- */
    if ($action === 'edit') {
      $viewer = requireUser($pdo);
      $userId  = (int) $viewer['id'];
      $postId  = intval($_POST['post_id']  ?? $reqPayload['post_id']  ?? 0);
      $caption = trim((string)($_POST['caption'] ?? $reqPayload['caption'] ?? ''));
      if ($postId <= 0) out_json(400, ['status'=>'error','message'=>'post_id required']);

      $stmt = $pdo->prepare("UPDATE posts SET caption=?, updated_at=NOW() WHERE id=? AND user_id=?");
      $affected = $stmt->execute([$caption, $postId, $userId]) ? $stmt->rowCount() : 0;
      if ($affected === 0) out_json(403, ['status'=>'error','message'=>'Post not found or not yours']);
      out_json(200, ['status'=>'success','message'=>'Post updated']);
    }

    /* --- Action: Report Post --- */
    if ($action === 'report') {
      $viewer    = requireUser($pdo);
      $userId    = (int) $viewer['id'];
      $postId    = intval($_POST['post_id'] ?? $reqPayload['post_id'] ?? 0);
      $reason    = trim((string)($_POST['reason']  ?? $reqPayload['reason']  ?? ''));
      $details   = trim((string)($_POST['details'] ?? $reqPayload['details'] ?? ''));
      if ($postId <= 0) out_json(400, ['status'=>'error','message'=>'post_id required']);
      if ($reason === '') out_json(400, ['status'=>'error','message'=>'reason required']);

      try {
        $stmt = $pdo->prepare(
          "INSERT INTO post_reports (post_id, reporter_id, reason, details) VALUES (?,?,?,?)"
        );
        $stmt->execute([$postId, $userId, $reason, $details ?: null]);
      } catch (\PDOException $e) {
        if ($e->errorInfo[1] === 1062) {
          out_json(409, ['status'=>'error','message'=>'Already reported']);
        }
        throw $e;
      }
      // Auto-flag post if it gets 5+ reports
      $pdo->prepare(
        "UPDATE posts SET is_flagged=1 WHERE id=? AND (SELECT COUNT(*) FROM post_reports WHERE post_id=?)>=5"
      )->execute([$postId, $postId]);
      out_json(200, ['status'=>'success','message'=>'Report submitted']);
    }

    /* --- Action: Upload --- */
    $viewer = requireUser($pdo);
    $userId = (int) $viewer['id'];

    // Pause ALL uploads when a prior NSFW violation flagged this account,
    // until an admin gives them a chance.
    try {
      $ubSt = $pdo->prepare("SELECT COALESCE(upload_blocked,0) FROM users WHERE id = ?");
      $ubSt->execute([$userId]);
      if ((int)$ubSt->fetchColumn() === 1) {
        out_json(403, ['status' => 'error', 'error_code' => 'upload_blocked',
          'message' => 'Your uploads are paused due to a content-policy violation. An admin must review your account before you can post again.']);
      }
    } catch (Throwable $e) {}

    $caption = trim((string) ($_POST['caption'] ?? $reqPayload['caption'] ?? ''));
    $type = strtolower(trim((string) ($_POST['type'] ?? $reqPayload['type'] ?? 'image')));
    if ($type === '')
      $type = 'image';

    // Normalize 'reel' to 'video' for storage (reels are short videos)
    if ($type === 'reel')
      $type = 'video';

    $isTextPost = ($type === 'text');

    // Check for PHP upload errors first
    $fileError = null;
    $hasFile = false;
    if (isset($_FILES['file'])) {
      if ($_FILES['file']['error'] !== UPLOAD_ERR_OK) {
        $fileError = $_FILES['file']['error'];
        $errorMsg = 'File upload failed';
        switch ($fileError) {
          case UPLOAD_ERR_INI_SIZE:
          case UPLOAD_ERR_FORM_SIZE:
            $errorMsg = 'File too large. Max upload size: ' . ini_get('upload_max_filesize');
            break;
          case UPLOAD_ERR_PARTIAL:
            $errorMsg = 'File upload was interrupted.';
            break;
          case UPLOAD_ERR_NO_FILE:
            $errorMsg = 'No file was uploaded.';
            break;
          case UPLOAD_ERR_NO_TMP_DIR:
            $errorMsg = 'Server temp folder missing.';
            break;
          case UPLOAD_ERR_CANT_WRITE:
            $errorMsg = 'Failed to write file to disk.';
            break;
          case UPLOAD_ERR_EXTENSION:
            $errorMsg = 'File upload stopped by extension.';
            break;
        }
        out_json(400, ['status' => 'error', 'message' => $errorMsg, 'upload_error_code' => $fileError]);
      }
      $hasFile = is_uploaded_file($_FILES['file']['tmp_name'] ?? '');
    }

    if (!$hasFile && !$isTextPost) {
      out_json(400, ['status' => 'error', 'message' => 'No file uploaded.']);
    }

    $fileUrl = '';
    $thumbnailUrl = null;
    if ($hasFile) {
      $uploadDir = __DIR__ . '/uploads/posts/';
      if (!is_dir($uploadDir))
        @mkdir($uploadDir, 0755, true);
      if (!is_writable($uploadDir)) {
        out_json(500, ['status' => 'error', 'message' => 'Upload directory not writable: ' . $uploadDir]);
      }
      $origName = basename((string) $_FILES['file']['name']);
      $ext = strtolower(pathinfo($origName, PATHINFO_EXTENSION));
      $allowedExts = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'mp4', 'mov', 'avi', 'webm', 'm4v', 'mp3', 'm4a', 'aac', 'wav'];
      if (!in_array($ext, $allowedExts, true)) {
        out_json(415, ['status' => 'error', 'message' => "File type not allowed: $ext"]);
      }
      $fileName = 'file_' . $userId . '_' . uniqid('', true) . '.' . $ext;
      $localPath = $uploadDir . $fileName;
      if (!move_uploaded_file($_FILES['file']['tmp_name'], $localPath)) {
        out_json(500, ['status' => 'error', 'message' => 'Failed to save uploaded file to disk.']);
      }
      $fileUrl = $baseUrl . '/uploads/posts/' . $fileName;
      // ── NSFW scan: remove adult content + flag the uploader ──
      $nsfwImg = ['jpg','jpeg','png','gif','webp'];
      $nsfwVid = ['mp4','mov','avi','webm','m4v'];
      $nsfwKind = in_array($ext, $nsfwVid, true) ? 'video' : (in_array($ext, $nsfwImg, true) ? 'image' : '');
      if ($nsfwKind !== '') {
        $nch = curl_init('http://127.0.0.1:8000/scan/local');
        curl_setopt_array($nch, [
          CURLOPT_RETURNTRANSFER => true, CURLOPT_POST => true,
          CURLOPT_HTTPHEADER => ['Content-Type: application/json'],
          CURLOPT_POSTFIELDS => json_encode(['path' => $localPath, 'kind' => $nsfwKind]),
          CURLOPT_TIMEOUT => 35,
        ]);
        $nresp = curl_exec($nch);
        $ncode = curl_getinfo($nch, CURLINFO_HTTP_CODE);
        curl_close($nch);
        $nj = ($nresp !== false && $ncode === 200) ? json_decode($nresp, true) : null;
        if (is_array($nj) && ($nj['status'] ?? '') === 'rejected') {
          try {
            $pdo->prepare('INSERT INTO nsfw_violations (user_id, content_type, reason, details) VALUES (?,?,?,?)')
                ->execute([$userId, $nsfwKind, $nj['reason'] ?? 'nsfw', json_encode($nj['detections'] ?? [])]);
            $pdo->prepare('UPDATE users SET nsfw_strikes = nsfw_strikes + 1 WHERE id = ?')->execute([$userId]);
            $pdo->prepare('UPDATE users SET upload_blocked = 1 WHERE id = ?')->execute([$userId]);
          } catch (Throwable $e) {}
          @unlink($localPath);
          out_json(403, ['status' => 'error', 'error_code' => 'nsfw_rejected',
            'message' => 'Your upload was removed for violating our content policy. Repeated violations may lead to your account being banned.']);
        }
      }

      // Optional thumbnail upload
      if (isset($_FILES['thumbnail']) && $_FILES['thumbnail']['error'] === UPLOAD_ERR_OK) {
        $thumbOrig = basename((string) $_FILES['thumbnail']['name']);
        $thumbExt = strtolower(pathinfo($thumbOrig, PATHINFO_EXTENSION));
        $thumbAllowed = ['jpg', 'jpeg', 'png', 'webp'];
        if (in_array($thumbExt, $thumbAllowed, true)) {
          $thumbName = 'thumbnail_' . $userId . '_' . uniqid('', true) . '.' . $thumbExt;
          $thumbPath = $uploadDir . $thumbName;
          if (move_uploaded_file($_FILES['thumbnail']['tmp_name'], $thumbPath)) {
            $thumbnailUrl = $baseUrl . '/uploads/posts/' . $thumbName;
          }
        }
      }
    }

    $subscriberOnly = intval($_POST['subscriber_only'] ?? $reqPayload['subscriber_only'] ?? 0);
    $muteAudio = intval($_POST['mute_audio'] ?? $reqPayload['mute_audio'] ?? 0);
    $soundName = trim((string) ($_POST['sound_name'] ?? $reqPayload['sound_name'] ?? ''));
    $hashtags = trim((string) ($_POST['hashtags'] ?? $reqPayload['hashtags'] ?? ''));

    // Build dynamic INSERT with optional columns
    $insertCols = [$pUserId, $pType, $pMedia, $pCaption, 'subscriber_only'];
    $insertPlaceholders = ['?', '?', '?', '?', '?'];
    $insertParams = [$userId, $type, $fileUrl, $caption, $subscriberOnly];

    // Check for optional columns
    $optCols = get_columns($pdo, $postsTbl);
    if (in_array('mute_audio', $optCols)) {
      $insertCols[] = 'mute_audio';
      $insertPlaceholders[] = '?';
      $insertParams[] = $muteAudio;
    }
    if (in_array('sound_name', $optCols) && $soundName !== '') {
      $insertCols[] = 'sound_name';
      $insertPlaceholders[] = '?';
      $insertParams[] = $soundName;
    }
    if (in_array('hashtags', $optCols) && $hashtags !== '') {
      $insertCols[] = 'hashtags';
      $insertPlaceholders[] = '?';
      $insertParams[] = $hashtags;
    }
    if ($pCreated) {
      $insertCols[] = $pCreated;
      $insertPlaceholders[] = 'NOW()';
    }

    $sql = "INSERT INTO $postsTbl (" . implode(', ', $insertCols) . ") VALUES (" . implode(', ', $insertPlaceholders) . ")";
    $pdo->prepare($sql)->execute($insertParams);
    $newId = $pdo->lastInsertId();

    // Fetch the created post with user info for the response
    $fetchSql = "SELECT p.*, u.username, u.profile_pic, u.name AS display_name, u.gender 
                 FROM $postsTbl p 
                 JOIN $usersTbl u ON u.$uId = p.$pUserId 
                 WHERE p.$pId = ? 
                 LIMIT 1";
    $stmt = $pdo->prepare($fetchSql);
    $stmt->execute([$newId]);
    $postRow = $stmt->fetch(PDO::FETCH_ASSOC);

    if ($postRow) {
      // Format the post similar to api_posts.php
      $pic = $postRow['profile_pic'] ?? '';
      if ($pic && !preg_match('~^https?://~i', $pic)) {
        $pic = $baseUrl . '/' . ltrim($pic, '/');
      }
      $fUrl = $postRow[$pMedia] ?? '';
      if ($fUrl && !preg_match('~^https?://~i', $fUrl)) {
        $fUrl = $baseUrl . '/' . ltrim($fUrl, '/');
      }
      $postData = [
        'id' => (int) $postRow[$pId],
        'user_id' => (int) $postRow[$pUserId],
        'username' => (string) ($postRow['username'] ?? ''),
        'display_name' => (string) ($postRow['display_name'] ?? ''),
        'profile_pic' => $pic,
        'gender' => (string) ($postRow['gender'] ?? ''),
        'caption' => (string) ($postRow[$pCaption] ?? ''),
        'type' => (string) ($postRow[$pType] ?? 'image'),
        'file_url' => $fUrl,
        'hashtags' => (string) ($postRow['hashtags'] ?? ''),
        'sound_name' => (string) ($postRow['sound_name'] ?? ''),
        'subscriber_only' => (int) ($postRow['subscriber_only'] ?? 0),
        'mute_audio' => (int) ($postRow['mute_audio'] ?? 0),
        'likes_count' => 0,
        'comments_count' => 0,
        'is_liked' => false,
        'created_at' => isset($postRow[$pCreated]) && $postRow[$pCreated]
          ? str_replace(' ', 'T', $postRow[$pCreated]) . 'Z'
          : '',
      ];
      out_json(200, ['status' => 'success', 'success' => true, 'post' => $postData, 'post_id' => $newId]);
    } else {
      out_json(200, ['status' => 'success', 'success' => true, 'post_id' => $newId]);
    }
  }

  /* =========================================================
   ✅ GET: Fetch Feed
   ========================================================= */
  /* =========================================================
   GET single post by ID: ?action=get&post_id=X
   ========================================================= */
  {
    $reqAction = strtolower(trim((string)($_GET['action'] ?? '')));
    $reqPostId = intval($_GET['post_id'] ?? $_GET['id'] ?? 0);
    if ($reqAction === 'get' && $reqPostId > 0) {
      // Resolve viewer
      $vid = 0;
      try { $vr = requireUser($pdo); $vid = (int)$vr['id']; } catch(Throwable $_){}

      $stmt = $pdo->prepare("SELECT p.*, u.name AS author_name, u.username AS author_username, u.profile_pic AS author_avatar,
        COALESCE((SELECT COUNT(*) FROM likes WHERE post_id = p.id),0) AS likes_count,
        COALESCE((SELECT COUNT(*) FROM comments WHERE post_id = p.id),0) AS comments_count,
        COALESCE((SELECT COUNT(*) FROM post_views WHERE post_id = p.id),0) AS views_total,
        CASE WHEN (SELECT id FROM likes WHERE post_id = p.id AND user_id = ?) IS NOT NULL THEN 1 ELSE 0 END AS is_liked
        FROM posts p LEFT JOIN users u ON p.user_id = u.id WHERE p.id = ? LIMIT 1");
      $stmt->execute([$vid, $reqPostId]);
      $row = $stmt->fetch(PDO::FETCH_ASSOC);
      if (!$row) {
        out_json(404, ['status' => false, 'message' => 'Post not found']);
      }
      $media = $row['file_url'] ?? $row['media_url'] ?? $row['image_url'] ?? $row['video_url'] ?? '';
      $avatar = $row['author_avatar'] ?? '';
      if ($avatar && !str_starts_with($avatar,'http')) {
        $avatar = 'https://goreto.org/ekloadmin/' . ltrim($avatar,'/');
      }
      $post = [
        'id'           => (string)$row['id'],
        'post_id'      => (string)$row['id'],
        'user_id'      => (string)$row['user_id'],
        'caption'      => $row['caption'] ?? '',
        'file_url'     => $media,
        'media_url'    => $media,
        'image_url'    => $media,
        'video_url'    => $media,
        'thumbnail_url'=> $row['thumbnail_url'] ?? '',
        'type'         => $row['type'] ?? 'image',
        'post_type'    => $row['type'] ?? 'image',
        'created_at'   => $row['created_at'] ?? '',
        'likes_count'  => (int)$row['likes_count'],
        'comments_count'=> (int)$row['comments_count'],
        'views_total'  => (int)$row['views_total'],
        'is_liked'     => (int)$row['is_liked'],
        'author_name'  => $row['author_name'] ?? '',
        'author_username'=> $row['author_username'] ?? '',
        'author_avatar'=> $avatar,
      ];
      out_json(200, ['status' => true, 'post' => $post]);
    }
  }

  $action = strtolower(trim((string) ($_GET['action'] ?? $_POST['action'] ?? '')));
  $viewerId = intval($_GET['viewer_id'] ?? $_POST['viewer_id'] ?? 0);
  $scope = strtolower(trim((string) ($_GET['scope'] ?? $_POST['scope'] ?? '')));
  $filterUserId = intval($_GET['filter_user_id'] ?? $_POST['filter_user_id'] ?? 0);
  if ($filterUserId <= 0 && $scope === 'profile') {
    $filterUserId = intval($_GET['user_id'] ?? $_POST['user_id'] ?? 0);
  }
  $type = strtolower(trim((string) ($_GET['type'] ?? $_POST['type'] ?? '')));
  // Map action=reels / action=following_reels to type filter — always override type for reel actions
  if ($action === 'reels' || $action === 'following_reels') {

  // [reels_cache_patched]
  // Cache reels response for 60 s per (action + viewer) to avoid repeated heavy queries.
  static $_reels_cache = [];
  $_reels_cache_key = $action . ':' . ($viewerId ?? 0);
  $_reels_cache_ttl = 60;
  if (isset($_reels_cache[$_reels_cache_key]) && (time() - $_reels_cache[$_reels_cache_key]['ts']) < $_reels_cache_ttl) {
    out_json(200, ['status' => 'success', 'posts' => $_reels_cache[$_reels_cache_key]['data']]);
  }    $type = 'reel';
  }
  $limit = max(1, min(500, intval($_GET['limit'] ?? $_POST['limit'] ?? 200)));
  $offset = max(0, intval($_GET['offset'] ?? $_POST['offset'] ?? 0));
  $soundNameFilter = trim((string) ($_GET['sound_name'] ?? $_POST['sound_name'] ?? ''));

  // Resolve viewer from token for subscription check
  $authViewerId = 0;
  try {
    $authViewer = requireUser($pdo);
    $authViewerId = (int) $authViewer['id'];
    if ($viewerId <= 0)
      $viewerId = $authViewerId;
  } catch (Throwable $e) {
  }

  // Columns
  $select = [
    "p.$pId AS id",
    "p.$pUserId AS user_id",
    ($pCaption ? "p.$pCaption AS caption" : "'' AS caption"),
    "p.$pMedia AS media",
    ($pType ? "p.$pType AS type" : "'' AS type"),
    ($pCreated ? "p.$pCreated AS created_at" : "'' AS created_at"),
    "COALESCE(lc.likes_count, 0) AS likes_count",
    "COALESCE(cc.comments_count, 0) AS comments_count",
    "COALESCE(vc.total_views, 0) AS views_total",
    "COALESCE(vcu.unique_views, 0) AS views_unique",
    "COALESCE(p.subscriber_only, 0) AS subscriber_only"
  ];

  // Add subscription check for gating (only if table exists)
  if ($authViewerId > 0 && $hasSubscriptionsTbl) {
    $select[] = "CASE WHEN p.subscriber_only = 1 AND p.$pUserId != $authViewerId AND sub_chk.id IS NULL THEN 1 ELSE 0 END AS is_locked";
    $select[] = "CASE WHEN sub_chk.id IS NOT NULL THEN 1 ELSE 0 END AS is_subscribed";
  } else {
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
  if ($pThumbnail)
    $select[] = "p.$pThumbnail AS thumbnail_url";
  if ($pSoundName)
    $select[] = "p.$pSoundName AS sound_name";
  if ($uId) {
    $select[] = ($uName ? "u.$uName AS author_name" : "'' AS author_name");
    $select[] = ($uUsername ? "u.$uUsername AS author_username" : "'' AS author_username");
    $select[] = ($uAvatar ? "u.$uAvatar AS author_avatar" : "'' AS author_avatar");
  }
  $select[] = ($viewerId > 0) ? "CASE WHEN ul.user_id IS NULL THEN 0 ELSE 1 END AS is_liked" : "0 AS is_liked";
  if ($viewerId > 0) {
    $select[] = "CASE WHEN fl.follower_id IS NOT NULL THEN 1 ELSE 0 END AS is_following";
  } else {
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

  // 🔥 Global Block Filtering
  if ($authViewerId > 0) {
    $where[] = "p.$pUserId NOT IN (SELECT blocked_id FROM user_blocks WHERE blocker_id = ?)";
    $params[] = $authViewerId;
    $where[] = "p.$pUserId NOT IN (SELECT blocker_id FROM user_blocks WHERE blocked_id = ?)";
    $params[] = $authViewerId;
  }

  if ($action === 'following_reels' && $viewerId > 0) {
    $where[] = "p.$pUserId IN (SELECT following_id FROM follows WHERE follower_id = ?)";
    $params[] = $viewerId;
  }
  if ($filterUserId > 0) {
    $where[] = "p.$pUserId = ?";
    $params[] = $filterUserId;
  }
  if ($soundNameFilter !== '') {
    if ($pSoundName) {
      $where[] = "p.$pSoundName = ?";
      $params[] = $soundNameFilter;
    } else {
      $where[] = "1=0"; // sound_name column doesn't exist, return nothing
    }
  }
  if ($type !== '' && $pType) {
    $t = strtolower($type);
    if ($t === 'photos' || $t === 'images')
      $t = 'image';
    if ($t === 'videos')
      $t = 'video';
    // For reel actions, match both 'reel' and 'video' types since videos are reels
    if ($t === 'reel') {
      $where[] = "LOWER(p.$pType) IN ('reel', 'video')";
    } elseif (in_array($t, ['image', 'text'])) {
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
    $id = (string) $r['id'];
    $media = norm_url($r['media'] ?? '', $baseUrl);
    $avatar = norm_url($r['author_avatar'] ?? '', $baseUrl);
    $oAvatar = norm_url($r['original_user_profile_pic'] ?? '', $baseUrl);
    $isLocked = intval($r['is_locked'] ?? 0);
    $subscriberOnly = intval($r['subscriber_only'] ?? 0);
    $isSubscribed = intval($r['is_subscribed'] ?? 0);

    // Resolve thumbnail URL — keep empty if none set (client shows its own placeholder)
    $thumbRaw = trim((string) ($r['thumbnail_url'] ?? ''));
    $effectiveThumb = $thumbRaw !== '' ? norm_url($thumbRaw, $baseUrl) : '';

    // Allowed to send media so the app can apply its own blur effect
    $displayMedia = $media;

    $posts[] = [
      'id' => $id,
      'post_id' => $id,
      'user_id' => (string) $r['user_id'],
      'uid' => (string) $r['user_id'],
      'caption' => (string) $r['caption'],
      'text' => (string) $r['caption'],
      'content' => (string) $r['caption'],
      'file_url' => $displayMedia,
      'media_url' => $displayMedia,
      'image_url' => $displayMedia,
      'video' => $displayMedia,
      'thumbnail_url' => $effectiveThumb,
      'sound_name' => (string) ($r['sound_name'] ?? ''),
      'type' => (string) $r['type'],
      'post_type' => (string) $r['type'],
      'created_at' => (string) $r['created_at'],
      'likes_count' => intval($r['likes_count']),
      'is_liked' => intval($r['is_liked']),
      'comments_count' => intval($r['comments_count']),
      'views_total' => intval($r['views_total']),
      'views_unique' => intval($r['views_unique']),
      'view_count' => intval($r['views_total']),
      'author_name' => (string) ($r['author_name'] ?? ''),
      'author_username' => (string) ($r['author_username'] ?? ''),
      'author_avatar' => $avatar,
      'repost_of' => intval($r['repost_of'] ?? 0),
      'is_repost' => (intval($r['repost_of'] ?? 0) > 0 ? 1 : 0),
      'original_user_id' => (string) ($r['original_user_id'] ?? ''),
      'original_user_name' => (string) ($r['original_user_name'] ?? ''),
      'original_avatar' => $oAvatar,
      'subscriber_only' => $subscriberOnly,
      'is_locked' => $isLocked,
      'is_subscribed' => $isSubscribed,
      'is_following' => intval($r['is_following'] ?? 0)
    ];
  }

    // Store result in per-worker static cache.
  if (isset($_reels_cache_key)) { $_reels_cache[$_reels_cache_key] = ['data' => $posts, 'ts' => time()]; }
out_json(200, ['status' => 'success', 'posts' => $posts]);

} catch (Throwable $e) {
  out_json(500, ['status' => 'error', 'message' => $e->getMessage()]);
}
