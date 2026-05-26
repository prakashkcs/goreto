<?php
// User-facing report endpoint — persists reports from the app
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

$viewer  = requireUser($pdo);
$userId  = (int)$viewer['id'];

$in      = json_decode(file_get_contents('php://input'), true) ?: $_POST;
$action  = strtolower(trim((string)($in['action'] ?? $_GET['action'] ?? 'report_post')));

// Ensure reports table exists
$pdo->exec("CREATE TABLE IF NOT EXISTS reports (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  reporter_id INT NOT NULL,
  target_type ENUM('post','user','comment','story') NOT NULL DEFAULT 'post',
  target_id BIGINT NOT NULL,
  reason VARCHAR(120) NOT NULL,
  details TEXT NULL,
  status ENUM('pending','reviewed','dismissed') NOT NULL DEFAULT 'pending',
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  KEY idx_target (target_type, target_id),
  KEY idx_reporter (reporter_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

$targetType = strtolower(trim((string)($in['target_type'] ?? 'post')));
$targetId   = (int)($in['target_id'] ?? $in['post_id'] ?? $in['user_id'] ?? 0);
$reason     = trim((string)($in['reason'] ?? ''));
$details    = trim((string)($in['details'] ?? ''));

if ($targetId <= 0) out_json(400, ['status' => 'error', 'message' => 'target_id required']);
if ($reason === '')  out_json(400, ['status' => 'error', 'message' => 'reason required']);

$allowed = ['post', 'user', 'comment', 'story'];
if (!in_array($targetType, $allowed, true)) $targetType = 'post';

$pdo->prepare("INSERT IGNORE INTO reports (reporter_id, target_type, target_id, reason, details) VALUES (?,?,?,?,?)")
    ->execute([$userId, $targetType, $targetId, $reason, $details ?: null]);

out_json(200, ['status' => 'success', 'message' => 'Report submitted']);
