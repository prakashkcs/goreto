<?php
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Content-Type, Authorization');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
  http_response_code(200);
  echo json_encode(['status' => 'success']);
  exit;
}

require_once __DIR__ . '/db_connect.php';
require_once __DIR__ . '/auth_middleware.php';
$config = require __DIR__ . '/../../config/config.php';

function out_json(int $code, array $payload): void {
  http_response_code($code);
  echo json_encode($payload);
  exit;
}

function base_url($config): string {
  return rtrim(($config['base_url'] ?? 'https://coinzop.com/ekloadmin'), '/');
}

function ensure_wallet(PDO $pdo, int $userId): void {
  $pdo->prepare("INSERT IGNORE INTO user_wallets (user_id, balance_coins, locked_coins) VALUES (?,0,0)")
      ->execute([$userId]);
}

function get_settings(PDO $pdo): array {
  $row = $pdo->query("SELECT * FROM wallet_settings WHERE id=1 LIMIT 1")->fetch(PDO::FETCH_ASSOC);
  if (!$row) {
    $pdo->exec("INSERT INTO wallet_settings (id,currency_code,currency_symbol,coins_per_currency,min_withdraw_coins,min_deposit_coins)
                VALUES (1,'NPR','Rs',1.0000,0,0)");
    $row = $pdo->query("SELECT * FROM wallet_settings WHERE id=1 LIMIT 1")->fetch(PDO::FETCH_ASSOC);
  }
  return $row ?: ['currency_code'=>'NPR','currency_symbol'=>'Rs','coins_per_currency'=>1,'min_withdraw_coins'=>0,'min_deposit_coins'=>0];
}

function add_tx(PDO $pdo, int $userId, string $type, string $direction, int $coins, ?float $currencyAmount, ?string $currencyCode, string $status, ?string $ref, ?string $note): int {
  $st = $pdo->prepare("INSERT INTO wallet_transactions (user_id,type,direction,coins,currency_amount,currency_code,status,reference,note)
                       VALUES (?,?,?,?,?,?,?,?,?)");
  $st->execute([$userId,$type,$direction,$coins,$currencyAmount,$currencyCode,$status,$ref,$note]);
  return (int)$pdo->lastInsertId();
}

try {
  $viewer = requireUser($pdo);
  $userId = (int)$viewer['id'];
  ensure_wallet($pdo, $userId);

  // --- Ensure NEW tables exist (safe to run repeatedly) ---
  // wallet_methods (admin adds QR wallets)
  $pdo->exec("
    CREATE TABLE IF NOT EXISTS wallet_methods (
      id INT AUTO_INCREMENT PRIMARY KEY,
      name VARCHAR(100) NOT NULL,
      type ENUM('deposit','withdraw','both') DEFAULT 'deposit',
      account_name VARCHAR(120) NULL,
      account_number VARCHAR(120) NULL,
      qr_image VARCHAR(255) NULL,
      is_active TINYINT(1) DEFAULT 1,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
  ");

  // wallet_deposits (QR deposit flow)
  $pdo->exec("
    CREATE TABLE IF NOT EXISTS wallet_deposits (
      id BIGINT AUTO_INCREMENT PRIMARY KEY,
      user_id INT NOT NULL,
      method_id INT NOT NULL,
      coins BIGINT NOT NULL,
      currency_amount DECIMAL(18,4) NOT NULL,
      currency_code VARCHAR(10) DEFAULT 'NPR',
      status ENUM('initiated','reviewing','approved','rejected') DEFAULT 'initiated',
      click_count INT DEFAULT 0,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      INDEX(user_id),
      INDEX(method_id),
      INDEX(status)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
  ");

  $action = strtolower(trim((string)($_GET['action'] ?? $_POST['action'] ?? '')));

  // ============================
  // GET
  // ============================
  if ($_SERVER['REQUEST_METHOD'] === 'GET') {

    if ($action === 'settings') {
      $s = get_settings($pdo);
      out_json(200, ['status'=>'success','settings'=>$s]);
    }

    if ($action === 'balance' || $action === '') {
      $s = get_settings($pdo);
      $w = $pdo->prepare("SELECT user_id,balance_coins,locked_coins,updated_at FROM user_wallets WHERE user_id=? LIMIT 1");
      $w->execute([$userId]);
      $wallet = $w->fetch(PDO::FETCH_ASSOC) ?: ['user_id'=>$userId,'balance_coins'=>0,'locked_coins'=>0];

      out_json(200, [
        'status'=>'success',
        'wallet'=>$wallet,
        'settings'=>$s,
      ]);
    }

    if ($action === 'transactions') {
      $limit = (int)($_GET['limit'] ?? 50);
      $limit = max(1, min(200, $limit));
      $st = $pdo->prepare("SELECT * FROM wallet_transactions WHERE user_id=? ORDER BY id DESC LIMIT $limit");
      $st->execute([$userId]);
      out_json(200, ['status'=>'success','transactions'=>$st->fetchAll(PDO::FETCH_ASSOC)]);
    }

    if ($action === 'requests') {
      $limit = (int)($_GET['limit'] ?? 50);
      $limit = max(1, min(200, $limit));
      $st = $pdo->prepare("SELECT * FROM wallet_requests WHERE user_id=? ORDER BY id DESC LIMIT $limit");
      $st->execute([$userId]);
      out_json(200, ['status'=>'success','requests'=>$st->fetchAll(PDO::FETCH_ASSOC)]);
    }

    // ✅ NEW: Deposit methods (admin QR wallets)
    if ($action === 'deposit_methods') {
      $rows = $pdo->query("SELECT id,name,account_name,account_number,qr_image
                           FROM wallet_methods
                           WHERE is_active=1 AND (type='deposit' OR type='both')
                           ORDER BY id DESC")->fetchAll(PDO::FETCH_ASSOC);
      out_json(200, ['status'=>'success','methods'=>$rows]);
    }

    out_json(400, ['status'=>'error','message'=>'Unknown action']);
  }

  // ============================
  // POST
  // ============================
  if ($_SERVER['REQUEST_METHOD'] === 'POST') {

    // ✅ NEW: Create QR deposit (returns QR + deposit_id)
    if ($action === 'create_qr_deposit') {
      $s = get_settings($pdo);

      $method_id = (int)($_POST['method_id'] ?? 0);
      $coins = (int)($_POST['coins'] ?? 0);

      if ($method_id <= 0 || $coins <= 0) {
        out_json(400, ['status'=>'error','message'=>'method_id and coins required']);
      }

      if ($coins < (int)$s['min_deposit_coins']) {
        out_json(400, ['status'=>'error','message'=>'Below minimum deposit coins']);
      }

      // verify method
      $st = $pdo->prepare("SELECT id,name,account_name,account_number,qr_image
                           FROM wallet_methods
                           WHERE id=? AND is_active=1 AND (type='deposit' OR type='both')
                           LIMIT 1");
      $st->execute([$method_id]);
      $method = $st->fetch(PDO::FETCH_ASSOC);
      if (!$method) {
        out_json(404, ['status'=>'error','message'=>'Wallet method not found']);
      }

      // calculate currency amount using wallet_settings
      $currencyCode = (string)($s['currency_code'] ?? 'NPR');
      $coinsPer = (float)($s['coins_per_currency'] ?? 1);
      if ($coinsPer <= 0) $coinsPer = 1;
      $currencyAmount = $coins / $coinsPer;

      // create deposit
      $ins = $pdo->prepare("INSERT INTO wallet_deposits (user_id, method_id, coins, currency_amount, currency_code, status, click_count)
                            VALUES (?,?,?,?,?,'initiated',0)");
      $ins->execute([$userId, $method_id, $coins, $currencyAmount, $currencyCode]);
      $depositId = (int)$pdo->lastInsertId();

      out_json(200, [
        'status' => 'success',
        'deposit_id' => $depositId,
        'method' => $method,
        'qr_image' => (string)($method['qr_image'] ?? ''),
        'coins' => $coins,
        'currency_amount' => $currencyAmount,
        'currency_code' => $currencyCode,
        'message' => 'Proceed to pay using QR then click Check Payment'
      ]);
    }

    // ✅ NEW: Check QR payment (1st click fail, 2nd reviewing)
    if ($action === 'check_qr_payment') {
      $deposit_id = (int)($_POST['deposit_id'] ?? 0);
      if ($deposit_id <= 0) out_json(400, ['status'=>'error','message'=>'deposit_id required']);

      $st = $pdo->prepare("SELECT * FROM wallet_deposits WHERE id=? AND user_id=? LIMIT 1");
      $st->execute([$deposit_id, $userId]);
      $dep = $st->fetch(PDO::FETCH_ASSOC);
      if (!$dep) out_json(404, ['status'=>'error','message'=>'Deposit not found']);

      $click = (int)$dep['click_count'] + 1;
      $pdo->prepare("UPDATE wallet_deposits SET click_count=?, updated_at=NOW() WHERE id=?")->execute([$click, $deposit_id]);

      if ($click === 1) {
        out_json(200, [
          'status' => 'error',
          'message' => 'Payment not received'
        ]);
      }

      // click >= 2
      $pdo->prepare("UPDATE wallet_deposits SET status='reviewing', updated_at=NOW() WHERE id=?")->execute([$deposit_id]);

      out_json(200, [
        'status' => 'reviewing',
        'message' => 'Payment under review. Please wait some time.'
      ]);
    }

    // OLD: manual request deposit/withdraw (admin approves)
    $s = get_settings($pdo);

    if ($action === 'request_deposit' || $action === 'request_withdraw') {
      $reqType = ($action === 'request_deposit') ? 'deposit' : 'withdraw';

      $coins = (int)($_POST['coins'] ?? 0);
      if ($coins <= 0) out_json(400, ['status'=>'error','message'=>'coins required']);

      if ($reqType === 'withdraw' && $coins < (int)$s['min_withdraw_coins']) {
        out_json(400, ['status'=>'error','message'=>'Below minimum withdraw coins']);
      }
      if ($reqType === 'deposit' && $coins < (int)$s['min_deposit_coins']) {
        out_json(400, ['status'=>'error','message'=>'Below minimum deposit coins']);
      }

      $currencyCode = (string)($s['currency_code'] ?? 'NPR');
      $coinsPer = (float)($s['coins_per_currency'] ?? 1);
      if ($coinsPer <= 0) $coinsPer = 1;
      $currencyAmount = $coins / $coinsPer;

      $method = trim((string)($_POST['method'] ?? ''));
      $note = trim((string)($_POST['note'] ?? ''));

      // optional proof screenshot upload
      $proofUrl = null;
      if (!empty($_FILES['proof']) && is_uploaded_file($_FILES['proof']['tmp_name'])) {
        $dir = __DIR__ . '/uploads/wallet/';
        if (!is_dir($dir)) @mkdir($dir, 0777, true);

        $ext = pathinfo((string)$_FILES['proof']['name'], PATHINFO_EXTENSION);
        $ext = $ext ? '.'.preg_replace('/[^a-zA-Z0-9]/', '', $ext) : '';
        $name = uniqid('proof_', true).$ext;

        if (move_uploaded_file($_FILES['proof']['tmp_name'], $dir.$name)) {
          $proofUrl = base_url($config)."/api/v1/uploads/wallet/".$name;
        }
      }

      $st = $pdo->prepare("INSERT INTO wallet_requests (user_id, req_type, coins, currency_amount, currency_code, method, proof_url, status)
                           VALUES (?,?,?,?,?,?,?, 'pending')");
      $st->execute([
        $userId,
        $reqType,
        $coins,
        $currencyAmount,
        $currencyCode,
        ($method !== '' ? $method : null),
        $proofUrl
      ]);

      $reqId = (int)$pdo->lastInsertId();

      // tx record as pending
      add_tx(
        $pdo,
        $userId,
        $reqType,
        ($reqType==='deposit' ? 'credit' : 'debit'),
        $coins,
        $currencyAmount,
        $currencyCode,
        'pending',
        'req:'.$reqId,
        ($note !== '' ? $note : null)
      );

      out_json(200, ['status'=>'success','request_id'=>$reqId]);
    }

    out_json(400, ['status'=>'error','message'=>'Unknown action']);
  }

  out_json(405, ['status'=>'error','message'=>'Method not allowed']);
} catch (Throwable $e) {
  out_json(500, ['status'=>'error','message'=>'Server error','detail'=>$e->getMessage()]);
}