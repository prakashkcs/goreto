<?php
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Content-Type, Authorization');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
  http_response_code(200);
  exit;
}

require_once __DIR__ . '/db_connect.php';
require_once __DIR__ . '/auth_middleware.php';

function out_json(int $code, array $payload): void
{
  http_response_code($code);
  echo json_encode($payload);
  exit;
}

function ensure_account_schema(PDO $pdo): void
{
  $pdo->exec("CREATE TABLE IF NOT EXISTS user_auth_tokens (
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

  $cols = [];
  try {
    $st = $pdo->query('SHOW COLUMNS FROM users');
    while ($r = $st->fetch(PDO::FETCH_ASSOC))
      $cols[] = $r['Field'];
  } catch (Throwable $e) {
  }

  if (!in_array('delete_requested_at', $cols, true)) {
    try {
      $pdo->exec('ALTER TABLE users ADD COLUMN delete_requested_at DATETIME NULL');
    } catch (Throwable $e) {
    }
  }
  if (!in_array('delete_scheduled_at', $cols, true)) {
    try {
      $pdo->exec('ALTER TABLE users ADD COLUMN delete_scheduled_at DATETIME NULL');
    } catch (Throwable $e) {
    }
  }
  if (!in_array('deactivated_until', $cols, true)) {
    try {
      $pdo->exec('ALTER TABLE users ADD COLUMN deactivated_until DATETIME NULL DEFAULT NULL');
    } catch (Throwable $e) {}
  }
  if (!in_array('deactivated_type', $cols, true)) {
    try {
      $pdo->exec("ALTER TABLE users ADD COLUMN deactivated_type ENUM('1d','7d','login') NULL DEFAULT NULL");
    } catch (Throwable $e) {}
  }
  if (!in_array('twofa_enabled', $cols, true)) {
    try { $pdo->exec('ALTER TABLE users ADD COLUMN twofa_enabled TINYINT(1) NOT NULL DEFAULT 0'); } catch (Throwable $e) {}
  }
  if (!in_array('twofa_method', $cols, true)) {
    try { $pdo->exec('ALTER TABLE users ADD COLUMN twofa_method VARCHAR(10) NULL DEFAULT NULL'); } catch (Throwable $e) {}
  }
}

ensure_account_schema($pdo);

$me = requireUser($pdo);
$meId = (int) $me['id'];

$action = $_GET['action'] ?? $_POST['action'] ?? '';

$raw = file_get_contents('php://input');
$j = json_decode($raw, true);
if (!is_array($j))
  $j = [];
$data = array_merge($_POST, $j);

$currentToken = normalize_token(getBearerToken());

// GET: me
if ($_SERVER['REQUEST_METHOD'] === 'GET' && ($action === '' || $action === 'me')) {
  out_json(200, [
    'status' => true,
    'me' => [
      'id' => $meId,
      'name' => (string) ($me['name'] ?? ''),
      'email' => (string) ($me['email'] ?? ''),
      'profile_pic' => (string) ($me['profile_pic'] ?? ''),
      'delete_requested_at' => $me['delete_requested_at'] ?? null,
      'delete_scheduled_at' => $me['delete_scheduled_at'] ?? null,
    ]
  ]);
}

// POST: change email
if ($_SERVER['REQUEST_METHOD'] === 'POST' && $action === 'change_email') {
  $newEmail = trim((string) ($data['new_email'] ?? $data['email'] ?? ''));
  $password = (string) ($data['password'] ?? '');

  if ($newEmail === '' || $password === '')
    out_json(400, ['status' => false, 'message' => 'new_email and password required']);
  if (!filter_var($newEmail, FILTER_VALIDATE_EMAIL))
    out_json(400, ['status' => false, 'message' => 'Invalid email']);

  $st = $pdo->prepare('SELECT email, password_hash FROM users WHERE id = ? LIMIT 1');
  $st->execute([$meId]);
  $row = $st->fetch(PDO::FETCH_ASSOC);
  if (!$row)
    out_json(404, ['status' => false, 'message' => 'User not found']);
  if (!password_verify($password, (string) $row['password_hash']))
    out_json(403, ['status' => false, 'message' => 'Wrong password']);

  $chk = $pdo->prepare('SELECT id FROM users WHERE email = ? AND id <> ? LIMIT 1');
  $chk->execute([$newEmail, $meId]);
  if ($chk->fetchColumn())
    out_json(409, ['status' => false, 'message' => 'Email already in use']);

  $pdo->prepare('UPDATE users SET email = ? WHERE id = ?')->execute([$newEmail, $meId]);
  out_json(200, ['status' => true, 'message' => 'Email updated', 'email' => $newEmail]);
}

// POST: change password
if ($_SERVER['REQUEST_METHOD'] === 'POST' && $action === 'change_password') {
  $current = (string) ($data['current_password'] ?? '');
  $newPass = (string) ($data['new_password'] ?? '');

  if ($current === '' || $newPass === '')
    out_json(400, ['status' => false, 'message' => 'current_password and new_password required']);
  if (strlen($newPass) < 6)
    out_json(400, ['status' => false, 'message' => 'New password too short']);

  $st = $pdo->prepare('SELECT password_hash FROM users WHERE id = ? LIMIT 1');
  $st->execute([$meId]);
  $hash = (string) ($st->fetchColumn() ?? '');
  if ($hash === '')
    out_json(404, ['status' => false, 'message' => 'User not found']);
  if (!password_verify($current, $hash))
    out_json(403, ['status' => false, 'message' => 'Wrong current password']);

  $newHash = password_hash($newPass, PASSWORD_BCRYPT);
  $pdo->prepare('UPDATE users SET password_hash = ? WHERE id = ?')->execute([$newHash, $meId]);

  // revoke all other sessions
  if (table_exists($pdo, 'user_auth_tokens')) {
    if ($currentToken) {
      $pdo->prepare('UPDATE user_auth_tokens SET revoked_at = NOW(), revoke_reason = ? WHERE user_id = ? AND token <> ? AND revoked_at IS NULL')
        ->execute(['password_changed', $meId, $currentToken]);
    } else {
      $pdo->prepare('UPDATE user_auth_tokens SET revoked_at = NOW(), revoke_reason = ? WHERE user_id = ? AND revoked_at IS NULL')
        ->execute(['password_changed', $meId]);
    }
  }

  out_json(200, ['status' => true, 'message' => 'Password updated']);
}

// GET: sessions
if ($_SERVER['REQUEST_METHOD'] === 'GET' && $action === 'sessions') {
  if (!table_exists($pdo, 'user_auth_tokens'))
    out_json(200, ['status' => true, 'sessions' => []]);

  $st = $pdo->prepare('SELECT id, token, device_name, platform, app_version, user_agent, ip_address, created_at, last_used_at, revoked_at
                       FROM user_auth_tokens WHERE user_id = ? ORDER BY created_at DESC');
  $st->execute([$meId]);
  $rows = $st->fetchAll(PDO::FETCH_ASSOC);

  $sessions = [];
  foreach ($rows as $r) {
    $sessions[] = [
      'id' => (int) $r['id'],
      'device_name' => (string) ($r['device_name'] ?? ''),
      'platform' => (string) ($r['platform'] ?? ''),
      'app_version' => (string) ($r['app_version'] ?? ''),
      'user_agent' => (string) ($r['user_agent'] ?? ''),
      'ip_address' => (string) ($r['ip_address'] ?? ''),
      'created_at' => (string) ($r['created_at'] ?? ''),
      'last_used_at' => (string) ($r['last_used_at'] ?? ''),
      'revoked_at' => (string) ($r['revoked_at'] ?? ''),
      'is_current' => ($currentToken && hash_equals($currentToken, (string) ($r['token'] ?? ''))) ? 1 : 0,
    ];
  }

  out_json(200, ['status' => true, 'sessions' => $sessions]);
}

// POST: terminate session
if ($_SERVER['REQUEST_METHOD'] === 'POST' && ($action === 'terminate_session' || $action === 'terminate')) {
  $sid = (int) ($data['session_id'] ?? $data['id'] ?? 0);
  if ($sid <= 0)
    out_json(400, ['status' => false, 'message' => 'session_id required']);
  if (!table_exists($pdo, 'user_auth_tokens'))
    out_json(400, ['status' => false, 'message' => 'Sessions not enabled']);

  $st = $pdo->prepare('UPDATE user_auth_tokens SET revoked_at = NOW(), revoke_reason = ? WHERE id = ? AND user_id = ?');
  $st->execute(['terminated_by_user', $sid, $meId]);
  out_json(200, ['status' => true, 'message' => 'Session terminated']);
}

// POST: delete account (30 days recover)
if ($_SERVER['REQUEST_METHOD'] === 'POST' && ($action === 'delete_account' || $action === 'delete_request')) {
  $password = (string) ($data['password'] ?? '');
  if ($password === '')
    out_json(400, ['status' => false, 'message' => 'Password is required. Please enter your current login password.']);

  $st = $pdo->prepare('SELECT password_hash FROM users WHERE id = ? LIMIT 1');
  $st->execute([$meId]);
  $hash = (string) ($st->fetchColumn() ?? '');
  if ($hash === '')
    out_json(404, ['status' => false, 'message' => 'User record not found. Please contact support.']);
  if (!password_verify($password, $hash)) {
    out_json(400, ['status' => false, 'message' => 'Incorrect password. Please enter the password you use to log in.']);
  }

  $pdo->prepare('UPDATE users SET delete_requested_at = NOW(), delete_scheduled_at = DATE_ADD(NOW(), INTERVAL 30 DAY) WHERE id = ?')
    ->execute([$meId]);

  // revoke all tokens
  try {
    $pdo->prepare('UPDATE users SET api_token = NULL WHERE id = ?')->execute([$meId]);
  } catch (Throwable $e) {
  }
  if (table_exists($pdo, 'user_auth_tokens')) {
    $pdo->prepare('UPDATE user_auth_tokens SET revoked_at = NOW(), revoke_reason = ? WHERE user_id = ? AND revoked_at IS NULL')
      ->execute(['account_deletion_requested', $meId]);
  }

  $when = $pdo->prepare('SELECT delete_scheduled_at FROM users WHERE id = ? LIMIT 1');
  $when->execute([$meId]);
  $ds = $when->fetchColumn();

  out_json(200, ['status' => true, 'message' => 'Account scheduled for deletion', 'delete_scheduled_at' => (string) $ds]);
}

// POST: temporarily deactivate account
if ($_SERVER['REQUEST_METHOD'] === 'POST' && $action === 'deactivate_account') {
  $period = (string) ($data['period'] ?? $_POST['period'] ?? '');
  if (!in_array($period, ['1d','7d','login'], true)) {
    out_json(400, ['status' => false, 'message' => 'Invalid period. Use 1d, 7d, or login']);
  }
  $until = null;
  if ($period === '1d')  $until = date('Y-m-d H:i:s', strtotime('+1 day'));
  if ($period === '7d')  $until = date('Y-m-d H:i:s', strtotime('+7 days'));
  // 'login' => $until stays null (reactivates on next login)
  $pdo->prepare('UPDATE users SET deactivated_until=?, deactivated_type=? WHERE id=?')
      ->execute([$until, $period, $meId]);
  out_json(200, ['status' => true, 'message' => 'Account deactivated', 'period' => $period, 'until' => $until]);
}

// POST: manually reactivate account early
if ($_SERVER['REQUEST_METHOD'] === 'POST' && $action === 'reactivate_account') {
  $pdo->prepare('UPDATE users SET deactivated_until=NULL, deactivated_type=NULL WHERE id=?')
      ->execute([$meId]);
  out_json(200, ['status' => true, 'message' => 'Account reactivated']);
}

// GET: check deactivation status
if ($_SERVER['REQUEST_METHOD'] === 'GET' && $action === 'deactivation_status') {
  $st = $pdo->prepare('SELECT deactivated_until, deactivated_type FROM users WHERE id=? LIMIT 1');
  $st->execute([$meId]);
  $row = $st->fetch(PDO::FETCH_ASSOC);
  out_json(200, ['status' => true, 'deactivated_until' => $row['deactivated_until'], 'deactivated_type' => $row['deactivated_type']]);
}

// POST: enable 2FA (email OTP)
if ($_SERVER['REQUEST_METHOD'] === 'POST' && $action === 'enable_2fa') {
  $password = (string) ($data['password'] ?? '');
  if ($password === '')
    out_json(400, ['status' => false, 'message' => 'Password is required']);
  $st = $pdo->prepare('SELECT password_hash, email, name FROM users WHERE id = ? LIMIT 1');
  $st->execute([$meId]);
  $row = $st->fetch(PDO::FETCH_ASSOC);
  if (!$row) out_json(404, ['status' => false, 'message' => 'User not found']);
  if (!password_verify($password, (string) $row['password_hash']))
    out_json(403, ['status' => false, 'message' => 'Wrong password']);
  $pdo->prepare("UPDATE users SET twofa_enabled = 1, twofa_method = 'email' WHERE id = ?")->execute([$meId]);
  try {
    require_once __DIR__ . '/email_helper.php';
    (new EmailHelper())->send((string) $row['email'], 'Two-factor authentication enabled',
      '<p>Two-factor authentication (email codes) is now enabled on your Goreto account. You will be asked for a code from this email each time you sign in.</p>');
  } catch (Throwable $e) {}
  out_json(200, ['status' => true, 'message' => '2FA enabled', 'enabled' => true, 'method' => 'email']);
}

// POST: disable 2FA
if ($_SERVER['REQUEST_METHOD'] === 'POST' && $action === 'disable_2fa') {
  $password = (string) ($data['password'] ?? '');
  if ($password === '')
    out_json(400, ['status' => false, 'message' => 'Password is required']);
  $st = $pdo->prepare('SELECT password_hash FROM users WHERE id = ? LIMIT 1');
  $st->execute([$meId]);
  $hash = (string) ($st->fetchColumn() ?? '');
  if ($hash === '') out_json(404, ['status' => false, 'message' => 'User not found']);
  if (!password_verify($password, $hash))
    out_json(403, ['status' => false, 'message' => 'Wrong password']);
  $pdo->prepare('UPDATE users SET twofa_enabled = 0, twofa_method = NULL WHERE id = ?')->execute([$meId]);
  out_json(200, ['status' => true, 'message' => '2FA disabled', 'enabled' => false]);
}

// GET: 2FA status
if ($_SERVER['REQUEST_METHOD'] === 'GET' && $action === 'get_2fa_status') {
  $st = $pdo->prepare('SELECT COALESCE(twofa_enabled,0) AS e, twofa_method AS m FROM users WHERE id = ? LIMIT 1');
  $st->execute([$meId]);
  $r = $st->fetch(PDO::FETCH_ASSOC) ?: ['e' => 0, 'm' => null];
  out_json(200, ['status' => true, 'enabled' => ((int) $r['e'] === 1), 'method' => $r['m']]);
}

out_json(400, ['status' => false, 'message' => 'Invalid action']);