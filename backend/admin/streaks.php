<?php
require_once __DIR__ . '/_core.php';
admin_require_login();
$pageTitle = 'Streaks';
$activeNav = 'streaks';

// Tables (idempotent — also created by api/v1/api_streak.php)
$pdo->exec("CREATE TABLE IF NOT EXISTS streak_settings (
    id TINYINT NOT NULL PRIMARY KEY,
    enabled TINYINT(1) NOT NULL DEFAULT 1,
    daily_bonus INT NOT NULL DEFAULT 0,
    milestones TEXT NULL,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
$pdo->exec("CREATE TABLE IF NOT EXISTS user_streaks (
    user_id INT NOT NULL PRIMARY KEY,
    current_streak INT NOT NULL DEFAULT 0,
    longest_streak INT NOT NULL DEFAULT 0,
    total_days INT NOT NULL DEFAULT 0,
    last_active_date DATE NULL,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

$msg = '';

// ── Save settings ───────────────────────────────────────────────────────────
if ($_SERVER['REQUEST_METHOD'] === 'POST' && ($_POST['form'] ?? '') === 'settings') {
    try {
        $enabled    = isset($_POST['enabled']) ? 1 : 0;
        $dailyBonus = max(0, (int) ($_POST['daily_bonus'] ?? 0));
        $milestones = [];
        for ($i = 0; $i < 8; $i++) {
            $day   = (int) ($_POST["day_$i"] ?? 0);
            $coins = (int) ($_POST["coins_$i"] ?? 0);
            if ($day > 0 && $coins > 0) $milestones[] = ['day' => $day, 'coins' => $coins];
        }
        usort($milestones, fn($a, $b) => $a['day'] <=> $b['day']);
        // Chat streak settings
        try { $pdo->exec("ALTER TABLE streak_settings ADD COLUMN chat_reward_enabled TINYINT(1) NOT NULL DEFAULT 0"); } catch (Throwable $e) {}
        try { $pdo->exec("ALTER TABLE streak_settings ADD COLUMN chat_start_threshold INT NOT NULL DEFAULT 3"); } catch (Throwable $e) {}
        try { $pdo->exec("ALTER TABLE streak_settings ADD COLUMN chat_milestones TEXT NULL"); } catch (Throwable $e) {}
        $chatRewardEnabled = isset($_POST['chat_reward_enabled']) ? 1 : 0;
        $chatThreshold = max(1, (int) ($_POST['chat_start_threshold'] ?? 3));
        $chatMilestones = [];
        for ($i = 0; $i < 8; $i++) {
            $day = (int) ($_POST["cday_$i"] ?? 0); $coins = (int) ($_POST["ccoins_$i"] ?? 0);
            if ($day > 0 && $coins > 0) $chatMilestones[] = ['day' => $day, 'coins' => $coins];
        }
        usort($chatMilestones, fn($a, $b) => $a['day'] <=> $b['day']);
        $pdo->prepare("INSERT INTO streak_settings (id, enabled, daily_bonus, milestones, chat_reward_enabled, chat_start_threshold, chat_milestones)
                       VALUES (1, ?, ?, ?, ?, ?, ?)
                       ON DUPLICATE KEY UPDATE enabled=VALUES(enabled), daily_bonus=VALUES(daily_bonus), milestones=VALUES(milestones), chat_reward_enabled=VALUES(chat_reward_enabled), chat_start_threshold=VALUES(chat_start_threshold), chat_milestones=VALUES(chat_milestones), updated_at=NOW()")
            ->execute([$enabled, $dailyBonus, json_encode($milestones), $chatRewardEnabled, $chatThreshold, json_encode($chatMilestones)]);
        $msg = 'Streak settings saved!';
    } catch (Throwable $e) { $msg = 'Error: ' . $e->getMessage(); }
}

// ── Reset a user's streak ───────────────────────────────────────────────────
if ($_SERVER['REQUEST_METHOD'] === 'POST' && ($_POST['form'] ?? '') === 'reset' && !empty($_POST['reset_user_id'])) {
    try {
        $pdo->prepare("UPDATE user_streaks SET current_streak=0, last_active_date=NULL WHERE user_id=?")
            ->execute([(int) $_POST['reset_user_id']]);
        $msg = 'Streak reset for user #' . (int) $_POST['reset_user_id'];
    } catch (Throwable $e) { $msg = 'Error: ' . $e->getMessage(); }
}

// Load current settings
$enabled = 1; $dailyBonus = 0; $milestones = [];
$chatRewardEnabled = 0; $chatThreshold = 3; $chatMilestones = [];
try {
    $row = $pdo->query("SELECT * FROM streak_settings WHERE id=1")->fetch(PDO::FETCH_ASSOC);
    if ($row) {
        $enabled = (int) $row['enabled'];
        $dailyBonus = (int) $row['daily_bonus'];
        $milestones = json_decode((string) ($row['milestones'] ?? '[]'), true) ?: [];
        $chatRewardEnabled = (int) ($row['chat_reward_enabled'] ?? 0);
        $chatThreshold = (int) ($row['chat_start_threshold'] ?? 3);
        $chatMilestones = json_decode((string) ($row['chat_milestones'] ?? '[]'), true) ?: [];
    }
} catch (Throwable $_) {}

// Stats
$activeStreakers = 0; $totalRewardCoins = 0; $top = [];
try {
    $activeStreakers = (int) $pdo->query("SELECT COUNT(*) FROM user_streaks WHERE current_streak > 0 AND last_active_date >= (CURDATE() - INTERVAL 1 DAY)")->fetchColumn();
} catch (Throwable $_) {}
try {
    $totalRewardCoins = (int) $pdo->query("SELECT COALESCE(SUM(coins),0) FROM streak_rewards_log")->fetchColumn();
} catch (Throwable $_) {}
try {
    $top = $pdo->query("SELECT s.user_id, s.current_streak, s.longest_streak, s.total_days, s.last_active_date,
                               COALESCE(u.name, u.username, CONCAT('User #', s.user_id)) AS name
                        FROM user_streaks s LEFT JOIN users u ON u.id = s.user_id
                        ORDER BY s.current_streak DESC, s.longest_streak DESC LIMIT 50")->fetchAll(PDO::FETCH_ASSOC);
} catch (Throwable $_) {}

require __DIR__ . '/_layout_header.php';
$inputStyle = 'width:100%;padding:9px 12px;border-radius:6px;border:1px solid #334;background:#0a0a14;color:#fff;font-size:14px';
?>
<div class="section">
  <div class="head"><b>🔥 Daily Streak Settings</b></div>
  <div class="body">
    <?php if ($msg): ?><div class="badge <?= str_starts_with($msg, 'Error') ? 'danger' : 'ok' ?>" style="margin-bottom:14px"><?= htmlspecialchars($msg) ?></div><?php endif; ?>

    <div style="display:flex;gap:14px;flex-wrap:wrap;margin-bottom:18px">
      <div class="badge" style="padding:10px 16px">Active streakers: <b><?= $activeStreakers ?></b></div>
      <div class="badge" style="padding:10px 16px">Reward coins paid: <b><?= number_format($totalRewardCoins) ?></b></div>
    </div>

    <form method="post" style="max-width:640px">
      <input type="hidden" name="form" value="settings">
      <label style="display:flex;align-items:center;gap:8px;margin-bottom:16px">
        <input type="checkbox" name="enabled" value="1" <?= $enabled ? 'checked' : '' ?>>
        <span><b>Enable streak rewards</b> (turn the whole reward system on/off)</span>
      </label>

      <div style="margin-bottom:16px">
        <label style="display:block;margin-bottom:5px;font-weight:600">Daily check-in bonus (coins, every day)</label>
        <input type="number" min="0" name="daily_bonus" value="<?= $dailyBonus ?>" style="<?= $inputStyle ?>;max-width:220px">
        <div style="color:#889;font-size:12px;margin-top:4px">Set 0 to reward only at milestones below.</div>
      </div>

      <div style="font-weight:700;margin:18px 0 8px">Milestone bonuses (extra coins when a streak reaches N days)</div>
      <table style="width:100%;border-collapse:collapse">
        <tr style="color:#889;font-size:12px"><th style="text-align:left;padding:4px">Day</th><th style="text-align:left;padding:4px">Reward coins</th></tr>
        <?php for ($i = 0; $i < 8; $i++): $m = $milestones[$i] ?? ['day' => '', 'coins' => '']; ?>
        <tr>
          <td style="padding:4px"><input type="number" min="0" name="day_<?= $i ?>" value="<?= htmlspecialchars((string) $m['day']) ?>" placeholder="e.g. 7" style="<?= $inputStyle ?>"></td>
          <td style="padding:4px"><input type="number" min="0" name="coins_<?= $i ?>" value="<?= htmlspecialchars((string) $m['coins']) ?>" placeholder="e.g. 30" style="<?= $inputStyle ?>"></td>
        </tr>
        <?php endfor; ?>
      </table>

      <hr style="border-color:#223;margin:22px 0">
      <div style="font-weight:700;margin:6px 0 8px">💬 Chat streak (consecutive days the user chats)</div>
      <label style="display:flex;align-items:center;gap:8px;margin-bottom:14px">
        <input type="checkbox" name="chat_reward_enabled" value="1" <?= $chatRewardEnabled ? 'checked' : '' ?>>
        <span><b>Enable optional chat-streak rewards</b> (off = chat streak shows but pays nothing)</span>
      </label>
      <div style="margin-bottom:14px">
        <label style="display:block;margin-bottom:5px;font-weight:600">Days of continuous chatting before the streak starts showing</label>
        <input type="number" min="1" name="chat_start_threshold" value="<?= $chatThreshold ?>" style="<?= $inputStyle ?>;max-width:220px">
        <div style="color:#889;font-size:12px;margin-top:4px">Default 3 — streak is hidden until the user chats this many days in a row.</div>
      </div>
      <div style="font-weight:700;margin:12px 0 8px">Optional chat-streak milestone rewards (only paid if enabled above)</div>
      <table style="width:100%;border-collapse:collapse">
        <tr style="color:#889;font-size:12px"><th style="text-align:left;padding:4px">Day</th><th style="text-align:left;padding:4px">Reward coins</th></tr>
        <?php for ($i = 0; $i < 8; $i++): $cm = $chatMilestones[$i] ?? ['day' => '', 'coins' => '']; ?>
        <tr>
          <td style="padding:4px"><input type="number" min="0" name="cday_<?= $i ?>" value="<?= htmlspecialchars((string) $cm['day']) ?>" placeholder="e.g. 7" style="<?= $inputStyle ?>"></td>
          <td style="padding:4px"><input type="number" min="0" name="ccoins_<?= $i ?>" value="<?= htmlspecialchars((string) $cm['coins']) ?>" placeholder="e.g. 50" style="<?= $inputStyle ?>"></td>
        </tr>
        <?php endfor; ?>
      </table>

      <button type="submit" style="margin-top:18px;padding:10px 28px;background:linear-gradient(135deg,#FF007F,#D946EF);color:#fff;border:none;border-radius:8px;font-weight:700;cursor:pointer;font-size:15px">Save Settings</button>
    </form>
  </div>
</div>

<div class="section">
  <div class="head"><b>Top Streaks</b></div>
  <div class="body">
    <table style="width:100%;border-collapse:collapse;font-size:14px">
      <tr style="color:#889;text-align:left"><th style="padding:8px">User</th><th style="padding:8px">Current</th><th style="padding:8px">Longest</th><th style="padding:8px">Total days</th><th style="padding:8px">Last active</th><th style="padding:8px"></th></tr>
      <?php if (!$top): ?>
        <tr><td colspan="6" style="padding:14px;color:#889">No streaks yet.</td></tr>
      <?php else: foreach ($top as $t): ?>
        <tr style="border-top:1px solid #223">
          <td style="padding:8px"><?= htmlspecialchars($t['name']) ?> <span style="color:#667">#<?= (int) $t['user_id'] ?></span></td>
          <td style="padding:8px">🔥 <b><?= (int) $t['current_streak'] ?></b></td>
          <td style="padding:8px"><?= (int) $t['longest_streak'] ?></td>
          <td style="padding:8px"><?= (int) $t['total_days'] ?></td>
          <td style="padding:8px;color:#889"><?= htmlspecialchars((string) ($t['last_active_date'] ?? '—')) ?></td>
          <td style="padding:8px">
            <form method="post" onsubmit="return confirm('Reset this user’s streak to 0?')" style="margin:0">
              <input type="hidden" name="form" value="reset">
              <input type="hidden" name="reset_user_id" value="<?= (int) $t['user_id'] ?>">
              <button type="submit" style="padding:4px 10px;background:#3a1a2a;color:#f88;border:1px solid #634;border-radius:6px;cursor:pointer;font-size:12px">Reset</button>
            </form>
          </td>
        </tr>
      <?php endforeach; endif; ?>
    </table>
  </div>
</div>
<?php require __DIR__ . '/_layout_footer.php'; ?>
