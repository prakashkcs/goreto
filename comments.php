<?php
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
  http_response_code(200);
  echo json_encode(['status' => 'success']);
  exit;
}

require_once __DIR__ . '/db_connect.php';
require_once __DIR__ . '/auth_middleware.php';

function out_json(int $code, array $payload): void {
  http_response_code($code);
  echo json_encode($payload);
  exit;
}

if (!isset($pdo) || !($pdo instanceof PDO)) {
  out_json(500, ["status"=>"error","message"=>"Database connection failed"]);
}

// ✅ Auth (your app sends token)
$user = requireUser($pdo);
$viewerId = (int)($user["id"] ?? 0);

$action = $_GET['action'] ?? $_POST['action'] ?? '';

$raw = file_get_contents("php://input");
$data = json_decode($raw, true);
if (!is_array($data)) $data = [];

// helper: read param from GET/POST/JSON
function param(string $key, $default = null) {
  global $data;
  if (isset($_GET[$key])) return $_GET[$key];
  if (isset($_POST[$key])) return $_POST[$key];
  if (isset($data[$key])) return $data[$key];
  return $default;
}

function table_cols(PDO $pdo, string $table): array {
  $cols = [];
  $stmt = $pdo->query("SHOW COLUMNS FROM {$table}");
  while ($r = $stmt->fetch(PDO::FETCH_ASSOC)) $cols[] = $r['Field'];
  return $cols;
}

function pick_col(array $cols, array $cands): ?string {
  foreach ($cands as $c) if (in_array($c, $cols, true)) return $c;
  return null;
}

function normalize_avatar($val): ?string {
  if ($val === null) return null;
  $val = trim((string)$val);
  return $val === '' ? null : $val;
}

try {
  $commentsTbl = 'post_comments';
  $usersTbl    = 'users';

  // detect user columns
  $usersCols = table_cols($pdo, $usersTbl);
  $uId       = pick_col($usersCols, ['id','user_id']);

  // ✅ pick best "real name" column (order matters)
  $uName     = pick_col($usersCols, ['name','full_name','display_name']);
  $uUsername = pick_col($usersCols, ['username','user_name','handle']);
  $uAvatar   = pick_col($usersCols, ['profile_pic','avatar','avatar_url','photo','image']);

  // Build COALESCE for name and avatar so it never falls back to "user"
  $nameExprParts = [];
  if ($uName)     $nameExprParts[] = "u.$uName";
  if ($uUsername) $nameExprParts[] = "u.$uUsername";
  if (empty($nameExprParts)) $nameExprParts[] = "''";
  $nameExpr = "COALESCE(" . implode(", ", $nameExprParts) . ", 'User')";

  $avatarExprParts = [];
  if ($uAvatar) $avatarExprParts[] = "u.$uAvatar";
  // if no avatar col, return empty
  if (empty($avatarExprParts)) $avatarExprParts[] = "''";
  $avatarExpr = "COALESCE(" . implode(", ", $avatarExprParts) . ", '')";

  // -----------------------------
  // ✅ LIST COMMENTS
  // GET comments.php?action=list&post_id=32
  // -----------------------------
  if ($action === 'list') {
    $postId = (int)param('post_id', 0);
    if ($postId <= 0) out_json(400, ["status"=>"error","message"=>"Missing post_id"]);

    $sql = "
      SELECT
        c.id, c.post_id, c.user_id, c.parent_id, c.comment, c.created_at,
        $nameExpr AS author_name,
        " . ($uUsername ? "u.$uUsername" : "''") . " AS author_username,
        $avatarExpr AS author_avatar
      FROM $commentsTbl c
      LEFT JOIN $usersTbl u ON u.$uId = c.user_id
      WHERE c.post_id = :pid
      ORDER BY c.created_at ASC, c.id ASC
    ";

    $stmt = $pdo->prepare($sql);
    $stmt->execute([":pid" => $postId]);
    $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

    $comments = [];
    foreach ($rows as $r) {
      $cid = (string)($r['id'] ?? '');
      $uid = (string)($r['user_id'] ?? '');
      $authorName = trim((string)($r['author_name'] ?? ''));
      if ($authorName === '') $authorName = 'User';

      $authorUsername = trim((string)($r['author_username'] ?? ''));
      $authorAvatar = normalize_avatar($r['author_avatar'] ?? null);

      $comments[] = [
        'id' => $cid,
        'comment_id' => $cid,
        'post_id' => (string)($r['post_id'] ?? ''),
        'user_id' => $uid,
        'uid' => $uid,
        'parent_id' => ($r['parent_id'] === null ? null : (string)$r['parent_id']),

        'comment' => (string)($r['comment'] ?? ''),
        'text' => (string)($r['comment'] ?? ''),
        'content' => (string)($r['comment'] ?? ''),

        'created_at' => (string)($r['created_at'] ?? ''),
        'created' => (string)($r['created_at'] ?? ''),

        // ✅ many aliases (prevents Flutter showing "user")
        'author_name' => $authorName,
        'name' => $authorName,
        'author_username' => $authorUsername,
        'username' => $authorUsername,

        'author_avatar' => $authorAvatar,
        'avatar' => $authorAvatar,
        'profile_pic' => $authorAvatar,

        'is_mine' => ((int)$uid === $viewerId),
      ];
    }

    out_json(200, [
      "status" => "success",
      "comments" => $comments,
      "data" => $comments,
      "count" => count($comments),
    ]);
  }

  // -----------------------------
  // ✅ ADD / REPLY
  // POST JSON: { action:"add", post_id:32, comment:"hi", parent_id:null }
  // -----------------------------
  if ($action === 'add' || $action === 'reply') {
    $postId = (int)param('post_id', 0);
    $comment = trim((string)param('comment', ''));
    $parentRaw = param('parent_id', null);

    if ($postId <= 0) out_json(400, ["status"=>"error","message"=>"Missing post_id"]);
    if ($comment === '') out_json(400, ["status"=>"error","message"=>"Empty comment"]);

    $parentId = null;
    if ($parentRaw !== null && $parentRaw !== '' && (int)$parentRaw > 0) $parentId = (int)$parentRaw;

    $ins = $pdo->prepare("
      INSERT INTO $commentsTbl (post_id, user_id, parent_id, comment, created_at)
      VALUES (:p, :u, :parent, :c, NOW())
    ");
    $ins->execute([
      ":p" => $postId,
      ":u" => $viewerId,
      ":parent" => $parentId,
      ":c" => $comment
    ]);

    $newId = (int)$pdo->lastInsertId();

    // Return created comment with author fields
    $sql = "
      SELECT
        c.id, c.post_id, c.user_id, c.parent_id, c.comment, c.created_at,
        $nameExpr AS author_name,
        " . ($uUsername ? "u.$uUsername" : "''") . " AS author_username,
        $avatarExpr AS author_avatar
      FROM $commentsTbl c
      LEFT JOIN $usersTbl u ON u.$uId = c.user_id
      WHERE c.id = :id
      LIMIT 1
    ";
    $stmt = $pdo->prepare($sql);
    $stmt->execute([":id" => $newId]);
    $r = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!$r) out_json(500, ["status"=>"error","message"=>"Failed to load created comment"]);

    $authorName = trim((string)($r['author_name'] ?? ''));
    if ($authorName === '') $authorName = 'User';

    $authorUsername = trim((string)($r['author_username'] ?? ''));
    $authorAvatar = normalize_avatar($r['author_avatar'] ?? null);

    $commentObj = [
      'id' => (string)$r['id'],
      'comment_id' => (string)$r['id'],
      'post_id' => (string)$r['post_id'],
      'user_id' => (string)$r['user_id'],
      'uid' => (string)$r['user_id'],
      'parent_id' => ($r['parent_id'] === null ? null : (string)$r['parent_id']),

      'comment' => (string)$r['comment'],
      'text' => (string)$r['comment'],
      'content' => (string)$r['comment'],

      'created_at' => (string)$r['created_at'],
      'created' => (string)$r['created_at'],

      'author_name' => $authorName,
      'name' => $authorName,
      'author_username' => $authorUsername,
      'username' => $authorUsername,

      'author_avatar' => $authorAvatar,
      'avatar' => $authorAvatar,
      'profile_pic' => $authorAvatar,

      'is_mine' => true,
    ];

    // --- SEND NOTIFICATIONS ---
    try {
        require_once __DIR__ . '/notification_helper.php';
        
        // Fetch post owner
        $pSt = $pdo->prepare("SELECT user_id FROM posts WHERE id = ?");
        $pSt->execute([$postId]);
        $postOwnerId = (int)$pSt->fetchColumn();

        if ($action === 'add' || ($action === 'reply' && !$parentId)) {
            if ($postOwnerId > 0 && $postOwnerId !== $viewerId) {
                send_app_notification($pdo, $postOwnerId, $viewerId, 'comment', 'New Comment', "$authorName commented on your post.", $postId);
            }
        } else if ($action === 'reply' && $parentId) {
            // Notify parent comment author
            $cSt = $pdo->prepare("SELECT user_id FROM post_comments WHERE id = ?");
            $cSt->execute([$parentId]);
            $parentAuthorId = (int)$cSt->fetchColumn();
            
            if ($parentAuthorId > 0 && $parentAuthorId !== $viewerId) {
                send_app_notification($pdo, $parentAuthorId, $viewerId, 'comment_reply', 'New Reply', "$authorName replied to your comment.", $postId);
            }
            
            // Also notify post owner if they aren't the parent author or viewer
            if ($postOwnerId > 0 && $postOwnerId !== $viewerId && $postOwnerId !== $parentAuthorId) {
                 send_app_notification($pdo, $postOwnerId, $viewerId, 'comment', 'New Comment', "$authorName replied to a comment on your post.", $postId);
            }
        }
    } catch (Throwable $e) {
        error_log("Comment Notification Error: " . $e->getMessage());
    }

    out_json(200, [
      "status" => "success",
      "message" => "Comment added",
      "comment" => $commentObj,
      "data" => $commentObj
    ]);
  }

  // -----------------------------
  // ✅ EDIT (only owner)
  // -----------------------------
  if ($action === 'edit') {
    $commentId = (int)param('comment_id', 0);
    $newText = trim((string)param('comment', ''));

    if ($commentId <= 0) out_json(400, ["status"=>"error","message"=>"Missing comment_id"]);
    if ($newText === '') out_json(400, ["status"=>"error","message"=>"Empty comment"]);

    $chk = $pdo->prepare("SELECT user_id FROM $commentsTbl WHERE id = :id LIMIT 1");
    $chk->execute([":id" => $commentId]);
    $own = $chk->fetch(PDO::FETCH_ASSOC);

    if (!$own) out_json(404, ["status"=>"error","message"=>"Comment not found"]);
    if ((int)$own['user_id'] !== $viewerId) out_json(403, ["status"=>"error","message"=>"Not allowed"]);

    $upd = $pdo->prepare("UPDATE $commentsTbl SET comment = :c WHERE id = :id");
    $upd->execute([":c" => $newText, ":id" => $commentId]);

    out_json(200, ["status"=>"success","message"=>"Comment updated"]);
  }

  // -----------------------------
  // ✅ DELETE (only owner)
  // -----------------------------
  if ($action === 'delete') {
    $commentId = (int)param('comment_id', 0);
    if ($commentId <= 0) out_json(400, ["status"=>"error","message"=>"Missing comment_id"]);

    $chk = $pdo->prepare("SELECT user_id FROM $commentsTbl WHERE id = :id LIMIT 1");
    $chk->execute([":id" => $commentId]);
    $own = $chk->fetch(PDO::FETCH_ASSOC);

    if (!$own) out_json(404, ["status"=>"error","message"=>"Comment not found"]);
    if ((int)$own['user_id'] !== $viewerId) out_json(403, ["status"=>"error","message"=>"Not allowed"]);

    // hard delete + remove replies
    $del = $pdo->prepare("DELETE FROM $commentsTbl WHERE id = :id OR parent_id = :id");
    $del->execute([":id" => $commentId]);

    out_json(200, ["status"=>"success","message"=>"Comment deleted"]);
  }

  out_json(400, ["status"=>"error","message"=>"Invalid action"]);

} catch (Throwable $e) {
  out_json(500, ["status"=>"error","message"=>"Server error","detail"=>$e->getMessage()]);
}