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

const REFERRAL_REWARD = 100;

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

        // The wallet screen advertises "+100 each"; pay what it promises.
        $referrerReward = REFERRAL_REWARD;
        $referredReward = REFERRAL_REWARD;

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

            // Wallet history entries. Without them the coins arrived silently
            // and both people reported that nothing was received.
            $tx = $pdo->prepare("INSERT INTO wallet_transactions (user_id, type, direction, coins, status, reference, note)
                                 VALUES (?, 'referral_bonus', 'credit', ?, 'completed', ?, ?)");
            $tx->execute([$referrerId, $referrerReward, 'ref_' . $userId, 'Referral bonus: a friend used your code']);
            $tx->execute([$userId, $referredReward, 'ref_' . $referrerId, "Referral bonus: used code $code"]);

            $pdo->commit();
        } catch (Throwable $e) {
            $pdo->rollBack();
            out(['status' => 'error', 'message' => 'Could not apply referral: ' . $e->getMessage()], 500);
        }

        // Tell the code owner they earned coins.
        try {
            require_once __DIR__ . '/notification_helper.php';
            if (function_exists('send_app_notification')) {
                $nm = $pdo->prepare("SELECT COALESCE(NULLIF(name, ''), username, 'Someone') FROM users WHERE id = ?");
                $nm->execute([$userId]);
                $who = (string) ($nm->fetchColumn() ?: 'Someone');
                send_app_notification($pdo, $referrerId, $userId, 'referral', 'Referral bonus',
                    "$who used your referral code. +$referrerReward coins added to your wallet.");
            }
        } catch (Throwable $e) { /* reward already saved */ }

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
        $code = (string) ($cSt->fetchColumn() ?: '');

        // Nobody had a code stored, so the app showed one it made up locally
        // and every redemption failed as "invalid". Persist a real code now —
        // preferring the one this phone already displayed (and the user may
        // have shared), as long as no one else owns it.
        if ($code === '') {
            $taken = $pdo->prepare("SELECT 1 FROM users WHERE UPPER(referral_code) = ? LIMIT 1");
            $local = strtoupper(preg_replace('/[^A-Za-z0-9]/', '', (string) ($merged['local_code'] ?? '')));
            $candidate = '';
            if (strlen($local) >= 4 && strlen($local) <= 20) {
                $taken->execute([$local]);
                if (!$taken->fetchColumn()) $candidate = $local;
            }
            for ($i = 0; $candidate === '' && $i < 10; $i++) {
                $try = strtoupper(substr(bin2hex(random_bytes(6)), 0, 8));
                $taken->execute([$try]);
                if (!$taken->fetchColumn()) $candidate = $try;
            }
            $pdo->prepare("UPDATE users SET referral_code = ? WHERE id = ? AND (referral_code IS NULL OR referral_code = '')")
                ->execute([$candidate, $userId]);
            $cSt->execute([$userId]);
            $code = (string) ($cSt->fetchColumn() ?: $candidate);
        }

        // Has this account already redeemed someone's code? The wallet hides
        // the redeem box when so (it showed it, then said "already used").
        $usedSt = $pdo->prepare("SELECT COALESCE(referral_used, 0) AS used, COALESCE(referral_used_code, '') AS used_code FROM users WHERE id = ?");
        try { $usedSt->execute([$userId]); $usedRow = $usedSt->fetch(PDO::FETCH_ASSOC) ?: []; }
        catch (Throwable $e) { $usedRow = []; }

        out([
            'status'             => 'success',
            'referral_code'      => $code,
            'coins_reward'       => REFERRAL_REWARD,
            'referral_used'      => (int) ($usedRow['used'] ?? 0),
            'referral_used_code' => (string) ($usedRow['used_code'] ?? ''),
            'plans'              => [],
        ]);
    }

    // ── Live availability check while editing a code (like usernames) ─────────
    if ($action === 'check_code') {
        $c = strtoupper(trim((string) ($merged['code'] ?? '')));
        if (strlen($c) < 4 || strlen($c) > 20 || !preg_match('/^[A-Z0-9]+$/', $c)) {
            out(['status' => 'success', 'available' => false, 'message' => 'Use 4-20 letters or numbers']);
        }
        $st = $pdo->prepare("SELECT id FROM users WHERE UPPER(referral_code) = ? LIMIT 1");
        $st->execute([$c]);
        $owner = (int) ($st->fetchColumn() ?: 0);
        out([
            'status'    => 'success',
            'available' => $owner === 0 || $owner === $userId,
            'message'   => ($owner === 0 || $owner === $userId) ? 'Available' : 'Not available',
        ]);
    }

    out(['status' => 'error', 'message' => 'Unknown action'], 400);
} catch (Throwable $e) {
    http_response_code(500);
    echo json_encode(['status' => 'error', 'message' => $e->getMessage()]);
}
