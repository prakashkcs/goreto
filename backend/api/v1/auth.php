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
  $data = (object) [];

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
  } catch (Throwable $e) {
  }

  $cols = [];
  try {
    $st = $db->query('SHOW COLUMNS FROM users');
    while ($r = $st->fetch(PDO::FETCH_ASSOC))
      $cols[] = $r['Field'];
  } catch (Throwable $e) {
  }

  if (!in_array('username', $cols, true)) {
    try {
      $db->exec('ALTER TABLE users ADD COLUMN username VARCHAR(100) NULL UNIQUE');
    } catch (Throwable $e) {
    }
  }
  if (!in_array('delete_requested_at', $cols, true)) {
    try {
      $db->exec('ALTER TABLE users ADD COLUMN delete_requested_at DATETIME NULL');
    } catch (Throwable $e) {
    }
  }
  if (!in_array('delete_scheduled_at', $cols, true)) {
    try {
      $db->exec('ALTER TABLE users ADD COLUMN delete_scheduled_at DATETIME NULL');
    } catch (Throwable $e) {
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
  } catch (Throwable $e) {
  }
  return $cols;
}

function append_ban_select(string $sel, array $cols): string
{
  if (in_array('is_banned', $cols, true)) {
    $sel .= ', is_banned';
    $sel .= in_array('ban_reason', $cols, true) ? ', ban_reason' : ", '' AS ban_reason";
    $sel .= in_array('banned_at', $cols, true) ? ', banned_at' : ', NULL AS banned_at';
  } else {
    $sel .= ', 0 AS is_banned, "" AS ban_reason, NULL AS banned_at';
  }
  return $sel;
}

function issue_token(PDO $db, int $userId): string
{
  $token = bin2hex(random_bytes(32));

  // legacy token still updated (compat)
  try {
    $db->prepare('UPDATE users SET api_token = :token WHERE id = :id')
      ->execute([":token" => $token, ":id" => $userId]);
  } catch (Throwable $e) {
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
  } catch (Throwable $e) {
  }

  return $token;
}

try {
  $database = new Database();
  $db = $database->connect();

  ensure_auth_schema($db);

  // VALIDATE — lightweight token check called on every cold start
  // GET /auth.php?action=validate  with  Authorization: Bearer <token>
  if ($action === 'validate') {
    $authHeader = $_SERVER['HTTP_AUTHORIZATION'] ?? '';
    $token = '';
    if (preg_match('/Bearer\s+(.+)/i', $authHeader, $m)) {
      $token = trim($m[1]);
    }
    if ($token === '') {
      http_response_code(401);
      echo json_encode(['status' => 'error', 'message' => 'No token']);
      exit;
    }

    // Check user_auth_tokens table first (multi-device sessions)
    try {
      $st = $db->prepare(
        'SELECT t.user_id, u.is_banned
           FROM user_auth_tokens t
           JOIN users u ON u.id = t.user_id
          WHERE t.token = ? AND t.revoked_at IS NULL
          LIMIT 1'
      );
      $st->execute([$token]);
      $row = $st->fetch(PDO::FETCH_ASSOC);
    } catch (Throwable $e) {
      $row = false;
    }

    // Fallback: legacy api_token column
    if (!$row) {
      try {
        $st = $db->prepare('SELECT id AS user_id, is_banned FROM users WHERE api_token = ? LIMIT 1');
        $st->execute([$token]);
        $row = $st->fetch(PDO::FETCH_ASSOC);
      } catch (Throwable $e) {
        $row = false;
      }
    }

    if (!$row) {
      http_response_code(401);
      echo json_encode(['status' => 'error', 'message' => 'Invalid token']);
      exit;
    }

    if (!empty($row['is_banned'])) {
      http_response_code(403);
      echo json_encode(['status' => 'error', 'message' => 'Account banned']);
      exit;
    }

    // Touch last_used_at (fire-and-forget, ignore errors)
    try {
      $db->prepare('UPDATE user_auth_tokens SET last_used_at = NOW() WHERE token = ?')
        ->execute([$token]);
    } catch (Throwable $e) {
    }

    echo json_encode(['status' => 'success', 'user_id' => (int) $row['user_id']]);
    exit;
  }

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

    // Generate unique username (5-15 chars)
    $baseUname = preg_replace('/[^a-zA-Z0-9]/', '', strtolower($name));
    if (strlen($baseUname) < 5)
      $baseUname = str_pad($baseUname, 5, 'u');
    if (strlen($baseUname) > 10)
      $baseUname = substr($baseUname, 0, 10);

    $username = '';
    for ($i = 0; $i < 20; $i++) {
      $temp = $baseUname . rand(100, 9999);
      if (strlen($temp) > 15)
        $temp = substr($temp, 0, 15);
      $chk = $db->prepare("SELECT id FROM users WHERE username = ?");
      $chk->execute([$temp]);
      if ($chk->rowCount() === 0) {
        $username = $temp;
        break;
      }
    }
    if (!$username)
      $username = substr($baseUname, 0, 5) . time();

    // Ensure username_updated_at exists
    try {
      $db->exec("ALTER TABLE users ADD COLUMN IF NOT EXISTS username_updated_at DATETIME DEFAULT NULL");
    } catch (Throwable $e) {
    }

    $stmt = $db->prepare("INSERT INTO users (name, email, username, password_hash) VALUES (:name, :email, :uname, :pass)");
    $ok = $stmt->execute([':name' => $name, ':email' => $email, ':uname' => $username, ':pass' => $pass]);

    if ($ok) {
      $newId = (int) $db->lastInsertId();

      // Fetch the newly created user without the password hash
      $cols = users_cols($db);
      $hasDel = in_array('delete_requested_at', $cols, true) && in_array('delete_scheduled_at', $cols, true);
      $sel = 'id, name, email, username, profile_pic, subscription_status';
      $sel = append_ban_select($sel, $cols);
      if ($hasDel)
        $sel .= ', delete_requested_at, delete_scheduled_at';

      $userStmt = $db->prepare("SELECT $sel FROM users WHERE id = :id");
      $userStmt->execute([':id' => $newId]);
      $user = $userStmt->fetch(PDO::FETCH_ASSOC);

      $token = issue_token($db, $newId);

      echo json_encode([
        "status" => "success",
        "message" => "User registered successfully",
        "data" => ["token" => $token, "user" => $user]
      ]);
    } else {
      echo json_encode(["status" => "error", "message" => "Registration failed"]);
    }
    exit;
  }

  // LOGIN
  if ($action === 'verify_2fa') {
    $email = isset($data->email) ? htmlspecialchars(strip_tags($data->email)) : '';
    $code = isset($data->code) ? trim((string) $data->code) : '';
    if ($email === '' || $code === '') { echo json_encode(['status' => 'error', 'message' => 'Email and code are required']); exit; }
    $cols = users_cols($db);
    $sel = 'id, name, email, username, profile_pic, subscription_status';
    $sel = append_ban_select($sel, $cols);
    $stmt = $db->prepare("SELECT $sel FROM users WHERE email = :email");
    $stmt->execute([':email' => $email]);
    $user = $stmt->fetch(PDO::FETCH_ASSOC);
    if (!$user) { echo json_encode(['status' => 'error', 'message' => 'Invalid code']); exit; }
    if ((int) ($user['is_banned'] ?? 0) === 1) { http_response_code(403); echo json_encode(['status' => 'banned', 'message' => 'Your account has been banned.']); exit; }
    $st = $db->prepare('SELECT id FROM twofa_otps WHERE user_id = ? AND code = ? AND used_at IS NULL AND expires_at > UTC_TIMESTAMP() ORDER BY created_at DESC LIMIT 1');
    $st->execute([(int) $user['id'], $code]);
    $otp = $st->fetch(PDO::FETCH_ASSOC);
    if (!$otp) { echo json_encode(['status' => 'error', 'message' => 'Invalid or expired code']); exit; }
    $db->prepare('UPDATE twofa_otps SET used_at = NOW() WHERE id = ?')->execute([(int) $otp['id']]);
    $token = issue_token($db, (int) $user['id']);
    echo json_encode(['status' => 'success', 'data' => ['token' => $token, 'user' => $user]]);
    exit;
  }

  if ($action === 'login') {
    if (!isset($data->email) || !isset($data->password)) {
      echo json_encode(["status" => "error", "message" => "Missing credentials"]);
      exit;
    }

    $email = htmlspecialchars(strip_tags($data->email));
    $password = $data->password;

    $cols = users_cols($db);
    $hasDel = in_array('delete_requested_at', $cols, true) && in_array('delete_scheduled_at', $cols, true);

    $sel = 'id, name, email, username, password_hash, profile_pic, subscription_status';
    $sel = append_ban_select($sel, $cols);
    if ($hasDel)
      $sel .= ', delete_requested_at, delete_scheduled_at';
    if (in_array('deactivated_type', $cols, true))
      $sel .= ', deactivated_type, deactivated_until';
    if (in_array('twofa_enabled', $cols, true))
      $sel .= ', twofa_enabled';

    $stmt = $db->prepare("SELECT $sel FROM users WHERE email = :email");
    $stmt->execute([':email' => $email]);
    $user = $stmt->fetch(PDO::FETCH_ASSOC);

    if ($user && password_verify($password, $user['password_hash'])) {
      if ((int) ($user['is_banned'] ?? 0) === 1) {
        http_response_code(403);
        echo json_encode([
          'status' => 'banned',
          'message' => 'Your account has been banned.',
          'ban_reason' => $user['ban_reason'] ?? '',
          'banned_at' => $user['banned_at'] ?? ''
        ]);
        exit;
      }

      // If pending deletion, do NOT login (app can show recover)
      if ($hasDel && !empty($user['delete_requested_at']) && !empty($user['delete_scheduled_at'])) {
        try {
          $now = new DateTime('now');
          $sched = new DateTime((string) $user['delete_scheduled_at']);
          if ($sched > $now) {
            echo json_encode([
              'status' => 'pending_delete',
              'message' => 'Account scheduled for deletion. You can recover within 30 days.',
              'delete_scheduled_at' => (string) $user['delete_scheduled_at'],
              'can_restore' => true
            ]);
            exit;
          }
        } catch (Throwable $e) {
        }
      }

      try {
        if (!empty($user['deactivated_type'])) {
          $db->prepare('UPDATE users SET deactivated_until=NULL, deactivated_type=NULL WHERE id=?')->execute([(int) $user['id']]);
        }
      } catch (Throwable $e) {}

      if (in_array('twofa_enabled', $cols, true) && (int) ($user['twofa_enabled'] ?? 0) === 1) {
        try {
          $db->exec("CREATE TABLE IF NOT EXISTS twofa_otps (id INT AUTO_INCREMENT PRIMARY KEY, user_id INT NOT NULL, email VARCHAR(255) NOT NULL, code VARCHAR(10) NOT NULL, expires_at DATETIME NOT NULL, used_at DATETIME DEFAULT NULL, created_at DATETIME DEFAULT CURRENT_TIMESTAMP, INDEX idx_user (user_id), INDEX idx_email (email)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
          $db->prepare('UPDATE twofa_otps SET used_at = NOW() WHERE user_id = ? AND used_at IS NULL')->execute([(int) $user['id']]);
          $otpCode = str_pad((string) random_int(0, 999999), 6, '0', STR_PAD_LEFT);
          $db->prepare('INSERT INTO twofa_otps (user_id, email, code, expires_at) VALUES (?,?,?, DATE_ADD(UTC_TIMESTAMP(), INTERVAL 10 MINUTE))')->execute([(int) $user['id'], $user['email'], $otpCode]);
          require_once __DIR__ . '/email_helper.php';
          (new EmailHelper())->sendOtp((string) $user['email'], $otpCode, (string) ($user['name'] ?? ''), 'sign in');
        } catch (Throwable $e) { error_log('2FA send error: ' . $e->getMessage()); }
        echo json_encode(['status' => '2fa_required', 'message' => 'Enter the 6-digit code we emailed you.', 'email' => $user['email']]);
        exit;
      }

      $token = issue_token($db, (int) $user['id']);
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
    $ch = curl_init($verifyUrl);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_TIMEOUT, 10);
    curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, true);
    $resp = curl_exec($ch);
    $curlError = curl_error($ch);
    $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);
    if ($resp === false || $httpCode !== 200) {
      http_response_code(401);
      echo json_encode(["status" => "error", "message" => "Failed to verify Google token" . ($curlError ? ": $curlError" : "")]);
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
    $googleSub = isset($tokenInfo["sub"]) ? (string) $tokenInfo["sub"] : null;

    $cols = users_cols($db);
    $hasDel = in_array('delete_requested_at', $cols, true) && in_array('delete_scheduled_at', $cols, true);

    if (!in_array('google_sub', $cols, true)) {
      try { $db->exec("ALTER TABLE users ADD COLUMN google_sub VARCHAR(64) NULL"); $cols[] = 'google_sub'; } catch (Throwable $e) {}
    }
    if (!in_array('google_email', $cols, true)) {
      try { $db->exec("ALTER TABLE users ADD COLUMN google_email VARCHAR(255) NULL"); $cols[] = 'google_email'; } catch (Throwable $e) {}
    }
    $hasSub = in_array('google_sub', $cols, true);
    $hasGEmail = in_array('google_email', $cols, true);
    $googleEmail = $email; // immutable Google address; survives account-email changes
    $sel = 'id, name, email, username, profile_pic, subscription_status';
    if ($hasDel)
      $sel .= ', delete_requested_at, delete_scheduled_at';
    if (in_array('deactivated_type', $cols, true))
      $sel .= ', deactivated_type, deactivated_until';
    if (in_array('twofa_enabled', $cols, true))
      $sel .= ', twofa_enabled';

    // Resolve account by stable Google identity (sub -> google_email -> email)
    // so changing the account email never spawns a duplicate.
    $user = null;
    if ($hasSub && $googleSub) {
      $stmt = $db->prepare("SELECT $sel FROM users WHERE google_sub = :sub LIMIT 1");
      $stmt->execute([":sub" => $googleSub]);
      $user = $stmt->fetch(PDO::FETCH_ASSOC) ?: null;
    }
    if (!$user && $hasGEmail) {
      $stmt = $db->prepare("SELECT $sel FROM users WHERE google_email = :gem LIMIT 1");
      $stmt->execute([":gem" => $googleEmail]);
      $user = $stmt->fetch(PDO::FETCH_ASSOC) ?: null;
    }
    if (!$user) {
      $stmt = $db->prepare("SELECT $sel FROM users WHERE email = :email LIMIT 1");
      $stmt->execute([":email" => $email]);
      $user = $stmt->fetch(PDO::FETCH_ASSOC) ?: null;
    }
    if ($user) {
      try {
        $db->prepare("UPDATE users SET google_sub = COALESCE(NULLIF(google_sub, ''), ?), google_email = COALESCE(NULLIF(google_email, ''), ?) WHERE id = ?")->execute([$googleSub, $googleEmail, (int) $user['id']]);
      } catch (Throwable $e) {}
    }
    $isNewUser = !$user; // true when no existing account found

    if (!$user) {
      $randomPass = password_hash(bin2hex(random_bytes(16)), PASSWORD_BCRYPT);

      // Generate unique username (5-15 chars)
      $baseUname = preg_replace('/[^a-zA-Z0-9]/', '', strtolower($name));
      if (strlen($baseUname) < 5)
        $baseUname = str_pad($baseUname, 5, 'u');
      if (strlen($baseUname) > 10)
        $baseUname = substr($baseUname, 0, 10);

      $username = '';
      for ($i = 0; $i < 20; $i++) {
        $temp = $baseUname . rand(100, 9999);
        if (strlen($temp) > 15)
          $temp = substr($temp, 0, 15);
        $chk = $db->prepare("SELECT id FROM users WHERE username = ?");
        $chk->execute([$temp]);
        if ($chk->rowCount() === 0) {
          $username = $temp;
          break;
        }
      }
      if (!$username)
        $username = substr($baseUname, 0, 5) . time();

      $db->prepare("INSERT INTO users (name, email, username, password_hash, profile_pic) VALUES (:name,:email,:uname,:pass,:pic)")
        ->execute([":name" => $name, ":email" => $email, ":uname" => $username, ":pass" => $randomPass, ":pic" => $picture]);

      $newId = (int) $db->lastInsertId();
      try { $db->prepare("UPDATE users SET google_sub = ?, google_email = ? WHERE id = ?")->execute([$googleSub, $googleEmail, $newId]); } catch (Throwable $e) {}
      $stmt = $db->prepare("SELECT id, name, email, profile_pic FROM users WHERE id = :id");
      $stmt->execute([":id" => $newId]);
      $user = $stmt->fetch(PDO::FETCH_ASSOC);
    }

    // If pending deletion, auto-restore for Google users
    if ($hasDel && !empty($user['delete_requested_at']) && !empty($user['delete_scheduled_at'])) {
      try {
        $db->prepare('UPDATE users SET delete_requested_at = NULL, delete_scheduled_at = NULL WHERE id = ?')
          ->execute([(int) $user['id']]);
      } catch (Throwable $e) {
      }
    }

    if (!$isNewUser && in_array('twofa_enabled', $cols, true) && (int) ($user['twofa_enabled'] ?? 0) === 1) {
      try {
        $db->exec("CREATE TABLE IF NOT EXISTS twofa_otps (id INT AUTO_INCREMENT PRIMARY KEY, user_id INT NOT NULL, email VARCHAR(255) NOT NULL, code VARCHAR(10) NOT NULL, expires_at DATETIME NOT NULL, used_at DATETIME DEFAULT NULL, created_at DATETIME DEFAULT CURRENT_TIMESTAMP, INDEX idx_user (user_id), INDEX idx_email (email)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
        $db->prepare('UPDATE twofa_otps SET used_at = NOW() WHERE user_id = ? AND used_at IS NULL')->execute([(int) $user['id']]);
        $otpCode = str_pad((string) random_int(0, 999999), 6, '0', STR_PAD_LEFT);
        $db->prepare('INSERT INTO twofa_otps (user_id, email, code, expires_at) VALUES (?,?,?, DATE_ADD(UTC_TIMESTAMP(), INTERVAL 10 MINUTE))')->execute([(int) $user['id'], $user['email'], $otpCode]);
        require_once __DIR__ . '/email_helper.php';
        (new EmailHelper())->sendOtp((string) $user['email'], $otpCode, (string) ($user['name'] ?? ''), 'sign in');
      } catch (Throwable $e) { error_log('2FA(google) send error: ' . $e->getMessage()); }
      echo json_encode(['status' => '2fa_required', 'message' => 'Enter the 6-digit code we emailed you.', 'email' => $user['email']]);
      exit;
    }

    $token = issue_token($db, (int) $user['id']);

    echo json_encode([
      "status" => "success",
      "is_new_user" => $isNewUser,
      "data" => ["token" => $token, "user" => $user]
    ]);
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
        ->execute([(int) $user['id']]);
    }

    $token = issue_token($db, (int) $user['id']);
    unset($user['password_hash']);

    echo json_encode(['status' => 'success', 'data' => ['token' => $token, 'user' => $user]]);
    exit;
  }

  http_response_code(400);
  echo json_encode(["status" => "error", "message" => "Invalid action"]);
  exit;

} catch (Exception $e) {
  http_response_code(500);
  echo json_encode(["status" => "error", "message" => "Server error", "details" => $e->getMessage()]);
  exit;
}