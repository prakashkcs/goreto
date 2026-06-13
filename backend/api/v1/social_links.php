<?php
header('Content-Type: application/json; charset=utf-8');
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Headers: Content-Type, Authorization");
header("Access-Control-Allow-Methods: GET, POST, OPTIONS");
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }

require_once __DIR__ . '/db_connect.php';

function out($arr,$code=200){ http_response_code($code); echo json_encode($arr); exit; }

$action = $_GET['action'] ?? $_POST['action'] ?? 'get';
$user_id = isset($_GET['user_id']) ? intval($_GET['user_id']) : intval($_POST['user_id'] ?? 0);
if ($user_id <= 0) out(["status"=>false,"message"=>"user_id required"], 400);

if ($action === 'get') {
  $st = $pdo->prepare("SELECT facebook, instagram, tiktok, youtube, website FROM user_social_links WHERE user_id = ? LIMIT 1");
  $st->execute([$user_id]);
  $row = $st->fetch(PDO::FETCH_ASSOC) ?: [];

  // Remove empty links so Flutter hides icons automatically
  $clean = [];
  foreach ($row as $k=>$v) {
    $v = trim((string)$v);
    if ($v !== '') $clean[$k] = $v;
  }

  out(["status"=>true,"links"=>$clean]);
}

out(["status"=>false,"message"=>"Invalid action"], 400);