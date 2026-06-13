<?php
header('Content-Type: application/json; charset=utf-8');
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Headers: Content-Type, Authorization");
header("Access-Control-Allow-Methods: GET, POST, OPTIONS");

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }

// Debug toggle (ONLY use temporarily)
$DEBUG = isset($_GET['debug']) && $_GET['debug'] == '1';
if ($DEBUG) {
  ini_set('display_errors', '1');
  error_reporting(E_ALL);
}

function out_json(int $code, array $payload): void {
  http_response_code($code);
  echo json_encode($payload);
  exit;
}

require_once __DIR__ . '/db_connect.php';
require_once __DIR__ . '/auth_middleware.php';

/**
 * ✅ DB connection compatibility:
 * Some projects use $pdo, some use $db.
 */
if (!isset($pdo) || !($pdo instanceof PDO)) {
  if (isset($db) && ($db instanceof PDO)) {
    $pdo = $db;
  }
}

// If still no PDO, try Database class (common in your project)
if (!isset($pdo) || !($pdo instanceof PDO)) {
  if (class_exists('Database')) {
    try {
      $database = new Database();
      $pdo = $database->connect();
    } catch (Throwable $e) {
      out_json(500, [
        "status" => false,
        "message" => "DB connection failed (Database->connect exception)",
        "error" => $DEBUG ? $e->getMessage() : "Enable ?debug=1"
      ]);
    }
  } else {
    out_json(500, [
      "status" => false,
      "message" => "DB connection failed (no PDO and Database class not found)",
      "hint" => "Check db_connect.php",
    ]);
  }
}

if (!($pdo instanceof PDO)) {
  out_json(500, [
    "status" => false,
    "message" => "DB connection failed (PDO not available)",
    "hint" => "Check db_connect.php returns PDO in $pdo (or $db)."
  ]);
}

function ensure_settings_schema(PDO $pdo): void {
  // DO NOT silently ignore errors: throw with clear message
  $pdo->exec("CREATE TABLE IF NOT EXISTS app_settings (
    id INT AUTO_INCREMENT PRIMARY KEY,
    setting_key VARCHAR(120) NOT NULL UNIQUE,
    setting_value TEXT NULL,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci");

  $pdo->exec("CREATE TABLE IF NOT EXISTS user_settings (
    user_id INT NOT NULL PRIMARY KEY,

    privacy_profile_visible TINYINT(1) NOT NULL DEFAULT 1,
    privacy_show_online TINYINT(1) NOT NULL DEFAULT 1,
    privacy_allow_nearby TINYINT(1) NOT NULL DEFAULT 1,

    notif_push_enabled TINYINT(1) NOT NULL DEFAULT 1,
    notif_like_enabled TINYINT(1) NOT NULL DEFAULT 1,
    notif_comment_enabled TINYINT(1) NOT NULL DEFAULT 1,
    notif_follow_enabled TINYINT(1) NOT NULL DEFAULT 1,

    discovery_enabled TINYINT(1) NOT NULL DEFAULT 1,

    privacy_allow_find_id TINYINT(1) NOT NULL DEFAULT 0,
    privacy_allow_random_video_call TINYINT(1) NOT NULL DEFAULT 0,
    privacy_allow_repost TINYINT(1) NOT NULL DEFAULT 0,
    privacy_allow_unknown_inbox TINYINT(1) NOT NULL DEFAULT 1,

    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci");
}

// ✅ Create tables (if permissions fail, you'll see the real error)
try {
  ensure_settings_schema($pdo);
} catch (Throwable $e) {
  out_json(500, [
    "status" => false,
    "message" => "Failed creating settings tables (DB permission issue?)",
    "error" => $DEBUG ? $e->getMessage() : "Enable ?debug=1"
  ]);
}

// ✅ Auth
$user = requireUser($pdo);
$uid = (int)($user['id'] ?? 0);
if ($uid <= 0) out_json(401, ["status"=>false, "message"=>"Unauthorized"]);

// ✅ Read JSON body
$raw = file_get_contents("php://input");
$j = json_decode($raw, true);
if (!is_array($j)) $j = [];

// JSON wins over POST
$data = array_merge($_POST, $j);

// ✅ action from GET/POST/JSON
$action = $_GET['action'] ?? $_POST['action'] ?? ($j['action'] ?? '');

// ✅ Fallback: if POST has toggle keys but action missing
if ($action === '' && $_SERVER['REQUEST_METHOD'] === 'POST') {
  $keys = [
    'privacy_allow_find_id',
    'privacy_allow_random_video_call',
    'privacy_allow_repost',
    'privacy_allow_unknown_inbox',
    'privacy_profile_visible',
    'privacy_show_online',
    'privacy_allow_nearby',
    'notif_push_enabled',
    'notif_like_enabled',
    'notif_comment_enabled',
    'notif_follow_enabled',
    'discovery_enabled'
  ];
  foreach ($keys as $k) {
    if (array_key_exists($k, $data)) { $action = 'user_update'; break; }
  }
}

// ✅ GET global settings
if ($action === 'global') {
  try {
    $rows = $pdo->query("SELECT setting_key, setting_value FROM app_settings")->fetchAll(PDO::FETCH_ASSOC);
  } catch (Throwable $e) {
    out_json(500, ["status"=>false, "message"=>"DB read error", "error"=>$DEBUG ? $e->getMessage() : "Enable ?debug=1"]);
  }
  $settings = [];
  foreach ($rows as $r) $settings[$r['setting_key']] = $r['setting_value'];
  out_json(200, ["status"=>true, "global"=>$settings]);
}

// ✅ GET user settings
if ($action === 'user') {
  try {
    $pdo->prepare("INSERT IGNORE INTO user_settings (user_id) VALUES (?)")->execute([$uid]);
    $st = $pdo->prepare("SELECT * FROM user_settings WHERE user_id=? LIMIT 1");
    $st->execute([$uid]);
    out_json(200, ["status"=>true, "user"=>$st->fetch(PDO::FETCH_ASSOC)]);
  } catch (Throwable $e) {
    out_json(500, ["status"=>false, "message"=>"DB error loading user settings", "error"=>$DEBUG ? $e->getMessage() : "Enable ?debug=1"]);
  }
}

// ✅ UPDATE user settings
if ($action === 'user_update') {
  $allowed = [
    'privacy_profile_visible',
    'privacy_show_online',
    'privacy_allow_nearby',
    'notif_push_enabled',
    'notif_like_enabled',
    'notif_comment_enabled',
    'notif_follow_enabled',
    'discovery_enabled',
    'privacy_allow_find_id',
    'privacy_allow_random_video_call',
    'privacy_allow_repost',
    'privacy_allow_unknown_inbox'
  ];

  // Normalize to 0/1 even if Flutter sends true/false or "true"/"false"
  $fields = [];
  $vals = [];
  foreach ($allowed as $k) {
    if (array_key_exists($k, $data)) {
      $v = $data[$k];
      $b = 0;
      if (is_bool($v)) $b = $v ? 1 : 0;
      else if (is_string($v)) {
        $vv = strtolower(trim($v));
        $b = in_array($vv, ['1','true','on','yes'], true) ? 1 : 0;
      } else {
        $b = intval($v) ? 1 : 0;
      }
      $fields[] = "$k=?";
      $vals[] = $b;
    }
  }

  try {
    $pdo->prepare("INSERT IGNORE INTO user_settings (user_id) VALUES (?)")->execute([$uid]);

    if (!empty($fields)) {
      $vals[] = $uid;
      $sql = "UPDATE user_settings SET " . implode(",", $fields) . " WHERE user_id=?";
      $pdo->prepare($sql)->execute($vals);
    }

    $st = $pdo->prepare("SELECT * FROM user_settings WHERE user_id=? LIMIT 1");
    $st->execute([$uid]);
    out_json(200, ["status"=>true, "message"=>"saved", "user"=>$st->fetch(PDO::FETCH_ASSOC)]);
  } catch (Throwable $e) {
    out_json(500, [
      "status"=>false,
      "message"=>"DB error saving user settings",
      "error"=>$DEBUG ? $e->getMessage() : "Enable ?debug=1",
      "received"=>$DEBUG ? $data : null
    ]);
  }
}

out_json(400, ["status"=>false, "message"=>"Invalid action", "action"=>$action, "hint"=>$DEBUG ? $data : null]);