<?php
header('Content-Type: application/json; charset=utf-8');
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Headers: Content-Type, Authorization");
header("Access-Control-Allow-Methods: GET, POST, OPTIONS");
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
  http_response_code(200);
  exit;
}

require_once __DIR__ . '/db_connect.php';

function out($arr, $code = 200)
{
  http_response_code($code);
  echo json_encode($arr);
  exit;
}

function auth_user_id(PDO $pdo): ?int
{
  $headers = function_exists('getallheaders') ? getallheaders() : [];
  $auth = $headers['Authorization'] ?? $headers['authorization'] ?? '';
  $token = trim($auth);
  if (stripos($token, 'Bearer ') === 0)
    $token = trim(substr($token, 7));
  if ($token === '')
    return null;

  $st = $pdo->prepare("SELECT id FROM users WHERE api_token = ? LIMIT 1");
  $st->execute([$token]);
  $r = $st->fetch(PDO::FETCH_ASSOC);
  return $r ? (int)$r['id'] : null;
}

function counts(PDO $pdo, int $userId): array
{
  $followers = (int)$pdo->query("SELECT COUNT(*) FROM follows WHERE following_id = " . intval($userId))->fetchColumn();
  $following = (int)$pdo->query("SELECT COUNT(*) FROM follows WHERE follower_id = " . intval($userId))->fetchColumn();
  $posts = 0;
  try {
    $posts = (int)$pdo->query("SELECT COUNT(*) FROM posts WHERE user_id = " . intval($userId))->fetchColumn();
  }
  catch (Throwable $e) {
  }
  return ["followers" => $followers, "following" => $following, "posts" => $posts];
}

$me = auth_user_id($pdo);
if (!$me)
  out(["status" => false, "message" => "Unauthorized"], 401);

$action = $_GET['action'] ?? $_POST['action'] ?? 'status';

$raw = file_get_contents("php://input");
$j = json_decode($raw, true);
if (!is_array($j))
  $j = [];
$data = array_merge($_GET, $_POST, $j);

$target = (int)($data['user_id'] ?? $data['target_user_id'] ?? 0);
if ($action !== 'counts' && $target <= 0)
  out(["status" => false, "message" => "user_id required"], 400);
if ($target === $me && $action === 'follow')
  out(["status" => false, "message" => "Cannot follow yourself"], 400);

if ($action === 'follow') {
  $st = $pdo->prepare("INSERT IGNORE INTO follows (follower_id, following_id) VALUES (?, ?)");
  $st->execute([$me, $target]);
  
  // Send Push Notification
  try {
    require_once __DIR__ . '/notification_helper.php';
    $uSt = $pdo->prepare('SELECT name FROM users WHERE id = ?');
    $uSt->execute([$me]);
    $uname = $uSt->fetchColumn() ?: 'Somebody';
    send_app_notification($pdo, $target, $me, 'follow', 'New Follower', "$uname started following you.", null, false);
  } catch (Throwable $ignore) {}

  out(["status" => true, "message" => "Followed", "is_following" => 1, "following" => 1, "counts" => counts($pdo, $target), "my_counts" => counts($pdo, $me)]);
}

if ($action === 'unfollow') {
  $st = $pdo->prepare("DELETE FROM follows WHERE follower_id = ? AND following_id = ?");
  $st->execute([$me, $target]);
  out(["status" => true, "message" => "Unfollowed", "is_following" => 0, "following" => 0, "counts" => counts($pdo, $target), "my_counts" => counts($pdo, $me)]);
}

if ($action === 'status') {
  $st = $pdo->prepare("SELECT 1 FROM follows WHERE follower_id = ? AND following_id = ? LIMIT 1");
  $st->execute([$me, $target]);
  $isFollowing = $st->fetchColumn() ? 1 : 0;
  out([
    "status" => true,
    "is_following" => $isFollowing,
    "counts" => counts($pdo, $target),
    "my_counts" => counts($pdo, $me)
  ]);
}

if ($action === 'counts') {
  $uid = (int)($data['user_id'] ?? $me);
  out(["status" => true, "counts" => counts($pdo, $uid)]);
}


if ($action === 'followers' || $action === 'following') {
    $uid   = isset($_GET['user_id']) && (int)$_GET['user_id'] > 0 ? (int)$_GET['user_id'] : $me;
    $page  = max(1, (int)($_GET['page'] ?? 1));
    $limit = min(50, max(1, (int)($_GET['limit'] ?? 20)));
    $off   = ($page - 1) * $limit;

    if ($action === 'followers') {
        // People who follow $uid
        $fetch_limit = (int)($limit + 1);
        $fetch_offset = (int)$off;
        $st = $pdo->prepare("
            SELECT u.id, u.name, u.username, u.profile_pic AS avatar,
                   COALESCE((SELECT 1 FROM follows WHERE follower_id=? AND following_id=u.id LIMIT 1), 0) AS is_following
            FROM follows f
            JOIN users u ON u.id = f.follower_id
            WHERE f.following_id = ? AND u.is_banned = 0
            ORDER BY f.created_at DESC
            LIMIT $fetch_limit OFFSET $fetch_offset");
        $st->execute([$me, $uid]);
    } else {
        // People $uid follows
        $fetch_limit = (int)($limit + 1);
        $fetch_offset = (int)$off;
        $st = $pdo->prepare("
            SELECT u.id, u.name, u.username, u.profile_pic AS avatar,
                   COALESCE((SELECT 1 FROM follows WHERE follower_id=? AND following_id=u.id LIMIT 1), 0) AS is_following
            FROM follows f
            JOIN users u ON u.id = f.following_id
            WHERE f.follower_id = ? AND u.is_banned = 0
            ORDER BY f.created_at DESC
            LIMIT $fetch_limit OFFSET $fetch_offset");
        $st->execute([$me, $uid]);
    }

    $rows    = $st->fetchAll(PDO::FETCH_ASSOC);
    $hasMore = count($rows) > $limit;
    if ($hasMore) array_pop($rows);

    $baseUrl = 'https://goreto.org/ekloadmin/';
    $users   = array_map(function ($r) use ($baseUrl) {
        $av = (string)($r['avatar'] ?? '');
        if ($av !== '' && !preg_match('~^https?://~i', $av)) {
            $av = $baseUrl . ltrim($av, '/');
        }
        return [
            'id'           => (string)$r['id'],
            'name'         => $r['name'] ?? '',
            'username'     => $r['username'] ?? '',
            'avatar'       => $av,
            'is_following' => (bool)$r['is_following'],
        ];
    }, $rows);

    out(['status' => true, 'users' => $users, 'has_more' => $hasMore, 'page' => $page]);
}

out(["status" => false, "message" => "Invalid action"], 400);