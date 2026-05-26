<?php
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');

require_once __DIR__ . '/db_connect.php';

$userId = isset($_GET['user_id']) ? intval($_GET['user_id']) : 9;

$u = [
    'status' => 'success_v5',
    'user' => [
        'id' => (string)$userId,
        'interests' => [],
        'looking_for' => [],
        'qualities' => []
    ]
];

try {
    $mpSt = $pdo->prepare("SELECT looking_for, interests, qualities FROM match_profiles WHERE user_id = ?");
    $mpSt->execute([$userId]);
    $mp = $mpSt->fetch(PDO::FETCH_ASSOC);
    if ($mp) {
        $u['user']['looking_for'] = explode(',', $mp['looking_for'] ?? '');
        $u['user']['interests'] = explode(',', $mp['interests'] ?? '');
        $u['user']['qualities'] = explode(',', $mp['qualities'] ?? '');
    }
}
catch (Throwable $e) {
    $u['error'] = $e->getMessage();
}

echo json_encode($u);
