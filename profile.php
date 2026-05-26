<?php
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Content-Type, Authorization');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
  http_response_code(200);
  echo json_encode(['status' => 'success']);
  exit;
}

/**
 * ✅ IMPORTANT FIX:
 * Register fatal-error handler BEFORE any require_once.
 * This ensures even db_connect.php/auth_middleware.php fatals return JSON.
 */
ini_set('display_errors', '0');
error_reporting(E_ALL);

register_shutdown_function(function () {
  $err = error_get_last();
  if ($err && in_array($err['type'], [E_ERROR, E_PARSE, E_CORE_ERROR, E_COMPILE_ERROR], true)) {
    if (!headers_sent()) {
      http_response_code(500);
      header('Content-Type: application/json; charset=utf-8');
    }
    echo json_encode([
    "status" => "error",
    "message" => "Fatal error in profile.php (or included file)",
    "detail" => $err['message'],
    "file" => $err['file'],
    "line" => $err['line'],
    ]);
  }
});

function json_out($code, $arr)
{
  http_response_code($code);
  echo json_encode($arr);
  exit;
}

function get_input()
{
  $raw = file_get_contents("php://input");
  $json = json_decode($raw, true);
  if (is_array($json))
    return $json;
  return $_POST;
}

function norm_url(?string $url, string $baseUrl): string
{
  $url = trim((string)$url);
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

/** ✅ Robust Authorization fetch (works on more servers) */
function get_auth_header(): ?string
{
  $h = null;
  if (function_exists('getallheaders')) {
    $headers = getallheaders();
    $h = $headers['Authorization'] ?? $headers['authorization'] ?? null;
  }
  if (!$h) {
    $h = $_SERVER['HTTP_AUTHORIZATION'] ?? $_SERVER['REDIRECT_HTTP_AUTHORIZATION'] ?? null;
  }
  $h = is_string($h) ? trim($h) : '';
  return $h !== '' ? $h : null;
}

/**
 * ✅ FIX: avoid function name conflict with auth_middleware.php
 */
function table_exists_local(PDO $pdo, string $table): bool
{
  try {
    $st = $pdo->prepare("SHOW TABLES LIKE ?");
    $st->execute([$table]);
    return (bool)$st->fetchColumn();
  }
  catch (Throwable $e) {
    return false;
  }
}

function live_counts(PDO $pdo, int $userId): array
{
  $followers = 0;
  $following = 0;
  $posts = 0;

  if (table_exists_local($pdo, 'follows')) {
    $followers = (int)$pdo->query("SELECT COUNT(*) FROM follows WHERE following_id = " . intval($userId))->fetchColumn();
    $following = (int)$pdo->query("SELECT COUNT(*) FROM follows WHERE follower_id = " . intval($userId))->fetchColumn();
  }

  if (table_exists_local($pdo, 'posts')) {
    try {
      $posts = (int)$pdo->query("SELECT COUNT(*) FROM posts WHERE user_id = " . intval($userId))->fetchColumn();
    }
    catch (Throwable $e) {
    }
  }

  return ["followers" => $followers, "following" => $following, "posts" => $posts];
}

function ensure_social_links_table(PDO $pdo): void
{
  $pdo->exec("CREATE TABLE IF NOT EXISTS user_social_links (
    user_id INT NOT NULL PRIMARY KEY,
    facebook VARCHAR(255) NULL,
    instagram VARCHAR(255) NULL,
    tiktok VARCHAR(255) NULL,
    youtube VARCHAR(255) NULL,
    website VARCHAR(255) NULL,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci");
}

function get_social_links(PDO $pdo, int $userId): array
{
  if (!table_exists_local($pdo, 'user_social_links'))
    return [];

  $st = $pdo->prepare("SELECT facebook, instagram, tiktok, youtube, website FROM user_social_links WHERE user_id = ? LIMIT 1");
  $st->execute([$userId]);
  $row = $st->fetch(PDO::FETCH_ASSOC) ?: [];

  $clean = [];
  foreach ($row as $k => $v) {
    $v = trim((string)$v);
    if ($v !== '')
      $clean[$k] = $v;
  }
  return $clean;
}

/** ✅ Safe config load (won’t fatal if missing) */
$configPath = __DIR__ . '/../../config/config.php';
$config = [];
if (file_exists($configPath)) {
  $tmp = require $configPath;
  if (is_array($tmp))
    $config = $tmp;
}

$baseUrl = 'https://goreto.org/ekloadmin';
if (isset($config['base_url']) && is_string($config['base_url']) && trim($config['base_url']) !== '') {
  $baseUrl = rtrim($config['base_url'], '/');
}

require_once __DIR__ . '/db_connect.php';
require_once __DIR__ . '/auth_middleware.php'; // provides requireUser($pdo)

if (!isset($pdo) || !($pdo instanceof PDO)) {
  json_out(500, ['status' => 'error', 'message' => 'Database not connected ($pdo missing) in db_connect.php']);
}

// ---- Detect users table columns safely (your original style) ----
try {
  $cols = [];
  $stmt = $pdo->query("SHOW COLUMNS FROM users");
  while ($r = $stmt->fetch(PDO::FETCH_ASSOC))
    $cols[] = $r['Field'];

  $pick = function (array $cands) use ($cols) {
    foreach ($cands as $c)
      if (in_array($c, $cols, true))
        return $c;
    return null;
  };

  $colId = $pick(['id', 'user_id', 'uid']);
  $colName = $pick(['name', 'full_name', 'fullname']);
  $colUsername = $pick(['username', 'user_name', 'uname', 'handle', 'user_handle']);
  $colBio = $pick(['bio', 'about', 'description']);
  $colLocation = $pick(['location', 'address', 'city']);

  // ✅ Force correct mapping for YOUR DB
  $colAvatar = $pick(['profile_pic', 'avatar', 'profile_image', 'photo']);
  $colCover = $pick(['cover_pic', 'cover', 'cover_image', 'cover_url']);

  $colCreated = $pick(['created_at', 'created', 'date_created', 'joined_at']);

  if (!$colId)
    json_out(500, ['status' => 'error', 'message' => 'users table missing id column']);
}
catch (Throwable $e) {
  json_out(500, ['status' => 'error', 'message' => 'Server error', 'detail' => $e->getMessage()]);
}

$method = $_SERVER['REQUEST_METHOD'];

// ---------- GET PROFILE ----------
if ($method === 'GET') {
  $userId = 0;
  if (isset($_GET['user_id']))
    $userId = intval($_GET['user_id']);
  if ($userId <= 0 && isset($_GET['id']))
    $userId = intval($_GET['id']);
  if ($userId <= 0)
    json_out(400, ['status' => 'error', 'message' => 'user_id (or id) required']);

  $viewer = null;
  $authHeader = get_auth_header();

  $vid = 0;
  if ($authHeader !== null) {
    $viewer = requireUser($pdo);
    $vid = (int)($viewer['id'] ?? 0);
  }

  $select = [$colId . " AS id"];
  if ($colName)
    $select[] = "$colName AS name";
  if ($colUsername)
    $select[] = "$colUsername AS username";
  if ($colBio)
    $select[] = "$colBio AS bio";
  if ($colLocation)
    $select[] = "$colLocation AS location";
  if ($colAvatar)
    $select[] = "$colAvatar AS avatar";
  if ($colCover)
    $select[] = "$colCover AS cover";
  if ($colCreated)
    $select[] = "$colCreated AS created_at";

  $sql = "SELECT " . implode(", ", $select) . " FROM users WHERE $colId = ? LIMIT 1";
  $q = $pdo->prepare($sql);
  $q->execute([$userId]);
  $u = $q->fetch(PDO::FETCH_ASSOC);
  if (!$u)
    json_out(404, ['status' => 'error', 'message' => 'User not found']);

  if (!isset($u['avatar']))
    $u['avatar'] = '';
  if (!isset($u['cover']))
    $u['cover'] = '';

  $u['avatar'] = norm_url($u['avatar'], $baseUrl);
  $u['cover'] = norm_url($u['cover'], $baseUrl);

  // ✅ IMPORTANT: DO NOT force cover=avatar anymore.
  // If cover_pic is empty, cover will be "" (Flutter should show placeholder/gradient)

  $c = live_counts($pdo, (int)$u['id']);
  $u['followers_count'] = $c['followers'];
  $u['following_count'] = $c['following'];
  $u['posts_count'] = $c['posts'];

  $u['followers'] = $c['followers'];
  $u['following'] = $c['following'];
  $u['total_posts'] = $c['posts'];

  $u['social_links'] = get_social_links($pdo, (int)$u['id']);

  $u['is_following'] = 0;
  if ($vid > 0 && $vid !== (int)$u['id'] && table_exists_local($pdo, 'follows')) {
    $st = $pdo->prepare("SELECT 1 FROM follows WHERE follower_id = ? AND following_id = ? LIMIT 1");
    $st->execute([$vid, (int)$u['id']]);
    $u['is_following'] = $st->fetchColumn() ? 1 : 0;
  }

  // Referral code fields
  $u['referral_code'] = '';
  $u['referral_code_edited'] = 0;
  if (in_array('referral_code', $cols, true)) {
    $rcSt = $pdo->prepare("SELECT referral_code, referral_code_edited FROM users WHERE $colId = ? LIMIT 1");
    $rcSt->execute([$userId]);
    $rcRow = $rcSt->fetch(PDO::FETCH_ASSOC);
    if ($rcRow) {
      $u['referral_code'] = $rcRow['referral_code'] ?? '';
      $u['referral_code_edited'] = intval($rcRow['referral_code_edited'] ?? 0);
    }
  }

  json_out(200, ['status' => 'success', 'user' => $u]);
}

// ---------- UPDATE PROFILE (POST) ----------
if ($method === 'POST') {
  $viewer = requireUser($pdo);
  $viewerId = (int)$viewer['id'];

  $in = get_input();

  // ── Referral code update action ──
  $action = $_GET['action'] ?? $in['action'] ?? '';
  if ($action === 'update_referral_code') {
    // Ensure columns exist
    if (!in_array('referral_code', $cols, true)) {
      try {
        $pdo->exec("ALTER TABLE users ADD COLUMN referral_code VARCHAR(20) NULL");
      }
      catch (Throwable $e) {
      }
    }
    if (!in_array('referral_code_edited', $cols, true)) {
      try {
        $pdo->exec("ALTER TABLE users ADD COLUMN referral_code_edited TINYINT(1) NOT NULL DEFAULT 0");
      }
      catch (Throwable $e) {
      }
    }

    // Check if already edited
    $chk = $pdo->prepare("SELECT referral_code_edited FROM users WHERE $colId = ? LIMIT 1");
    $chk->execute([$viewerId]);
    $edited = intval($chk->fetchColumn() ?? 0);
    if ($edited >= 1) {
      json_out(400, ['status' => 'error', 'message' => 'Referral code can only be edited once']);
    }

    $newCode = strtoupper(trim((string)($in['referral_code'] ?? '')));
    if (strlen($newCode) < 4 || strlen($newCode) > 20 || !preg_match('/^[A-Z0-9]+$/', $newCode)) {
      json_out(400, ['status' => 'error', 'message' => 'Invalid referral code. Use 4-20 alphanumeric characters.']);
    }

    // Uniqueness check
    $dup = $pdo->prepare("SELECT $colId FROM users WHERE referral_code = ? AND $colId != ? LIMIT 1");
    $dup->execute([$newCode, $viewerId]);
    if ($dup->fetchColumn()) {
      json_out(400, ['status' => 'error', 'message' => 'This referral code is already in use']);
    }

    $pdo->prepare("UPDATE users SET referral_code = ?, referral_code_edited = 1 WHERE $colId = ?")->execute([$newCode, $viewerId]);

    json_out(200, ['status' => 'success', 'message' => 'Referral code updated successfully', 'referral_code' => $newCode]);
  }

  $userId = isset($in['user_id']) ? intval($in['user_id']) : 0;

  if ($userId <= 0)
    $userId = $viewerId;
  if ($userId !== $viewerId) {
    json_out(403, ['status' => 'error', 'message' => 'You can only update your own profile']);
  }

  $name = trim((string)($in['name'] ?? ''));
  $username = trim((string)($in['username'] ?? ''));
  $bio = (string)($in['bio'] ?? '');
  $location = (string)($in['location'] ?? '');

  $social = $in['social_links'] ?? null;
  if (is_string($social)) {
    $decoded = json_decode($social, true);
    if (is_array($decoded))
      $social = $decoded;
  }
  if (!is_array($social))
    $social = [];
    
  // Map 'x' (Twitter) to 'website' if present, because DB only supports website
  if (isset($social['x']) && trim((string)$social['x']) !== '') {
      $social['website'] = trim((string)$social['x']);
  }

  $fields = [];
  $params = [];

  if ($colName && $name !== '') {
    $fields[] = "$colName=?";
    $params[] = $name;
  }
  if ($colUsername && $username !== '') {
    // Check if username actually changed
    $currUname = '';
    if (in_array('username', $cols, true)) {
      $hasUpdatedAt = in_array('username_updated_at', $cols, true);
      
      $selCols = "username";
      if ($hasUpdatedAt) {
          $selCols .= ", username_updated_at";
      }
      
      try {
          $st = $pdo->prepare("SELECT $selCols FROM users WHERE $colId = ?");
          $st->execute([$viewerId]);
          $uRow = $st->fetch(PDO::FETCH_ASSOC);
          $currUname = $uRow['username'] ?? '';
          $lastUpdate = $uRow['username_updated_at'] ?? null;
    
          if ($username !== $currUname) {
            // 1. Uniqueness check
            $dup = $pdo->prepare("SELECT $colId FROM users WHERE username = ? AND $colId != ? LIMIT 1");
            $dup->execute([$username, $viewerId]);
            if ($dup->fetchColumn()) {
              json_out(400, ['status' => 'error', 'message' => 'This username is already taken']);
            }
    
            // 2. 60-day cooldown check
            if ($hasUpdatedAt && $lastUpdate) {
              $diff = time() - strtotime($lastUpdate);
              $days = floor($diff / 86400);
              if ($days < 60) {
                $rem = 60 - $days;
                json_out(400, ['status' => 'error', 'message' => "Username can only be changed once every 60 days. Wait $rem more days."]);
              }
            }
    
            $fields[] = "$colUsername=?";
            $params[] = $username;
            if ($hasUpdatedAt) {
                $fields[] = "username_updated_at=NOW()";
            } else {
                // Try to create the column
                try {
                    $pdo->exec("ALTER TABLE users ADD COLUMN username_updated_at DATETIME NULL");
                    $fields[] = "username_updated_at=NOW()";
                } catch(Throwable $ex) {}
            }
          }
      } catch (Throwable $dbErr) {
          // If query fails, just proceed to update anyway without cooldown checks
          if ($username !== $currUname) {
              $fields[] = "$colUsername=?";
              $params[] = $username;
          }
      }
    }
  }
  if ($colBio && array_key_exists('bio', $in)) {
    $fields[] = "$colBio=?";
    $params[] = $bio;
  }
  if ($colLocation && array_key_exists('location', $in)) {
    $fields[] = "$colLocation=?";
    $params[] = $location;
  }

  // ✅ Accept cover_pic updates
  $avatar = null;
  if (isset($in['avatar']))
    $avatar = trim((string)$in['avatar']);
  if ($avatar === null && isset($in['profile_pic']))
    $avatar = trim((string)$in['profile_pic']);

  $cover = null;
  if (isset($in['cover']))
    $cover = trim((string)$in['cover']);
  if ($cover === null && isset($in['cover_pic']))
    $cover = trim((string)$in['cover_pic']);
  if ($cover === null && isset($in['cover_url']))
    $cover = trim((string)$in['cover_url']);
  if ($cover === null && isset($in['cover_image']))
    $cover = trim((string)$in['cover_image']);

  if ($colAvatar && $avatar !== null) {
    $fields[] = "$colAvatar=?";
    $params[] = $avatar;
  }
  if ($colCover && $cover !== null) {
    $fields[] = "$colCover=?";
    $params[] = $cover;
  }

  if (!empty($fields)) {
    $params[] = $viewerId;
    $sql = "UPDATE users SET " . implode(", ", $fields) . " WHERE $colId=?";
    
    // START DEBUG LOG
    file_put_contents(__DIR__ . '/profile_debug.log', date('Y-m-d H:i:s') . " - UPDATE TRY:\n" . 
        "SQL: " . $sql . "\n" . 
        "PARAMS: " . print_r($params, true) . "\n", FILE_APPEND);
    // END DEBUG LOG
    
    $q = $pdo->prepare($sql);
    try {
        $q->execute($params);
        file_put_contents(__DIR__ . '/profile_debug.log', date('Y-m-d H:i:s') . " - UPDATE SUCCESS, rows: " . $q->rowCount() . "\n", FILE_APPEND);
    } catch (Exception $e) {
        file_put_contents(__DIR__ . '/profile_debug.log', date('Y-m-d H:i:s') . " - UPDATE ERROR: " . $e->getMessage() . "\n", FILE_APPEND);
    }
  }

  $allowedKeys = ['facebook', 'instagram', 'tiktok', 'youtube', 'website'];
  $filtered = [];
  foreach ($allowedKeys as $k) {
    if (array_key_exists($k, $social))
      $filtered[$k] = trim((string)$social[$k]);
  }

  if (!empty($filtered)) {
    try {
      ensure_social_links_table($pdo);
    }
    catch (Throwable $e) {
    }

    $cols2 = array_keys($filtered);
    $place = implode(",", array_fill(0, count($cols2), "?"));
    $updates = implode(",", array_map(fn($c) => "$c=VALUES($c)", $cols2));

    $sqlS = "INSERT INTO user_social_links (user_id, " . implode(",", $cols2) . ") VALUES (?, $place)
             ON DUPLICATE KEY UPDATE $updates";
    $vals = [$viewerId];
    foreach ($cols2 as $c)
      $vals[] = $filtered[$c];

    $pdo->prepare($sqlS)->execute($vals);
  }

  // return fresh profile
  $select = [$colId . " AS id"];
  if ($colName)
    $select[] = "$colName AS name";
  if ($colUsername)
    $select[] = "$colUsername AS username";
  if ($colBio)
    $select[] = "$colBio AS bio";
  if ($colLocation)
    $select[] = "$colLocation AS location";
  if ($colAvatar)
    $select[] = "$colAvatar AS avatar";
  if ($colCover)
    $select[] = "$colCover AS cover";
  if ($colCreated)
    $select[] = "$colCreated AS created_at";

  $sql2 = "SELECT " . implode(", ", $select) . " FROM users WHERE $colId = ? LIMIT 1";
  $q2 = $pdo->prepare($sql2);
  $q2->execute([$viewerId]);
  $u = $q2->fetch(PDO::FETCH_ASSOC) ?: [];

  if (!isset($u['avatar']))
    $u['avatar'] = '';
  if (!isset($u['cover']))
    $u['cover'] = '';

  $u['avatar'] = norm_url($u['avatar'], $baseUrl);
  $u['cover'] = norm_url($u['cover'], $baseUrl);

  $c = live_counts($pdo, $viewerId);
  $u['followers_count'] = $c['followers'];
  $u['following_count'] = $c['following'];
  $u['posts_count'] = $c['posts'];
  $u['followers'] = $c['followers'];
  $u['following'] = $c['following'];
  $u['total_posts'] = $c['posts'];

  $u['social_links'] = get_social_links($pdo, $viewerId);
  $u['is_following'] = 0;

  json_out(200, ['status' => 'success', 'user' => $u]);
}

json_out(405, ['status' => 'error', 'message' => 'Method not allowed']);
