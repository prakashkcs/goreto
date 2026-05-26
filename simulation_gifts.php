<?php
header('Content-Type: application/json');
require_once __DIR__ . '/db_connect.php';

function step_log($msg) {
    // Optional: write to a file if needed
}

try {
    $senderId = 9; // Prakash
    $toUserId = 10; // ArPaN
    $giftId = 1;   // Flower
    $qty = 1;

    echo "Step 0: Start\n";

    // Mock ensure_tables just in case
    require_once __DIR__ . '/gifts.php'; // Load functions but it might execute top-level code? 
    // Wait, gifts.php has top-level code. Better to just COPY the logic here.

    echo "Step 1: Check Gift\n";
    $st = $pdo->prepare("SELECT id,name,coin_price,COALESCE(is_active,1) AS is_active FROM gifts WHERE id=? LIMIT 1");
    $st->execute([$giftId]);
    $gift = $st->fetch(PDO::FETCH_ASSOC);
    if (!$gift) throw new Exception("Gift not found");
    $priceEach = (int)$gift['coin_price'];
    $totalCost = $priceEach * $qty;

    echo "Step 2: Start Transaction\n";
    $pdo->beginTransaction();

    echo "Step 3: Check Balance\n";
    $balStmt = $pdo->prepare("SELECT balance_coins FROM user_wallets WHERE user_id=? LIMIT 1");
    $balStmt->execute([$senderId]);
    $bal = (int)$balStmt->fetchColumn();
    echo "Current Balance: $bal, Cost: $totalCost\n";

    echo "Step 4: Deduct Coins\n";
    $pdo->prepare("UPDATE user_wallets SET balance_coins = balance_coins - ?, updated_at=NOW() WHERE user_id=?")
        ->execute([$totalCost, $senderId]);

    echo "Step 5: Log Transaction\n";
    $pdo->prepare("
        INSERT INTO gift_transactions (sender_id, receiver_id, gift_id, coins, context_type, context_id)
        VALUES (?,?,?,?,?,?)
    ")->execute([$senderId, $toUserId, $giftId, $totalCost, 'test', 'test']);

    echo "Step 6: Update Inventory\n";
    $st = $pdo->prepare("
        INSERT INTO user_gifts (user_id, gift_id, qty)
        VALUES (?,?,?)
        ON DUPLICATE KEY UPDATE qty = qty + VALUES(qty), updated_at = NOW()
    ");
    $st->execute([$toUserId, $giftId, $qty]);

    echo "Step 7: Log Received\n";
    $stNotif = $pdo->prepare("
        INSERT INTO gifts_received (gift_id, receiver_id, sender_id, qty)
        VALUES (?,?,?,?)
    ");
    $stNotif->execute([$giftId, $toUserId, $senderId, $qty]);

    echo "Step 8: Commit\n";
    $pdo->commit();

    echo "Step 9: Notification\n";
    require_once __DIR__ . "/notification_helper.php";
    send_app_notification($pdo, $toUserId, $senderId, "gift", "New Gift Received", "Test from simulation");

    echo "SUCCESS: Simulation completed\n";

} catch (Throwable $e) {
    if (isset($pdo) && $pdo->inTransaction()) $pdo->rollBack();
    echo "ERROR at Step: " . $e->getMessage() . "\n";
    echo $e->getTraceAsString();
}
