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

        'qualities' => []

    ]

];



try {

    $st = $pdo->prepare("SELECT name, username, bio, profile_pic FROM users WHERE id = ?");

    $st->execute([$userId]);

    $u = $st->fetch(PDO::FETCH_ASSOC);

    if ($u) {

        $res['user']['name'] = $u['name'] ?? '';

        $res['user']['username'] = $u['username'] ?? '';

        $res['user']['bio'] = $u['bio'] ?? '';



        $p = trim((string)($u['profile_pic'] ?? ''));



echo json_encode($res);

