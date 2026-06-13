<?php
/**
 * api_referral.php  —  Referral code management
 *
 * POST ?action=apply         { code }  → redeem someone else's referral code
 * GET/POST ?action=settings         → fetch current user's referral code
 * GET/POST ?action=get_plans        → fetch referral plan settings
 */
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Content-Type, Authorization');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }

require_once __DIR__ . '/db_connect.php';
require_once __DIR__ . '/auth_middleware.php';

function out(array $d, int $code = 200): void {
    http_response_code($code);
    echo json_encode($d);
    exit;
}

try {
    $viewer = requireUser($pdo);
    $userId = (int)$viewer['id'];

    $raw    = file_get_contents('php://input');
    $body   = json_decode($raw, true) ?? [];
    $merged = array_merge($_GET, $_POST, $body);
    $action = strtolower(trim($merged['action'] ?? 'settings'));

    // ── Apply a referral code ──────────────────────────────────────────────────
    if ($action === 'apply') {
        $code = strtoupper(trim($merged['code'] ?? $merged['referral_code'] ?? ''));
        if (empty($code)) out(['status' => 'error', 'message' => 'Please enter a referral code'], 400);

        // Ensure referral columns exist
        try {
            $pdo->exec("ALTER TABLE users ADD COLUMN IF NOT EXISTS referral_used TINYINT(1) NOT NULL DEFAULT 0");
            $pdo->exec("ALTER TABLE users ADD COLUMN IF NOT EXISTS referral_used_code VARCHAR(20) NULL");
            $pdo->exec("ALTER TABLE users ADD COLUMN IF NOT EXISTS referral_code VARCHAR(20) NULL");
            $pdo->exec("ALTER TABLE users ADD COLUMN IF NOT EXISTS is_banned TINYINT(1) NOT NULL DEFAULT 0");
        } catch (Throwable $e) {}

        // Has the current user already used a referral?
        $uSt = $pdo->prepare("SELECT COALESCE(referral_used, 0) AS used FROM users WHERE id = ?");
        $uSt->execute([$userId]);
        $uRow = $uSt->fetch(PDO::FETCH_ASSOC) ?: [];
        if (!empty($uRow['used'])) {
            out(['status' => 'error', 'message' => 'You have already used a referral code.']);
        }

        // Find the referral code owner (cannot use your own code)
        $cSt = $pdo->prepare("SELECT id, name FROM users WHERE UPPER(referral_code) = ? AND id != ? AND is_banned = 0 LIMIT 1");
        $cSt->execute([$code, $userId]);
        $referrer = $cSt->fetch(PDO::FETCH_ASSOC);
        if (!$referrer) {
            out(['status' => 'error', 'message' => 'Invalid referral code. Please check and try again.']);
        }

        $referrerId = (int)$referrer['id'];

        // Reward amounts (coins) — adjust as needed
        $referrerReward = 50;
        $referredReward = 20;

        $pdo->beginTransaction();
        try {
            // Credit referrer
            $pdo->prepare("INSERT INTO user_wallets (user_id, balance_coins, locked_coins) VALUES (?, ?, 0)
                ON DUPLICATE KEY UPDATE balance_coins = balance_coins + ?")->execute([$referrerId, $referrerReward, $referrerReward]);

            // Credit referred user
            $pdo->prepare("INSERT INTO user_wallets (user_id, balance_coins, locked_coins) VALUES (?, ?, 0)
                ON DUPLICATE KEY UPDATE balance_coins = balance_coins + ?")->execute([$userId, $referredReward, $referredReward]);

            // Mark referral as used
            $pdo->prepare("UPDATE users SET referral_used = 1, referral_used_code = ? WHERE id = ?")
                ->execute([$code, $userId]);

            $pdo->commit();
        } catch (Throwable $e) {
            $pdo->rollBack();
            out(['status' => 'error', 'message' => 'Could not apply referral: ' . $e->getMessage()], 500);
        }

        // Return new balance
        $bSt = $pdo->prepare("SELECT COALESCE(balance_coins, 0) FROM user_wallets WHERE user_id = ? LIMIT 1");
        $bSt->execute([$userId]);
        $newBalance = (int)($bSt->fetchColumn() ?? 0);

        out([
            'status'       => 'success',
            'message'      => "Referral applied! You received $referredReward coins.",
            'coins_earned' => $referredReward,
            'balance'      => $newBalance,
        ]);
    }

    // ── Get settings / referral code ───────────────────────────────────────────
    if ($action === 'settings' || $action === 'get_plans') {
        $cSt = $pdo->prepare("SELECT COALESCE(referral_code, '') AS referral_code FROM users WHERE id = ?");
        $cSt->execute([$userId]);
        $row = $cSt->fetch(PDO::FETCH_ASSOC) ?: ['referral_code' => ''];
        out([
            'status'        => 'success',
            'referral_code' => $row['referral_code'],
            'plans'         => [],
        ]);
    }

    out(['status' => 'error', 'message' => 'Unknown action'], 400);
} catch (Throwable $e) {
    http_response_code(500);
    echo json_encode(['status' => 'error', 'message' => $e->getMessage()]);
}
