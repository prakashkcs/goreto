<?php
require_once __DIR__ . '/_core.php';
admin_require_login();
$pageTitle = 'Referral Settings';
$activeNav = 'referral_settings';

// Ensure table exists
$pdo->exec("CREATE TABLE IF NOT EXISTS referral_settings (
  id INT AUTO_INCREMENT PRIMARY KEY,
  setting_key VARCHAR(80) NOT NULL UNIQUE,
  setting_value VARCHAR(500) NOT NULL DEFAULT '',
  updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

$pdo->exec("CREATE TABLE IF NOT EXISTS referral_claims (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  claimer_user_id INT NOT NULL,
  referrer_user_id INT NOT NULL,
  referral_code VARCHAR(50) NOT NULL,
  coins_awarded INT NOT NULL DEFAULT 0,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_claimer (claimer_user_id),
  INDEX idx_referrer (referrer_user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

$pdo->exec("CREATE TABLE IF NOT EXISTS user_activity_log (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  user_id INT NOT NULL,
  activity_date DATE NOT NULL,
  open_count INT NOT NULL DEFAULT 1,
  total_seconds INT NOT NULL DEFAULT 0,
  updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uq_user_date (user_id, activity_date),
  INDEX idx_user (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

$defaults = [
  'enabled'           => '1',
  'coins_reward'      => '100',
  'min_active_days'   => '0',
  'min_daily_minutes' => '0',
];

$msg = '';
$msgType = 'ok';
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
  try {
    $values = [
      'enabled'           => isset($_POST['enabled']) ? '1' : '0',
      'coins_reward'      => (string)max(0, (int)($_POST['coins_reward'] ?? 100)),
      'min_active_days'   => (string)max(0, (int)($_POST['min_active_days'] ?? 0)),
      'min_daily_minutes' => (string)max(0, (int)($_POST['min_daily_minutes'] ?? 0)),
    ];
    $ins = $pdo->prepare("INSERT INTO referral_settings (setting_key, setting_value) VALUES (?,?)
      ON DUPLICATE KEY UPDATE setting_value=VALUES(setting_value), updated_at=NOW()");
    foreach ($values as $k => $v) {
      $ins->execute([$k, $v]);
    }
    $msg = 'Referral settings saved!';
  } catch (Throwable $e) {
    $msg = 'Error: ' . $e->getMessage();
    $msgType = 'danger';
  }
}

$settings = [];
try {
  foreach ($pdo->query("SELECT setting_key, setting_value FROM referral_settings")->fetchAll() as $r)
    $settings[$r['setting_key']] = $r['setting_value'];
} catch (Throwable $_) {}
foreach ($defaults as $k => $v) $settings[$k] ??= $v;

// Stats
$totalClaims = 0;
$totalCoinsAwarded = 0;
$recentClaims = [];
$topReferrers = [];
$activeUsersToday = 0;

try {
  $totalClaims      = (int)$pdo->query("SELECT COUNT(*) FROM referral_claims")->fetchColumn();
  $totalCoinsAwarded = (int)($pdo->query("SELECT COALESCE(SUM(coins_awarded*2),0) FROM referral_claims")->fetchColumn());
  $activeUsersToday  = (int)$pdo->query("SELECT COUNT(DISTINCT user_id) FROM user_activity_log WHERE activity_date = CURDATE()")->fetchColumn();

  $recentClaims = $pdo->query(
    "SELECT rc.*, u1.username AS claimer_name, u2.username AS referrer_name
     FROM referral_claims rc
     LEFT JOIN users u1 ON u1.id = rc.claimer_user_id
     LEFT JOIN users u2 ON u2.id = rc.referrer_user_id
     ORDER BY rc.created_at DESC LIMIT 20"
  )->fetchAll(PDO::FETCH_ASSOC);

  $topReferrers = $pdo->query(
    "SELECT u.username, COUNT(*) AS total_referrals, SUM(rc.coins_awarded) AS coins_earned
     FROM referral_claims rc
     LEFT JOIN users u ON u.id = rc.referrer_user_id
     GROUP BY rc.referrer_user_id
     ORDER BY total_referrals DESC LIMIT 10"
  )->fetchAll(PDO::FETCH_ASSOC);
} catch (Throwable $_) {}

require __DIR__ . '/_layout_header.php';
?>
<style>
  .ref-grid { display:grid; grid-template-columns:repeat(auto-fit,minmax(160px,1fr)); gap:14px; margin-bottom:24px }
  .ref-stat { background:#0d0d1a; border:1px solid #1e2a45; border-radius:12px; padding:16px 20px }
  .ref-stat .val { font-size:28px; font-weight:800; color:#d946ef; line-height:1 }
  .ref-stat .lbl { font-size:12px; color:#94a3b8; margin-top:4px }
  .field-wrap { margin-bottom:16px }
  .field-wrap label { display:block; font-size:13px; font-weight:600; margin-bottom:6px; color:#c4cfe0 }
  .field-wrap input[type=number], .field-wrap select {
    width:100%; padding:9px 12px; border-radius:8px; border:1px solid #1e2a45;
    background:#080818; color:#fff; font-size:14px; box-sizing:border-box }
  .field-wrap .hint { font-size:11px; color:#64748b; margin-top:4px }
  .toggle-row { display:flex; align-items:center; gap:12px; padding:14px 0; border-bottom:1px solid #1e2a45 }
  .toggle-row label { font-weight:600; font-size:14px }
  table.data { width:100%; border-collapse:collapse; font-size:13px }
  table.data th { text-align:left; padding:10px 12px; color:#94a3b8; border-bottom:1px solid #1e2a45; font-weight:600 }
  table.data td { padding:10px 12px; border-bottom:1px solid #0d1626; color:#d1d5db }
  table.data tr:hover td { background:rgba(217,70,239,.06) }
  .badge-ok { display:inline-block; padding:2px 8px; border-radius:20px; background:rgba(34,197,94,.15); color:#22c55e; font-size:11px; font-weight:700 }
</style>

<div class="ref-grid">
  <div class="ref-stat">
    <div class="val"><?= number_format($totalClaims) ?></div>
    <div class="lbl">Total Referrals</div>
  </div>
  <div class="ref-stat">
    <div class="val"><?= number_format($totalCoinsAwarded) ?></div>
    <div class="lbl">Total Coins Awarded</div>
  </div>
  <div class="ref-stat">
    <div class="val"><?= number_format($activeUsersToday) ?></div>
    <div class="lbl">Active Users Today</div>
  </div>
  <div class="ref-stat">
    <div class="val"><?= $settings['enabled'] === '1' ? '<span style="color:#22c55e">ON</span>' : '<span style="color:#ef4444">OFF</span>' ?></div>
    <div class="lbl">Program Status</div>
  </div>
</div>

<div class="section" style="margin-bottom:24px">
  <div class="head"><b>Referral Program Settings</b></div>
  <div class="body">
    <?php if ($msg): ?>
      <div class="badge <?= $msgType ?>" style="margin-bottom:16px"><?= htmlspecialchars($msg) ?></div>
    <?php endif; ?>
    <form method="post" style="max-width:500px">

      <div class="toggle-row" style="margin-bottom:16px">
        <input type="checkbox" name="enabled" id="enabled" value="1" <?= $settings['enabled'] === '1' ? 'checked' : '' ?> style="width:18px;height:18px;accent-color:#d946ef">
        <label for="enabled">Referral Program Enabled</label>
      </div>

      <div class="field-wrap">
        <label>Coins Reward per Referral</label>
        <input type="number" name="coins_reward" value="<?= (int)$settings['coins_reward'] ?>" min="0" step="1">
        <div class="hint">Both the referrer and the new user receive this many coins</div>
      </div>

      <div class="field-wrap">
        <label>Minimum Active Days Required</label>
        <input type="number" name="min_active_days" value="<?= (int)$settings['min_active_days'] ?>" min="0" step="1">
        <div class="hint">How many unique days the new user must open the app before they can redeem. Set 0 to disable.</div>
      </div>

      <div class="field-wrap">
        <label>Minimum Daily Minutes Required (avg)</label>
        <input type="number" name="min_daily_minutes" value="<?= (int)$settings['min_daily_minutes'] ?>" min="0" step="1">
        <div class="hint">Average daily minutes the new user must spend in the app. Set 0 to disable.</div>
      </div>

      <button type="submit" style="padding:10px 28px;background:linear-gradient(135deg,#d946ef,#7c3aed);color:#fff;border:none;border-radius:8px;font-weight:700;cursor:pointer;font-size:15px">
        Save Settings
      </button>
    </form>
  </div>
</div>

<?php if (!empty($topReferrers)): ?>
<div class="section" style="margin-bottom:24px">
  <div class="head"><b>Top Referrers</b></div>
  <div class="body" style="padding:0">
    <table class="data">
      <thead><tr><th>#</th><th>Username</th><th>Referrals</th><th>Coins Earned</th></tr></thead>
      <tbody>
        <?php foreach ($topReferrers as $i => $r): ?>
        <tr>
          <td><?= $i + 1 ?></td>
          <td><?= htmlspecialchars($r['username'] ?? '—') ?></td>
          <td><?= number_format((int)$r['total_referrals']) ?></td>
          <td><?= number_format((int)$r['coins_earned']) ?></td>
        </tr>
        <?php endforeach; ?>
      </tbody>
    </table>
  </div>
</div>
<?php endif; ?>

<?php if (!empty($recentClaims)): ?>
<div class="section">
  <div class="head"><b>Recent Referral Claims</b></div>
  <div class="body" style="padding:0">
    <table class="data">
      <thead><tr><th>Date</th><th>New User</th><th>Used Code</th><th>Referrer</th><th>Coins</th></tr></thead>
      <tbody>
        <?php foreach ($recentClaims as $c): ?>
        <tr>
          <td><?= htmlspecialchars(substr($c['created_at'], 0, 16)) ?></td>
          <td><?= htmlspecialchars($c['claimer_name'] ?? '#'.$c['claimer_user_id']) ?></td>
          <td><code><?= htmlspecialchars($c['referral_code']) ?></code></td>
          <td><?= htmlspecialchars($c['referrer_name'] ?? '#'.$c['referrer_user_id']) ?></td>
          <td><span class="badge-ok"><?= (int)$c['coins_awarded'] ?> coins each</span></td>
        </tr>
        <?php endforeach; ?>
      </tbody>
    </table>
  </div>
</div>
<?php endif; ?>

<?php require __DIR__ . '/_layout_footer.php'; ?>
