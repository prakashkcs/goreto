<?php
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Content-Type, Authorization');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
  http_response_code(200);
  echo json_encode(['status' => true]);
  exit;
}

require_once __DIR__ . '/db_connect.php';
require_once __DIR__ . '/auth_middleware.php';

function out_json(int $code, array $payload): void
{
  http_response_code($code);
  echo json_encode($payload, JSON_UNESCAPED_UNICODE);
  exit;
}

function read_body_data(): array
{
  $data = [];
  if (!empty($_POST))
    $data = $_POST;

  $ct = strtolower((string)($_SERVER['CONTENT_TYPE'] ?? $_SERVER['HTTP_CONTENT_TYPE'] ?? ''));
  $raw = file_get_contents('php://input');

  if ($raw && (str_contains($ct, 'application/json') || (empty($data) && trim($raw) !== ''))) {
    $json = json_decode($raw, true);
    if (is_array($json))
      $data = array_merge($data, $json);
  }
  return $data;
}

function ensure_tables(PDO $pdo): void
{
  // gifts
  try {
    $pdo->query("SELECT 1 FROM gifts LIMIT 1");
  }
  catch (Throwable $e) {
    $pdo->exec("
      CREATE TABLE IF NOT EXISTS gifts (
        id INT AUTO_INCREMENT PRIMARY KEY,
        name VARCHAR(191) NOT NULL,
        coin_price INT NOT NULL DEFAULT 0,
        glb_url TEXT NULL,
        gif_url TEXT NULL,
        thumb_image TEXT NULL,
        is_active TINYINT(1) NOT NULL DEFAULT 1,
        created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at DATETIME NULL
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ");
  }

  // gift_transactions
  try {
    $pdo->query("SELECT 1 FROM gift_transactions LIMIT 1");
  }
  catch (Throwable $e) {
    $pdo->exec("
      CREATE TABLE IF NOT EXISTS gift_transactions (
        id BIGINT AUTO_INCREMENT PRIMARY KEY,
        sender_id INT NOT NULL,
        receiver_id INT NOT NULL,
        gift_id INT NOT NULL,
        coins INT NOT NULL,
        context_type VARCHAR(30) NULL,
        context_id VARCHAR(40) NULL,
        created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        INDEX(sender_id),
        INDEX(receiver_id),
        INDEX(gift_id),
        INDEX(context_type),
        INDEX(context_id)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ");
  }

  // user_wallets (match your dump style)
  try {
    $pdo->query("SELECT 1 FROM user_wallets LIMIT 1");
  }
  catch (Throwable $e) {
    $pdo->exec("
      CREATE TABLE IF NOT EXISTS user_wallets (
        user_id INT NOT NULL,
        balance_coins BIGINT NOT NULL DEFAULT 0,
        locked_coins BIGINT NOT NULL DEFAULT 0,
        updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (user_id)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ");
  }

  // wallet_transactions (match your dump style)
  try {
    $pdo->query("SELECT 1 FROM wallet_transactions LIMIT 1");
  }
  catch (Throwable $e) {
    $pdo->exec("
      CREATE TABLE IF NOT EXISTS wallet_transactions (
        id BIGINT AUTO_INCREMENT PRIMARY KEY,
        user_id INT NOT NULL,
        type VARCHAR(30) NOT NULL,
        direction ENUM('credit','debit') NOT NULL,
        coins BIGINT NOT NULL,
        status ENUM('pending','approved','rejected','completed') NOT NULL DEFAULT 'completed',
        reference VARCHAR(64) NULL,
        note VARCHAR(255) NULL,
        created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        INDEX(user_id),
        INDEX(type),
        INDEX(status),
        INDEX(created_at)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ");
  }

  // user_gifts (inventory)
  try {
    $pdo->query("SELECT 1 FROM user_gifts LIMIT 1");
  }
  catch (Throwable $e) {
    $pdo->exec("
      CREATE TABLE IF NOT EXISTS user_gifts (
        id BIGINT AUTO_INCREMENT PRIMARY KEY,
        user_id INT NOT NULL,
        gift_id INT NOT NULL,
        qty INT NOT NULL DEFAULT 0,
        updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        UNIQUE KEY uq_user_gift (user_id, gift_id),
        KEY idx_user (user_id),
        KEY idx_gift (gift_id)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ");
  }

  // gift_sales (history)
  try {
    $pdo->query("SELECT 1 FROM gift_sales LIMIT 1");
  }
  catch (Throwable $e) {
    $pdo->exec("
      CREATE TABLE IF NOT EXISTS gift_sales (
        id BIGINT AUTO_INCREMENT PRIMARY KEY,
        user_id INT NOT NULL,
        gift_id INT NOT NULL,
        qty INT NOT NULL,
        coin_each INT NOT NULL,
        total_coins INT NOT NULL,
        created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        KEY idx_user (user_id),
        KEY idx_gift (gift_id),
        KEY idx_created (created_at)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ");
  }

  // gifts_received (offline notification log)
  try {
    $pdo->query("SELECT 1 FROM gifts_received LIMIT 1");
  }
  catch (Throwable $e) {
    $pdo->exec("
      CREATE TABLE IF NOT EXISTS gifts_received (
        id BIGINT AUTO_INCREMENT PRIMARY KEY,
        gift_id INT NOT NULL,
        receiver_id INT NOT NULL,
        sender_id INT NOT NULL,
        qty INT NOT NULL DEFAULT 1,
        message TEXT NULL,
        is_read TINYINT(1) DEFAULT 0,
        created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        INDEX(gift_id),
        INDEX(receiver_id),
        INDEX(sender_id)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ");
  }
}

function ensure_wallet(PDO $pdo, int $userId): void
{
  $pdo->prepare("INSERT IGNORE INTO user_wallets (user_id, balance_coins, locked_coins) VALUES (?,0,0)")
    ->execute([$userId]);
}

function add_wallet_tx(PDO $pdo, int $userId, string $type, string $direction, int $coins, string $reference, string $note): void
{
  $st = $pdo->prepare("
    INSERT INTO wallet_transactions (user_id, type, direction, coins, status, reference, note)
    VALUES (?,?,?,?, 'completed', ?, ?)
  ");
  $st->execute([$userId, $type, $direction, $coins, $reference, $note]);
}

function add_user_gift(PDO $pdo, int $userId, int $giftId, int $qty, int $senderId = 0, ?string $message = null): void
{
  // Upsert inventory
  $st = $pdo->prepare("
    INSERT INTO user_gifts (user_id, gift_id, qty)
    VALUES (?,?,?)
    ON DUPLICATE KEY UPDATE qty = qty + VALUES(qty), updated_at = NOW()
  ");
  $st->execute([$userId, $giftId, $qty]);

  // Log to offline notifications table (`gifts_received`)
  if ($senderId > 0) {
    if ($message !== null && $message !== '') {
      $stNotif = $pdo->prepare("
          INSERT INTO gifts_received (gift_id, receiver_id, sender_id, qty, message)
          VALUES (?,?,?,?,?)
        ");
      $stNotif->execute([$giftId, $userId, $senderId, $qty, $message]);
    }
    else {
      $stNotif = $pdo->prepare("
          INSERT INTO gifts_received (gift_id, receiver_id, sender_id, qty)
          VALUES (?,?,?,?)
        ");
      $stNotif->execute([$giftId, $userId, $senderId, $qty]);
    }
  }
}

try {
  ensure_tables($pdo);

  $action = strtolower(trim((string)($_GET['action'] ?? $_POST['action'] ?? '')));

  /* --------------------------
   * GET
   * -------------------------- */
  if ($_SERVER['REQUEST_METHOD'] === 'GET') {

    // List available gifts in shop
    if ($action === 'list' || $action === '') {
      $rows = [];
      try {
        $rows = $pdo->query("
          SELECT id,name,coin_price,glb_url,thumb_image,COALESCE(is_active,1) AS is_active,gif_url
          FROM gifts
          WHERE COALESCE(is_active,1)=1
          ORDER BY coin_price ASC, id DESC
        ")->fetchAll(PDO::FETCH_ASSOC);
      }
      catch (Throwable $e) {
        $rows = [];
      }

      if (empty($rows)) {
        try {
          $rows = $pdo->query("
            SELECT id,name,coin_price,glb_url,thumb_image,COALESCE(is_active,1) AS is_active,gif_url
            FROM gifts
            ORDER BY coin_price ASC, id DESC
          ")->fetchAll(PDO::FETCH_ASSOC);
        }
        catch (Throwable $e) {
          $rows = [];
        }
      }

      foreach ($rows as &$r) {
        $r['model_url'] = $r['glb_url'] ?? '';
        $r['type'] = 'glb';
      }
      unset($r);

      out_json(200, ['status' => true, 'count' => count($rows), 'gifts' => $rows, 'data' => $rows, 'items' => $rows]);
    }

    // Wallet gifts (received inventory) - auth required
    if ($action === 'wallet') {
      $viewer = requireUser($pdo);
      $userId = (int)$viewer['id'];

      $sellRate = 1.0; // sell = 100% of price (change if you want 70% etc)

      $st = $pdo->prepare("
        SELECT
          ug.gift_id,
          ug.qty,
          ug.updated_at,
          g.name,
          g.coin_price,
          g.thumb_image,
          g.gif_url,
          g.glb_url
        FROM user_gifts ug
        JOIN gifts g ON g.id = ug.gift_id
        WHERE ug.user_id = ? AND ug.qty > 0
        ORDER BY ug.updated_at DESC
      ");
      $st->execute([$userId]);
      $items = $st->fetchAll(PDO::FETCH_ASSOC) ?: [];

      foreach ($items as &$it) {
        $price = (int)($it['coin_price'] ?? 0);
        $it['sell_price'] = (int)round($price * $sellRate); // per 1 gift
        $it['total_value'] = $it['sell_price'] * (int)$it['qty'];
        $it['model_url'] = $it['glb_url'] ?? '';
      }
      unset($it);

      out_json(200, ['status' => true, 'count' => count($items), 'gifts' => $items]);
    }

    out_json(400, ['status' => false, 'message' => 'Unknown action']);
  }

  /* --------------------------
   * POST
   * -------------------------- */
  if ($_SERVER['REQUEST_METHOD'] === 'POST') {

    // SEND GIFT (deduct coins + add to receiver inventory)
    if ($action === 'send') {
      $viewer = requireUser($pdo);
      $senderId = (int)$viewer['id'];
      ensure_wallet($pdo, $senderId);

      $body = read_body_data();

      $giftId = (int)($body['gift_id'] ?? $body['giftId'] ?? 0);
      $toUserId = (int)($body['to_user_id'] ?? $body['toUserId'] ?? 0);
      $qty = (int)($body['qty'] ?? 1);
      if ($qty <= 0)
        $qty = 1;

      $contextType = trim((string)($body['context_type'] ?? $body['contextType'] ?? ''));
      $contextId = trim((string)($body['context_id'] ?? $body['contextId'] ?? ''));
      $message = isset($body['message']) ? substr(trim((string)$body['message']), 0, 30) : null;

      if ($giftId <= 0 || $toUserId <= 0)
        out_json(400, ['status' => false, 'message' => 'gift_id and to_user_id required']);
      if ($toUserId === $senderId)
        out_json(400, ['status' => false, 'message' => 'You cannot gift yourself']);

      $st = $pdo->prepare("SELECT id,name,coin_price,COALESCE(is_active,1) AS is_active FROM gifts WHERE id=? LIMIT 1");
      $st->execute([$giftId]);
      $gift = $st->fetch(PDO::FETCH_ASSOC);

      if (!$gift || (int)$gift['is_active'] !== 1)
        out_json(404, ['status' => false, 'message' => 'Gift not found or inactive']);

      $priceEach = (int)$gift['coin_price'];
      if ($priceEach <= 0)
        out_json(400, ['status' => false, 'message' => 'Invalid gift price']);

      $totalCost = $priceEach * $qty;

      ensure_wallet($pdo, $toUserId);

      $pdo->beginTransaction();

      $balStmt = $pdo->prepare("SELECT balance_coins FROM user_wallets WHERE user_id=? LIMIT 1");
      $balStmt->execute([$senderId]);
      $bal = (int)$balStmt->fetchColumn();

      if ($bal < $totalCost) {
        $pdo->rollBack();
        out_json(400, ['status' => false, 'message' => 'Not enough coins']);
      }

      // Deduct sender coins
      $pdo->prepare("UPDATE user_wallets SET balance_coins = balance_coins - ?, updated_at=NOW() WHERE user_id=?")
        ->execute([$totalCost, $senderId]);

      // Gift tx history (per send)
      $pdo->prepare("
        INSERT INTO gift_transactions (sender_id, receiver_id, gift_id, coins, context_type, context_id)
        VALUES (?,?,?,?,?,?)
      ")->execute([$senderId, $toUserId, $giftId, $totalCost, ($contextType ?: null), ($contextId ?: null)]);

      $giftTxId = (int)$pdo->lastInsertId();
      $ref = 'gift_' . $giftTxId;

      // Wallet log (sender debit)
      add_wallet_tx($pdo, $senderId, 'gift_send', 'debit', $totalCost, $ref, 'Sent gift: ' . $gift['name'] . ' x' . $qty . ' to user ' . $toUserId);

      // ✅ Receiver inventory add AND offline notification log
      add_user_gift($pdo, $toUserId, $giftId, $qty, $senderId, $message);

      $pdo->commit();

      require_once __DIR__ . "/notification_helper.php";
      $uname = "Someone";
      try {
        $us = $pdo->prepare("SELECT name FROM users WHERE id=?");
        $us->execute([$senderId]);
        $uname = $us->fetchColumn() ?: "Someone";
      }
      catch (Exception $e) {
      }
      send_app_notification($pdo, $toUserId, $senderId, "gift", "New Gift Received", "$uname sent you a gift.");

      $balStmt->execute([$senderId]);
      $newBal = (int)$balStmt->fetchColumn();

      out_json(200, ['status' => true, 'message' => 'Gift sent', 'balance_coins' => $newBal]);
    }

    // SELL GIFT (reduce inventory + add coins to wallet)
    if ($action === 'sell') {
      $viewer = requireUser($pdo);
      $userId = (int)$viewer['id'];
      ensure_wallet($pdo, $userId);

      $body = read_body_data();
      $giftId = (int)($body['gift_id'] ?? $body['giftId'] ?? 0);
      $qty = (int)($body['qty'] ?? 1);
      if ($qty <= 0)
        $qty = 1;

      if ($giftId <= 0)
        out_json(400, ['status' => false, 'message' => 'gift_id required']);

      $sellRate = 1.0; // sell = 100% of gift price. change to 0.7 for 70% etc.

      $st = $pdo->prepare("SELECT id,name,coin_price,COALESCE(is_active,1) AS is_active FROM gifts WHERE id=? LIMIT 1");
      $st->execute([$giftId]);
      $gift = $st->fetch(PDO::FETCH_ASSOC);
      if (!$gift)
        out_json(404, ['status' => false, 'message' => 'Gift not found']);

      $priceEach = (int)$gift['coin_price'];
      $sellEach = (int)round($priceEach * $sellRate);
      if ($sellEach <= 0)
        out_json(400, ['status' => false, 'message' => 'Gift sell price invalid']);

      $pdo->beginTransaction();

      // lock row by selecting qty
      $st = $pdo->prepare("SELECT qty FROM user_gifts WHERE user_id=? AND gift_id=? LIMIT 1 FOR UPDATE");
      $st->execute([$userId, $giftId]);
      $have = (int)$st->fetchColumn();

      if ($have < $qty) {
        $pdo->rollBack();
        out_json(400, ['status' => false, 'message' => 'Not enough gifts to sell']);
      }

      // decrement inventory
      $pdo->prepare("UPDATE user_gifts SET qty = qty - ?, updated_at=NOW() WHERE user_id=? AND gift_id=?")
        ->execute([$qty, $userId, $giftId]);

      $totalCoins = $sellEach * $qty;

      // credit wallet
      $pdo->prepare("UPDATE user_wallets SET balance_coins = balance_coins + ?, updated_at=NOW() WHERE user_id=?")
        ->execute([$totalCoins, $userId]);

      // sales history
      $pdo->prepare("INSERT INTO gift_sales (user_id, gift_id, qty, coin_each, total_coins) VALUES (?,?,?,?,?)")
        ->execute([$userId, $giftId, $qty, $sellEach, $totalCoins]);

      $saleId = (int)$pdo->lastInsertId();
      $ref = 'gift_sale_' . $saleId;

      // wallet tx log
      add_wallet_tx($pdo, $userId, 'gift_sell', 'credit', $totalCoins, $ref, 'Sold gift: ' . $gift['name'] . ' x' . $qty);

      $pdo->commit();

      $balStmt = $pdo->prepare("SELECT balance_coins FROM user_wallets WHERE user_id=? LIMIT 1");
      $balStmt->execute([$userId]);
      $newBal = (int)$balStmt->fetchColumn();

      out_json(200, [
        'status' => true,
        'message' => 'Gift sold',
        'sold_qty' => $qty,
        'coin_each' => $sellEach,
        'coins_added' => $totalCoins,
        'balance_coins' => $newBal
      ]);
    }

    out_json(400, ['status' => false, 'message' => 'Unknown action']);
  }

  out_json(405, ['status' => false, 'message' => 'Method not allowed']);

}
catch (Throwable $e) {
  $logMsg = date('[Y-m-d H:i:s] ') . "ERROR: " . $e->getMessage() . " in " . $e->getFile() . " on line " . $e->getLine() . "\n";
  $logMsg .= "Stack Trace: " . $e->getTraceAsString() . "\n";
  $logMsg .= "Request Data: " . file_get_contents('php://input') . "\n";
  $logMsg .= "GET Data: " . json_encode($_GET) . "\n\n";
  
  if (!file_exists(__DIR__ . '/uploads')) {
      mkdir(__DIR__ . '/uploads', 0777, true);
  }
  file_put_contents(__DIR__ . '/uploads/gift_error.log', $logMsg, FILE_APPEND);
  
  out_json(500, ['status' => false, 'message' => 'Server error', 'error' => $e->getMessage()]);
}
