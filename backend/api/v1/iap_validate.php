<?php
/**
 * iap_validate.php — Validate a native store purchase (Apple IAP / Google Play
 * Billing) and credit coins. The client NEVER credits coins; this endpoint is
 * the single source of truth.
 *
 * POST JSON: { product_id, coins, source, receipt, transaction_id }
 *
 * Security:
 *   - Coin amount is resolved server-side from product_id (client value ignored)
 *   - transaction_id is unique -> no double credit / replay
 *   - Apple receipts verified against Apple; Google purchases are default-denied
 *     until a Play service account is configured (never credit unverified)
 */
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Content-Type, Authorization');
header('Access-Control-Allow-Methods: POST, OPTIONS');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); echo '{}'; exit; }

require_once __DIR__ . '/db_connect.php';
require_once __DIR__ . '/auth_middleware.php';

function jout(int $code, array $arr): void { http_response_code($code); echo json_encode($arr); exit; }

if (!isset($pdo) || !($pdo instanceof PDO)) jout(500, ['status' => 'error', 'message' => 'DB error']);

$user = requireUser($pdo);
$userId = (int) $user['id'];

// Server-authoritative product -> coins map (must match the client packages).
$PRODUCT_COINS = [
    'coins_100'  => 100,
    'coins_500'  => 500,
    'coins_1000' => 1000,
    'coins_5000' => 5000,
];

$body = json_decode(file_get_contents('php://input'), true) ?? $_POST;
$productId     = (string) ($body['product_id'] ?? '');
$source        = (string) ($body['source'] ?? '');
$receipt       = (string) ($body['receipt'] ?? '');
$transactionId = (string) ($body['transaction_id'] ?? '');

if ($productId === '' || $receipt === '' || $transactionId === '') {
    jout(400, ['status' => 'error', 'message' => 'Missing purchase data']);
}
if (!isset($PRODUCT_COINS[$productId])) {
    jout(400, ['status' => 'error', 'message' => 'Unknown product']);
}
$coins = (int) $PRODUCT_COINS[$productId];

// Replay protection table
$pdo->exec("CREATE TABLE IF NOT EXISTS iap_purchases (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    product_id VARCHAR(64) NOT NULL,
    coins INT NOT NULL,
    source VARCHAR(32) NOT NULL,
    transaction_id VARCHAR(191) NOT NULL,
    status ENUM('credited','rejected') NOT NULL DEFAULT 'credited',
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uniq_txn (transaction_id),
    KEY idx_user (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

// Already processed? Return idempotent success (no double credit).
$dup = $pdo->prepare("SELECT status FROM iap_purchases WHERE transaction_id = ? LIMIT 1");
$dup->execute([$transactionId]);
$existing = $dup->fetchColumn();
if ($existing !== false) {
    if ($existing === 'credited') {
        jout(200, ['status' => 'success', 'message' => 'Already credited', 'duplicate' => true]);
    }
    jout(400, ['status' => 'error', 'message' => 'Purchase previously rejected']);
}

// Verify with the store
$isApple  = (stripos($source, 'apple') !== false || stripos($source, 'app_store') !== false || stripos($source, 'ios') !== false);
$isGoogle = (stripos($source, 'google') !== false || stripos($source, 'play') !== false || stripos($source, 'android') !== false);

$verified = false;
$failReason = 'unverified';

if ($isApple) {
    // Apple verifyReceipt: try production, fall back to sandbox (status 21007).
    $sharedSecret = '';
    $secretFile = '/var/www/private/apple_shared_secret.txt';
    if (is_readable($secretFile)) $sharedSecret = trim((string) file_get_contents($secretFile));

    $payload = ['receipt-data' => $receipt];
    if ($sharedSecret !== '') $payload['password'] = $sharedSecret;

    $verifyOn = function (string $url) use ($payload) {
        $ch = curl_init($url);
        curl_setopt_array($ch, [
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_POST => true,
            CURLOPT_POSTFIELDS => json_encode($payload),
            CURLOPT_HTTPHEADER => ['Content-Type: application/json'],
            CURLOPT_TIMEOUT => 20,
        ]);
        $resp = curl_exec($ch);
        curl_close($ch);
        return $resp ? json_decode($resp, true) : null;
    };

    $res = $verifyOn('https://buy.itunes.apple.com/verifyReceipt');
    if (is_array($res) && (int) ($res['status'] ?? -1) === 21007) {
        $res = $verifyOn('https://sandbox.itunes.apple.com/verifyReceipt');
    }
    if (is_array($res) && (int) ($res['status'] ?? -1) === 0) {
        $found = false;
        foreach (($res['receipt']['in_app'] ?? []) as $item) {
            if (($item['product_id'] ?? '') === $productId) { $found = true; break; }
        }
        if (!$found) {
            foreach (($res['latest_receipt_info'] ?? []) as $item) {
                if (($item['product_id'] ?? '') === $productId) { $found = true; break; }
            }
        }
        $verified = $found;
        $failReason = $found ? '' : 'product_mismatch';
    } else {
        $failReason = 'apple_status_' . (is_array($res) ? ($res['status'] ?? 'null') : 'no_response');
    }
} elseif ($isGoogle) {
    // Google Play verification requires the Play Developer API with a service
    // account. Until configured we DEFAULT-DENY (never credit blindly).
    $saFile = '/var/www/private/google_play_service_account.json';
    if (!is_readable($saFile)) {
        $pdo->prepare("INSERT INTO iap_purchases (user_id, product_id, coins, source, transaction_id, status) VALUES (?,?,?,?,?,'rejected')")
            ->execute([$userId, $productId, $coins, 'google_play', $transactionId]);
        jout(503, ['status' => 'error', 'message' => 'Google purchase verification is not configured yet.', 'code' => 'google_verification_unavailable']);
    }
    // Full Play Developer API verification goes here once the service account
    // is in place. Default-deny until then.
    $failReason = 'google_verification_pending';
} else {
    $failReason = 'unknown_source';
}

if (!$verified) {
    $pdo->prepare("INSERT INTO iap_purchases (user_id, product_id, coins, source, transaction_id, status) VALUES (?,?,?,?,?,'rejected')")
        ->execute([$userId, $productId, $coins, $source ?: 'unknown', $transactionId]);
    jout(400, ['status' => 'error', 'message' => 'Could not verify purchase', 'code' => $failReason]);
}

// Credit coins (mirror the deposit-approval path)
try {
    $pdo->beginTransaction();
    $pdo->prepare("INSERT INTO iap_purchases (user_id, product_id, coins, source, transaction_id, status) VALUES (?,?,?,?,?,'credited')")
        ->execute([$userId, $productId, $coins, $source ?: 'store', $transactionId]);
    $pdo->prepare("INSERT IGNORE INTO user_wallets (user_id, balance_coins, locked_coins) VALUES (?,0,0)")
        ->execute([$userId]);
    $pdo->prepare("UPDATE user_wallets SET balance_coins = balance_coins + ?, updated_at = NOW() WHERE user_id = ?")
        ->execute([$coins, $userId]);
    $pdo->prepare("INSERT INTO wallet_transactions (user_id, type, direction, coins, currency_amount, currency_code, status, reference, note)
                   VALUES (?, 'iap_purchase', 'credit', ?, NULL, NULL, 'completed', ?, ?)")
        ->execute([$userId, $coins, 'iap:' . substr($transactionId, 0, 50), 'In-app purchase: ' . $productId]);
    $pdo->commit();
} catch (Throwable $e) {
    if ($pdo->inTransaction()) $pdo->rollBack();
    jout(200, ['status' => 'success', 'message' => 'Already credited', 'duplicate' => true]);
}

jout(200, ['status' => 'success', 'message' => 'Coins added', 'coins' => $coins]);
