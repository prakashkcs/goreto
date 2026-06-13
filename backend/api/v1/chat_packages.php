<?php
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Content-Type, Authorization');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') exit;

require_once __DIR__ . '/db_connect.php';
require_once __DIR__ . '/auth_middleware.php';

try {
    $viewer  = requireUser($pdo);
    $userId  = (int) $viewer['id'];
    $action  = $_REQUEST['action'] ?? '';
    $body    = (array) (json_decode(file_get_contents('php://input'), true) ?? []);

    // ── list packages for a creator ──────────────────────────────────────
    if ($action === 'list' || $action === '') {
        $creatorId = (int) ($_GET['creator_id'] ?? $userId);
        $st = $pdo->prepare("SELECT * FROM chat_time_packages WHERE creator_id = ? AND is_active = 1 ORDER BY minutes ASC");
        $st->execute([$creatorId]);
        $rows = $st->fetchAll(PDO::FETCH_ASSOC);

        // Always prepend the global free-5min entry the buyer has left
        // (we query remaining free time from sessions).
        $freeUsed = 0;
        if ($creatorId !== $userId) {
            $fsSt = $pdo->prepare("SELECT COALESCE(SUM(minutes_total),0) FROM chat_time_sessions WHERE buyer_id=? AND seller_id=? AND package_id=0");
            $fsSt->execute([$userId, $creatorId]);
            $freeUsed = (int) $fsSt->fetchColumn();
        }
        $freeMinLeft = max(0, 5 - $freeUsed);

        echo json_encode([
            'status'        => 'success',
            'packages'      => $rows,
            'free_min_left' => $freeMinLeft,
        ]);
        exit;
    }

    // ── creator: create package ───────────────────────────────────────────
    if ($action === 'create') {
        $name   = trim((string) ($body['name'] ?? $_POST['name'] ?? ''));
        $min    = max(1, (int) ($body['minutes'] ?? $_POST['minutes'] ?? 5));
        $coins  = max(0, (int) ($body['price_coins'] ?? $_POST['price_coins'] ?? 0));
        $isFree = (int) ($body['is_free'] ?? $_POST['is_free'] ?? 0);
        if (empty($name)) out_json(400, ['status'=>'error','message'=>'Name required']);
        $pdo->prepare("INSERT INTO chat_time_packages (creator_id, name, minutes, price_coins, is_free) VALUES (?, ?, ?, ?, ?)")
            ->execute([$userId, $name, $min, $coins, $isFree]);
        out_json(200, ['status'=>'success','id'=>(int)$pdo->lastInsertId()]);
    }

    // ── creator: delete package ───────────────────────────────────────────
    if ($action === 'delete') {
        $pkgId = (int) ($body['id'] ?? $_POST['id'] ?? 0);
        $pdo->prepare("UPDATE chat_time_packages SET is_active=0 WHERE id=? AND creator_id=?")->execute([$pkgId, $userId]);
        out_json(200, ['status'=>'success']);
    }

    // ── buyer: buy a package (deduct coins, create session) ───────────────
    if ($action === 'buy') {
        $pkgId    = (int) ($body['package_id'] ?? $_POST['package_id'] ?? 0);
        $sellerId = (int) ($body['seller_id']  ?? $_POST['seller_id']  ?? 0);

        if ($sellerId <= 0 || $sellerId === $userId)
            out_json(400, ['status'=>'error','message'=>'Invalid seller']);

        // Already have an active session?
        $actSt = $pdo->prepare("SELECT id, expires_at FROM chat_time_sessions WHERE buyer_id=? AND seller_id=? AND status='active' AND expires_at > UTC_TIMESTAMP() LIMIT 1");
        $actSt->execute([$userId, $sellerId]);
        $existing = $actSt->fetch(PDO::FETCH_ASSOC);
        if ($existing) {
            out_json(200, ['status'=>'success','session_id'=>(int)$existing['id'],'seconds_left'=>max(0,strtotime($existing['expires_at'])-time()),'minutes'=>5,'expires_at'=>$existing['expires_at'],'reused'=>true]);
        }

        // Free 5-min package (pkgId == 0)
        if ($pkgId === 0) {
            // Check how many free minutes this buyer has already used with this seller.
            $fsSt = $pdo->prepare("SELECT COALESCE(SUM(minutes_total),0) FROM chat_time_sessions WHERE buyer_id=? AND seller_id=? AND package_id=0");
            $fsSt->execute([$userId, $sellerId]);
            $usedFree = (int) $fsSt->fetchColumn();
            if ($usedFree >= 5)
                out_json(400, ['status'=>'error','message'=>'Free chat already used. Buy a package to continue.','error_code'=>'free_exhausted']);
            $minutes = 5;
            $coinsCost = 0;
        } else {
            $pkgSt = $pdo->prepare("SELECT * FROM chat_time_packages WHERE id=? AND creator_id=? AND is_active=1");
            $pkgSt->execute([$pkgId, $sellerId]);
            $pkg = $pkgSt->fetch(PDO::FETCH_ASSOC);
            if (!$pkg) out_json(404, ['status'=>'error','message'=>'Package not found']);
            $minutes   = (int) $pkg['minutes'];
            $coinsCost = (int) $pkg['price_coins'];
        }

        if ($coinsCost > 0) {
            $wSt = $pdo->prepare("SELECT COALESCE(balance_coins,0) FROM user_wallets WHERE user_id=? LIMIT 1");
            $wSt->execute([$userId]);
            $bal = (int) $wSt->fetchColumn();
            if ($bal < $coinsCost)
                out_json(400, ['status'=>'error','message'=>'Insufficient coins','error_code'=>'insufficient_coins','needed'=>$coinsCost,'balance'=>$bal]);
        }

        $pdo->beginTransaction();
        try {
            if ($coinsCost > 0) {
                $pdo->prepare("UPDATE user_wallets SET balance_coins = balance_coins - ? WHERE user_id = ?")->execute([$coinsCost, $userId]);
                $pdo->prepare("INSERT INTO user_wallets (user_id, balance_coins, locked_coins) VALUES (?, ?, 0) ON DUPLICATE KEY UPDATE balance_coins = balance_coins + ?")->execute([$sellerId, $coinsCost, $coinsCost]);
            }
            $pdo->prepare("INSERT INTO chat_time_sessions (buyer_id, seller_id, package_id, minutes_total, expires_at, coins_paid) VALUES (?, ?, ?, ?, DATE_ADD(UTC_TIMESTAMP(), INTERVAL ? MINUTE), ?)")
                ->execute([$userId, $sellerId, $pkgId, $minutes, $minutes, $coinsCost]);
            $sessionId = (int) $pdo->lastInsertId();
            $pdo->commit();

            // Record in wallet_transactions so it appears in transaction history
            if ($coinsCost > 0) {
                try {
                    $pkgNote = $minutes . '-min chat package';
                    $pdo->prepare("INSERT INTO wallet_transactions (user_id, type, direction, coins, status, reference, note) VALUES (?, 'chat_package', 'debit', ?, 'completed', ?, ?)")
                        ->execute([$userId, $coinsCost, 'session:' . $sessionId, $pkgNote]);
                    $pdo->prepare("INSERT INTO wallet_transactions (user_id, type, direction, coins, status, reference, note) VALUES (?, 'chat_package', 'credit', ?, 'completed', ?, ?)")
                        ->execute([$sellerId, $coinsCost, 'session:' . $sessionId, $pkgNote . ' (sold)']);
                } catch (Throwable $e) { /* non-fatal — balance already updated */ }
            }
        } catch (Throwable $e) {
            $pdo->rollBack();
            out_json(500, ['status'=>'error','message'=>'Session creation failed: '.$e->getMessage()]);
        }

        // Notify the seller (FCM) that a chat session started.
        try {
            require_once __DIR__ . '/notification_helper.php';
            $uSt = $pdo->prepare("SELECT name, username FROM users WHERE id = ?");
            $uSt->execute([$userId]);
            $u = $uSt->fetch(PDO::FETCH_ASSOC) ?: [];
            $uname = $u['name'] ?: ($u['username'] ?? 'Someone');
            $label = $pkgId === 0 ? '5-minute free chat' : $minutes.'min chat';
            send_app_notification($pdo, $sellerId, $userId, 'chat_session',
                'Chat session started',
                "$uname started a $label with you".($coinsCost > 0 ? " ($coinsCost coins)" : ''),
                $sessionId, false, [
                    'action'         => 'chat_session_started',
                    'buyer_id'       => (string)$userId,
                    'buyer_name'     => $uname,
                    'session_id'     => (string)$sessionId,
                    'minutes'        => (string)$minutes,
                    'coins_paid'     => (string)$coinsCost,
                    'expires_at'     => date('Y-m-d H:i:s', strtotime("+$minutes minutes")),
                ]);
        } catch (Throwable $e) { /* notification failure is non-fatal */ }

        $wBalSt = $pdo->prepare("SELECT COALESCE(balance_coins,0) FROM user_wallets WHERE user_id=? LIMIT 1");
        $wBalSt->execute([$userId]);
        $newBalance = (int) $wBalSt->fetchColumn();

        out_json(200, [
            'status'      => 'success',
            'session_id'  => $sessionId,
            'minutes'     => $minutes,
            'seconds_left' => $minutes * 60,
            'coins_paid'  => $coinsCost,
            'balance'     => $newBalance,
            'expires_at'  => gmdate('Y-m-d\TH:i:s\Z', time() + ($minutes * 60)),
        ]);
    }

    // ── session status ────────────────────────────────────────────────────
    if ($action === 'session_status') {
        $sellerId = (int) ($_GET['seller_id'] ?? 0);
        if ($sellerId <= 0) out_json(400, ['status'=>'error','message'=>'seller_id required']);
        $st = $pdo->prepare("SELECT id, expires_at, minutes_total, coins_paid, status, TIMESTAMPDIFF(SECOND, UTC_TIMESTAMP(), expires_at) AS sec_left FROM chat_time_sessions WHERE buyer_id=? AND seller_id=? AND status='active' AND expires_at > UTC_TIMESTAMP() ORDER BY expires_at DESC LIMIT 1");
        $st->execute([$userId, $sellerId]);
        $s = $st->fetch(PDO::FETCH_ASSOC);
        if (!$s) {
            // Return free time left too
            $fsSt = $pdo->prepare("SELECT COALESCE(SUM(minutes_total),0) FROM chat_time_sessions WHERE buyer_id=? AND seller_id=? AND package_id=0");
            $fsSt->execute([$userId, $sellerId]);
            $usedFree = (int) $fsSt->fetchColumn();
            echo json_encode(['status'=>'success','active'=>false,'free_min_left'=>max(0, 5-$usedFree)]);
        } else {
            $secLeft = max(0, (int)$s['sec_left']);
            echo json_encode(['status'=>'success','active'=>true,'session_id'=>(int)$s['id'],'seconds_left'=>$secLeft,'minutes_total'=>(int)$s['minutes_total'],'coins_paid'=>(int)$s['coins_paid'],'expires_at'=>gmdate('Y-m-d\TH:i:s\Z', time() + $secLeft),'free_min_left'=>0]);
        }
        exit;
    }

    out_json(400, ['status'=>'error','message'=>'Unknown action']);
} catch (Throwable $e) {
    http_response_code(500);
    echo json_encode(['status'=>'error','message'=>$e->getMessage()]);
}

function out_json(int $code, array $data): void {
    http_response_code($code);
    echo json_encode($data);
    exit;
}
