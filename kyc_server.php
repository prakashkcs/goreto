<?php
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Content-Type, Authorization');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
  http_response_code(200);
  echo json_encode(['status'=>'success']);
  exit;
}

require_once __DIR__ . '/db_connect.php';
require_once __DIR__ . '/auth_middleware.php';
$config = require __DIR__ . '/../../config/config.php';

function out_json(int $code, array $payload): void {
  http_response_code($code);
  echo json_encode($payload);
  exit;
}
function base_url($config): string {
  return rtrim(($config['base_url'] ?? 'https://coinzop.com/ekloadmin'), '/');
}
function ensure_user_kyc(PDO $pdo, int $userId): void {
  $pdo->prepare("INSERT IGNORE INTO user_kyc (user_id, basic_status, full_status) VALUES (?, 'none', 'none')")
      ->execute([$userId]);
}
function pick_random_task(PDO $pdo, string $level): ?array {
  $st = $pdo->prepare("SELECT id,title,instructions,level FROM kyc_task_templates WHERE is_active=1 AND level=? ORDER BY RAND() LIMIT 1");
  $st->execute([$level]);
  $row = $st->fetch(PDO::FETCH_ASSOC);
  return $row ?: null;
}
function save_video($config): ?string {
  if (empty($_FILES['video']) || !is_uploaded_file($_FILES['video']['tmp_name'])) return null;
  $dir = __DIR__ . '/uploads/kyc/';
  if (!is_dir($dir)) @mkdir($dir, 0777, true);
  if (!is_dir($dir) || !is_writable($dir)) return null;

  $ext = pathinfo((string)$_FILES['video']['name'], PATHINFO_EXTENSION);
  $ext = $ext ? '.'.preg_replace('/[^a-zA-Z0-9]/', '', $ext) : '.mp4';
  $name = uniqid('kyc_', true).$ext;
  if (!move_uploaded_file($_FILES['video']['tmp_name'], $dir.$name)) return null;
  return base_url($config)."/api/v1/uploads/kyc/".$name;
}

try {
  $viewer = requireUser($pdo);
  $userId = (int)$viewer['id'];
  ensure_user_kyc($pdo, $userId);

  $action = strtolower(trim((string)($_GET['action'] ?? $_POST['action'] ?? '')));
  $level = strtolower(trim((string)($_GET['level'] ?? $_POST['level'] ?? 'basic')));
  if ($level !== 'basic' && $level !== 'full') $level = 'basic';

  if ($_SERVER['REQUEST_METHOD'] === 'GET') {

    if ($action === 'status' || $action === '') {
      $st = $pdo->prepare("SELECT kyc_status FROM users WHERE id=? LIMIT 1");
      $st->execute([$userId]);
      $user = $st->fetch(PDO::FETCH_ASSOC);
      $status = $user ? $user['kyc_status'] : 'none';

      $st2 = $pdo->prepare("SELECT admin_note FROM kyc_verifications WHERE user_id=? ORDER BY id DESC LIMIT 1");
      $st2->execute([$userId]);
      $sub = $st2->fetch(PDO::FETCH_ASSOC);
      $note = $sub ? $sub['admin_note'] : '';

      $row = [
          'user_id' => $userId,
          'basic_status' => $status,
          'full_status' => $status,
          'admin_note' => $note
      ];
      out_json(200, ['status'=>'success','kyc'=>$row]);
    }

    if ($action === 'random_task') {
      $task = pick_random_task($pdo, $level);
      if (!$task) out_json(404, ['status'=>'error','message'=>'No active tasks']);
      out_json(200, ['status'=>'success','task'=>$task]);
    }

    out_json(400, ['status'=>'error','message'=>'Unknown action']);
  }

  if ($_SERVER['REQUEST_METHOD'] === 'POST') {

    if ($action === 'submit_basic') {
      $fullName = trim((string)($_POST['full_name'] ?? ''));
      if ($fullName === '') out_json(400, ['status'=>'error','message'=>'full_name required']);

      $taskId = (int)($_POST['task_id'] ?? 0);
      if ($taskId <= 0) out_json(400, ['status'=>'error','message'=>'task_id required']);

      $videoUrl = save_video($config);
      if (!$videoUrl) out_json(400, ['status'=>'error','message'=>'video file required (field name: video)']);

      // write submission
      $pdo->prepare("INSERT INTO kyc_submissions (user_id, level, task_id, full_name, video_url, status)
                     VALUES (?,?,?,?,?, 'pending')")
          ->execute([$userId,'basic',$taskId,$fullName,$videoUrl]);

      // update user_kyc
      $pdo->prepare("UPDATE user_kyc
                     SET basic_status='pending', full_name=?, basic_video_url=?, basic_task_id=?, basic_submitted_at=NOW()
                     WHERE user_id=?")
          ->execute([$fullName,$videoUrl,$taskId,$userId]);

      out_json(200, ['status'=>'success','message'=>'Basic KYC submitted','video_url'=>$videoUrl]);
    }

    if ($action === 'submit_full') {
      $taskId = (int)($_POST['task_id'] ?? 0);
      if ($taskId <= 0) out_json(400, ['status'=>'error','message'=>'task_id required']);

      $videoUrl = save_video($config);
      if (!$videoUrl) out_json(400, ['status'=>'error','message'=>'video file required (field name: video)']);

      $pdo->prepare("INSERT INTO kyc_submissions (user_id, level, task_id, video_url, status)
                     VALUES (?,?,?,?, 'pending')")
          ->execute([$userId,'full',$taskId,$videoUrl]);

      $pdo->prepare("UPDATE user_kyc
                     SET full_status='pending', full_video_url=?, full_task_id=?, full_submitted_at=NOW()
                     WHERE user_id=?")
          ->execute([$videoUrl,$taskId,$userId]);

      out_json(200, ['status'=>'success','message'=>'Full KYC submitted','video_url'=>$videoUrl]);
    }

    out_json(400, ['status'=>'error','message'=>'Unknown action']);
  }

  out_json(405, ['status'=>'error','message'=>'Method not allowed']);
} catch (Throwable $e) {
  out_json(500, ['status'=>'error','message'=>'Server error','detail'=>$e->getMessage()]);
}