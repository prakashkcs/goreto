<?php
header('Content-Type: application/json; charset=utf-8');
require_once __DIR__ . '/db_connect.php';
require_once __DIR__ . '/auth_middleware.php';

$viewer = requireUser($pdo);
$userId = (int)$viewer['id'];
$method = $_SERVER['REQUEST_METHOD'];

// Handle GET: Fetch withdrawal history
if ($method === 'GET') {
    try {
        $stmt = $pdo->prepare("SELECT * FROM withdrawals WHERE user_id = ? ORDER BY created_at DESC");
        $stmt->execute([$userId]);
        $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

        // Map status and include reject_reason
        $data = array_map(function ($r) {
            return [
            'id' => $r['id'],
            'coins' => intval($r['coins']),
            'amount' => floatval($r['amount']),
            'method' => $r['payment_method'],
            'details' => $r['payment_details'],
            'status' => $r['status'], // pending, accepted, rejected
            'reject_reason' => $r['reject_reason'] ?? '',
            'created_at' => $r['created_at']
            ];
        }, $rows);

        out_json(200, ['status' => true, 'data' => $data]);
    }
    catch (Exception $e) {
        out_json(500, ['status' => false, 'message' => $e->getMessage()]);
    }
}

// Handle POST: Request withdrawal
if ($method === 'POST') {
    $in = json_decode(file_get_contents("php://input"), true) ?: $_POST;

    $coins = intval($in['coins'] ?? 0);
    $methodName = trim((string)($in['payment_method'] ?? ''));
    $details = trim((string)($in['payment_details'] ?? ''));

    if ($coins <= 0)
        out_json(400, ['status' => false, 'message' => 'Invalid coins amount']);
    if (!$methodName || !$details)
        out_json(400, ['status' => false, 'message' => 'Payment info required']);

    if (intval($viewer['coins']) < $coins) {
        out_json(400, ['status' => false, 'message' => 'Insufficient coins balance']);
    }

    try {
        $pdo->beginTransaction();

        // Deduct coins immediately
        $stBal = $pdo->prepare("UPDATE users SET coins = coins - ? WHERE id = ?");
        $stBal->execute([$coins, $userId]);

        // Record withdrawal request
        $stReq = $pdo->prepare("INSERT INTO withdrawals (user_id, coins, payment_method, payment_details, status) VALUES (?, ?, ?, ?, 'pending')");
        $stReq->execute([$userId, $coins, $methodName, $details]);

        // Insert notification
        try {
            $stNotif = $pdo->prepare("INSERT INTO app_notifications (user_id, type, title, message) VALUES (?, 'withdrawal', 'Withdrawal Requested', ?)");
            $stNotif->execute([$userId, "Your request for $coins c via $methodName is pending review."]);
        }
        catch (Exception $e) {
        // Ignore notification errors to not block withdrawal
        }

        $pdo->commit();
        out_json(200, ['status' => true, 'message' => 'Withdrawal request submitted']);
    }
    catch (Exception $e) {
        $pdo->rollBack();
        out_json(500, ['status' => false, 'message' => $e->getMessage()]);
    }
}
