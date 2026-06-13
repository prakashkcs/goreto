<?php
// gift_notifications.php
header('Content-Type: application/json; charset=utf-8');
require_once __DIR__ . '/db_connect.php';
require_once __DIR__ . '/auth_middleware.php';

try {
    $viewer = requireUser($pdo);
    $user_id = (int)$viewer['id'];
} catch (Exception $e) {
    echo json_encode(['status' => false, 'message' => $e->getMessage()]);
    exit;
}

$action = $_GET['action'] ?? 'list';

if ($action === 'list') {
    $sql = "SELECT gr.id, gr.gift_id, gr.sender_id, gr.qty, gr.message, gr.created_at,
                   u.name as sender_name, u.profile_pic as sender_avatar,
                   g.name as gift_name, g.coin_price, g.gif_url, g.thumb_image
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
                'id'           => (string)$row['id'],
                'gift_id'      => (string)$row['gift_id'],
                'sender_id'    => (string)$row['sender_id'],
                'sender_name'  => $row['sender_name'] ?? '',
                'sender_avatar'=> $row['sender_avatar'] ?? '',
                'name'         => $row['gift_name'] ?? '',
                'gift_name'    => $row['gift_name'] ?? '',
                'qty'          => (int)$row['qty'],
                'coin_price'   => (int)$row['coin_price'],
                'price'        => (int)$row['coin_price'],
                'gif_url'      => $row['gif_url'] ?? '',
                'thumb_image'  => $row['thumb_image'] ?? '',
                'message'      => $row['message'] ?? '',
                'created_at'   => $row['created_at'] ?? '',
            ];
        }

        echo json_encode(['status' => true, 'data' => $notifications]);
    } catch (\PDOException $e) {
        echo json_encode(["status" => false, "message" => "Database error: " . $e->getMessage()]);
    }
} elseif ($action === 'post_gifts') {
    // Gifts shown on a post/reel overlay. Gifts may be recorded with
    // context_type 'post' or the post's media type; exclude 'live' to avoid
    // context_id collisions with live rooms.
    $contextId = trim((string)($_GET['context_id'] ?? $_POST['context_id'] ?? ''));
    if ($contextId === '') { echo json_encode(['status' => true, 'data' => []]); exit; }
    $sql = "SELECT gt.id, gt.sender_id, gt.gift_id, gt.coins, gt.created_at,
                   u.name AS sender_name, u.username AS sender_username, u.profile_pic AS sender_avatar,
                   g.name AS gift_name, g.coin_price, g.gif_url, g.thumb_image, g.emoji
            FROM gift_transactions gt
            LEFT JOIN users u ON gt.sender_id = u.id
            LEFT JOIN gifts g ON gt.gift_id = g.id
            WHERE gt.context_id = ?
              AND gt.context_type IN ('post','photo','image','video','reel')
            ORDER BY gt.coins DESC, gt.created_at DESC
            LIMIT 50";
    try {
        $stmt = $pdo->prepare($sql);
        $stmt->execute([$contextId]);
        $base = 'https://goreto.org/ekloadmin/';
        $norm = function ($u) use ($base) {
            $u = trim((string)$u);
            if ($u === '') return '';
            if (preg_match('~^https?://~i', $u)) return $u;
            return $base . ltrim($u, '/');
        };
        $gifts = [];
        while ($row = $stmt->fetch(PDO::FETCH_ASSOC)) {
            $coins = (int)($row['coins'] ?? 0);
            if ($coins <= 0) $coins = (int)($row['coin_price'] ?? 0);
            $gifts[] = [
                'id'            => (string)$row['id'],
                'gift_id'       => (string)$row['gift_id'],
                'sender_id'     => (string)$row['sender_id'],
                'sender_name'   => $row['sender_name'] ?: ($row['sender_username'] ?: 'User'),
                'sender_avatar' => $norm($row['sender_avatar'] ?? ''),
                'name'          => $row['gift_name'] ?? 'Gift',
                'gift_name'     => $row['gift_name'] ?? 'Gift',
                'coin_price'    => $coins,
                'price'         => $coins,
                'gif_url'       => $norm($row['gif_url'] ?? ''),
                'thumb_image'   => $norm($row['thumb_image'] ?? ''),
                'emoji'         => $row['emoji'] ?? '',
                'created_at'    => $row['created_at'] ?? '',
            ];
        }
        echo json_encode(['status' => true, 'data' => $gifts]);
    } catch (\PDOException $e) {
        echo json_encode(['status' => false, 'message' => 'Database error: ' . $e->getMessage()]);
    }
} elseif ($action === 'post_gift_leaderboard') {
    // Aggregated top-gifters leaderboard for a post (sum coins per sender).
    $contextId = trim((string)($_GET['context_id'] ?? $_POST['context_id'] ?? ''));
    if ($contextId === '') { echo json_encode(['status'=>true,'total_gifts'=>0,'total_coins'=>0,'leaders'=>[]]); exit; }
    $sql = "SELECT gt.sender_id, COUNT(*) AS gift_count, SUM(gt.coins) AS total_coins,
                   u.name, u.username, u.profile_pic
            FROM gift_transactions gt
            LEFT JOIN users u ON u.id = gt.sender_id
            WHERE gt.context_id = ? AND gt.context_type IN ('post','photo','image','video','reel')
            GROUP BY gt.sender_id, u.name, u.username, u.profile_pic
            ORDER BY total_coins DESC, gift_count DESC
            LIMIT 100";
    $stmt = $pdo->prepare($sql);
    $stmt->execute([$contextId]);
    $leaders = []; $totalGifts = 0; $totalCoins = 0; $rank = 0;
    foreach ($stmt->fetchAll(PDO::FETCH_ASSOC) as $r) {
        $rank++;
        $pic = (string)($r['profile_pic'] ?? '');
        if ($pic !== '' && !preg_match('~^https?://~i', $pic)) { $pic = 'https://goreto.org/ekloadmin/' . ltrim($pic, '/'); }
        $gc = (int)$r['gift_count']; $tc = (int)$r['total_coins'];
        $totalGifts += $gc; $totalCoins += $tc;
        $leaders[] = [
            'rank' => $rank,
            'user_id' => (string)$r['sender_id'],
            'name' => $r['name'] ?: ($r['username'] ?: 'User'),
            'username' => (string)($r['username'] ?? ''),
            'avatar' => $pic !== '' ? $pic : null,
            'gift_count' => $gc,
            'total_coins' => $tc,
        ];
    }
    echo json_encode(['status'=>true,'total_gifts'=>$totalGifts,'total_coins'=>$totalCoins,'leaders'=>$leaders]);

} else {
    echo json_encode(['status' => false, 'message' => 'Invalid action']);
}
?>