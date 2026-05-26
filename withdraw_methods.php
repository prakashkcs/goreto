<?php
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Content-Type, Authorization');
header('Access-Control-Allow-Methods: GET, OPTIONS');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }

require_once __DIR__ . '/db_connect.php';
require_once __DIR__ . '/auth_middleware.php';

function out_json(int $code, array $payload): void {
  http_response_code($code);
  echo json_encode($payload);
  exit;
}

requireUser($pdo);

// Ensure table exists
$pdo->exec("CREATE TABLE IF NOT EXISTS withdrawal_methods (
  id INT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(100) DEFAULT NULL,
  description VARCHAR(255) DEFAULT NULL,
  account_hint VARCHAR(255) DEFAULT NULL,
  min_coins INT NOT NULL DEFAULT 100,
  max_coins INT NOT NULL DEFAULT 100000,
  fee_percent DECIMAL(5,2) NOT NULL DEFAULT 0.00,
  is_active TINYINT(1) NOT NULL DEFAULT 1,
  sort_order INT NOT NULL DEFAULT 0,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

// Withdrawal global settings
$settings = [];
try {
  foreach ($pdo->query("SELECT setting_key, setting_value FROM withdrawal_settings")->fetchAll(PDO::FETCH_ASSOC) as $r) {
    $settings[$r['setting_key']] = $r['setting_value'];
  }
} catch (Throwable $_) {}

$withdrawEnabled = (bool)(int)($settings['withdraw_enabled'] ?? 1);
$minCoins        = (int)($settings['min_withdraw_coins'] ?? 100);
$maxCoins        = (int)($settings['max_withdraw_coins'] ?? 100000);
$feePercent      = (float)($settings['withdraw_fee_pct'] ?? 0);
$coinsPerUnit    = (float)($settings['coins_per_unit'] ?? 1);
$currencyCode    = (string)($settings['currency_code'] ?? 'NPR');

// Fetch active withdrawal methods
$rows = $pdo->query(
  "SELECT id, name, description, account_hint, min_coins, max_coins, fee_percent
   FROM withdrawal_methods
   WHERE is_active = 1
   ORDER BY sort_order ASC, id ASC"
)->fetchAll(PDO::FETCH_ASSOC);

$methods = array_map(function ($r) {
  return [
    'id'           => (int)$r['id'],
    'name'         => (string)($r['name'] ?? ''),
    'description'  => (string)($r['description'] ?? ''),
    'account_hint' => (string)($r['account_hint'] ?? ''),
    'min_coins'    => (int)$r['min_coins'],
    'max_coins'    => (int)$r['max_coins'],
    'fee_percent'  => (float)$r['fee_percent'],
  ];
}, $rows);

out_json(200, [
  'status'          => true,
  'withdraw_enabled'=> $withdrawEnabled,
  'min_coins'       => $minCoins,
  'max_coins'       => $maxCoins,
  'fee_percent'     => $feePercent,
  'coins_per_unit'  => $coinsPerUnit,
  'currency_code'   => $currencyCode,
  'methods'         => $methods,
]);
