<?php
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');

require_once __DIR__ . '/db_connect.php';

$userId = isset($_GET['user_id']) ? intval($_GET['user_id']) : 9;

$res = [
    'status' => 'success_v9',
    'user' => [
        'id' => (string)$userId,
        'name' => '',
        'bio' => '',
        'interests' => [],
        'looking_for' => [],
        'qualities' => []
    ]
];

try {
    $st = $pdo->prepare("SELECT name, bio FROM users WHERE id = ?");
    $st->execute([$userId]);
    $u = $st->fetch(PDO::FETCH_ASSOC);
    if ($u) {
        $res['user']['name'] = $u['name'] ?? '';
        $res['user']['bio'] = $u['bio'] ?? '';
    }

    $mpSt = $pdo->prepare("SELECT looking_for, interests, qualities FROM match_profiles WHERE user_id = ?");
    $mpSt->execute([$userId]);
    $mp = $mpSt->fetch(PDO::FETCH_ASSOC);
    if ($mp) {
        $res['user']['looking_for'] = explode(',', $mp['looking_for'] ?? '');
        $res['user']['interests'] = explode(',', $mp['interests'] ?? '');
        $res['user']['qualities'] = explode(',', $mp['qualities'] ?? '');
    }
}
catch (Throwable $e) {
    $res['error'] = $e->getMessage();
}

echo json_encode($res);
