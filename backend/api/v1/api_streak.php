<?php
/**
 * api_streak.php — Daily streak ("strike") + Chat streak.
 *
 *  POST ?action=checkin        → daily app-open streak (+daily/milestone coins).
 *  POST ?action=chat_checkin   → chat streak (consecutive days the user chats).
 *                                Shows only after `chat_start_threshold` days.
 *                                No reward unless admin enables chat rewards.
 *  GET  ?action=get[&user_id]  → daily + chat streak summary (+ break countdown).
 *  GET  ?action=settings       → public streak settings.
 *
 * Streak rule: +1 per consecutive UTC calendar day; miss a day → reset to 0,
 * restart at 1 on next check-in. Rewards credit the wallet (user_wallets) and
 * are logged so they are never double-paid per day.
 */
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Content-Type, Authorization');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); echo '{}'; exit; }

require_once __DIR__ . '/db_connect.php';
require_once __DIR__ . '/auth_middleware.php';

function sout(int $code, array $a): void { http_response_code($code); echo json_encode($a); exit; }
if (!isset($pdo) || !($pdo instanceof PDO)) sout(500, ['status' => 'error', 'message' => 'DB error']);

// ── Schema ──────────────────────────────────────────────────────────────────
try {
    foreach (['user_streaks', 'user_chat_streaks'] as $t) {
        $pdo->exec("CREATE TABLE IF NOT EXISTS $t (
            user_id INT NOT NULL PRIMARY KEY,
            current_streak INT NOT NULL DEFAULT 0,
            longest_streak INT NOT NULL DEFAULT 0,
            total_days INT NOT NULL DEFAULT 0,
            last_active_date DATE NULL,
            updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
    }
    $pdo->exec("CREATE TABLE IF NOT EXISTS streak_settings (
        id TINYINT NOT NULL PRIMARY KEY,
        enabled TINYINT(1) NOT NULL DEFAULT 1,
        daily_bonus INT NOT NULL DEFAULT 0,
        milestones TEXT NULL,
        updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
    // Chat-streak settings columns (guarded).
    try { $pdo->exec("ALTER TABLE streak_settings ADD COLUMN chat_reward_enabled TINYINT(1) NOT NULL DEFAULT 0"); } catch (Throwable $e) {}
    try { $pdo->exec("ALTER TABLE streak_settings ADD COLUMN chat_start_threshold INT NOT NULL DEFAULT 3"); } catch (Throwable $e) {}
    try { $pdo->exec("ALTER TABLE streak_settings ADD COLUMN chat_milestones TEXT NULL"); } catch (Throwable $e) {}

    $pdo->exec("CREATE TABLE IF NOT EXISTS streak_rewards_log (
        id BIGINT AUTO_INCREMENT PRIMARY KEY,
        user_id INT NOT NULL,
        kind VARCHAR(24) NOT NULL,
        milestone_day INT NOT NULL DEFAULT 0,
        coins INT NOT NULL,
        award_date DATE NOT NULL,
        created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        UNIQUE KEY uniq_award (user_id, kind, milestone_day, award_date),
        KEY idx_user (user_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

    $cnt = (int) $pdo->query("SELECT COUNT(*) FROM streak_settings WHERE id=1")->fetchColumn();
    if ($cnt === 0) {
        $defaultMilestones = json_encode([
            ['day' => 3, 'coins' => 10], ['day' => 7, 'coins' => 30],
            ['day' => 14, 'coins' => 70], ['day' => 30, 'coins' => 200], ['day' => 100, 'coins' => 1000],
        ]);
        $pdo->prepare("INSERT INTO streak_settings (id, enabled, daily_bonus, milestones, chat_reward_enabled, chat_start_threshold, chat_milestones) VALUES (1,1,0,?,0,3,'[]')")
            ->execute([$defaultMilestones]);
    }
} catch (Throwable $e) { /* ignore */ }

function streak_settings(PDO $pdo): array {
    $row = $pdo->query("SELECT * FROM streak_settings WHERE id=1 LIMIT 1")->fetch(PDO::FETCH_ASSOC) ?: [];
    $ms  = json_decode((string) ($row['milestones'] ?? '[]'), true);
    $cms = json_decode((string) ($row['chat_milestones'] ?? '[]'), true);
    return [
        'enabled' => (int) ($row['enabled'] ?? 1),
        'daily_bonus' => (int) ($row['daily_bonus'] ?? 0),
        'milestones' => is_array($ms) ? $ms : [],
        'chat_reward_enabled' => (int) ($row['chat_reward_enabled'] ?? 0),
        'chat_start_threshold' => max(1, (int) ($row['chat_start_threshold'] ?? 3)),
        'chat_milestones' => is_array($cms) ? $cms : [],
    ];
}

function streak_credit_wallet(PDO $pdo, int $userId, int $coins, string $note): void {
    if ($coins <= 0) return;
    $pdo->prepare("INSERT IGNORE INTO user_wallets (user_id, balance_coins, locked_coins) VALUES (?,0,0)")->execute([$userId]);
    $pdo->prepare("UPDATE user_wallets SET balance_coins = balance_coins + ?, updated_at = NOW() WHERE user_id = ?")->execute([$coins, $userId]);
    try {
        $pdo->prepare("INSERT INTO wallet_transactions (user_id, type, direction, coins, currency_amount, currency_code, status, reference, note)
                       VALUES (?, 'streak_reward', 'credit', ?, NULL, NULL, 'completed', 'streak', ?)")
            ->execute([$userId, $coins, $note]);
    } catch (Throwable $e) {}
}

/** Advance a consecutive-day streak in $tbl. Returns state + whether it changed. */
function advance_streak(PDO $pdo, string $tbl, int $userId): array {
    $today = date('Y-m-d'); $yest = date('Y-m-d', strtotime('-1 day'));
    $st = $pdo->prepare("SELECT current_streak, longest_streak, total_days, last_active_date FROM $tbl WHERE user_id=? LIMIT 1");
    $st->execute([$userId]); $row = $st->fetch(PDO::FETCH_ASSOC);
    if (!$row) {
        $pdo->prepare("INSERT INTO $tbl (user_id, current_streak, longest_streak, total_days, last_active_date) VALUES (?,1,1,1,?)")->execute([$userId, $today]);
        return ['current' => 1, 'longest' => 1, 'total' => 1, 'changed' => true, 'last' => $today];
    }
    $last = $row['last_active_date']; $cur = (int) $row['current_streak']; $lng = (int) $row['longest_streak']; $tot = (int) $row['total_days'];
    if ($last === $today) return ['current' => $cur, 'longest' => $lng, 'total' => $tot, 'changed' => false, 'last' => $today];
    $cur = ($last === $yest) ? $cur + 1 : 1;
    $tot += 1; $lng = max($lng, $cur);
    $pdo->prepare("UPDATE $tbl SET current_streak=?, longest_streak=?, total_days=?, last_active_date=? WHERE user_id=?")->execute([$cur, $lng, $tot, $today, $userId]);
    return ['current' => $cur, 'longest' => $lng, 'total' => $tot, 'changed' => true, 'last' => $today];
}

/** When does this streak break, and how many seconds remain. */
function break_info(?string $lastDate): array {
    if (!$lastDate) return ['break_at' => null, 'seconds_left' => 0, 'alive' => false];
    $breakTs = strtotime($lastDate . ' 00:00:00 UTC') + 2 * 86400; // start of (last+2 days)
    $left = $breakTs - time();
    return ['break_at' => gmdate('c', $breakTs), 'seconds_left' => max(0, $left), 'alive' => $left > 0];
}

/** Award daily bonus + milestones for a streak; logs to prevent double-pay. */
function award_rewards(PDO $pdo, int $userId, int $current, string $today, int $dailyBonus, array $milestones, string $dailyKind, string $msKind, string $label): array {
    $coins = 0; $list = [];
    if ($dailyBonus > 0) {
        try {
            $pdo->prepare("INSERT INTO streak_rewards_log (user_id, kind, milestone_day, coins, award_date) VALUES (?, ?, 0, ?, ?)")->execute([$userId, $dailyKind, $dailyBonus, $today]);
            streak_credit_wallet($pdo, $userId, $dailyBonus, "$label daily bonus (day $current)");
            $coins += $dailyBonus; $list[] = ['kind' => $dailyKind, 'coins' => $dailyBonus];
        } catch (Throwable $e) {}
    }
    foreach ($milestones as $m) {
        $day = (int) ($m['day'] ?? 0); $c = (int) ($m['coins'] ?? 0);
        if ($day > 0 && $c > 0 && $current === $day) {
            try {
                $pdo->prepare("INSERT INTO streak_rewards_log (user_id, kind, milestone_day, coins, award_date) VALUES (?, ?, ?, ?, ?)")->execute([$userId, $msKind, $day, $c, $today]);
                streak_credit_wallet($pdo, $userId, $c, "$label $day-day milestone");
                $coins += $c; $list[] = ['kind' => $msKind, 'day' => $day, 'coins' => $c];
            } catch (Throwable $e) {}
        }
    }
    return ['coins' => $coins, 'rewards' => $list];
}

$action = $_GET['action'] ?? $_POST['action'] ?? '';

if ($_SERVER['REQUEST_METHOD'] === 'GET' && $action === 'settings') {
    sout(200, ['status' => 'success', 'settings' => streak_settings($pdo)]);
}

$viewer = requireUser($pdo);
$meId = (int) $viewer['id'];
$cfg = streak_settings($pdo);

// ── GET summary ──────────────────────────────────────────────────────────────
if ($_SERVER['REQUEST_METHOD'] === 'GET' && ($action === 'get' || $action === '')) {
    $uid = isset($_GET['user_id']) && (int) $_GET['user_id'] > 0 ? (int) $_GET['user_id'] : $meId;
    $today = date('Y-m-d'); $yest = date('Y-m-d', strtotime('-1 day'));

    $d = $pdo->prepare("SELECT current_streak, longest_streak, total_days, last_active_date FROM user_streaks WHERE user_id=? LIMIT 1");
    $d->execute([$uid]); $dr = $d->fetch(PDO::FETCH_ASSOC) ?: [];
    $dLast = $dr['last_active_date'] ?? null; $dCur = (int) ($dr['current_streak'] ?? 0);
    $dAlive = ($dLast === $today || $dLast === $yest);
    $dInfo = break_info($dLast);

    $ch = $pdo->prepare("SELECT current_streak, longest_streak, total_days, last_active_date FROM user_chat_streaks WHERE user_id=? LIMIT 1");
    $ch->execute([$uid]); $cr = $ch->fetch(PDO::FETCH_ASSOC) ?: [];
    $cLast = $cr['last_active_date'] ?? null; $cCur = (int) ($cr['current_streak'] ?? 0);
    $cAlive = ($cLast === $today || $cLast === $yest);
    $cInfo = break_info($cLast);
    $threshold = $cfg['chat_start_threshold'];

    sout(200, ['status' => 'success',
        'streak' => [
            'current_streak' => $dCur,
            'display_streak' => $dAlive ? $dCur : 0,
            'longest_streak' => (int) ($dr['longest_streak'] ?? 0),
            'total_days' => (int) ($dr['total_days'] ?? 0),
            'last_active_date' => $dLast,
            'active_today' => ($dLast === $today),
            'break_at' => $dInfo['break_at'],
            'seconds_left' => $dInfo['seconds_left'],
        ],
        'chat_streak' => [
            'current_streak' => $cCur,
            // Only "starts"/shows after the threshold (e.g. 3 days) of chatting.
            'display_streak' => ($cAlive && $cCur >= $threshold) ? $cCur : 0,
            'longest_streak' => (int) ($cr['longest_streak'] ?? 0),
            'last_active_date' => $cLast,
            'start_threshold' => $threshold,
            'break_at' => $cInfo['break_at'],
            'seconds_left' => $cInfo['seconds_left'],
        ],
    ]);
}

// ── POST daily checkin ───────────────────────────────────────────────────────
if ($_SERVER['REQUEST_METHOD'] === 'POST' && ($action === 'checkin' || $action === '')) {
    $s = advance_streak($pdo, 'user_streaks', $meId);
    $reward = ['coins' => 0, 'rewards' => []];
    if ($s['changed'] && $cfg['enabled'] === 1) {
        $reward = award_rewards($pdo, $meId, $s['current'], $s['last'], $cfg['daily_bonus'], $cfg['milestones'], 'daily', 'milestone', 'Streak');
    }
    $info = break_info($s['last']);
    sout(200, ['status' => 'success', 'changed' => $s['changed'],
        'streak' => ['current_streak' => $s['current'], 'longest_streak' => $s['longest'], 'total_days' => $s['total'], 'last_active_date' => $s['last'], 'active_today' => true, 'break_at' => $info['break_at'], 'seconds_left' => $info['seconds_left']],
        'reward_coins' => $reward['coins'], 'rewards' => $reward['rewards']]);
}

// ── POST chat checkin ────────────────────────────────────────────────────────
if ($_SERVER['REQUEST_METHOD'] === 'POST' && $action === 'chat_checkin') {
    $s = advance_streak($pdo, 'user_chat_streaks', $meId);
    $reward = ['coins' => 0, 'rewards' => []];
    // Chat streak has NO reward unless the admin enables optional chat rewards.
    if ($s['changed'] && $cfg['chat_reward_enabled'] === 1) {
        $reward = award_rewards($pdo, $meId, $s['current'], $s['last'], 0, $cfg['chat_milestones'], 'chat_daily', 'chat_milestone', 'Chat streak');
    }
    $info = break_info($s['last']);
    $threshold = $cfg['chat_start_threshold'];
    sout(200, ['status' => 'success', 'changed' => $s['changed'],
        'chat_streak' => ['current_streak' => $s['current'], 'display_streak' => $s['current'] >= $threshold ? $s['current'] : 0, 'longest_streak' => $s['longest'], 'last_active_date' => $s['last'], 'start_threshold' => $threshold, 'break_at' => $info['break_at'], 'seconds_left' => $info['seconds_left']],
        'reward_coins' => $reward['coins'], 'rewards' => $reward['rewards']]);
}

sout(400, ['status' => 'error', 'message' => 'Invalid action']);
