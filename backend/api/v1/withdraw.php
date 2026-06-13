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

function ensure_withdrawal_table(PDO $pdo): void
{
    try {
        $pdo->query("SELECT 1 FROM withdrawals LIMIT 1");
    }
    catch (Throwable $e) {
        $pdo->exec("
            CREATE TABLE IF NOT EXISTS withdrawals (
                id INT AUTO_INCREMENT PRIMARY KEY,
                user_id INT NOT NULL,
                coins BIGINT NOT NULL,
                usd_amount DECIMAL(10,2) NOT NULL,
                payment_method VARCHAR(50) NOT NULL,
                payment_details TEXT NOT NULL,
                status ENUM('pending','approved','rejected') NOT NULL DEFAULT 'pending',
                admin_notes TEXT NULL,
                created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                INDEX(user_id),
                INDEX(status)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        ");
    }

    // Ensure admin_notes column exists (may be missing from earlier schema)
    try {
        $pdo->query("SELECT admin_notes FROM withdrawals LIMIT 0");
    }
    catch (Throwable $e) {
        try {
            $pdo->exec("ALTER TABLE withdrawals ADD COLUMN admin_notes TEXT NULL AFTER status");
        }
        catch (Throwable $e2) {
        }
    }
}

try {
    ensure_withdrawal_table($pdo);
    $viewer = requireUser($pdo);
    $user_id = (int)$viewer['id'];

    if ($_SERVER['REQUEST_METHOD'] === 'POST') {
        $raw = file_get_contents('php://input');
        $body = json_decode($raw, true) ?? $_POST;

        $coins = (int)($body['coins'] ?? 0);
        $paymentMethod = trim((string)($body['payment_method'] ?? ''));
        $paymentDetails = trim((string)($body['payment_details'] ?? ''));

        if ($coins < 100) {
            out_json(400, ['status' => false, 'message' => 'Minimum withdrawal is 100 coins']);
        }
        if (empty($paymentMethod) || empty($paymentDetails)) {
            out_json(400, ['status' => false, 'message' => 'Payment method and details are required']);
        }

        // Conversion Rate: 100 coins = $1.00 USD
        $conversionRate = 0.01;
        $usdAmount = $coins * $conversionRate;

        $pdo->beginTransaction();

        // Lock wallet row for update
        $st = $pdo->prepare("SELECT balance_coins, locked_coins FROM user_wallets WHERE user_id=? LIMIT 1 FOR UPDATE");
        $st->execute([$user_id]);
        $wallet = $st->fetch(PDO::FETCH_ASSOC);

        if (!$wallet) {
            $pdo->rollBack();
            out_json(400, ['status' => false, 'message' => 'Wallet not found']);
        }

        $balance = (int)$wallet['balance_coins'];
        if ($balance < $coins) {
            $pdo->rollBack();
            out_json(400, ['status' => false, 'message' => 'Insufficient coin balance']);
        }

        // Create pending withdrawal
        $st = $pdo->prepare("INSERT INTO withdrawals (user_id, coins, usd_amount, payment_method, payment_details, status) VALUES (?,?,?,?,?,?)");
        $st->execute([$user_id, $coins, $usdAmount, $paymentMethod, $paymentDetails, 'pending']);
        $withdrawalId = (int)$pdo->lastInsertId();

        // Decrement balance and increase locked coins
        $st = $pdo->prepare("UPDATE user_wallets SET balance_coins = balance_coins - ?, locked_coins = locked_coins + ?, updated_at = NOW() WHERE user_id = ?");
        $st->execute([$coins, $coins, $user_id]);

        // Add to wallet_transactions
        $ref = 'wd_req_' . $withdrawalId;
        $st = $pdo->prepare("INSERT INTO wallet_transactions (user_id, type, direction, coins, status, reference, note) VALUES (?,?,?,?,?,?,?)");
        $st->execute([$user_id, 'withdrawal', 'debit', $coins, 'pending', $ref, 'Requested withdrawal to ' . $paymentMethod]);

        // Insert app notification for withdrawal request
        try {
            $pdo->prepare("INSERT INTO app_notifications (user_id, title, body) VALUES (?, ?, ?)")
                ->execute([$user_id, 'Withdrawal Requested', "Your withdrawal of {$coins} coins is pending review."]);
        }
        catch (Throwable $e) {
        }

        $pdo->commit();

        $newBal = $balance - $coins;
        out_json(200, ['status' => true, 'message' => 'Withdrawal request submitted successfully', 'balance' => $newBal]);
    }

    if ($_SERVER['REQUEST_METHOD'] === 'GET') {
        // List user's withdrawal requests including admin_notes (rejection reason)
        $st = $pdo->prepare("SELECT id, coins, usd_amount as amount_usd, payment_method, status, admin_notes, created_at FROM withdrawals WHERE user_id=? ORDER BY created_at DESC");
        $st->execute([$user_id]);
        $history = $st->fetchAll(PDO::FETCH_ASSOC);

        out_json(200, ['status' => true, 'data' => $history]);
    }

}
catch (Throwable $e) {
    if ($pdo && $pdo->inTransaction()) {
        $pdo->rollBack();
    }
    out_json(500, ['status' => false, 'message' => 'Server error', 'error' => $e->getMessage()]);
}
