<?php
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Content-Type, Authorization');
header('Access-Control-Allow-Methods: GET, OPTIONS');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }

require_once __DIR__ . '/db_connect.php';

function out_json(int $code, array $payload): void {
  http_response_code($code);
  echo json_encode($payload);
  exit;
}

$action = $_GET['action'] ?? $_POST['action'] ?? '';

if ($action === 'get_public_settings') {
  $settings = [];
  try {
    $pdo->exec("CREATE TABLE IF NOT EXISTS app_settings (
      id INT AUTO_INCREMENT PRIMARY KEY,
      setting_key VARCHAR(80) NOT NULL UNIQUE,
      setting_value VARCHAR(500) NOT NULL DEFAULT '',
      updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

    foreach ($pdo->query("SELECT setting_key, setting_value FROM app_settings")->fetchAll(PDO::FETCH_ASSOC) as $r) {
      $settings[$r['setting_key']] = $r['setting_value'];
    }
  } catch (Throwable $_) {}

  // Provide sensible defaults for keys the Flutter app reads
  $settings += [
    'enable_guest_mode'   => '1',
    'pay_per_min_rate'    => '0',
    'subscription_status' => 'inactive',
  ];

  out_json(200, ['status' => 'success', 'settings' => $settings]);
}

out_json(400, ['status' => 'error', 'message' => 'Unknown action']);
