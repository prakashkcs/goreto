<?php
error_reporting(0);
ini_set('display_errors', 0);

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Content-Type, Authorization');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
  http_response_code(200);
  echo json_encode(['status' => 'success']);
  exit;
}

function ref_json(int $code, array $data): void
{
  http_response_code($code);
  echo json_encode($data, JSON_UNESCAPED_UNICODE);
  exit;
}

require_once __DIR__ . '/db_connect.php';
require_once __DIR__ . '/auth_middleware.php';

// Ensure tables exist (safe to run every request)
$pdo->exec("CREATE TABLE IF NOT EXISTS referral_settings (
  id INT AUTO_INCREMENT PRIMARY KEY,
  setting_key VARCHAR(80) NOT NULL UNIQUE,
  setting_value VARCHAR(500) NOT NULL DEFAULT '',
  updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

$pdo->exec("CREATE TABLE IF NOT EXISTS referral_claims (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  claimer_user_id INT NOT NULL,
  referrer_user_id INT NOT NULL,
  referral_code VARCHAR(50) NOT NULL,
  coins_awarded INT NOT NULL DEFAULT 0,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_claimer (claimer_user_id),
  INDEX idx_referrer (referrer_user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

$pdo->exec("CREATE TABLE IF NOT EXISTS user_activity_log (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  user_id INT NOT NULL,
  activity_date DATE NOT NULL,
  open_count INT NOT NULL DEFAULT 1,
  total_seconds INT NOT NULL DEFAULT 0,
  updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uq_user_date (user_id, activity_date),
  INDEX idx_user (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

function ref_get_settings(PDO $pdo): array
{
  $defaults = [
    'enabled'           => '1',
    'coins_reward'      => '100',
    'min_active_days'   => '0',
    'min_daily_minutes' => '0',
  ];
  $settings = [];
  try {
    foreach ($pdo->query("SELECT setting_key, setting_value FROM referral_settings")->fetchAll(PDO::FETCH_ASSOC) as $r) {
      $settings[$r['setting_key']] = $r['setting_value'];
    }
  } catch (Throwable $_) {}
  foreach ($defaults as $k => $v) {
    $settings[$k] ??= $v;
  }
  return $settings;
}

function ref_get_app_links(PDO $pdo): array
{
  $playstore = '';
  $appstore  = '';
  try {
    foreach ($pdo->query(
      "SELECT setting_key, setting_value FROM app_settings WHERE setting_key IN ('playstore_url','appstore_url')"
    )->fetchAll(PDO::FETCH_ASSOC) as $r) {
      if ($r['setting_key'] === 'playstore_url') $playstore = $r['setting_value'];
      if ($r['setting_key'] === 'appstore_url')  $appstore  = $r['setting_value'];
    }
  } catch (Throwable $_) {}
  return ['playstore_url' => $playstore, 'appstore_url' => $appstore];
}

try {
  $viewer  = requireUser($pdo);
  $userId  = (int)$viewer['id'];
  $action  = strtolower(trim((string)($_GET['action'] ?? $_POST['action'] ?? '')));

  // ── GET referral settings + app store links ──────────────────────────────
  if ($action === 'settings') {
    $s     = ref_get_settings($pdo);
    $links = ref_get_app_links($pdo);
    ref_json(200, [
      'status'            => 'success',
      'enabled'           => (bool)(int)$s['enabled'],
      'coins_reward'      => (int)$s['coins_reward'],
      'min_active_days'   => (int)$s['min_active_days'],
      'min_daily_minutes' => (int)$s['min_daily_minutes'],
      'playstore_url'     => $links['playstore_url'],
      'appstore_url'      => $links['appstore_url'],
    ]);
  }

  // ── Log daily activity (called on every app open) ────────────────────────
  if ($action === 'log_activity') {
    $seconds = max(0, (int)($_POST['seconds'] ?? 0));
    $today   = date('Y-m-d');
    $pdo->prepare(
      "INSERT INTO user_activity_log (user_id, activity_date, open_count, total_seconds)
       VALUES (?, ?, 1, ?)
       ON DUPLICATE KEY UPDATE
         open_count    = open_count + 1,
         total_seconds = total_seconds + VALUES(total_seconds),
         updated_at    = NOW()"
    )->execute([$userId, $today, $seconds]);
    ref_json(200, ['status' => 'success']);
  }

  // ── Apply a referral code ─────────────────────────────────────────────────
  if ($action === 'apply') {
    $s = ref_get_settings($pdo);

    if (!(bool)(int)$s['enabled']) {
      ref_json(400, ['status' => 'error', 'message' => 'Referral program is currently disabled']);
    }

    $code = strtoupper(trim((string)($_POST['code'] ?? $_POST['referral_code'] ?? '')));
    if (empty($code)) {
      ref_json(400, ['status' => 'error', 'message' => 'Referral code is required']);
    }

    // Check already claimed
    $chk = $pdo->prepare("SELECT id FROM referral_claims WHERE claimer_user_id = ? LIMIT 1");
    $chk->execute([$userId]);
    if ($chk->fetch()) {
      ref_json(400, ['status' => 'error', 'message' => 'You have already used a referral code']);
    }

    // Find referrer
    $refStmt = $pdo->prepare("SELECT id FROM users WHERE referral_code = ? LIMIT 1");
    $refStmt->execute([$code]);
    $referrer = $refStmt->fetch(PDO::FETCH_ASSOC);
    if (!$referrer) {
      ref_json(404, ['status' => 'error', 'message' => 'Invalid referral code']);
    }
    $referrerId = (int)$referrer['id'];

    if ($referrerId === $userId) {
      ref_json(400, ['status' => 'error', 'message' => 'You cannot use your own referral code']);
    }

    // Activity requirements check
    $minDays    = (int)$s['min_active_days'];
    $minMinutes = (int)$s['min_daily_minutes'];

    if ($minDays > 0) {
      $daysStmt = $pdo->prepare("SELECT COUNT(DISTINCT activity_date) FROM user_activity_log WHERE user_id = ?");
      $daysStmt->execute([$userId]);
      $activeDays = (int)$daysStmt->fetchColumn();
      if ($activeDays < $minDays) {
        ref_json(400, [
          'status'  => 'error',
          'message' => "You need to be active for at least {$minDays} day(s) before redeeming a referral reward",
        ]);
      }
    }

    if ($minMinutes > 0) {
      $minSeconds = $minMinutes * 60;
      $avgStmt    = $pdo->prepare("SELECT AVG(total_seconds) FROM user_activity_log WHERE user_id = ?");
      $avgStmt->execute([$userId]);
      $avgSeconds = (float)$avgStmt->fetchColumn();
      if ($avgSeconds < $minSeconds) {
        ref_json(400, [
          'status'  => 'error',
          'message' => "You need to spend at least {$minMinutes} min/day in the app before redeeming",
        ]);
      }
    }

    $coinsReward = (int)$s['coins_reward'];

    $pdo->beginTransaction();
    try {
      // Ensure wallets exist
      $pdo->prepare("INSERT IGNORE INTO user_wallets (user_id, balance_coins, locked_coins) VALUES (?,0,0)")->execute([$userId]);
      $pdo->prepare("INSERT IGNORE INTO user_wallets (user_id, balance_coins, locked_coins) VALUES (?,0,0)")->execute([$referrerId]);

      // Credit claimer
      $pdo->prepare("UPDATE user_wallets SET balance_coins = balance_coins + ? WHERE user_id = ?")->execute([$coinsReward, $userId]);
      $pdo->prepare("INSERT INTO wallet_transactions (user_id, type, direction, coins, status, note) VALUES (?, 'referral', 'credit', ?, 'completed', ?)")
        ->execute([$userId, $coinsReward, "Referral reward for using code: $code"]);

      // Credit referrer
      $pdo->prepare("UPDATE user_wallets SET balance_coins = balance_coins + ? WHERE user_id = ?")->execute([$coinsReward, $referrerId]);
      $pdo->prepare("INSERT INTO wallet_transactions (user_id, type, direction, coins, status, note) VALUES (?, 'referral', 'credit', ?, 'completed', ?)")
        ->execute([$referrerId, $coinsReward, "Referral bonus: someone joined using your code"]);

      // Record claim
      $pdo->prepare("INSERT INTO referral_claims (claimer_user_id, referrer_user_id, referral_code, coins_awarded) VALUES (?,?,?,?)")
        ->execute([$userId, $referrerId, $code, $coinsReward]);

      $pdo->commit();
      ref_json(200, [
        'status'        => 'success',
        'message'       => "{$coinsReward} coins added to your wallet!",
        'coins_awarded' => $coinsReward,
      ]);
    } catch (Throwable $e) {
      $pdo->rollBack();
      ref_json(500, ['status' => 'error', 'message' => 'Failed to apply referral: ' . $e->getMessage()]);
    }
  }

  ref_json(400, ['status' => 'error', 'message' => 'Invalid action']);
} catch (Throwable $e) {
  ref_json(500, ['status' => 'error', 'message' => 'Server error: ' . $e->getMessage()]);
}
