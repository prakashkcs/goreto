<?php
/**
 * cron_streak_reminder.php — Warn users whose streak is about to break.
 *
 * A daily streak survives if the user checks in today or yesterday. So a user
 * whose last_active_date == yesterday will LOSE the streak at the next UTC
 * midnight unless they return today. This script (run hourly) sends one push
 * per day to such users once they are within the final ~10 hours, including the
 * remaining time. Same logic for the chat streak (once it has started).
 *
 * Schedule (UTC):  0 * * * *  php .../cron_streak_reminder.php
 */
require_once __DIR__ . '/db_connect.php';
require_once __DIR__ . '/notification_helper.php';

if (!isset($pdo) || !($pdo instanceof PDO)) { fwrite(STDERR, "no pdo\n"); exit(1); }

$today = date('Y-m-d');
$yest  = date('Y-m-d', strtotime('-1 day'));
$nextMidnight = strtotime($today . ' 00:00:00 UTC') + 86400;
$secondsLeft  = $nextMidnight - time();

// Only nag in the final stretch of the day (≤10h to break).
if ($secondsLeft > 10 * 3600) { echo "too early — {$secondsLeft}s left\n"; exit; }
$hoursLeft = max(1, (int) round($secondsLeft / 3600));

$threshold = 3;
try {
    $threshold = max(1, (int) ($pdo->query("SELECT chat_start_threshold FROM streak_settings WHERE id=1")->fetchColumn() ?: 3));
} catch (Throwable $e) {}

function notify_user(PDO $pdo, int $uid, string $title, string $body, array $data): void {
    if (function_exists('send_app_notification')) {
        @send_app_notification($pdo, $uid, 0, 'streak_reminder', $title, $body, null, true, $data);
    } elseif (function_exists('sendFcmNotification')) {
        @sendFcmNotification($pdo, $uid, $title, $body, $data);
    }
}

/** Dedupe one reminder of a kind per user per day. Returns true if not yet sent. */
function reserve_reminder(PDO $pdo, int $uid, string $kind, string $today): bool {
    try {
        $pdo->prepare("INSERT INTO streak_rewards_log (user_id, kind, milestone_day, coins, award_date) VALUES (?, ?, 0, 0, ?)")
            ->execute([$uid, $kind, $today]);
        return true;
    } catch (Throwable $e) {
        return false; // unique key → already reminded today
    }
}

$sentDaily = 0; $sentChat = 0;

// ── Daily streak at risk ──────────────────────────────────────────────────
try {
    $st = $pdo->prepare("SELECT user_id, current_streak FROM user_streaks WHERE last_active_date = ? AND current_streak > 0");
    $st->execute([$yest]);
    foreach ($st->fetchAll(PDO::FETCH_ASSOC) as $r) {
        $uid = (int) $r['user_id']; $cur = (int) $r['current_streak'];
        if (!reserve_reminder($pdo, $uid, 'reminder_daily', $today)) continue;
        notify_user($pdo, $uid,
            "🔥 Keep your $cur-day streak!",
            "Your streak ends in about {$hoursLeft}h. Open Goreto today to keep it going.",
            ['type' => 'streak_reminder', 'streak' => $cur, 'hours_left' => $hoursLeft]);
        $sentDaily++;
    }
} catch (Throwable $e) { fwrite(STDERR, 'daily: ' . $e->getMessage() . "\n"); }

// ── Chat streak at risk (only once it has started) ─────────────────────────
try {
    $st = $pdo->prepare("SELECT user_id, current_streak FROM user_chat_streaks WHERE last_active_date = ? AND current_streak >= ?");
    $st->execute([$yest, $threshold]);
    foreach ($st->fetchAll(PDO::FETCH_ASSOC) as $r) {
        $uid = (int) $r['user_id']; $cur = (int) $r['current_streak'];
        if (!reserve_reminder($pdo, $uid, 'reminder_chat', $today)) continue;
        notify_user($pdo, $uid,
            "💬 Keep your $cur-day chat streak!",
            "Send a message in the next {$hoursLeft}h to keep your chat streak alive.",
            ['type' => 'chat_streak_reminder', 'streak' => $cur, 'hours_left' => $hoursLeft]);
        $sentChat++;
    }
} catch (Throwable $e) { fwrite(STDERR, 'chat: ' . $e->getMessage() . "\n"); }

echo "streak reminders — daily: $sentDaily, chat: $sentChat ({$hoursLeft}h left)\n";
