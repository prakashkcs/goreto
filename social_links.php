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

// Ensure table exists
$pdo->exec("CREATE TABLE IF NOT EXISTS user_social_links (
  id INT AUTO_INCREMENT PRIMARY KEY,
  user_id INT NOT NULL UNIQUE,
  facebook VARCHAR(255) DEFAULT NULL,
  instagram VARCHAR(255) DEFAULT NULL,
  tiktok VARCHAR(255) DEFAULT NULL,
  youtube VARCHAR(255) DEFAULT NULL,
  twitter VARCHAR(255) DEFAULT NULL,
  website VARCHAR(255) DEFAULT NULL,
  updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

$action  = $_GET['action'] ?? $_POST['action'] ?? 'get';
$userId  = (int)($_GET['user_id'] ?? $_POST['user_id'] ?? 0);

// GET: fetch social links for a user (no auth required — public profile)
if ($_SERVER['REQUEST_METHOD'] === 'GET' && $action === 'get') {
  if ($userId <= 0) out_json(400, ['status' => false, 'message' => 'user_id required']);

  $st = $pdo->prepare("SELECT facebook, instagram, tiktok, youtube, twitter, website
                        FROM user_social_links WHERE user_id = ? LIMIT 1");
  $st->execute([$userId]);
  $row = $st->fetch(PDO::FETCH_ASSOC) ?: [];

  $clean = [];
  foreach ($row as $k => $v) {
    $v = trim((string)$v);
    if ($v !== '') $clean[$k] = $v;
  }

  out_json(200, ['status' => true, 'links' => $clean]);
}

// POST: update social links (auth required — own profile only)
if ($_SERVER['REQUEST_METHOD'] === 'POST' && $action === 'update') {
  $viewer  = requireUser($pdo);
  $meId    = (int)$viewer['id'];

  $in = json_decode(file_get_contents('php://input'), true) ?: $_POST;

  $fields   = ['facebook', 'instagram', 'tiktok', 'youtube', 'twitter', 'website'];
  $setCols  = [];
  $params   = [];

  foreach ($fields as $f) {
    if (array_key_exists($f, $in)) {
      $setCols[] = "$f = ?";
      $params[]  = trim((string)($in[$f] ?? '')) ?: null;
    }
  }

  if (empty($setCols)) out_json(400, ['status' => false, 'message' => 'No fields to update']);

  // Upsert: insert row if not exists, then update changed columns
  $pdo->prepare("INSERT IGNORE INTO user_social_links (user_id) VALUES (?)")->execute([$meId]);
  $params[] = $meId;
  $pdo->prepare("UPDATE user_social_links SET " . implode(', ', $setCols) . " WHERE user_id = ?")
      ->execute($params);

  out_json(200, ['status' => true, 'message' => 'Social links updated']);
}

out_json(400, ['status' => false, 'message' => 'Invalid action']);
