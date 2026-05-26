<?php
// auth.php (FULL FIXED VERSION)

header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
  http_response_code(200);
  exit;
}

$raw = file_get_contents("php://input");
$data = json_decode($raw);
if (!$data)
  $data = (object)[];

$action = $_GET['action'] ?? $_POST['action'] ?? $data->action ?? '';

include_once 'db_connect.php';

function ensure_auth_schema(PDO $db): void
{
  try {
    $db->exec("CREATE TABLE IF NOT EXISTS user_auth_tokens (
      id BIGINT AUTO_INCREMENT PRIMARY KEY,
      user_id INT NOT NULL,
      token VARCHAR(64) NOT NULL,
      device_name VARCHAR(100) DEFAULT NULL,
      platform VARCHAR(20) DEFAULT NULL,
      app_version VARCHAR(30) DEFAULT NULL,
      user_agent VARCHAR(255) DEFAULT NULL,
      ip_address VARCHAR(45) DEFAULT NULL,
      created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
      last_used_at DATETIME DEFAULT NULL,
      revoked_at DATETIME DEFAULT NULL,
      revoke_reason VARCHAR(255) DEFAULT NULL,
      UNIQUE KEY uniq_token (token),
      KEY idx_user (user_id),
      KEY idx_user_revoked (user_id, revoked_at)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci");
  }
  catch (Throwable $e) {
  }

  $cols = [];
  try {
    $st = $db->query('SHOW COLUMNS FROM users');
    while ($r = $st->fetch(PDO::FETCH_ASSOC))
      $cols[] = $r['Field'];
  }
  catch (Throwable $e) {
  }

  if (!in_array('delete_requested_at', $cols, true)) {
    try {
      $db->exec('ALTER TABLE users ADD COLUMN delete_requested_at DATETIME NULL');
    }
    catch (Throwable $e) {
    }
  }
  if (!in_array('delete_scheduled_at', $cols, true)) {
    try {
      $db->exec('ALTER TABLE users ADD COLUMN delete_scheduled_at DATETIME NULL');
    }
    catch (Throwable $e) {
    }
  }
}

function users_cols(PDO $db): array
{
  $cols = [];
  try {
    $st = $db->query('SHOW COLUMNS FROM users');
    while ($r = $st->fetch(PDO::FETCH_ASSOC))
      $cols[] = $r['Field'];
  }
  catch (Throwable $e) {
  }
  return $cols;
}

function issue_token(PDO $db, int $userId): string
{
  $token = bin2hex(random_bytes(32));

  // legacy token still updated (compat)
  try {
    $db->prepare('UPDATE users SET api_token = :token WHERE id = :id')
      ->execute([":token" => $token, ":id" => $userId]);
  }
  catch (Throwable $e) {
  }

  // multi-device sessions
  try {
    $device = $_SERVER['HTTP_X_DEVICE_NAME'] ?? ($_SERVER['HTTP_X_DEVICE'] ?? null);
    $platform = $_SERVER['HTTP_X_PLATFORM'] ?? null;
    $appVersion = $_SERVER['HTTP_X_APP_VERSION'] ?? null;
    $ua = $_SERVER['HTTP_USER_AGENT'] ?? null;
    $ip = $_SERVER['REMOTE_ADDR'] ?? null;

    $db->prepare('INSERT INTO user_auth_tokens (user_id, token, device_name, platform, app_version, user_agent, ip_address, created_at, last_used_at)
                  VALUES (?,?,?,?,?,?,?,?,NOW())')
      ->execute([$userId, $token, $device, $platform, $appVersion, $ua, $ip, date('Y-m-d H:i:s')]);
  }
  catch (Throwable $e) {
  }

  return $token;
}

try {
  $database = new Database();
  $db = $database->connect();

  ensure_auth_schema($db);

  // REGISTER
  if ($action === 'register') {
    if (!isset($data->name) || !isset($data->email) || !isset($data->password)) {
      echo json_encode(["status" => "error", "message" => "Missing required fields"]);
      exit;
    }

    $name = htmlspecialchars(strip_tags($data->name));
    $email = htmlspecialchars(strip_tags($data->email));
    $pass = password_hash($data->password, PASSWORD_BCRYPT);

    $check = $db->prepare("SELECT id FROM users WHERE email = ?");
    $check->execute([$email]);
    if ($check->rowCount() > 0) {
      echo json_encode(["status" => "error", "message" => "Email already exists"]);
      exit;
    }

    $stmt = $db->prepare("INSERT INTO users (name, email, password_hash) VALUES (:name, :email, :pass)");
    $ok = $stmt->execute([':name' => $name, ':email' => $email, ':pass' => $pass]);

    echo json_encode($ok
      ? ["status" => "success", "message" => "User registered successfully"]
      : ["status" => "error", "message" => "Registration failed"]
    );
    exit;
  }

  // LOGIN
  if ($action === 'login') {
    if (!isset($data->email) || !isset($data->password)) {
      echo json_encode(["status" => "error", "message" => "Missing credentials"]);
      exit;
    }

    $email = htmlspecialchars(strip_tags($data->email));
    $password = $data->password;

    $cols = users_cols($db);
    $hasDel = in_array('delete_requested_at', $cols, true) && in_array('delete_scheduled_at', $cols, true);

    $sel = 'id, name, email, password_hash, profile_pic, subscription_status';
    if ($hasDel)
      $sel .= ', delete_requested_at, delete_scheduled_at';

    $stmt = $db->prepare("SELECT $sel FROM users WHERE email = :email");
    $stmt->execute([':email' => $email]);
    $user = $stmt->fetch(PDO::FETCH_ASSOC);

    if ($user && password_verify($password, $user['password_hash'])) {
      // If pending deletion, do NOT login (app can show recover)
      if ($hasDel && !empty($user['delete_requested_at']) && !empty($user['delete_scheduled_at'])) {
        try {
          $now = new DateTime('now');
          $sched = new DateTime((string)$user['delete_scheduled_at']);
          if ($sched > $now) {
            echo json_encode([
              'status' => 'pending_delete',
              'message' => 'Account scheduled for deletion. You can recover within 30 days.',
              'delete_scheduled_at' => (string)$user['delete_scheduled_at'],
              'can_restore' => true
            ]);
            exit;
          }
        }
        catch (Throwable $e) {
        }
      }

      $token = issue_token($db, (int)$user['id']);
      unset($user['password_hash']);

      echo json_encode([
        "status" => "success",
        "data" => ["token" => $token, "user" => $user]
      ]);
      exit;
    }

    http_response_code(401);
    echo json_encode(["status" => "error", "message" => "Invalid credentials"]);
    exit;
  }

  // GOOGLE LOGIN
  if ($action === 'google') {
    if (!isset($data->id_token) || empty($data->id_token)) {
      echo json_encode(["status" => "error", "message" => "Missing id_token"]);
      exit;
    }

    $verifyUrl = "https://oauth2.googleapis.com/tokeninfo?id_token=" . urlencode($data->id_token);
    $resp = @file_get_contents($verifyUrl);
    if ($resp === false) {
      http_response_code(401);
      echo json_encode(["status" => "error", "message" => "Failed to verify Google token"]);
      exit;
    }

    $tokenInfo = json_decode($resp, true);
    if (!isset($tokenInfo["email"])) {
      http_response_code(401);
      echo json_encode(["status" => "error", "message" => "Invalid Google token"]);
      exit;
    }

    $email = $tokenInfo["email"];
    $name = $tokenInfo["name"] ?? "Google User";
    $picture = $tokenInfo["picture"] ?? null;

    $cols = users_cols($db);
    $hasDel = in_array('delete_requested_at', $cols, true) && in_array('delete_scheduled_at', $cols, true);

    $sel = 'id, name, email, profile_pic, subscription_status';
    if ($hasDel)
      $sel .= ', delete_requested_at, delete_scheduled_at';

    $stmt = $db->prepare("SELECT $sel FROM users WHERE email = :email");
    $stmt->execute([":email" => $email]);
    $user = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!$user) {
      $randomPass = password_hash(bin2hex(random_bytes(16)), PASSWORD_BCRYPT);
      $db->prepare("INSERT INTO users (name, email, password_hash, profile_pic) VALUES (:name,:email,:pass,:pic)")
        ->execute([":name" => $name, ":email" => $email, ":pass" => $randomPass, ":pic" => $picture]);

      $newId = (int)$db->lastInsertId();
      $stmt = $db->prepare("SELECT id, name, email, profile_pic FROM users WHERE id = :id");
      $stmt->execute([":id" => $newId]);
      $user = $stmt->fetch(PDO::FETCH_ASSOC);
    }

    // If pending deletion, auto-restore for Google users
    if ($hasDel && !empty($user['delete_requested_at']) && !empty($user['delete_scheduled_at'])) {
      try {
        $db->prepare('UPDATE users SET delete_requested_at = NULL, delete_scheduled_at = NULL WHERE id = ?')
          ->execute([(int)$user['id']]);
      }
      catch (Throwable $e) {
      }
    }

    $token = issue_token($db, (int)$user['id']);

    echo json_encode([
      "status" => "success",
      "data" => ["token" => $token, "user" => $user]
    ]);
    exit;
  }

  // UPDATE FCM TOKEN
  if ($action === 'update_fcm_token') {
    // Debug sync attempts
    file_put_contents('fcm_sync_debug.log', date('[Y-m-d H:i:s] ') . "Sync attempt for action: $action\n", FILE_APPEND);

    $headers = function_exists('getallheaders') ? getallheaders() : [];
    $authHeader = $headers['Authorization'] ?? $headers['authorization'] ?? $_SERVER['HTTP_AUTHORIZATION'] ?? $_SERVER['REDIRECT_HTTP_AUTHORIZATION'] ?? '';
    $token = trim(str_replace('Bearer', '', $authHeader));

    if (empty($token)) {
      file_put_contents('fcm_sync_debug.log', "  Error: No auth header found\n", FILE_APPEND);
      http_response_code(401);
      echo json_encode(['status' => 'error', 'message' => 'Unauthorized']);
      exit;
    }

    // Check legacy api_token column first
    $stmt = $db->prepare('SELECT id FROM users WHERE api_token = ?');
    $stmt->execute([$token]);
    $user = $stmt->fetch(PDO::FETCH_ASSOC);

    // If not found, check user_auth_tokens table
    if (!$user) {
      $stmt = $db->prepare('SELECT user_id as id FROM user_auth_tokens WHERE token = ? AND revoked_at IS NULL');
      $stmt->execute([$token]);
      $user = $stmt->fetch(PDO::FETCH_ASSOC);
    }

    if (!$user) {
      http_response_code(401);
      echo json_encode(['status' => 'error', 'message' => 'Invalid token']);
      exit;
    }

    $fcmToken = $_POST['fcm_token'] ?? $data->fcm_token ?? '';

    if (!empty($fcmToken)) {
      $db->prepare('UPDATE users SET fcm_token = ? WHERE id = ?')->execute([$fcmToken, $user['id']]);
      echo json_encode(['status' => 'success', 'message' => 'FCM token updated']);
    }
    else {
      echo json_encode(['status' => 'error', 'message' => 'No FCM token provided']);
    }
    exit;
  }

  // RESTORE (cancel deletion + issue token)
  if ($action === 'restore') {
    if (!isset($data->email) || !isset($data->password)) {
      echo json_encode(["status" => "error", "message" => "Missing credentials"]);
      exit;
    }

    $email = htmlspecialchars(strip_tags($data->email));
    $password = $data->password;

    $cols = users_cols($db);
    $hasDel = in_array('delete_requested_at', $cols, true) && in_array('delete_scheduled_at', $cols, true);

    $sel = 'id, name, email, password_hash, profile_pic, subscription_status';
    if ($hasDel)
      $sel .= ', delete_requested_at, delete_scheduled_at';

    $stmt = $db->prepare("SELECT $sel FROM users WHERE email = :email");
    $stmt->execute([':email' => $email]);
    $user = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!$user || !password_verify($password, $user['password_hash'])) {
      http_response_code(401);
      echo json_encode(["status" => "error", "message" => "Invalid credentials"]);
      exit;
    }

    if ($hasDel) {
      $db->prepare('UPDATE users SET delete_requested_at = NULL, delete_scheduled_at = NULL WHERE id = ?')
        ->execute([(int)$user['id']]);
    }

    $token = issue_token($db, (int)$user['id']);
    unset($user['password_hash']);

    echo json_encode(['status' => 'success', 'data' => ['token' => $token, 'user' => $user]]);
    exit;
  }

  http_response_code(400);
  echo json_encode(["status" => "error", "message" => "Invalid action"]);
  exit;

}
catch (Exception $e) {
  http_response_code(500);
  echo json_encode(["status" => "error", "message" => "Server error", "details" => $e->getMessage()]);
  exit;
}