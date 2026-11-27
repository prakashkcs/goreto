<?php
/**
 * gifts.php — Virtual gift catalog, send, and received API
 * Actions: list | send | received | wallet | sell
 */
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Content-Type, Authorization');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200); echo json_encode(['status' => 'ok']); exit;
}

require_once __DIR__ . '/db_connect.php';
require_once __DIR__ . '/auth_middleware.php';
require_once __DIR__ . '/notification_helper.php';

// Merge JSON body into $_POST so the app's application/json requests work
if ($_SERVER['REQUEST_METHOD'] === 'POST' && empty($_POST)) {
    $rawBody = file_get_contents('php://input');
    if ($rawBody !== '') {
        $json = json_decode($rawBody, true);
        if (is_array($json)) { $_POST = array_merge($_POST, $json); }
    }
}

$action = strtolower(trim($_GET['action'] ?? 'list'));

// ── helpers ──────────────────────────────────────────────────────────────────
function out(array $payload, int $code = 200): void {
    http_response_code($code);
    echo json_encode($payload, JSON_UNESCAPED_UNICODE);
    exit;
}

function base(): string {
    return 'https://goreto.org/ekloadmin/api/v1/';
}

function abs_url(string $url): string {
    if ($url === '') return '';
    if (preg_match('#^https?://#i', $url)) return $url;
    return base() . ltrim($url, '/');
}

// Admin-controlled gift economics (admin/gifts.php → gift_settings):
//   receiver_percent — share of the price the receiver gets when a gift arrives
//   sell_percent     — share of the price paid when the receiver sells it back
//                      (0 = selling switched off)
function gift_setting(PDO $pdo, string $key, int $default): int {
    static $cache = null;
    if ($cache === null) {
        $cache = [];
        try {
            foreach ($pdo->query("SELECT setting_key, setting_value FROM gift_settings") as $r) {
                $cache[$r['setting_key']] = (int)$r['setting_value'];
            }
        } catch (\Throwable $_) { /* table not created yet: defaults */ }
    }
    $v = $cache[$key] ?? $default;
    return max(0, min(100, $v));
}

function gift_sell_price(PDO $pdo, int $coinPrice): int {
    return (int)floor($coinPrice * gift_setting($pdo, 'sell_percent', 0) / 100);
}

function get_coin_balance(PDO $pdo, int $userId): int {
    // Prefer user_wallets table; fall back to users.coins column
    try {
        $r = $pdo->prepare("SELECT balance_coins FROM user_wallets WHERE user_id=? LIMIT 1");
        $r->execute([$userId]);
        $row = $r->fetch(PDO::FETCH_ASSOC);
        if ($row !== false) return (int)($row['balance_coins'] ?? 0);
    } catch (\Throwable $_) {}
    try {
        $r = $pdo->prepare("SELECT coins FROM users WHERE id=? LIMIT 1");
        $r->execute([$userId]);
        $row = $r->fetch(PDO::FETCH_ASSOC);
        if ($row !== false) return (int)($row['coins'] ?? 0);
    } catch (\Throwable $_) {}
    return 0;
}

function deduct_coins(PDO $pdo, int $userId, int $amount, string $note): bool {
    // Try user_wallets first
    try {
        $r = $pdo->prepare(
            "UPDATE user_wallets SET balance_coins = balance_coins - ? WHERE user_id=? AND balance_coins >= ?"
        );
        $r->execute([$amount, $userId, $amount]);
        if ($r->rowCount() > 0) {
            // Log transaction
            try {
                $pdo->prepare(
                    "INSERT INTO wallet_transactions (user_id,type,direction,coins,status,note) VALUES (?,?,?,?,?,?)"
                )->execute([$userId, 'gift_send', 'debit', $amount, 'completed', $note]);
            } catch (\Throwable $_) {}
            return true;
        }
    } catch (\Throwable $_) {}
    // Fall back to users.coins column
    try {
        $r = $pdo->prepare(
            "UPDATE users SET coins = coins - ? WHERE id=? AND coins >= ?"
        );
        $r->execute([$amount, $userId, $amount]);
        return $r->rowCount() > 0;
    } catch (\Throwable $_) {}
    return false;
}

function credit_coins(PDO $pdo, int $userId, int $amount, string $note): void {
    try {
        $r = $pdo->prepare(
            "INSERT INTO user_wallets (user_id, balance_coins) VALUES (?,?)
             ON DUPLICATE KEY UPDATE balance_coins = balance_coins + ?"
        );
        $r->execute([$userId, $amount, $amount]);
        try {
            $pdo->prepare(
                "INSERT INTO wallet_transactions (user_id,type,direction,coins,status,note) VALUES (?,?,?,?,?,?)"
            )->execute([$userId, 'gift_receive', 'credit', $amount, 'completed', $note]);
        } catch (\Throwable $_) {}
    } catch (\Throwable $_) {
        try {
            $pdo->prepare("UPDATE users SET coins = coins + ? WHERE id=?")->execute([$amount, $userId]);
        } catch (\Throwable $_) {}
    }
}

// ── action=list ───────────────────────────────────────────────────────────────
if ($action === 'list') {
    $stmt = $pdo->query(
        "SELECT id, name,
                COALESCE(category, 'love') AS category,
                COALESCE(emoji, '') AS emoji,
                COALESCE(animation_type, 'float') AS animation_type,
                coin_price,
                COALESCE(gif_url, '') AS gif_url,
                COALESCE(thumb_image, '') AS thumb_image,
                COALESCE(glb_url, '') AS glb_url
         FROM gifts
         WHERE is_active = 1
         ORDER BY COALESCE(sort_order,0) ASC, id ASC"
    );
    $gifts = [];
    while ($row = $stmt->fetch(PDO::FETCH_ASSOC)) {
        $gifts[] = [
            'id'             => (int)$row['id'],
            'name'           => $row['name'],
            'category'       => $row['category'],
            'emoji'          => $row['emoji'],
            'animation_type' => $row['animation_type'],
            'coin_price'     => (int)$row['coin_price'],
            'gif_url'        => abs_url($row['gif_url']),
            'thumb_image'    => abs_url($row['thumb_image']),
            'glb_url'        => abs_url($row['glb_url']),
        ];
    }
    out(['status' => true, 'gifts' => $gifts]);
}

// ── action=send ───────────────────────────────────────────────────────────────
if ($action === 'send') {
    try { $sender = requireUser($pdo); }
    catch (\Exception $e) { out(['status' => false, 'message' => 'Unauthorized'], 401); }

    $senderId  = (int)$sender['id'];
    $giftId    = (int)($_POST['gift_id']     ?? $_GET['gift_id']     ?? 0);
    $toUserId  = (int)($_POST['to_user_id']  ?? $_GET['to_user_id']  ?? 0);
    $ctxType   = trim($_POST['context_type'] ?? $_GET['context_type'] ?? 'profile');
    $ctxId     = trim($_POST['context_id']   ?? $_GET['context_id']  ?? '');
    $message   = substr(trim($_POST['message'] ?? ''), 0, 30);

    if ($giftId <= 0 || $toUserId <= 0) {
        out(['status' => false, 'message' => 'Missing gift_id or to_user_id'], 400);
    }
    if ($senderId === $toUserId) {
        out(['status' => false, 'message' => 'Cannot send gift to yourself'], 400);
    }

    // Fetch gift
    $gStmt = $pdo->prepare("SELECT * FROM gifts WHERE id=? AND is_active=1 LIMIT 1");
    $gStmt->execute([$giftId]);
    $gift = $gStmt->fetch(PDO::FETCH_ASSOC);
    if (!$gift) out(['status' => false, 'message' => 'Gift not found'], 404);

    $price = (int)$gift['coin_price'];

    // Check balance
    $balance = get_coin_balance($pdo, $senderId);
    if ($balance < $price) {
        out(['status' => false, 'message' => 'Not enough coins', 'balance' => $balance]);
    }

    // Deduct from sender
    if (!deduct_coins($pdo, $senderId, $price, "Sent gift: {$gift['name']} to user $toUserId")) {
        out(['status' => false, 'message' => 'Not enough coins']);
    }

    // Credit receiver (admin-set share, 50% by default)
    $receiverCredit = (int)floor($price * gift_setting($pdo, 'receiver_percent', 50) / 100);
    if ($receiverCredit > 0) {
        credit_coins($pdo, $toUserId, $receiverCredit, "Received gift: {$gift['name']} from user $senderId");
    }

    // Record in gift_transactions
    try {
        $pdo->prepare(
            "INSERT INTO gift_transactions (sender_id,receiver_id,gift_id,coins,context_type,context_id)
             VALUES (?,?,?,?,?,?)"
        )->execute([$senderId, $toUserId, $giftId, $price, $ctxType, $ctxId]);
    } catch (\Throwable $_) {}

    // Record in gifts_received
    try {
        $pdo->prepare(
            "INSERT INTO gifts_received (gift_id,receiver_id,sender_id,qty,message)
             VALUES (?,?,?,1,?)
             ON DUPLICATE KEY UPDATE qty=qty+1"
        )->execute([$giftId, $toUserId, $senderId, $message]);
    } catch (\Throwable $_) {
        try {
            $pdo->prepare(
                "INSERT INTO gifts_received (gift_id,receiver_id,sender_id,qty,message) VALUES (?,?,?,1,?)"
            )->execute([$giftId, $toUserId, $senderId, $message]);
        } catch (\Throwable $_) {}
    }

    // Track lifetime gifting for badge system
    try {
        $pdo->prepare(
            "UPDATE users SET total_coins_sent = COALESCE(total_coins_sent,0) + ? WHERE id=?"
        )->execute([$price, $senderId]);
    } catch (\Throwable $_) {}

    $newBalance = get_coin_balance($pdo, $senderId);

    // Push notification to receiver via FCM v1 API
    try {
        $senderRow = $pdo->prepare("SELECT name FROM users WHERE id=? LIMIT 1");
        $senderRow->execute([$senderId]);
        $senderName = $senderRow->fetchColumn() ?: 'Someone';

        $emoji = $gift['emoji'] ?? '';
        send_app_notification(
            $pdo,
            $toUserId,
            $senderId,
            'gift',
            "$senderName sent you a gift!",
            "You received {$gift['name']} $emoji (+$receiverCredit coins)",
            (int)$giftId
        );
    } catch (\Throwable $_) {}

    // Fetch updated gifter level for the sender
    $gifterLevel = 0;
    try {
        $glRow = $pdo->prepare("SELECT total_coins_sent FROM users WHERE id=? LIMIT 1");
        $glRow->execute([$senderId]);
        $glData = $glRow->fetch(PDO::FETCH_ASSOC);
        $tcs = (int)($glData['total_coins_sent'] ?? 0);
        if ($tcs >= 5000000)      $gifterLevel = 6;
        elseif ($tcs >= 1500000)  $gifterLevel = 5;
        elseif ($tcs >= 500000)   $gifterLevel = 4;
        elseif ($tcs >= 200000)   $gifterLevel = 3;
        elseif ($tcs >= 50000)    $gifterLevel = 2;
        elseif ($tcs >= 10000)    $gifterLevel = 1;
    } catch (\Throwable $_) {}

    out([
        'status'            => 'success',
        'message'           => 'Gift sent!',
        'gift_name'         => $gift['name'],
        'gift_emoji'        => $gift['emoji'] ?? '',
        'gif_url'           => abs_url($gift['gif_url'] ?? ''),
        'new_balance'       => $newBalance,
        'coins_spent'       => $price,
        'gifter_level'      => $gifterLevel,
    ]);
}

// ── action=received ───────────────────────────────────────────────────────────
if ($action === 'received') {
    $userId = (int)($_GET['user_id'] ?? 0);
    if ($userId <= 0) {
        try { $u = requireUser($pdo); $userId = (int)$u['id']; }
        catch (\Exception $_) { out(['status' => false, 'message' => 'Missing user_id'], 400); }
    }

    $stmt = $pdo->prepare(
        "SELECT gr.id, gr.qty, gr.message,
                u.name AS sender_name, u.profile_pic AS sender_pic,
                g.id AS gift_id, g.name AS gift_name,
                COALESCE(g.emoji,'') AS emoji,
                g.coin_price, g.gif_url, g.thumb_image,
                gr.created_at
         FROM gifts_received gr
         LEFT JOIN users u ON u.id = gr.sender_id
         LEFT JOIN gifts g ON g.id = gr.gift_id
         WHERE gr.receiver_id = ?
         ORDER BY gr.created_at DESC
         LIMIT 20"
    );
    $stmt->execute([$userId]);
    $rows = [];
    while ($r = $stmt->fetch(PDO::FETCH_ASSOC)) {
        $rows[] = [
            'id'          => (int)$r['id'],
            'gift_id'     => (int)$r['gift_id'],
            'gift_name'   => $r['gift_name'],
            // The app reads 'name' and 'total_value'; without them every
            // gift in "My gifts" showed a blank name and a value of 0.
            'name'        => $r['gift_name'] ?? 'Gift',
            'emoji'       => $r['emoji'],
            'qty'         => (int)$r['qty'],
            'coin_price'  => (int)$r['coin_price'],
            'total_value' => (int)$r['coin_price'] * (int)$r['qty'],
            'sell_price'  => gift_sell_price($pdo, (int)$r['coin_price']),
            'gif_url'     => abs_url($r['gif_url'] ?? ''),
            'thumb_image' => abs_url($r['thumb_image'] ?? ''),
            'sender_name' => $r['sender_name'],
            'sender_pic'  => abs_url($r['sender_pic'] ?? ''),
            'message'     => $r['message'] ?? '',
            'created_at'  => $r['created_at'],
        ];
    }
    out(['status' => true, 'data' => $rows]);
}

// ── action=wallet ─────────────────────────────────────────────────────────────
// Returns all gifts received by the authenticated user (for wallet/gift shelf).
if ($action === 'wallet') {
    try { $user = requireUser($pdo); }
    catch (\Exception $e) { out(['status' => false, 'message' => 'Unauthorized'], 401); }

    $userId = (int)$user['id'];

    $stmt = $pdo->prepare(
        "SELECT gr.id, gr.qty, gr.message,
                u.name AS sender_name, u.profile_pic AS sender_pic,
                g.id AS gift_id, g.name AS gift_name,
                COALESCE(g.emoji,'') AS emoji,
                g.coin_price, g.gif_url, g.thumb_image,
                gr.created_at
         FROM gifts_received gr
         LEFT JOIN users u ON u.id = gr.sender_id
         LEFT JOIN gifts g ON g.id = gr.gift_id
         WHERE gr.receiver_id = ?
         ORDER BY gr.created_at DESC
         LIMIT 50"
    );
    $stmt->execute([$userId]);
    $rows = [];
    while ($r = $stmt->fetch(PDO::FETCH_ASSOC)) {
        $rows[] = [
            'id'          => (int)$r['id'],
            'gift_id'     => (int)$r['gift_id'],
            'gift_name'   => $r['gift_name'],
            // The app reads 'name' and 'total_value'; without them every
            // gift in "My gifts" showed a blank name and a value of 0.
            'name'        => $r['gift_name'] ?? 'Gift',
            'emoji'       => $r['emoji'],
            'qty'         => (int)$r['qty'],
            'coin_price'  => (int)$r['coin_price'],
            'total_value' => (int)$r['coin_price'] * (int)$r['qty'],
            'sell_price'  => gift_sell_price($pdo, (int)$r['coin_price']),
            'gif_url'     => abs_url($r['gif_url'] ?? ''),
            'thumb_image' => abs_url($r['thumb_image'] ?? ''),
            'sender_name' => $r['sender_name'],
            'sender_pic'  => abs_url($r['sender_pic'] ?? ''),
            'message'     => $r['message'] ?? '',
            'created_at'  => $r['created_at'],
        ];
    }
    out(['status' => true, 'gifts' => $rows]);
}

// ── action=sell ───────────────────────────────────────────────────────────────
// Sell received gifts back for coins at the admin-set sell_percent of the
// gift's price. The receiver already earned receiver_percent when the gift
// arrived, so this is a separate, admin-controlled payout (0% = off).
if ($action === 'sell') {
    try { $user = requireUser($pdo); }
    catch (\Exception $e) { out(['status' => false, 'message' => 'Unauthorized'], 401); }
    $userId = (int)$user['id'];
    $giftId = (int)($_POST['gift_id'] ?? $_GET['gift_id'] ?? 0);
    $qty    = (int)($_POST['qty'] ?? $_GET['qty'] ?? 1);
    if ($giftId <= 0 || $qty <= 0) out(['status' => false, 'message' => 'Missing gift_id or qty'], 400);

    $pct = gift_setting($pdo, 'sell_percent', 0);
    if ($pct <= 0) out(['status' => false, 'message' => 'Gift selling is turned off right now']);

    $g = $pdo->prepare("SELECT name, coin_price FROM gifts WHERE id=? LIMIT 1");
    $g->execute([$giftId]);
    $gift = $g->fetch(PDO::FETCH_ASSOC);
    if (!$gift) out(['status' => false, 'message' => 'Gift not found'], 404);
    $unit = gift_sell_price($pdo, (int)$gift['coin_price']);
    if ($unit <= 0) out(['status' => false, 'message' => 'This gift has no sell value']);

    $pdo->beginTransaction();
    try {
        $rowsSt = $pdo->prepare("SELECT id, qty FROM gifts_received WHERE receiver_id=? AND gift_id=? AND qty>0 ORDER BY created_at ASC, id ASC FOR UPDATE");
        $rowsSt->execute([$userId, $giftId]);
        $rows = $rowsSt->fetchAll(PDO::FETCH_ASSOC);
        $owned = array_sum(array_map(fn($r) => (int)$r['qty'], $rows));
        if ($owned < $qty) {
            $pdo->rollBack();
            out(['status' => false, 'message' => "You only have $owned of this gift"]);
        }
        $left = $qty;
        $del = $pdo->prepare("DELETE FROM gifts_received WHERE id=?");
        $dec = $pdo->prepare("UPDATE gifts_received SET qty=qty-? WHERE id=?");
        foreach ($rows as $r) {
            if ($left <= 0) break;
            $take = min($left, (int)$r['qty']);
            if ($take === (int)$r['qty']) $del->execute([(int)$r['id']]);
            else $dec->execute([$take, (int)$r['id']]);
            $left -= $take;
        }
        $coins = $unit * $qty;
        $pdo->prepare("INSERT INTO user_wallets (user_id, balance_coins) VALUES (?,?)
                       ON DUPLICATE KEY UPDATE balance_coins = balance_coins + ?")
            ->execute([$userId, $coins, $coins]);
        $pdo->prepare("INSERT INTO wallet_transactions (user_id,type,direction,coins,status,reference,note)
                       VALUES (?,?,?,?,?,?,?)")
            ->execute([$userId, 'gift_sell', 'credit', $coins, 'completed', 'gift:' . $giftId,
                       "Sold {$qty}x {$gift['name']}"]);
        $pdo->commit();
    } catch (\Throwable $e) {
        if ($pdo->inTransaction()) $pdo->rollBack();
        out(['status' => false, 'message' => 'Could not sell the gift right now'], 500);
    }

    out([
        'status'      => 'success',
        'message'     => "Sold {$qty}x {$gift['name']}",
        'coins_added' => $coins,
        'balance'     => get_coin_balance($pdo, $userId),
    ]);
}

out(['status' => false, 'message' => 'Unknown action'], 400);
