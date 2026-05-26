<?php
header('Content-Type: text/plain');
require_once __DIR__ . '/db_connect.php';

try {
    $senderId = 9; // Prakash
    $toUserId = 10; // ArPaN
    $giftId = 1;   // Flower
    $qty = 1;
    $token = "55f5a36057fbdbb8e5b807a68f79bd2291234c909779aa135b9c1c8ad3a015fa";

    echo "Step 1: Check Database Tables\n";
    // Check if required tables exist and can be queried
    $pdo->query("SELECT 1 FROM gifts LIMIT 1");
    $pdo->query("SELECT 1 FROM user_wallets LIMIT 1");
    $pdo->query("SELECT 1 FROM gift_transactions LIMIT 1");
    $pdo->query("SELECT 1 FROM user_gifts LIMIT 1");
    $pdo->query("SELECT 1 FROM gifts_received LIMIT 1");
    $pdo->query("SELECT 1 FROM notifications LIMIT 1");

    echo "Step 2: Fetch Gift Details\n";
    $st = $pdo->prepare("SELECT id, name, coin_price FROM gifts WHERE id=? AND COALESCE(is_active,1)=1");
    $st->execute([$giftId]);
    $gift = $st->fetch(PDO::FETCH_ASSOC);
    if (!$gift) throw new Exception("Gift 1 not found or inactive");
    $price = (int)$gift['coin_price'];
    $total = $price * $qty;

    echo "Step 3: Check/Add Sender Wallet\n";
    $pdo->prepare("INSERT IGNORE INTO user_wallets (user_id, balance_coins) VALUES (?, 0)")->execute([$senderId]);
    
    echo "Step 4: Check Balance\n";
    $st = $pdo->prepare("SELECT balance_coins FROM user_wallets WHERE user_id=?");
    $st->execute([$senderId]);
    $bal = (int)$st->fetchColumn();
    echo "Prakash Balance: $bal, Cost: $total\n";
    
    if ($bal < $total) {
        echo "Adding 1000 coins for testing...\n";
        $pdo->prepare("UPDATE user_wallets SET balance_coins = balance_coins + 1000 WHERE user_id=?")->execute([$senderId]);
    }

    echo "Step 5: Execute Send Logic (Simulated Transaction)\n";
    $pdo->beginTransaction();
    
    // Deduct
    $pdo->prepare("UPDATE user_wallets SET balance_coins = balance_coins - ? WHERE user_id=?")->execute([$total, $senderId]);
    
    // Log GT
    $pdo->prepare("INSERT INTO gift_transactions (sender_id, receiver_id, gift_id, coins) VALUES (?,?,?,?)")->execute([$senderId, $toUserId, $giftId, $total]);
    
    // Update Inventory
    $pdo->prepare("INSERT INTO user_gifts (user_id, gift_id, qty) VALUES (?,?,?) ON DUPLICATE KEY UPDATE qty = qty + VALUES(qty)")->execute([$toUserId, $giftId, $qty]);
    
    // Log Received
    $pdo->prepare("INSERT INTO gifts_received (gift_id, receiver_id, sender_id, qty) VALUES (?,?,?,?)")->execute([$giftId, $toUserId, $senderId, $qty]);
    
    $pdo->commit();
    echo "Database Transaction Committed\n";

    echo "Step 6: Notification Step\n";
    require_once __DIR__ . '/notification_helper.php';
    echo "Imported notification_helper.php\n";
    
    $uname = "Prakash (Sim)";
    send_app_notification($pdo, $toUserId, $senderId, "gift", "New Gift Received", "$uname sent you a gift.");
    echo "Notification Sent\n";

    echo "FINAL: SUCCESS\n";

} catch (Throwable $e) {
    if (isset($pdo) && $pdo->inTransaction()) $pdo->rollBack();
    echo "FAILED at Step: " . $e->getMessage() . "\n";
    echo "Line: " . $e->getLine() . "\n";
    echo $e->getTraceAsString();
}
