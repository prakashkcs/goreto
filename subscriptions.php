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

function out_json(int $code, array $payload): void
{
    http_response_code($code);
    echo json_encode($payload);
    exit;
}

// ── Auto-migration ──────────────────────────────────────────────────────────
try {
    $pdo->exec("CREATE TABLE IF NOT EXISTS `subscription_plans` (
        `id` INT AUTO_INCREMENT PRIMARY KEY,
        `creator_id` INT NOT NULL,
        `name` VARCHAR(100) NOT NULL,
        `price_coins` INT NOT NULL DEFAULT 0,
        `duration_days` INT NOT NULL DEFAULT 30,
        `custom_features` TEXT NULL,
        `can_message_first` TINYINT(1) DEFAULT 0,
        `is_active` TINYINT(1) NOT NULL DEFAULT 1,
        `created_at` DATETIME DEFAULT CURRENT_TIMESTAMP,
        KEY `idx_creator` (`creator_id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;");

    // Ensure columns exist for older tables
    try {
        $pdo->exec("ALTER TABLE `subscription_plans` ADD COLUMN `custom_features` TEXT NULL");
    }
    catch (Throwable $e) {
    }
    try {
        $pdo->exec("ALTER TABLE `subscription_plans` ADD COLUMN `can_message_first` TINYINT(1) DEFAULT 0");
    }
    catch (Throwable $e) {
    }

    $pdo->exec("CREATE TABLE IF NOT EXISTS `user_subscriptions` (
        `id` INT AUTO_INCREMENT PRIMARY KEY,
        `subscriber_id` INT NOT NULL,
        `creator_id` INT NOT NULL,
        `plan_id` INT NOT NULL,
        `started_at` DATETIME DEFAULT CURRENT_TIMESTAMP,
        `expires_at` DATETIME NOT NULL,
        `status` VARCHAR(20) NOT NULL DEFAULT 'active',
        KEY `idx_subscriber` (`subscriber_id`),
        KEY `idx_creator` (`creator_id`),
        UNIQUE KEY `uq_active_sub` (`subscriber_id`, `creator_id`, `status`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;");
}
catch (Throwable $e) {
// Tables may already exist — ignore
}

// ── Router ──────────────────────────────────────────────────────────────────
try {
    $action = strtolower(trim($_REQUEST['action'] ?? ''));

    // ──────────────── PUBLIC GET: get_plans ────────────────
    if ($_SERVER['REQUEST_METHOD'] === 'GET' && $action === 'get_plans') {
        $creatorId = intval($_GET['creator_id'] ?? 0);
        if ($creatorId <= 0)
            out_json(400, ['status' => 'error', 'message' => 'creator_id required']);

        $st = $pdo->prepare("SELECT * FROM subscription_plans WHERE creator_id = ? AND is_active = 1 ORDER BY price_coins ASC");
        $st->execute([$creatorId]);
        $plans = $st->fetchAll(PDO::FETCH_ASSOC);
        out_json(200, ['status' => 'success', 'plans' => $plans]);
    }

    // Everything below requires auth
    $viewer = requireUser($pdo);
    $userId = (int)$viewer['id'];

    // ──────────────── GET: my_plans ────────────────
    if ($_SERVER['REQUEST_METHOD'] === 'GET' && ($action === 'my_plans' || $action === '')) {
        $st = $pdo->prepare("SELECT * FROM subscription_plans WHERE creator_id = ? AND is_active = 1 ORDER BY id ASC");
        $st->execute([$userId]);
        $plans = $st->fetchAll(PDO::FETCH_ASSOC);
        out_json(200, ['status' => 'success', 'plans' => $plans]);
    }

    // ──────────────── GET: check ────────────────
    if ($_SERVER['REQUEST_METHOD'] === 'GET' && $action === 'check') {
        $creatorId = intval($_GET['creator_id'] ?? 0);
        if ($creatorId <= 0)
            out_json(400, ['status' => 'error', 'message' => 'creator_id required']);

        // Self-check always true
        if ($creatorId === $userId) {
            out_json(200, ['status' => 'success', 'is_subscribed' => true, 'plan' => null]);
        }

        $st = $pdo->prepare("SELECT us.*, sp.name AS plan_name, sp.price_coins
            FROM user_subscriptions us
            JOIN subscription_plans sp ON sp.id = us.plan_id
            WHERE us.subscriber_id = ? AND us.creator_id = ? AND us.status = 'active' AND us.expires_at > NOW()
            LIMIT 1");
        $st->execute([$userId, $creatorId]);
        $sub = $st->fetch(PDO::FETCH_ASSOC);

        out_json(200, [
            'status' => 'success',
            'is_subscribed' => $sub ? true : false,
            'subscription' => $sub ?: null,
        ]);
    }

    // ──────────────── GET: my_subscriptions ────────────────
    if ($_SERVER['REQUEST_METHOD'] === 'GET' && ($action === 'my_subscriptions' || $action === 'subscriptions')) {
        $st = $pdo->prepare("
            SELECT us.*, sp.name AS plan_name, sp.price_coins, u.name AS creator_name, u.profile_pic AS creator_avatar
            FROM user_subscriptions us
            JOIN subscription_plans sp ON sp.id = us.plan_id
            JOIN users u ON u.id = us.creator_id
            WHERE us.subscriber_id = ? AND us.status = 'active' AND us.expires_at > NOW()
            ORDER BY us.started_at DESC
        ");
        $st->execute([$userId]);
        $subs = $st->fetchAll(PDO::FETCH_ASSOC);
        out_json(200, ['status' => 'success', 'subscriptions' => $subs]);
    }

    // ──────────────── POST actions ────────────────
    if ($_SERVER['REQUEST_METHOD'] === 'POST') {
        $body = json_decode(file_get_contents('php://input'), true) ?? $_POST;

        // ── create_plan ──
        if ($action === 'create_plan') {
            // Check limit (max 2)
            $countSt = $pdo->prepare("SELECT COUNT(*) FROM subscription_plans WHERE creator_id = ? AND is_active = 1");
            $countSt->execute([$userId]);
            if ($countSt->fetchColumn() >= 2) {
                out_json(400, ['status' => 'error', 'message' => 'Maximum 2 plans allowed']);
            }

            $name = trim($body['name'] ?? '');
            $priceCoins = intval($body['price_coins'] ?? 0);
            $durationDays = intval($body['duration_days'] ?? 30);
            $customFeatures = $body['custom_features'] ?? null;
            if (is_array($customFeatures))
                $customFeatures = json_encode($customFeatures);
            $canMsg = (isset($body['can_message_first']) && ($body['can_message_first'] == '1' || $body['can_message_first'] == true)) ? 1 : 0;

            if ($name === '')
                out_json(400, ['status' => 'error', 'message' => 'Plan name is required']);
            if ($priceCoins <= 0)
                out_json(400, ['status' => 'error', 'message' => 'Price must be greater than 0']);
            if ($durationDays <= 0)
                $durationDays = 30;

            $st = $pdo->prepare("INSERT INTO subscription_plans (creator_id, name, price_coins, duration_days, custom_features, can_message_first) VALUES (?, ?, ?, ?, ?, ?)");
            $st->execute([$userId, $name, $priceCoins, $durationDays, $customFeatures, $canMsg]);
            $planId = $pdo->lastInsertId();

            $fetchSt = $pdo->prepare("SELECT * FROM subscription_plans WHERE id = ?");
            $fetchSt->execute([$planId]);
            out_json(200, ['status' => 'success', 'message' => 'Plan created', 'plan' => $fetchSt->fetch(PDO::FETCH_ASSOC)]);
        }

        // ── update_plan ──
        if ($action === 'update_plan') {
            $planId = intval($body['plan_id'] ?? $body['id'] ?? 0);
            if ($planId <= 0)
                out_json(400, ['status' => 'error', 'message' => 'plan_id required']);

            // Verify ownership
            $chk = $pdo->prepare("SELECT * FROM subscription_plans WHERE id = ? AND creator_id = ?");
            $chk->execute([$planId, $userId]);
            if (!$chk->fetch())
                out_json(403, ['status' => 'error', 'message' => 'Not your plan']);

            $sets = [];
            $params = [];
            if (isset($body['name']) && trim($body['name']) !== '') {
                $sets[] = "name = ?";
                $params[] = trim($body['name']);
            }
            if (isset($body['price_coins'])) {
                $sets[] = "price_coins = ?";
                $params[] = intval($body['price_coins']);
            }
            if (isset($body['duration_days'])) {
                $sets[] = "duration_days = ?";
                $params[] = intval($body['duration_days']);
            }
            if (isset($body['custom_features'])) {
                $f = $body['custom_features'];
                if (is_array($f))
                    $f = json_encode($f);
                $sets[] = "custom_features = ?";
                $params[] = $f;
            }
            if (isset($body['can_message_first'])) {
                $sets[] = "can_message_first = ?";
                $params[] = ($body['can_message_first'] == '1' || $body['can_message_first'] == true) ? 1 : 0;
            }
            if (empty($sets))
                out_json(400, ['status' => 'error', 'message' => 'Nothing to update']);

            $params[] = $planId;
            $pdo->prepare("UPDATE subscription_plans SET " . implode(', ', $sets) . " WHERE id = ?")->execute($params);

            $fetchSt = $pdo->prepare("SELECT * FROM subscription_plans WHERE id = ?");
            $fetchSt->execute([$planId]);
            out_json(200, ['status' => 'success', 'message' => 'Plan updated', 'plan' => $fetchSt->fetch(PDO::FETCH_ASSOC)]);
        }

        // ── delete_plan ──
        if ($action === 'delete_plan') {
            $planId = intval($body['plan_id'] ?? $body['id'] ?? 0);
            if ($planId <= 0)
                out_json(400, ['status' => 'error', 'message' => 'plan_id required']);

            $chk = $pdo->prepare("SELECT * FROM subscription_plans WHERE id = ? AND creator_id = ?");
            $chk->execute([$planId, $userId]);
            if (!$chk->fetch())
                out_json(403, ['status' => 'error', 'message' => 'Not your plan']);

            // Soft-delete
            $pdo->prepare("UPDATE subscription_plans SET is_active = 0 WHERE id = ?")->execute([$planId]);
            out_json(200, ['status' => 'success', 'message' => 'Plan deleted']);
        }

        // ── subscribe ──
        if ($action === 'subscribe') {
            $planId = intval($body['plan_id'] ?? 0);
            if ($planId <= 0)
                out_json(400, ['status' => 'error', 'message' => 'plan_id required']);

            // Get plan
            $planSt = $pdo->prepare("SELECT * FROM subscription_plans WHERE id = ? AND is_active = 1");
            $planSt->execute([$planId]);
            $plan = $planSt->fetch(PDO::FETCH_ASSOC);
            if (!$plan)
                out_json(404, ['status' => 'error', 'message' => 'Plan not found']);

            $creatorId = intval($plan['creator_id']);
            if ($creatorId === $userId)
                out_json(400, ['status' => 'error', 'message' => 'Cannot subscribe to yourself']);

            // Check existing active subscription
            $existSt = $pdo->prepare("SELECT id FROM user_subscriptions WHERE subscriber_id = ? AND creator_id = ? AND status = 'active' AND expires_at > NOW()");
            $existSt->execute([$userId, $creatorId]);
            if ($existSt->fetch())
                out_json(400, ['status' => 'error', 'message' => 'Already subscribed to this creator']);

            // Deduct coins from wallet
            $walletSt = $pdo->prepare("SELECT balance_coins FROM user_wallets WHERE user_id = ?");
            $walletSt->execute([$userId]);
            $currentCoins = intval($walletSt->fetchColumn());
            $price = intval($plan['price_coins']);

            if ($currentCoins < $price) {
                out_json(400, ['status' => 'error', 'message' => 'Insufficient coins. You need ' . $price . ' coins.']);
            }

            // Deduct
            $pdo->prepare("UPDATE user_wallets SET balance_coins = balance_coins - ? WHERE user_id = ?")->execute([$price, $userId]);

            // Credit creator
            $pdo->prepare("INSERT INTO user_wallets (user_id, balance_coins, locked_coins) VALUES (?, ?, 0) ON DUPLICATE KEY UPDATE balance_coins = balance_coins + ?")->execute([$creatorId, $price, $price]);

            // Create subscription
            $durationDays = intval($plan['duration_days']);
            $pdo->prepare("INSERT INTO user_subscriptions (subscriber_id, creator_id, plan_id, expires_at, status) VALUES (?, ?, ?, DATE_ADD(NOW(), INTERVAL ? DAY), 'active')")
                ->execute([$userId, $creatorId, $planId, $durationDays]);

            out_json(200, ['status' => 'success', 'message' => 'Subscribed successfully! ' . $price . ' coins deducted.']);
        }

        // ── cancel ──
        if ($action === 'cancel' || $action === 'cancel_subscription') {
            $subId = intval($body['subscription_id'] ?? $body['id'] ?? 0);
            if ($subId <= 0)
                out_json(400, ['status' => 'error', 'message' => 'subscription_id required']);

            $chk = $pdo->prepare("SELECT * FROM user_subscriptions WHERE id = ? AND subscriber_id = ?");
            $chk->execute([$subId, $userId]);
            if (!$chk->fetch())
                out_json(403, ['status' => 'error', 'message' => 'Not your subscription']);

            $pdo->prepare("UPDATE user_subscriptions SET status = 'cancelled' WHERE id = ?")->execute([$subId]);
            out_json(200, ['status' => 'success', 'message' => 'Subscription cancelled']);
        }

        out_json(400, ['status' => 'error', 'message' => 'Unknown action']);
    }

    out_json(400, ['status' => 'error', 'message' => 'Unknown action']);

}
catch (Throwable $e) {
    out_json(500, ['status' => 'error', 'message' => 'Server error', 'detail' => $e->getMessage()]);
}
?>
