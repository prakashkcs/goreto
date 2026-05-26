<?php
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Content-Type, Authorization');
header('Access-Control-Allow-Methods: POST, OPTIONS');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }

require_once __DIR__ . '/db_connect.php';
require_once __DIR__ . '/auth_middleware.php';

function out_json(int $code, array $payload): void {
  http_response_code($code);
  echo json_encode($payload);
  exit;
}

$viewer = requireUser($pdo);
$userId = (int)$viewer['id'];

$in = $_POST ?: (json_decode(file_get_contents('php://input'), true) ?: []);

// Ensure pay_per_min columns exist (auto-migrate)
try {
  $cols = array_column(
    $pdo->query("SHOW COLUMNS FROM users")->fetchAll(PDO::FETCH_ASSOC),
    'Field'
  );
  if (!in_array('pay_per_min_enabled', $cols, true)) {
    $pdo->exec("ALTER TABLE users ADD COLUMN pay_per_min_enabled TINYINT(1) NOT NULL DEFAULT 0");
  }
  if (!in_array('pay_per_min_rate', $cols, true)) {
    $pdo->exec("ALTER TABLE users ADD COLUMN pay_per_min_rate DECIMAL(10,2) NOT NULL DEFAULT 0.00");
  }
} catch (Throwable $_) {}

$updates = [];
$params  = [];

if (isset($in['pay_per_min_enabled'])) {
  $updates[] = 'pay_per_min_enabled = ?';
  $params[]  = (int)(bool)(int)$in['pay_per_min_enabled'];
}

if (isset($in['pay_per_min_rate'])) {
  $rate = (float)$in['pay_per_min_rate'];
  if ($rate < 0) $rate = 0;
  $updates[] = 'pay_per_min_rate = ?';
  $params[]  = $rate;
}

if (empty($updates)) {
  out_json(400, ['status' => false, 'message' => 'No updatable fields provided']);
}

$params[] = $userId;
$pdo->prepare("UPDATE users SET " . implode(', ', $updates) . " WHERE id = ?")
    ->execute($params);

out_json(200, ['status' => true, 'message' => 'Profile updated']);
