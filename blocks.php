<?php
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Content-Type, Authorization');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }

require_once __DIR__ . '/db_connect.php';
require_once __DIR__ . '/auth_middleware.php';

function out_json(int $code, array $payload): void {
  http_response_code($code);
  echo json_encode($payload);
  exit;
}

$pdo->exec("CREATE TABLE IF NOT EXISTS user_blocks (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  blocker_id INT NOT NULL,
  blocked_id INT NOT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uniq_pair (blocker_id, blocked_id),
  KEY idx_blocker (blocker_id),
  KEY idx_blocked (blocked_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci");

$me = requireUser($pdo);
$meId = (int)$me['id'];

$action = $_GET['action'] ?? $_POST['action'] ?? 'list';

$raw = file_get_contents('php://input');
$j = json_decode($raw, true);
if (!is_array($j)) $j = [];
$data = array_merge($_POST, $j);

// LIST
if ($_SERVER['REQUEST_METHOD'] === 'GET' && ($action === 'list' || $action === 'blocked')) {
  $st = $pdo->prepare("
    SELECT b.blocked_id, b.created_at AS blocked_at,
           u.name, u.profile_pic
    FROM user_blocks b
    JOIN users u ON u.id = b.blocked_id
    WHERE b.blocker_id = ?
    ORDER BY b.created_at DESC
  ");
  $st->execute([$meId]);
  $rows = $st->fetchAll(PDO::FETCH_ASSOC);

  $out = [];
  foreach ($rows as $r) {
    $out[] = [
      'user_id'    => (int)$r['blocked_id'],
      'name'       => (string)($r['name'] ?? ''),
      'profile_pic'=> (string)($r['profile_pic'] ?? ''),
      'blocked_at' => (string)($r['blocked_at'] ?? ''),
    ];
  }

  out_json(200, ['status' => true, 'blocked_users' => $out]);
}

// BLOCK
if ($_SERVER['REQUEST_METHOD'] === 'POST' && $action === 'block') {
  $target = (int)($data['user_id'] ?? $data['target_user_id'] ?? 0);
  if ($target <= 0) out_json(400, ['status' => false, 'message' => 'target_user_id required']);
  if ($target === $meId) out_json(400, ['status' => false, 'message' => 'Cannot block yourself']);

  $pdo->prepare('INSERT IGNORE INTO user_blocks (blocker_id, blocked_id, created_at) VALUES (?, ?, NOW())')
      ->execute([$meId, $target]);

  out_json(200, ['status' => true, 'message' => 'User blocked']);
}

// UNBLOCK
if ($_SERVER['REQUEST_METHOD'] === 'POST' && ($action === 'unblock' || $action === 'remove')) {
  $target = (int)($data['user_id'] ?? $data['target_user_id'] ?? 0);
  if ($target <= 0) out_json(400, ['status' => false, 'message' => 'target_user_id required']);

  $pdo->prepare('DELETE FROM user_blocks WHERE blocker_id = ? AND blocked_id = ?')
      ->execute([$meId, $target]);

  out_json(200, ['status' => true, 'message' => 'User unblocked']);
}

out_json(400, ['status' => false, 'message' => 'Invalid action']);
