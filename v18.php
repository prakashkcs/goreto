<?php
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');

require_once __DIR__ . '/db_connect.php';

$userId = isset($_GET['user_id']) ? intval($_GET['user_id']) : 9;

$res = [
    'status' => 'success',
    'user' => [
        'id' => (string)$userId,
        'name' => '',
        'username' => '',
        'bio' => '',
        'avatar' => '',
        'interests' => [],
        'looking_for' => [],
        'qualities' => [],
        'income' => 0,
        'income_status' => 'none'
    ]
];

try {
    $st = $pdo->prepare("SELECT name, username, bio, profile_pic FROM users WHERE id = ?");
    $st->execute([$userId]);
    $u = $st->fetch(PDO::FETCH_ASSOC);
    if ($u) {
        $res['user']['name'] = isset($u['name']) ? $u['name'] : '';
        $res['user']['username'] = isset($u['username']) ? $u['username'] : '';
        $res['user']['bio'] = isset($u['bio']) ? $u['bio'] : '';

        $p = isset($u['profile_pic']) ? trim((string)$u['profile_pic']) : '';
        if ($p !== '' && !preg_match('~^https?://~i', $p)) {
            $p = 'https://coinzop.com/ekloadmin/' . ltrim($p, '/');
        }
        $res['user']['avatar'] = $p;
    }

    $mpSt = $pdo->prepare("SELECT looking_for, interests, qualities, income, income_status FROM match_profiles WHERE user_id = ?");
    $mpSt->execute([$userId]);
    $mp = $mpSt->fetch(PDO::FETCH_ASSOC);
    if ($mp) {
        $lf = isset($mp['looking_for']) ? $mp['looking_for'] : '';
        $res['user']['looking_for'] = $lf ? explode(',', $lf) : [];
        
        $int = isset($mp['interests']) ? $mp['interests'] : '';
        $res['user']['interests'] = $int ? explode(',', $int) : [];
        
        $qual = isset($mp['qualities']) ? $mp['qualities'] : '';
        $res['user']['qualities'] = $qual ? explode(',', $qual) : [];
        
        $inc = 0;
        if (isset($mp['income']) && is_numeric($mp['income'])) {
            $inc = (float)$mp['income'];
        }
        $res['user']['income'] = $inc;
        $res['user']['income_status'] = isset($mp['income_status']) ? $mp['income_status'] : 'none';
    }
}
catch (Exception $e) {
    if (!isset($res['error'])) {
        $res['error'] = $e->getMessage();
    }
}

echo json_encode($res);
