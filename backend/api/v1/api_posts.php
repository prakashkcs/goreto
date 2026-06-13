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
  static $cache = [];
  if (isset($cache[$table])) return $cache[$table];
  $cols = [];
  try {
    $stmt = $pdo->query("SHOW COLUMNS FROM `{$table}`");
    while ($r = $stmt->fetch(PDO::FETCH_ASSOC))
      $cols[] = $r['Field'];
  } catch (Exception $e) {
  }
  $cache[$table] = $cols;
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
    return 'https://coinzop.com/ekloadmin/' . ltrim($url, '/');
  }

  if (preg_match('~^https?://~i', $url))
    return $url;
  $baseUrl = rtrim($baseUrl, '/');
  if ($url[0] === '/')
    return $baseUrl . $url;
  return $baseUrl . '/' . $url;
}

/**
 * Build a normalised post array from a raw DB row.
 * Used by all feed paths (trending, profile, personalised tiers).
 */
function build_post_row(array $r, string $baseUrl): array
{
  $id           = (string)($r['id'] ?? '');
  $media        = norm_url($r['media'] ?? '', $baseUrl);
  $avatar       = norm_url($r['author_avatar'] ?? '', $baseUrl);
  $oAvatar      = norm_url($r['original_user_profile_pic'] ?? '', $baseUrl);
  $isLocked     = (int)($r['is_locked'] ?? 0);
  $displayMedia = $isLocked ? '' : $media;

  return [
    'id'                               => $id,
    'post_id'                          => $id,
    'user_id'                          => (string)($r['user_id'] ?? ''),
    'uid'                              => (string)($r['user_id'] ?? ''),
    'caption'                          => (string)($r['caption'] ?? ''),
    'text'                             => (string)($r['caption'] ?? ''),
    'content'                          => (string)($r['caption'] ?? ''),
    'file_url'                         => $displayMedia,
    'media_url'                        => $displayMedia,
    'image_url'                        => $displayMedia,
    'video'                            => $displayMedia,
    'type'                             => (string)($r['type'] ?? ''),
    'post_type'                        => (string)($r['type'] ?? ''),
    'created_at'                       => (string)($r['created_at'] ?? ''),
    'likes_count'                      => (int)($r['likes_count'] ?? 0),
    'is_liked'                         => (int)($r['is_liked'] ?? 0),
    'comments_count'                   => (int)($r['comments_count'] ?? 0),
    'views_total'                      => (int)($r['views_total'] ?? 0),
    'views_unique'                     => (int)($r['views_unique'] ?? 0),
    'view_count'                       => (int)($r['views_total'] ?? 0),
    'author_name'                      => (string)($r['author_name'] ?? ''),
    'author_username'                  => (string)($r['author_username'] ?? ''),
    'author_avatar'                    => (string)$avatar,
    'author_subscription_status'       => (string)($r['author_subscription_status'] ?? 'inactive'),
    'repost_of'                        => (int)($r['repost_of'] ?? 0),
    'is_repost'                        => ((int)($r['repost_of'] ?? 0) > 0 ? 1 : 0),
    'original_user_id'                 => (string)($r['original_user_id'] ?? ''),
    'original_user_name'               => (string)($r['original_user_name'] ?? ''),
    'original_avatar'                  => (string)$oAvatar,
    'original_user_subscription_status'=> (string)($r['original_user_subscription_status'] ?? 'active'),
    'subscriber_only'                  => (int)($r['subscriber_only'] ?? 0),
    'is_locked'                        => $isLocked,
    'is_subscribed'                    => (int)($r['is_subscribed'] ?? 0),
    'is_following'                     => (int)($r['is_following'] ?? 0),
    'viral_score'                      => round((float)($r['viral_score'] ?? 0), 4),
    'is_viral'                         => (int)($r['is_viral'] ?? 0),
    'velocity_1h'                      => round((float)($r['velocity_1h'] ?? 1.0), 4),
  ];
}

try {
  if (!isset($pdo) || !($pdo instanceof PDO)) {
    out_json(500, ['status' => 'error', 'message' => 'DB connection not available']);
  }

  // 🔧 Auto-migration: Ensure tables exist
  static $schema_done = false;
  if (!$schema_done) {
  $schema_done = true;
  $pdo->exec("CREATE TABLE IF NOT EXISTS `post_views` (
        `id` INT AUTO_INCREMENT PRIMARY KEY,
        `post_id` INT NOT NULL,
        `user_id` INT NULL,
        `ip_address` VARCHAR(45) NULL,
        `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        UNIQUE KEY `unique_post_view` (`post_id`, `user_id`, `ip_address`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;");

  // Engagement signals table for algorithm (watch time, skips, shares)
  $pdo->exec("CREATE TABLE IF NOT EXISTS `post_engagements` (
        `id` INT AUTO_INCREMENT PRIMARY KEY,
        `post_id` INT NOT NULL,
        `user_id` INT NOT NULL,
        `action` ENUM('watch','skip','share','save') NOT NULL DEFAULT 'watch',
        `watch_seconds` INT NOT NULL DEFAULT 0,
        `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        UNIQUE KEY `unique_engagement` (`post_id`, `user_id`, `action`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;");

  // Trending scores table (updated periodically by algorithm)
  $pdo->exec("CREATE TABLE IF NOT EXISTS `post_trending_scores` (
        `post_id` INT PRIMARY KEY,
        `score` FLOAT NOT NULL DEFAULT 0,
        `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;");

  // 🔒 Subscriber-only column
  try {
    $pdo->exec("ALTER TABLE posts ADD COLUMN subscriber_only TINYINT(1) NOT NULL DEFAULT 0");
  } catch (Throwable $e) {
  }

  } // end $schema_done
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
      } catch (Exception $e) {
      }
      $ip = $_SERVER['REMOTE_ADDR'] ?? null;

      // record unique view
      $stmt = $pdo->prepare("INSERT IGNORE INTO `post_views` (post_id, user_id, ip_address) VALUES (?, ?, ?)");
      $stmt->execute([$postId, $viewerId ?: null, $ip]);

      out_json(200, ['status' => 'success', 'message' => 'View recorded']);
    }

    /* --- Action: Record Engagement (watch time / skip / share / save) --- */
    if ($action === 'engage') {
      $postId = intval($_POST['post_id'] ?? $reqPayload['post_id'] ?? 0);
      $engAction = $_POST['engage_action'] ?? $reqPayload['engage_action'] ?? 'watch';
      $watchSecs = intval($_POST['watch_seconds'] ?? $reqPayload['watch_seconds'] ?? 0);
      if ($postId <= 0)
        out_json(400, ['status' => 'error', 'message' => 'post_id required']);

      $engViewer = 0;
      try {
        $ev = requireUser($pdo);
        $engViewer = intval($ev['id']);
      } catch (Exception $e) {
      }
      if ($engViewer <= 0)
        out_json(401, ['status' => 'error', 'message' => 'Auth required']);

      $validActions = ['watch', 'skip', 'share', 'save'];
      if (!in_array($engAction, $validActions))
        $engAction = 'watch';

      $pdo->prepare("INSERT INTO post_engagements (post_id, user_id, action, watch_seconds)
          VALUES (?, ?, ?, ?)
          ON DUPLICATE KEY UPDATE watch_seconds = GREATEST(watch_seconds, VALUES(watch_seconds)), updated_at = NOW()")
        ->execute([$postId, $engViewer, $engAction, $watchSecs]);

      // Recompute trending score for this post
      $scoreStmt = $pdo->prepare("
        SELECT
          COALESCE(lc.likes_count, 0) AS likes,
          COALESCE(cc.comments_count, 0) AS comments,
          COALESCE(vc.views, 0) AS views,
          COALESCE(wt.avg_watch, 0) AS avg_watch,
          COALESCE(sk.skip_rate, 0) AS skip_rate,
          TIMESTAMPDIFF(HOUR, p.created_at, NOW()) AS age_hours
        FROM posts p
        LEFT JOIN (SELECT post_id, COUNT(*) AS likes_count FROM post_likes GROUP BY post_id) lc ON lc.post_id = p.id
        LEFT JOIN (SELECT post_id, COUNT(*) AS comments_count FROM post_comments GROUP BY post_id) cc ON cc.post_id = p.id
        LEFT JOIN (SELECT post_id, COUNT(*) AS views FROM post_views GROUP BY post_id) vc ON vc.post_id = p.id
        LEFT JOIN (SELECT post_id, AVG(watch_seconds) AS avg_watch FROM post_engagements WHERE action='watch' GROUP BY post_id) wt ON wt.post_id = p.id
        LEFT JOIN (SELECT post_id, COUNT(*)*1.0/(COUNT(*)+1) AS skip_rate FROM post_engagements WHERE action='skip' GROUP BY post_id) sk ON sk.post_id = p.id
        WHERE p.id = ?
      ");
      $scoreStmt->execute([$postId]);
      $sd = $scoreStmt->fetch(PDO::FETCH_ASSOC);
      if ($sd) {
        $ageHours = max(1, floatval($sd['age_hours']));
        $likes = floatval($sd['likes']);
        $comments = floatval($sd['comments']);
        $views = max(1, floatval($sd['views']));
        $avgWatch = floatval($sd['avg_watch']);
        $skipRate = floatval($sd['skip_rate']);

        // TikTok-style Wilson score + time decay
        $engagementRate = ($likes * 2 + $comments * 3 + $avgWatch * 0.5) / $views;
        $timeDecay = 1.0 / pow($ageHours + 2, 1.5);
        $score = ($engagementRate * (1 - $skipRate * 0.5)) * $timeDecay * 1000;

        $pdo->prepare("INSERT INTO post_trending_scores (post_id, score) VALUES (?, ?)
            ON DUPLICATE KEY UPDATE score = ?, updated_at = NOW()")
          ->execute([$postId, $score, $score]);
      }

      
      if ($engAction === 'share') {
          try {
              require_once __DIR__ . '/notification_helper.php';
              $ownerSt = $pdo->prepare("SELECT user_id FROM posts WHERE id = ?");
              $ownerSt->execute([$postId]);
              $ownerId = (int) $ownerSt->fetchColumn();
              if ($ownerId > 0 && $ownerId !== $engViewer) {
                  $uSt = $pdo->prepare("SELECT name, username FROM users WHERE id = ?");
                  $uSt->execute([$engViewer]);
                  $u = $uSt->fetch(PDO::FETCH_ASSOC) ?: [];
                  $uname = $u['name'] ?: ($u['username'] ?? 'Someone');
                  send_app_notification($pdo, $ownerId, $engViewer, 'share', 'Post Shared', "$uname shared your post.", $postId);
              }
          } catch (Throwable $e) { /* ignore share notification failures */ }
      }
      out_json(200, ['status' => 'success', 'message' => 'Engagement recorded']);
    }

    /* --- Action: Report Sound --- */
    if ($action === 'report_sound') {
      try {
        $viewer = requireUser($pdo);
        $userId = (int) $viewer['id'];
        $postId = intval($_POST['post_id'] ?? $reqPayload['post_id'] ?? 0);
        $reason = trim((string) ($_POST['reason'] ?? $reqPayload['reason'] ?? ''));
        $details = trim((string) ($_POST['details'] ?? $reqPayload['details'] ?? ''));
        $soundName = trim((string) ($_POST['sound_name'] ?? $reqPayload['sound_name'] ?? ''));

        if ($postId <= 0 || $reason === '') {
          out_json(400, ['status' => 'error', 'message' => 'post_id and reason are required']);
        }

        $pdo->exec("CREATE TABLE IF NOT EXISTS sound_reports (
          id INT AUTO_INCREMENT PRIMARY KEY,
          reporter_id INT NOT NULL,
          post_id INT NOT NULL,
          post_user_id INT NULL,
          sound_name VARCHAR(255) DEFAULT '',
          reason VARCHAR(120) NOT NULL,
          details TEXT NULL,
          status ENUM('pending','reviewed','resolved','dismissed') NOT NULL DEFAULT 'pending',
          admin_notes TEXT NULL,
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
          updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
          INDEX idx_sound_reports_status (status),
          INDEX idx_sound_reports_post_id (post_id),
          INDEX idx_sound_reports_reporter_id (reporter_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

        try {
          $soundReportCols = get_columns($pdo, 'sound_reports');
          if (!in_array('post_user_id', $soundReportCols, true)) {
            $pdo->exec("ALTER TABLE sound_reports ADD COLUMN post_user_id INT NULL AFTER post_id");
          }
          if (!in_array('sound_name', $soundReportCols, true)) {
            $pdo->exec("ALTER TABLE sound_reports ADD COLUMN sound_name VARCHAR(255) DEFAULT '' AFTER post_user_id");
          }
          if (!in_array('reason', $soundReportCols, true)) {
            $pdo->exec("ALTER TABLE sound_reports ADD COLUMN reason VARCHAR(120) NOT NULL DEFAULT 'Other' AFTER sound_name");
          }
          if (!in_array('details', $soundReportCols, true)) {
            $pdo->exec("ALTER TABLE sound_reports ADD COLUMN details TEXT NULL AFTER reason");
          }
          if (!in_array('status', $soundReportCols, true)) {
            $pdo->exec("ALTER TABLE sound_reports ADD COLUMN status ENUM('pending','reviewed','resolved','dismissed') NOT NULL DEFAULT 'pending' AFTER details");
          }
          if (!in_array('admin_notes', $soundReportCols, true)) {
            $pdo->exec("ALTER TABLE sound_reports ADD COLUMN admin_notes TEXT NULL AFTER status");
          }
          if (!in_array('created_at', $soundReportCols, true)) {
            $pdo->exec("ALTER TABLE sound_reports ADD COLUMN created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP AFTER admin_notes");
          }
          if (!in_array('updated_at', $soundReportCols, true)) {
            $pdo->exec("ALTER TABLE sound_reports ADD COLUMN updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP AFTER created_at");
          }
        } catch (Throwable $e) {
        }

        $postLookup = $pdo->prepare("SELECT $pUserId AS owner_id, " . ($pCaption ? "$pCaption AS caption" : "'' AS caption") . " FROM $postsTbl WHERE $pId = ? LIMIT 1");
        $postLookup->execute([$postId]);
        $postRow = $postLookup->fetch(PDO::FETCH_ASSOC);
        if (!$postRow) {
          out_json(404, ['status' => 'error', 'message' => 'Post not found']);
        }

        if ($soundName === '') {
          $soundName = trim((string) ($postRow['caption'] ?? ''));
        }

        $dupSt = $pdo->prepare("SELECT id FROM sound_reports WHERE reporter_id = ? AND post_id = ? AND created_at > DATE_SUB(NOW(), INTERVAL 24 HOUR) LIMIT 1");
        $dupSt->execute([$userId, $postId]);
        if ($dupSt->fetch(PDO::FETCH_ASSOC)) {
          out_json(200, ['status' => 'success', 'message' => 'Sound already reported recently']);
        }

        $ins = $pdo->prepare("INSERT INTO sound_reports (reporter_id, post_id, post_user_id, sound_name, reason, details) VALUES (?, ?, ?, ?, ?, ?)");
        $ins->execute([
          $userId,
          $postId,
          isset($postRow['owner_id']) ? intval($postRow['owner_id']) : null,
          $soundName,
          $reason,
          $details !== '' ? $details : null,
        ]);

        out_json(200, ['status' => 'success', 'message' => 'Sound report submitted']);
      } catch (Throwable $e) {
        out_json(500, ['status' => 'error', 'message' => 'Failed to submit sound report']);
      }
    }

    /* --- Action: Upload --- */
    $viewer = requireUser($pdo);
    $userId = (int) $viewer['id'];

    $caption = trim((string) ($_POST['caption'] ?? $reqPayload['caption'] ?? ''));
    $type = strtolower(trim((string) ($_POST['type'] ?? $reqPayload['type'] ?? 'image')));
    if ($type === '')
      $type = 'image';

    $isTextPost = ($type === 'text');
    $hasFile = isset($_FILES['file']) && is_uploaded_file($_FILES['file']['tmp_name'] ?? '');

    if (!$hasFile && !$isTextPost) {
      out_json(400, ['status' => 'error', 'message' => 'No file uploaded.']);
    }

    $fileUrl       = '';
    $savedFilePath = '';
    if ($hasFile) {
      $uploadDir = __DIR__ . '/uploads/';
      if (!is_dir($uploadDir))
        @mkdir($uploadDir, 0777, true);
      $origName = basename((string) $_FILES['file']['name']);
      $ext = pathinfo($origName, PATHINFO_EXTENSION);
      $fileName = uniqid('p_', true) . ($ext ? '.' . preg_replace('/[^a-zA-Z0-9]/', '', $ext) : '');
      $savedFilePath = $uploadDir . $fileName;
      if (move_uploaded_file($_FILES['file']['tmp_name'], $savedFilePath)) {
        $fileUrl = rtrim(($config['base_url'] ?? 'https://coinzop.com/ekloadmin'), '/') . "/api/v1/uploads/" . $fileName;
      }
    }

    // ── Content moderation ───────────────────────────────────────────────────
    if ($savedFilePath !== '' && file_exists($savedFilePath)) {
      require_once __DIR__ . '/content_moderation.php';
      $cmSettings = cm_load_settings($pdo);
      $cmResult   = cm_moderate($savedFilePath, $type, $cmSettings);
      cm_log($pdo, $cmResult, $userId, null, $savedFilePath);
      if (($cmResult['safe'] ?? true) === false) {
        @unlink($savedFilePath);
        out_json(422, [
          'status'  => 'error',
          'message' => $cmResult['reason'] ?? 'Content violates community guidelines',
          'blocked' => true,
        ]);
      }
    }

    // ── NSFW scan (NudeNet): remove adult content + flag the uploader ──
    if ($savedFilePath !== '' && file_exists($savedFilePath)) {
      $nsfwImg = ['jpg','jpeg','png','gif','webp'];
      $nsfwVid = ['mp4','mov','avi','webm','m4v'];
      $nsfwExtL = strtolower($ext ?? '');
      $nsfwKind = in_array($nsfwExtL, $nsfwVid, true) ? 'video' : (in_array($nsfwExtL, $nsfwImg, true) ? 'image' : '');
      if ($nsfwKind !== '') {
        $nch = curl_init('http://127.0.0.1:8000/scan/local');
        curl_setopt_array($nch, [
          CURLOPT_RETURNTRANSFER => true, CURLOPT_POST => true,
          CURLOPT_HTTPHEADER => ['Content-Type: application/json'],
          CURLOPT_POSTFIELDS => json_encode(['path' => $savedFilePath, 'kind' => $nsfwKind]),
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
          } catch (Throwable $e) {}
          @unlink($savedFilePath);
          out_json(403, ['status' => 'error', 'error_code' => 'nsfw_rejected',
            'message' => 'Your upload was removed for violating our content policy. Repeated violations may lead to your account being banned.']);
        }
      }
    }

    $subscriberOnly = intval($_POST['subscriber_only'] ?? $reqPayload['subscriber_only'] ?? 0);

    $sql = "INSERT INTO $postsTbl ($pUserId, $pType, $pMedia, $pCaption, subscriber_only" . ($pCreated ? ", $pCreated" : "") . ")
                VALUES (?, ?, ?, ?, ?" . ($pCreated ? ", NOW()" : "") . ")";
    $pdo->prepare($sql)->execute([$userId, $type, $fileUrl, $caption, $subscriberOnly]);
    $newId = $pdo->lastInsertId();

    // Attach a custom sound to the post (if one was chosen).
    $soundIdIn = (int)($_POST['sound_id'] ?? ($reqPayload['sound_id'] ?? 0));
    if ($soundIdIn > 0) {
      try { $pdo->prepare("UPDATE $postsTbl SET sound_id = ? WHERE id = ?")->execute([$soundIdIn, $newId]); } catch (Throwable $e) {}
    }

    // Update moderation log with the new post ID
    if ($savedFilePath !== '') {
      try {
        $pdo->prepare("UPDATE moderation_log SET post_id=? WHERE post_id IS NULL AND user_id=? ORDER BY id DESC LIMIT 1")
            ->execute([$newId, $userId]);
      } catch (Throwable $e) {}
    }

    
    if (!empty($repostOf) && (int) $repostOf > 0) {
        try {
            require_once __DIR__ . '/notification_helper.php';
            $oSt = $pdo->prepare("SELECT user_id FROM posts WHERE id = ?");
            $oSt->execute([(int) $repostOf]);
            $origOwner = (int) $oSt->fetchColumn();
            if ($origOwner > 0 && $origOwner !== $pUserId) {
                $uSt = $pdo->prepare("SELECT name, username FROM users WHERE id = ?");
                $uSt->execute([$pUserId]);
                $u = $uSt->fetch(PDO::FETCH_ASSOC) ?: [];
                $uname = $u['name'] ?: ($u['username'] ?? 'Someone');
                send_app_notification($pdo, $origOwner, $pUserId, 'repost', 'Post Reposted', "$uname reposted your post.", (int) $repostOf);
            }
        } catch (Throwable $e) { /* ignore repost notification failures */ }
    }
    out_json(200, ['status' => 'success', 'post_id' => $newId]);
  }

  /* =========================================================
   ✅ GET: Fetch Feed
   ========================================================= */
  $viewerId = intval($_GET['viewer_id'] ?? $_POST['viewer_id'] ?? 0);
  $scope = strtolower(trim((string) ($_GET['scope'] ?? $_POST['scope'] ?? '')));
  $filterUserId = intval($_GET['filter_user_id'] ?? $_POST['filter_user_id'] ?? 0);
  if ($filterUserId <= 0 && $scope === 'profile') {
    $filterUserId = intval($_GET['user_id'] ?? $_POST['user_id'] ?? 0);
  }
  $type = strtolower(trim((string) ($_GET['type'] ?? $_POST['type'] ?? '')));
  $limit = max(1, min(500, intval($_GET['limit'] ?? $_POST['limit'] ?? 200)));
  $offset = max(0, intval($_GET['offset'] ?? $_POST['offset'] ?? 0));

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
    $select[] = "ou.subscription_status AS original_user_subscription_status";
  }
  if ($pRepostCaption)
    $select[] = "p.$pRepostCaption AS repost_caption";
  if ($uId) {
    $select[] = ($uName ? "u.$uName AS author_name" : "'' AS author_name");
    $select[] = ($uUsername ? "u.$uUsername AS author_username" : "'' AS author_username");
    $select[] = ($uAvatar ? "u.$uAvatar AS author_avatar" : "'' AS author_avatar");
    $select[] = "u.subscription_status AS author_subscription_status, COALESCE(u.privacy_feed_action_subscribe, 0) AS author_feed_action_subscribe";
  }
  // Custom trending audio attached to this post (for feed autoplay).
  $select[] = "snd.audio_url AS sound_url";
  $select[] = "snd.title AS sound_title";
  $select[] = "snd.duration AS sound_duration";
  $select[] = "COALESCE(suse.sound_id, p.sound_id) AS sound_id";
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

  // Sound join — link a post to its custom audio via sound_uses (recorded by
  // useSound), falling back to posts.sound_id. One row per post via GROUP BY.
  $joins[] = "LEFT JOIN (SELECT post_id, MAX(sound_id) AS sound_id FROM sound_uses GROUP BY post_id) suse ON suse.post_id = p.$pId";
  $joins[] = "LEFT JOIN sounds snd ON snd.id = COALESCE(suse.sound_id, p.sound_id)";

  // Trending score join (legacy compatibility)
  $joins[] = "LEFT JOIN post_trending_scores pts ON pts.post_id = p.$pId";

  // Viral score join (new post_virality table)
  $joins[] = "LEFT JOIN post_virality pv ON pv.post_id = p.$pId";

  // Subscription check join (only if table exists)
  if ($authViewerId > 0 && $hasSubscriptionsTbl) {
    $joins[] = "LEFT JOIN user_subscriptions sub_chk ON sub_chk.subscriber_id = $authViewerId AND sub_chk.creator_id = p.$pUserId AND sub_chk.status = 'active' AND sub_chk.expires_at > NOW()";
  }

  // Add viral_score and is_viral to select list
  $select[] = "COALESCE(pv.viral_score, 0) AS viral_score";
  $select[] = "COALESCE(pv.is_viral, 0) AS is_viral";
  $select[] = "COALESCE(pv.velocity_1h, 1.0) AS velocity_1h";

  // ── Parse interest vector from client ──────────────────────────────────────
  // Flutter sends top-6 interest categories as JSON: {"video":3.5,"dance":2.1,...}
  $interestsRaw = $_GET['interests'] ?? $_POST['interests'] ?? '';
  $interestMap = [];
  if ($interestsRaw !== '') {
    try {
      $decoded = json_decode($interestsRaw, true);
      if (is_array($decoded))
        $interestMap = $decoded;
    } catch (Throwable $_) {
    }
  }

  // Build interest boost SQL fragment (used in tier queries)
  $interestBoost = "0";
  if (!empty($interestMap) && $pCaption) {
    $interestParts = [];
    foreach ($interestMap as $cat => $weight) {
      $cat = preg_replace('/[^a-z0-9_]/', '', strtolower((string) $cat));
      $w = round(min(floatval($weight), 5.0), 2);
      if ($cat !== '' && $w > 0) {
        $interestParts[] = "IF(LOWER(p.$pCaption) LIKE '%{$cat}%', {$w}, 0)";
      }
    }
    if (!empty($interestParts)) {
      $interestBoost = "(" . implode(" + ", $interestParts) . ")";
    }
  }

  // ── Determine feed strategy ────────────────────────────────────────────────
  $isPersonalised = ($filterUserId <= 0 && $scope !== 'profile');
  $isTrending     = ($type === 'trending');

  // ── WHERE base conditions (blocks, type filter, profile filter) ────────────
  $baseWhere  = [];
  $baseParams = [];

  // Global Block Filtering: exclude blocked users
  if ($authViewerId > 0) {
    $baseWhere[] = "p.$pUserId NOT IN (SELECT blocked_id FROM user_blocks WHERE blocker_id = ?)";
    $baseParams[] = $authViewerId;
    $baseWhere[] = "p.$pUserId NOT IN (SELECT blocker_id FROM user_blocks WHERE blocked_id = ?)";
    $baseParams[] = $authViewerId;
  }

  if ($filterUserId > 0) {
    $baseWhere[] = "p.$pUserId = ?";
    $baseParams[] = $filterUserId;
  }

  if ($type !== '' && !$isTrending && $pType) {
    $t = strtolower($type);
    if ($t === 'photos' || $t === 'images') $t = 'image';
    if ($t === 'videos')                    $t = 'video';
    if (in_array($t, ['image', 'video', 'reel', 'text'])) {
      $baseWhere[] = "LOWER(p.$pType) = ?";
      $baseParams[] = $t;
    }
  }

  // Shared JOIN fragment string (everything except post_virality, which is already in $joins)
  $joinStr = implode(" ", $joins);
  $selectStr = implode(", ", $select);

  // ─────────────────────────────────────────────────────────────────────────
  // TRENDING feed: rank purely by viral_score
  // ─────────────────────────────────────────────────────────────────────────
  if ($isTrending) {
    $trendWhere  = $baseWhere;
    $trendParams = $baseParams;
    $trendWhere[] = "COALESCE(pv.viral_score, pts.score, 0) > 0";

    $sql = "SELECT $selectStr FROM $postsTbl p $joinStr";
    if (!empty($trendWhere))
      $sql .= " WHERE " . implode(" AND ", $trendWhere);
    $sql .= " ORDER BY COALESCE(pv.viral_score, pts.score, 0) DESC, p.$pId DESC LIMIT $limit OFFSET $offset";

    $stmt = $pdo->prepare($sql);
    $stmt->execute($trendParams);
    $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

    $posts = [];
    foreach ($rows as $r) {
      $posts[] = build_post_row($r, $baseUrl);
    }
    out_json(200, ['status' => 'success', 'posts' => $posts]);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PROFILE / following-only / filter_user: pure chronological, single query
  // ─────────────────────────────────────────────────────────────────────────
  if (!$isPersonalised || ($action === 'following_reels' && $viewerId > 0)) {
    $singleWhere  = $baseWhere;
    $singleParams = $baseParams;

    if ($action === 'following_reels' && $viewerId > 0) {
      $singleWhere[] = "p.$pUserId IN (SELECT following_id FROM follows WHERE follower_id = ?)";
      $singleParams[] = $viewerId;
    }

    $sql = "SELECT $selectStr FROM $postsTbl p $joinStr";
    if (!empty($singleWhere))
      $sql .= " WHERE " . implode(" AND ", $singleWhere);
    $sql .= " ORDER BY p.$pId DESC LIMIT $limit OFFSET $offset";

    $stmt = $pdo->prepare($sql);
    $stmt->execute($singleParams);
    $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

    $posts = [];
    foreach ($rows as $r) {
      $posts[] = build_post_row($r, $baseUrl);
    }
    out_json(200, ['status' => 'success', 'posts' => $posts]);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PERSONALISED FEED: two-tier "following-first then viral" algorithm
  // ─────────────────────────────────────────────────────────────────────────

  // For guests (no viewer_id): return viral posts by viral_score only
  if ($viewerId <= 0) {
    $guestWhere  = $baseWhere;
    $guestParams = $baseParams;

    $sql = "SELECT $selectStr FROM $postsTbl p $joinStr";
    if (!empty($guestWhere))
      $sql .= " WHERE " . implode(" AND ", $guestWhere);
    $sql .= " ORDER BY COALESCE(pv.viral_score, pts.score, 0) DESC, p.$pId DESC LIMIT $limit OFFSET $offset";

    $stmt = $pdo->prepare($sql);
    $stmt->execute($guestParams);
    $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

    $posts = [];
    foreach ($rows as $r) {
      $posts[] = build_post_row($r, $baseUrl);
    }
    out_json(200, ['status' => 'success', 'posts' => $posts]);
  }

  // ── Seen-posts exclusion (passed as CSV or JSON array from client) ─────────
  $seenRaw  = $_GET['seen_ids'] ?? $_POST['seen_ids'] ?? '';
  $seenIds  = [];
  if ($seenRaw !== '') {
    $decoded = json_decode($seenRaw, true);
    if (is_array($decoded)) {
      $seenIds = array_map('intval', $decoded);
    } else {
      $seenIds = array_map('intval', explode(',', $seenRaw));
    }
    $seenIds = array_filter($seenIds, fn($v) => $v > 0);
    $seenIds = array_values(array_unique($seenIds));
  }

  // Build a NOT IN fragment for seen posts (safe: all are ints)
  $seenExclude = '';
  if (!empty($seenIds)) {
    $seenExclude = "AND p.$pId NOT IN (" . implode(',', $seenIds) . ")";
  }

  // Block WHERE fragment — embedded as literal SQL for use in tier sub-queries
  // (authViewerId is a trusted int cast above, safe to interpolate)
  $blockFragment = '';
  if ($authViewerId > 0) {
    $blockFragment = "AND p.$pUserId NOT IN (SELECT blocked_id FROM user_blocks WHERE blocker_id = $authViewerId)
                      AND p.$pUserId NOT IN (SELECT blocker_id FROM user_blocks WHERE blocked_id = $authViewerId)";
  }

  // Type filter fragment — built directly from the already-validated $type variable
  $typeFragment = '';
  $typeParam    = null;
  if ($type !== '' && !$isTrending && $pType) {
    $t = strtolower($type);
    if ($t === 'photos' || $t === 'images') $t = 'image';
    if ($t === 'videos')                    $t = 'video';
    if (in_array($t, ['image', 'video', 'reel', 'text'], true)) {
      $typeFragment = "AND LOWER(p.$pType) = ?";
      $typeParam    = $t;
    }
  }

  // Recency decay expression
  $recencyExpr = $pCreated
    ? "EXP(-0.02 * GREATEST(0, TIMESTAMPDIFF(HOUR, p.$pCreated, NOW()) - 6))"
    : "1";

  // Engagement rate expression
  $engRateExpr = "((COALESCE(lc.likes_count,0)*2 + COALESCE(cc.comments_count,0)*3) / GREATEST(COALESCE(vc.total_views,0),1))";

  // Tier sizes (60/40 split)
  $tier1_limit = (int)ceil($limit * 0.6) + 5; // fetch a few extra for interleaving
  $tier2_limit = (int)ceil($limit * 0.4) + 5;

  // ── Tier 1: Posts from followed users, last 48 hours ──────────────────────
  // Rank by (viral_score * 0.3 + recency_factor)
  $tier1Sql = "SELECT $selectStr, 1 AS feed_tier
               FROM $postsTbl p $joinStr
               WHERE p.$pUserId IN (SELECT following_id FROM follows WHERE follower_id = ?)
                 AND p.$pCreated > NOW() - INTERVAL 48 HOUR
                 $seenExclude
                 $blockFragment
                 $typeFragment
               ORDER BY (COALESCE(pv.viral_score, pts.score, 0) * 0.3 + $recencyExpr * $engRateExpr * 5 + $interestBoost) * (0.55 + RAND() * 0.9) DESC,
                        p.$pId DESC
               LIMIT $tier1_limit";

  $tier1Params = [$viewerId];
  if ($typeParam !== null) $tier1Params[] = $typeParam;

  $stmt1 = $pdo->prepare($tier1Sql);
  $stmt1->execute($tier1Params);
  $tier1Rows = $stmt1->fetchAll(PDO::FETCH_ASSOC);

  // ── Tier 2: Viral posts outside the follow network ────────────────────────
  $tier2Sql = "SELECT $selectStr, 2 AS feed_tier
               FROM $postsTbl p $joinStr
               WHERE p.$pUserId NOT IN (SELECT following_id FROM follows WHERE follower_id = ?)
                 AND p.$pUserId != ?
                 AND COALESCE(pv.viral_score, pts.score, 0) > 5
                 $seenExclude
                 $blockFragment
                 $typeFragment
               ORDER BY COALESCE(pv.viral_score, pts.score, 0) * (0.55 + RAND() * 0.9) DESC,
                        p.$pId DESC
               LIMIT $tier2_limit";

  $tier2Params = [$viewerId, $viewerId];
  if ($typeParam !== null) $tier2Params[] = $typeParam;

  $stmt2 = $pdo->prepare($tier2Sql);
  $stmt2->execute($tier2Params);
  $tier2Rows = $stmt2->fetchAll(PDO::FETCH_ASSOC);

  // ── Interleave 60/40: 3 from tier1, 2 from tier2, repeat ──────────────────
  $interleaved = [];
  $i1 = 0;
  $i2 = 0;
  $t1total = count($tier1Rows);
  $t2total = count($tier2Rows);

  while (count($interleaved) < $limit && ($i1 < $t1total || $i2 < $t2total)) {
    // Take up to 3 from tier 1
    for ($k = 0; $k < 3 && $i1 < $t1total && count($interleaved) < $limit; $k++, $i1++) {
      $interleaved[] = $tier1Rows[$i1];
    }
    // Take up to 2 from tier 2
    for ($k = 0; $k < 2 && $i2 < $t2total && count($interleaved) < $limit; $k++, $i2++) {
      $interleaved[] = $tier2Rows[$i2];
    }
  }

  $posts = [];
  foreach ($interleaved as $r) {
    $post = build_post_row($r, $baseUrl);
    $post['feed_tier'] = (int)($r['feed_tier'] ?? 1);
    $posts[] = $post;
  }

  out_json(200, ['status' => 'success', 'posts' => $posts]);

} catch (Throwable $e) {
  out_json(500, ['status' => 'error', 'message' => $e->getMessage()]);
}
