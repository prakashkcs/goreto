<?php
// gift_notifications.php
header('Content-Type: application/json; charset=utf-8');

require_once __DIR__ . '/db_connect.php';
require_once __DIR__ . '/auth_middleware.php';

function gn_emoji_fallback(string $name): string {
    static $map = [
        'rose'=>'🌹','kiss'=>'💋','heart'=>'❤️','sweet'=>'💕','teddy'=>'🧸',
        'letter'=>'💌','chocolate'=>'🍫','cupid'=>'💘','angel'=>'😇',
        'wings'=>'🪽','bouquet'=>'💐','ring'=>'💍','diamond'=>'💎',
        'crown'=>'👑','castle'=>'🏰','golden'=>'✨','love'=>'💗','bear'=>'🐻',
    ];
    $lower = mb_strtolower($name);
    foreach ($map as $k => $e) { if (str_contains($lower, $k)) return $e; }
    return '🎁';
}

function gn_abs_url(string $url): string {
    if ($url === '') return '';
    if (preg_match('#^https?://#i', $url)) return $url;
    return 'https://goreto.org/ekloadmin/api/v1/' . ltrim($url, '/');
}

// Authenticate and get user
$user = requireUser($pdo);
$user_id = $user['id'];

$action = $_GET['action'] ?? 'list';

if ($action === 'list') {
    $sql = "SELECT gr.id, gr.gift_id, gr.qty, gr.created_at,
                   u.id AS sender_id, u.name AS sender_name, u.profile_pic AS sender_pic,
                   g.name, g.coin_price, g.gif_url, g.thumb_image, g.glb_url,
                   COALESCE(g.emoji,'') AS emoji
            FROM gifts_received gr
            LEFT JOIN users u ON gr.sender_id = u.id
            LEFT JOIN gifts g ON gr.gift_id = g.id
            WHERE gr.receiver_id = ?
            ORDER BY gr.created_at DESC
            LIMIT 20";

    try {
        $stmt = $pdo->prepare($sql);
        $stmt->execute([$user_id]);
        $notifications = [];

        while ($row = $stmt->fetch(PDO::FETCH_ASSOC)) {
            $notifications[] = [
                'id'            => (int)$row['id'],
                'gift_id'       => (int)$row['gift_id'],
                'name'          => $row['name'],
                'gift_name'     => $row['name'],
                'sender_id'     => (string)($row['sender_id'] ?? ''),
                'sender_name'   => $row['sender_name'] ?? '',
                'sender_avatar' => gn_abs_url($row['sender_pic'] ?? ''),
                'sender_pic'    => gn_abs_url($row['sender_pic'] ?? ''),
                'qty'           => (int)$row['qty'],
                'coin_price'    => (int)$row['coin_price'],
                'price'         => (int)$row['coin_price'],
                'emoji'         => $row['emoji'] ?: gn_emoji_fallback($row['name'] ?? ''),
                'gif_url'       => gn_abs_url($row['gif_url'] ?? ''),
                'thumb_image'   => gn_abs_url($row['thumb_image'] ?? ''),
                'glb_url'       => gn_abs_url($row['glb_url'] ?? ''),
                'model_url'     => gn_abs_url($row['glb_url'] ?? ''),
                'created_at'    => $row['created_at'],
            ];
        }

        echo json_encode(['status' => true, 'data' => $notifications]);
    } catch (\PDOException $e) {
        http_response_code(500);
        echo json_encode(["status" => false, "message" => "Database error: " . $e->getMessage()]);
    }
} else {
    http_response_code(400);
    echo json_encode(['status' => false, 'message' => 'Invalid action']);
}
?>
