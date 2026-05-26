<?php
header('Content-Type: application/json; charset=utf-8');
require_once __DIR__ . '/db_connect.php';
require_once __DIR__ . '/auth_middleware.php';

function json_out($code, $arr)
{
    http_response_code($code);
    echo json_encode($arr);
    exit;
}

$userId = isset($_GET['user_id']) ? intval($_GET['user_id']) : 9;

// Minimal profile fetch
$st = $pdo->prepare("SELECT id, name FROM users WHERE id = ?");
$st->execute([$userId]);
$u = $st->fetch(PDO::FETCH_ASSOC);

if (!$u)
    json_out(404, ['status' => 'error', 'message' => 'no user']);

$u['interests'] = [];
$u['looking_for'] = [];
$u['qualities'] = [];

$stMP = $pdo->prepare("SELECT looking_for, interests, qualities FROM match_profiles WHERE user_id = ?");
$stMP->execute([$userId]);
$mp = $stMP->fetch(PDO::FETCH_ASSOC);
if ($mp) {
    $u['looking_for'] = explode(',', $mp['looking_for'] ?? '');
    $u['interests'] = explode(',', $mp['interests'] ?? '');
    $u['qualities'] = explode(',', $mp['qualities'] ?? '');
}

json_out(200, ['status' => 'success_minimal', 'user' => $u]);
