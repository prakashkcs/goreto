<?php
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Content-Type, Authorization');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}


// Handle JSON input
$jsonInput = json_decode(file_get_contents('php://input'), true);
if (is_array($jsonInput)) {
    $_REQUEST = array_merge($_REQUEST, $jsonInput);
    $_POST = array_merge($_POST, $jsonInput);
}

require_once __DIR__ . '/db_connect.php';
require_once __DIR__ . '/auth_middleware.php';

// Auto-create message_requests table
$pdo->exec("
    CREATE TABLE IF NOT EXISTS message_requests (
        requester_id INT NOT NULL,
        receiver_id  INT NOT NULL,
        accepted     TINYINT(1) DEFAULT 0,
        created_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (requester_id, receiver_id),
        INDEX idx_receiver_pending (receiver_id, accepted)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
");

// ── helpers ──────────────────────────────────────────────────────────────────

function isMutualFriend(PDO $pdo, int $a, int $b): bool {
    $s = $pdo->prepare("SELECT COUNT(*) FROM follows WHERE follower_id=? AND following_id=?");
    $s->execute([$a, $b]); $aFollowsB = (int)$s->fetchColumn();
    $s->execute([$b, $a]); $bFollowsA = (int)$s->fetchColumn();
    return $aFollowsB > 0 && $bFollowsA > 0;
}

// Returns ['exists'=>bool, 'accepted'=>bool, 'i_am_requester'=>bool]
function getRequestStatus(PDO $pdo, int $userId, int $otherId): array {
    $s = $pdo->prepare("SELECT requester_id, accepted FROM message_requests
                        WHERE (requester_id=? AND receiver_id=?)
                           OR (requester_id=? AND receiver_id=?) LIMIT 1");
    $s->execute([$userId, $otherId, $otherId, $userId]);
    $row = $s->fetch(PDO::FETCH_ASSOC);
    if (!$row) return ['exists' => false, 'accepted' => false, 'i_am_requester' => false];
    return [
        'exists'        => true,
        'accepted'      => (bool)$row['accepted'],
        'i_am_requester'=> (int)$row['requester_id'] === $userId,
    ];
}

// 'none' | 'pending_sent' | 'pending_received' | 'accepted'
function requestStatusLabel(array $rs, bool $isFriend): string {
    if ($isFriend) return 'none';
    if (!$rs['exists']) return 'none';
    if ($rs['accepted']) return 'accepted';
    return $rs['i_am_requester'] ? 'pending_sent' : 'pending_received';
}

function buildAvatarUrl(string $rawPic): string {
    if ($rawPic === '') return '';
    if (preg_match('~^https?://~i', $rawPic)) return $rawPic;
    return 'https://goreto.org/ekloadmin/' . ltrim($rawPic, '/');
}

try {
    $viewer = requireUser($pdo);
    $userId = (int)$viewer['id'];
    $action = $_REQUEST['action'] ?? '';

    // ── get_conversations ─────────────────────────────────────────────────────
    if ($action === 'get_conversations') {
        // Self-heal: a conversation I have already replied to is not a
        // "message request" (covers socket/other send paths that bypass the
        // reply-accepts-request gate).
        try { $pdo->prepare("UPDATE message_requests mr SET mr.accepted=1 WHERE mr.receiver_id=? AND mr.accepted=0 AND EXISTS(SELECT 1 FROM messages m WHERE m.sender_id=mr.receiver_id AND m.receiver_id=mr.requester_id)")->execute([$userId]); } catch (Throwable $e) {}
        $stmt = $pdo->prepare('
            SELECT
                CASE WHEN sender_id = ? THEN receiver_id ELSE sender_id END AS other_user_id,
                MAX(created_at) AS last_interaction
            FROM messages
            WHERE sender_id = ? OR receiver_id = ?
            GROUP BY other_user_id
            ORDER BY last_interaction DESC
        ');
        $stmt->execute([$userId, $userId, $userId]);
        $convs = $stmt->fetchAll(PDO::FETCH_ASSOC);

        $res = [];
        foreach ($convs as $c) {
            $otherId = (int)$c['other_user_id'];

            $uSt = $pdo->prepare('SELECT name, profile_pic FROM users WHERE id = ?');
            $uSt->execute([$otherId]);
            $other = $uSt->fetch(PDO::FETCH_ASSOC);

            $mSt = $pdo->prepare('SELECT * FROM messages WHERE (sender_id = ? AND receiver_id = ?) OR (sender_id = ? AND receiver_id = ?) ORDER BY created_at DESC LIMIT 1');
            $mSt->execute([$userId, $otherId, $otherId, $userId]);
            $lastMsg = $mSt->fetch(PDO::FETCH_ASSOC);

            $urSt = $pdo->prepare("SELECT COUNT(*) FROM messages WHERE receiver_id = ? AND sender_id = ? AND status != 'read'");
            $urSt->execute([$userId, $otherId]);
            $unread = $urSt->fetchColumn();

            $isFriend = isMutualFriend($pdo, $userId, $otherId);
            $rs       = getRequestStatus($pdo, $userId, $otherId);
            $rsLabel  = requestStatusLabel($rs, $isFriend);

            $res[] = [
                'other_user_id'    => $otherId,
                'other_user_name'  => $other ? $other['name'] : 'User',
                'other_user_avatar'=> buildAvatarUrl($other ? ($other['profile_pic'] ?? '') : ''),
                'last_message'     => $lastMsg,
                'unread_count'     => $unread,
                'updated_at'       => $c['last_interaction'],
                'is_friend'        => $isFriend,
                'request_status'   => $rsLabel,
            ];
        }
        echo json_encode(['status' => 'success', 'conversations' => $res]);
    }

    // ── get_messages ──────────────────────────────────────────────────────────
    elseif ($action === 'get_messages') {
        $withUserId = (int)($_GET['with_user_id'] ?? 0);

        $bSt = $pdo->prepare('SELECT blocker_id, blocked_id FROM user_blocks WHERE (blocker_id = ? AND blocked_id = ?) OR (blocker_id = ? AND blocked_id = ?)');
        $bSt->execute([$userId, $withUserId, $withUserId, $userId]);
        $blocks = $bSt->fetchAll(PDO::FETCH_ASSOC);
        $isBlockedByMe = false;
        $isBlockedByThem = false;
        foreach ($blocks as $b) {
            if ($b['blocker_id'] == $userId)      $isBlockedByMe = true;
            if ($b['blocker_id'] == $withUserId)  $isBlockedByThem = true;
        }

        $rSt = $pdo->prepare("UPDATE messages SET status='read', read_at=NOW() WHERE receiver_id=? AND sender_id=? AND status!='read'");
        $rSt->execute([$userId, $withUserId]);

        $stmt = $pdo->prepare('SELECT * FROM messages WHERE (sender_id = ? AND receiver_id = ?) OR (sender_id = ? AND receiver_id = ?) ORDER BY created_at ASC LIMIT 200');
        $stmt->execute([$userId, $withUserId, $withUserId, $userId]);
        $msgs = $stmt->fetchAll(PDO::FETCH_ASSOC);

        $isFriend = isMutualFriend($pdo, $userId, $withUserId);
        $rs       = getRequestStatus($pdo, $userId, $withUserId);
        $rsLabel  = requestStatusLabel($rs, $isFriend);
        $aiSt = $pdo->prepare("SELECT COALESCE(privacy_allow_unknown_inbox, 1) FROM users WHERE id = ? LIMIT 1");
        $aiSt->execute([$withUserId]);
        $allowUnknownInbox = (int)$aiSt->fetchColumn();

        echo json_encode([
            'status'           => 'success',
            'messages'         => $msgs,
            'is_blocked_by_me' => $isBlockedByMe,
            'is_blocked_by_them'=> $isBlockedByThem,
            'is_friend'        => $isFriend,
            'request_status'   => $rsLabel,
            'allow_unknown_inbox' => $allowUnknownInbox,
        ]);
    }

    // ── get_new_messages ──────────────────────────────────────────────────────
    elseif ($action === 'get_new_messages') {
        $withUserId = (int)($_GET['with_user_id'] ?? 0);
        $lastId     = (int)($_GET['last_id'] ?? 0);

        $rSt = $pdo->prepare("UPDATE messages SET status='read', read_at=NOW() WHERE receiver_id=? AND sender_id=? AND id > ? AND status!='read'");
        $rSt->execute([$userId, $withUserId, $lastId]);

        $stmt = $pdo->prepare('SELECT * FROM messages WHERE id > ? AND ((sender_id = ? AND receiver_id = ?) OR (sender_id = ? AND receiver_id = ?)) ORDER BY created_at ASC');
        $stmt->execute([$lastId, $userId, $withUserId, $withUserId, $userId]);
        $msgs = $stmt->fetchAll(PDO::FETCH_ASSOC);

        $stmt2 = $pdo->prepare("SELECT id, status, read_at FROM messages WHERE sender_id = ? AND receiver_id = ? AND status IN ('delivered', 'read')");
        $stmt2->execute([$userId, $withUserId]);
        $statusUpdates = $stmt2->fetchAll(PDO::FETCH_ASSOC);

        echo json_encode(['status' => 'success', 'messages' => $msgs, 'status_updates' => $statusUpdates]);
    }

    // ── send_message ──────────────────────────────────────────────────────────
    elseif ($action === 'send_message') {
        $receiverId = (int)($_POST['receiver_id'] ?? 0);
        $type       = $_POST['type'] ?? 'text';
        $content    = $_POST['content'] ?? '';
        $voiceDur   = $_POST['voice_duration'] ?? 0;

        // Block check
        $bSt = $pdo->prepare('SELECT blocker_id, blocked_id FROM user_blocks WHERE (blocker_id = ? AND blocked_id = ?) OR (blocker_id = ? AND blocked_id = ?) LIMIT 1');
        $bSt->execute([$userId, $receiverId, $receiverId, $userId]);
        $block = $bSt->fetch(PDO::FETCH_ASSOC);
        if ($block) {
            echo json_encode(['status' => 'error', 'message' => $block['blocker_id'] == $userId ? 'You have blocked this user' : 'User unavailable']);
            exit;
        }

        // Chat time-session gate.
        // If receiver uses chat packages, sender needs an active session
        // (or free time) OR must be a friend with charge-friends OFF.
        $pkgSt = $pdo->prepare("SELECT COUNT(*) FROM chat_time_packages WHERE creator_id=? AND is_active=1");
        $pkgSt->execute([$receiverId]);
        $hasPkgs = ((int) $pkgSt->fetchColumn()) > 0;
        // "Paid chat only" per-user override is enforced even without general packages.
        $forcePkg = false;
        try {
            $ovSt = $pdo->prepare("SELECT 1 FROM chat_ppm_overrides WHERE owner_id=? AND target_id=? LIMIT 1");
            $ovSt->execute([$receiverId, $userId]);
            $forcePkg = (bool) $ovSt->fetchColumn();
        } catch (Throwable $e) { $forcePkg = false; }
        if ($hasPkgs || $forcePkg) {
            // Check active session
            $actSt = $pdo->prepare("SELECT id FROM chat_time_sessions WHERE buyer_id=? AND seller_id=? AND status='active' AND expires_at > NOW() LIMIT 1");
            $actSt->execute([$userId, $receiverId]);
            $hasSession = (bool) $actSt->fetchColumn();
            if (!$hasSession) {
                // Check free time
                $fsSt = $pdo->prepare("SELECT COALESCE(SUM(minutes_total),0) FROM chat_time_sessions WHERE buyer_id=? AND seller_id=? AND package_id=0");
                $fsSt->execute([$userId, $receiverId]);
                $usedFree = (int) $fsSt->fetchColumn();
                // No free minutes when paid-chat-only is forced.
                $freeLeft = $forcePkg ? 0 : max(0, 5 - $usedFree);

                // $isFriend may not be set yet; check it now if needed
                $isFriendNow = function_exists('isMutualFriend') ? isMutualFriend($pdo, $userId, $receiverId) : false;
                // Fetch charge_friends flag for receiver
                $cfSt = $pdo->prepare("SELECT COALESCE(ppm_charge_friends,0) FROM users WHERE id=? LIMIT 1");
                $cfSt->execute([$receiverId]);
                $chargeF = (int)$cfSt->fetchColumn();
                // Paid-chat-only override blocks the free-time bypass entirely.
                $bypass = (!$forcePkg) && (($isFriendNow && $chargeF !== 1) || $freeLeft > 0);
                if (!$bypass) {
                    echo json_encode([
                        'status' => 'error',
                        'message' => 'Start a chat session to message this user.',
                        'error_code' => 'session_required',
                        'target_id' => (int) $receiverId,
                        'free_min_left' => 0,
                    ]);
                    exit;
                }
            }
        }

        // Subscriber-only DM gate — if the receiver has restricted DMs to
        // subscribers and the sender isn't an active subscriber of the
        // receiver, block the message. App should already have hidden the
        // input but enforce server-side as well.
        $sSt = $pdo->prepare('SELECT COALESCE(subscriber_only_dm, 0) AS gate FROM users WHERE id = ? LIMIT 1');
        $sSt->execute([$receiverId]);
        $gateRow = $sSt->fetch(PDO::FETCH_ASSOC);
        if ($gateRow && (int)$gateRow['gate'] === 1) {
            $subSt = $pdo->prepare("
                SELECT 1 FROM user_subscriptions us
                JOIN subscription_plans sp ON sp.id = us.plan_id
                WHERE us.subscriber_id = ? AND sp.creator_id = ?
                  AND us.status = 'active'
                  AND (us.expires_at IS NULL OR us.expires_at > NOW())
                LIMIT 1
            ");
            try {
                $subSt->execute([$userId, $receiverId]);
                if (!$subSt->fetchColumn()) {
                    echo json_encode([
                        'status' => 'error',
                        'message' => 'This user only accepts messages from subscribers. Subscribe to send a message.',
                        'error_code' => 'subscriber_only_dm',
                    ]);
                    exit;
                }
            } catch (Throwable $e) {
                // Subscription tables missing — fall through rather than 500.
            }
        }

        $isFriend = isMutualFriend($pdo, $userId, $receiverId);
        $rs       = getRequestStatus($pdo, $userId, $receiverId);

        // Privacy: block strangers when the receiver has disabled unknown inbox.
        // A 'stranger' = not a mutual friend AND no ACCEPTED request between them.
        // This now also blocks a requester who keeps messaging on a still-pending
        // request (previously they slipped through once the request row existed,
        // so toggling the option OFF didn't stop them).
        if (!$isFriend && empty($rs['accepted'])) {
            // 'Receiver of a pending request' is handled by the accept-first gate below.
            $iAmReceiverOfPending = !empty($rs['exists']) && empty($rs['i_am_requester']);
            // Active paid chat-time session bypasses the friends-only block until it expires.
            $hasPaidSession = false;
            try {
                $psSt = $pdo->prepare("SELECT 1 FROM chat_time_sessions WHERE status='active' AND expires_at > UTC_TIMESTAMP() AND ((buyer_id=? AND seller_id=?) OR (buyer_id=? AND seller_id=?)) LIMIT 1");
                $psSt->execute([$userId, $receiverId, $receiverId, $userId]);
                $hasPaidSession = (bool)$psSt->fetchColumn();
            } catch (Throwable $e) {}
            // They reached out first (sent me a message) -> I can reply even if
            // they only accept messages from followers. Covers socket-sent
            // messages that never created a message_request row.
            $theyMessagedMe = false;
            try {
                $tmSt = $pdo->prepare("SELECT 1 FROM messages WHERE sender_id=? AND receiver_id=? LIMIT 1");
                $tmSt->execute([$receiverId, $userId]);
                $theyMessagedMe = (bool)$tmSt->fetchColumn();
            } catch (Throwable $e) {}
            if (!$iAmReceiverOfPending && !$hasPaidSession && !$theyMessagedMe) {
                try {
                    $privSt = $pdo->prepare("SELECT COALESCE(privacy_allow_unknown_inbox, 1) FROM users WHERE id = ? LIMIT 1");
                    $privSt->execute([$receiverId]);
                    if (!(int)$privSt->fetchColumn()) {
                        echo json_encode(['status' => 'error', 'message' => 'This user does not accept messages from strangers.', 'error_code' => 'strangers_blocked']);
                        exit;
                    }
                } catch (Throwable $e) { /* allow if column missing */ }
            }
        }

        $isNewRequest = false;
        if (!$isFriend) {
            if ($rs['exists'] && $rs['accepted']) {
                // Accepted request — full messaging allowed, fall through
            } elseif ($rs['exists'] && !$rs['i_am_requester']) {
                // I am the receiver of a pending request — must accept before replying
                // Reply accepts the request: the person who messaged me first
                // can keep chatting without us being friends.
                $pdo->prepare("UPDATE message_requests SET accepted=1 WHERE requester_id=? AND receiver_id=?")->execute([$receiverId, $userId]);
            } elseif (!$rs['exists']) {
                // First message from a non-friend — create the request
                $ins = $pdo->prepare("INSERT IGNORE INTO message_requests (requester_id, receiver_id, accepted) VALUES (?, ?, 0)");
                $ins->execute([$userId, $receiverId]);
                $isNewRequest = true;
            }
            // If $rs['exists'] && $rs['i_am_requester'] && !$rs['accepted'] → requester can keep sending
        }

        // Handle media upload
        $mediaUrl = '';
        if (isset($_FILES['file']) && $_FILES['file']['error'] == 0) {
            $ext      = pathinfo($_FILES['file']['name'], PATHINFO_EXTENSION);
            $filename = uniqid('chat_') . '.' . $ext;
            $dest     = __DIR__ . '/../../uploads/' . $filename;
            if (move_uploaded_file($_FILES['file']['tmp_name'], $dest)) {
                $proto    = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off') ? 'https' : 'http';
                $host     = $_SERVER['HTTP_HOST'] ?? 'goreto.org';
                $mediaUrl = $proto . '://' . $host . '/ekloadmin/uploads/' . $filename;
            }
        }

        $stmt = $pdo->prepare("INSERT INTO messages (sender_id, receiver_id, type, content, media_url, voice_duration, status, created_at) VALUES (?, ?, ?, ?, ?, ?, 'sent', NOW())");
        $stmt->execute([$userId, $receiverId, $type, $content, $mediaUrl, $voiceDur]);
        $msgId = $pdo->lastInsertId();

        require_once __DIR__ . '/notification_helper.php';
        $uname = 'Someone';
        try {
            $uSt = $pdo->prepare('SELECT name FROM users WHERE id=?');
            $uSt->execute([$userId]);
            $uname = $uSt->fetchColumn() ?: 'Someone';
        } catch (Exception $e) {}

        $msgText    = $type === 'text' ? substr($content, 0, 40) : ($type === 'call' ? $content : "Sent a $type message");
        $notifType  = $isNewRequest ? 'message_request' : 'chat';
        $notifTitle = $isNewRequest ? "Message request from $uname" : "Message from $uname";
        send_app_notification($pdo, $receiverId, $userId, $notifType, $notifTitle, $msgText);

        $fSt = $pdo->prepare('SELECT * FROM messages WHERE id = ?');
        $fSt->execute([$msgId]);
        $newMsg = $fSt->fetch(PDO::FETCH_ASSOC);

        $rsLabel = requestStatusLabel(
            $rs['exists'] ? $rs : ['exists' => true, 'accepted' => false, 'i_am_requester' => true],
            $isFriend
        );

        echo json_encode(['status' => 'success', 'message' => $newMsg, 'request_status' => $rsLabel, 'is_friend' => $isFriend]);
    }

    // ── accept_request ────────────────────────────────────────────────────────
    elseif ($action === 'accept_request') {
        $requesterId = (int)($_POST['requester_id'] ?? 0);
        if ($requesterId <= 0) {
            echo json_encode(['status' => 'error', 'message' => 'Missing requester_id']);
            exit;
        }
        $upd = $pdo->prepare("UPDATE message_requests SET accepted=1 WHERE requester_id=? AND receiver_id=?");
        $upd->execute([$requesterId, $userId]);
        if ($upd->rowCount() === 0) {
            // Row may not exist yet (edge case: both followed each other before first message)
            $ins = $pdo->prepare("INSERT IGNORE INTO message_requests (requester_id, receiver_id, accepted) VALUES (?, ?, 1)");
            $ins->execute([$requesterId, $userId]);
        }
        echo json_encode(['status' => 'success']);
    }

    // ── decline_request ───────────────────────────────────────────────────────
    elseif ($action === 'decline_request') {
        $requesterId = (int)($_POST['requester_id'] ?? 0);
        if ($requesterId <= 0) {
            echo json_encode(['status' => 'error', 'message' => 'Missing requester_id']);
            exit;
        }
        // Delete the request record
        $pdo->prepare("DELETE FROM message_requests WHERE requester_id=? AND receiver_id=?")->execute([$requesterId, $userId]);
        // Delete all messages between them
        $pdo->prepare("DELETE FROM messages WHERE (sender_id=? AND receiver_id=?) OR (sender_id=? AND receiver_id=?)")->execute([$requesterId, $userId, $userId, $requesterId]);
        echo json_encode(['status' => 'success']);
    }

    // ── get_unread_count ──────────────────────────────────────────────────────
    elseif ($action === 'get_unread_count') {
        $stmt = $pdo->prepare("SELECT COUNT(*) FROM messages WHERE receiver_id = ? AND status != 'read'");
        $stmt->execute([$userId]);
        $count = $stmt->fetchColumn();
        echo json_encode(['status' => 'success', 'unread_count' => $count]);
    }

    // ── mark_read ─────────────────────────────────────────────────────────────
    elseif ($action === 'mark_read') {
        $senderId = $_POST['sender_id'] ?? 0;
        $stmt = $pdo->prepare("UPDATE messages SET status='read', read_at=NOW() WHERE receiver_id=? AND sender_id=? AND status!='read'");
        $stmt->execute([$userId, $senderId]);
        echo json_encode(['status' => 'success']);
    }

    // ── mark_delivered ────────────────────────────────────────────────────────
    elseif ($action === 'mark_delivered') {
        $senderId = $_POST['sender_id'] ?? 0;
        $stmt = $pdo->prepare("UPDATE messages SET status='delivered' WHERE receiver_id=? AND sender_id=? AND status='sent'");
        $stmt->execute([$userId, $senderId]);
        echo json_encode(['status' => 'success']);
    }

    // ── delete_conversation ───────────────────────────────────────────────────
    elseif ($action === 'delete_conversation') {
        $otherUserId = (int)($_POST['other_user_id'] ?? 0);
        if ($otherUserId <= 0) {
            echo json_encode(['status' => 'error', 'message' => 'Invalid user ID']);
            exit;
        }
        $stmt = $pdo->prepare('DELETE FROM messages WHERE (sender_id = ? AND receiver_id = ?) OR (sender_id = ? AND receiver_id = ?)');
        $stmt->execute([$userId, $otherUserId, $otherUserId, $userId]);
        $deleted = $stmt->rowCount();
        // Also clean up any request record
        $pdo->prepare("DELETE FROM message_requests WHERE (requester_id=? AND receiver_id=?) OR (requester_id=? AND receiver_id=?)")->execute([$userId, $otherUserId, $otherUserId, $userId]);
        echo json_encode(['status' => 'success', 'deleted_count' => $deleted]);
    }


    // PPM Pay-Per-Minute Session
    elseif ($action === 'ppm_start') {
        $sellerId = (int) ($_POST['seller_id'] ?? 0);
        if ($sellerId <= 0 || $sellerId === $userId) {
            echo json_encode(['status' => 'error', 'message' => 'Invalid seller']);
            exit;
        }
        $s = $pdo->prepare("SELECT COALESCE(pay_per_min_enabled,0) AS en, COALESCE(pay_per_min_rate,0) AS rate FROM users WHERE id=? LIMIT 1");
        $s->execute([$sellerId]);
        $seller = $s->fetch(PDO::FETCH_ASSOC);
        if (!$seller || (int)$seller['en'] !== 1 || (int)$seller['rate'] <= 0) {
            echo json_encode(['status' => 'error', 'message' => 'This user does not accept paid chat']);
            exit;
        }
        $rate = (int) $seller['rate'];
        $existsSt = $pdo->prepare("SELECT id FROM ppm_sessions WHERE buyer_id=? AND seller_id=? AND status='active' LIMIT 1");
        $existsSt->execute([$userId, $sellerId]);
        if ($existsSt->fetchColumn()) {
            echo json_encode(['status' => 'error', 'message' => 'You already have an active paid chat with this user', 'error_code' => 'ppm_already_active']);
            exit;
        }
        $w = $pdo->prepare("SELECT COALESCE(balance_coins,0) AS bal FROM user_wallets WHERE user_id=? LIMIT 1");
        $w->execute([$userId]);
        $balance = (int) ($w->fetchColumn() ?? 0);
        if ($balance < $rate) {
            echo json_encode(['status' => 'error', 'message' => 'Insufficient coins for the first minute', 'error_code' => 'ppm_insufficient_coins', 'rate' => $rate, 'balance' => $balance]);
            exit;
        }
        $pdo->beginTransaction();
        try {
            $pdo->prepare("UPDATE user_wallets SET balance_coins = balance_coins - ? WHERE user_id = ?")->execute([$rate, $userId]);
            $pdo->prepare("INSERT INTO user_wallets (user_id, balance_coins, locked_coins) VALUES (?, ?, 0) ON DUPLICATE KEY UPDATE balance_coins = balance_coins + ?")->execute([$sellerId, $rate, $rate]);
            $pdo->prepare("INSERT INTO ppm_sessions (buyer_id, seller_id, rate_per_min, minutes_charged, total_coins_charged) VALUES (?, ?, ?, 1, ?)")->execute([$userId, $sellerId, $rate, $rate]);
            $sessionId = (int) $pdo->lastInsertId();
            $pdo->commit();
        } catch (Throwable $e) {
            $pdo->rollBack();
            echo json_encode(['status' => 'error', 'message' => 'Could not start session: ' . $e->getMessage()]);
            exit;
        }
        $balance -= $rate;
        echo json_encode(['status' => 'success', 'session_id' => $sessionId, 'rate_per_min' => $rate, 'minutes_charged' => 1, 'balance' => $balance]);
        exit;
    }
    elseif ($action === 'ppm_tick') {
        $sessionId = (int) ($_POST['session_id'] ?? 0);
        if ($sessionId <= 0) { echo json_encode(['status' => 'error', 'message' => 'session_id required']); exit; }
        $st = $pdo->prepare("SELECT * FROM ppm_sessions WHERE id=? AND buyer_id=? LIMIT 1");
        $st->execute([$sessionId, $userId]);
        $sess = $st->fetch(PDO::FETCH_ASSOC);
        if (!$sess) { echo json_encode(['status' => 'error', 'message' => 'Session not found']); exit; }
        if ($sess['status'] !== 'active') {
            echo json_encode(['status' => 'success', 'session_status' => $sess['status'], 'minutes_charged' => (int)$sess['minutes_charged'], 'total_coins_charged' => (int)$sess['total_coins_charged']]);
            exit;
        }
        $rate = (int) $sess['rate_per_min'];
        $secondsSince = strtotime('now') - strtotime($sess['last_tick_at']);
        if ($secondsSince < 55) {
            $w = $pdo->prepare("SELECT COALESCE(balance_coins,0) FROM user_wallets WHERE user_id=? LIMIT 1");
            $w->execute([$userId]);
            $balance = (int) ($w->fetchColumn() ?? 0);
            echo json_encode(['status' => 'success', 'session_status' => 'active', 'minutes_charged' => (int)$sess['minutes_charged'], 'total_coins_charged' => (int)$sess['total_coins_charged'], 'balance' => $balance, 'next_tick_in' => max(0, 60 - $secondsSince)]);
            exit;
        }
        $w = $pdo->prepare("SELECT COALESCE(balance_coins,0) FROM user_wallets WHERE user_id=? LIMIT 1");
        $w->execute([$userId]);
        $balance = (int) ($w->fetchColumn() ?? 0);
        if ($balance < $rate) {
            $pdo->prepare("UPDATE ppm_sessions SET status='ended', ended_at=NOW(), end_reason='no_funds' WHERE id=?")->execute([$sessionId]);
            echo json_encode(['status' => 'success', 'session_status' => 'ended', 'end_reason' => 'no_funds', 'minutes_charged' => (int)$sess['minutes_charged'], 'total_coins_charged' => (int)$sess['total_coins_charged'], 'balance' => $balance]);
            exit;
        }
        $pdo->beginTransaction();
        try {
            $pdo->prepare("UPDATE user_wallets SET balance_coins = balance_coins - ? WHERE user_id = ?")->execute([$rate, $userId]);
            $pdo->prepare("INSERT INTO user_wallets (user_id, balance_coins, locked_coins) VALUES (?, ?, 0) ON DUPLICATE KEY UPDATE balance_coins = balance_coins + ?")->execute([(int)$sess['seller_id'], $rate, $rate]);
            $pdo->prepare("UPDATE ppm_sessions SET minutes_charged = minutes_charged + 1, total_coins_charged = total_coins_charged + ?, last_tick_at = NOW() WHERE id = ?")->execute([$rate, $sessionId]);
            $pdo->commit();
        } catch (Throwable $e) {
            $pdo->rollBack();
            echo json_encode(['status' => 'error', 'message' => 'Tick failed: ' . $e->getMessage()]);
            exit;
        }
        echo json_encode(['status' => 'success', 'session_status' => 'active', 'minutes_charged' => (int)$sess['minutes_charged'] + 1, 'total_coins_charged' => (int)$sess['total_coins_charged'] + $rate, 'balance' => $balance - $rate]);
        exit;
    }
    elseif ($action === 'ppm_end') {
        $sessionId = (int) ($_POST['session_id'] ?? 0);
        $reason = trim((string) ($_POST['reason'] ?? 'user_stop'));
        if ($sessionId <= 0) { echo json_encode(['status' => 'error', 'message' => 'session_id required']); exit; }
        $st = $pdo->prepare("UPDATE ppm_sessions SET status='ended', ended_at=NOW(), end_reason=? WHERE id=? AND (buyer_id=? OR seller_id=?) AND status='active'");
        $st->execute([$reason, $sessionId, $userId, $userId]);
        echo json_encode(['status' => 'success']);
        exit;
    }
    elseif ($action === 'ppm_status') {
        $sessionId = (int) ($_GET['session_id'] ?? $_POST['session_id'] ?? 0);
        if ($sessionId <= 0) { echo json_encode(['status' => 'error', 'message' => 'session_id required']); exit; }
        $st = $pdo->prepare("SELECT status, end_reason, minutes_charged, total_coins_charged FROM ppm_sessions WHERE id=? AND (buyer_id=? OR seller_id=?) LIMIT 1");
        $st->execute([$sessionId, $userId, $userId]);
        $sess = $st->fetch(PDO::FETCH_ASSOC);
        if (!$sess) { echo json_encode(['status' => 'error', 'message' => 'Session not found']); exit; }
        echo json_encode(['status' => 'success'] + $sess);
        exit;
    }
    elseif ($action === 'ppm_override_set') {
        $targetId = (int) ($_POST['target_user_id'] ?? 0);
        $force = (int) ($_POST['force'] ?? 1);
        if ($targetId <= 0 || $targetId === $userId) {
            echo json_encode(['status' => 'error', 'message' => 'Invalid target']);
            exit;
        }
        try {
            $pdo->exec("CREATE TABLE IF NOT EXISTS chat_ppm_overrides (owner_id INT NOT NULL, target_id INT NOT NULL, created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP, PRIMARY KEY (owner_id, target_id), INDEX idx_owner (owner_id), INDEX idx_target (target_id)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
            if ($force === 1) {
                $pdo->prepare("INSERT IGNORE INTO chat_ppm_overrides (owner_id, target_id) VALUES (?, ?)")->execute([$userId, $targetId]);
            } else {
                $pdo->prepare("DELETE FROM chat_ppm_overrides WHERE owner_id=? AND target_id=?")->execute([$userId, $targetId]);
            }
            echo json_encode(['status' => 'success', 'force' => $force]);
        } catch (Throwable $e) {
            echo json_encode(['status' => 'error', 'message' => $e->getMessage()]);
        }
        exit;
    }
    elseif ($action === 'ppm_override_status') {
        $targetId = (int) ($_GET['target_user_id'] ?? $_POST['target_user_id'] ?? 0);
        if ($targetId <= 0) {
            echo json_encode(['status' => 'error', 'message' => 'Invalid target']);
            exit;
        }
        try {
            $st = $pdo->prepare("SELECT 1 FROM chat_ppm_overrides WHERE owner_id=? AND target_id=? LIMIT 1");
            $st->execute([$userId, $targetId]);
            $has = (bool) $st->fetchColumn();
            echo json_encode(['status' => 'success', 'force' => $has ? 1 : 0]);
        } catch (Throwable $e) {
            echo json_encode(['status' => 'success', 'force' => 0]);
        }
        exit;
    }

    else {
        echo json_encode(['status' => 'error', 'message' => 'Unknown action']);
    }
}
catch (Throwable $e) {
    http_response_code(500);
    echo json_encode(['status' => 'error', 'message' => $e->getMessage()]);
}
?>
