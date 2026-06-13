<?php
require_once __DIR__ . '/_core.php';
admin_require_login();

$pageTitle = 'Dashboard';
$activeNav = 'dashboard';

$counts = [
  'users' => table_count($pdo, 'users'),
  'posts' => table_count($pdo, 'posts'),
  'stories' => table_count($pdo, 'stories'),
  'collections' => table_count($pdo, 'collections'),
  'comments' => table_count($pdo, 'comments'),
  'likes' => table_count($pdo, 'likes'),
  'pending_kyc' => 0,
  'pending_wallet' => 0,
  'total_calls' => 0,
  'call_minutes' => 0,
];
try {
  $counts['pending_kyc'] = (int) $pdo->query("SELECT COUNT(*) FROM kyc_submissions WHERE status='pending'")->fetchColumn();
} catch (Throwable $_) {}
try {
  $counts['pending_wallet'] = (int) $pdo->query("SELECT COUNT(*) FROM wallet_requests WHERE status='pending'")->fetchColumn();
} catch (Throwable $_) {}
try {
  $counts['total_calls'] = (int) $pdo->query("SELECT COUNT(*) FROM calls WHERE status='ended'")->fetchColumn();
  $totalSec = (int) $pdo->query("SELECT COALESCE(SUM(TIMESTAMPDIFF(SECOND,created_at,updated_at)),0) FROM calls WHERE status='ended'")->fetchColumn();
  $counts['call_minutes'] = (int) round($totalSec / 60);
} catch (Throwable $_) {}

// ── Video API trial info ──────────────────────────────────────────────────────
$videoApiInfo = null;
try {
  try { $pdo->exec("ALTER TABLE video_providers ADD COLUMN trial_started_at DATETIME NULL"); } catch (Throwable $_) {}
  $vRow = $pdo->query("SELECT provider_name, updated_at, trial_started_at FROM video_providers WHERE is_active=1 LIMIT 1")->fetch(PDO::FETCH_ASSOC);
  if ($vRow) {
    $trialStart  = $vRow['trial_started_at'] ?: $vRow['updated_at'];
    $daysUsed    = max(0, (int) floor((time() - strtotime($trialStart)) / 86400));
    $daysLeft    = max(0, 30 - $daysUsed);
    $pctUsed     = min(100, round($daysUsed / 30 * 100));
    $videoApiInfo = [
      'name'       => ucfirst($vRow['provider_name']),
      'start_date' => date('M j, Y', strtotime($trialStart)),
      'days_used'  => $daysUsed,
      'days_left'  => $daysLeft,
      'pct_used'   => $pctUsed,
    ];
  }
} catch (Throwable $_) {}

$alertCounts = admin_alert_counts($pdo);
$importantCards = [
  ['label' => 'Deposit Checks', 'count' => (int) ($alertCounts['wallet_requests'] ?? 0), 'href' => 'wallet_requests.php', 'hint' => 'Pending deposit / wallet review'],
  ['label' => 'Withdrawal Checks', 'count' => (int) ($alertCounts['withdrawals'] ?? 0), 'href' => 'withdrawals.php', 'hint' => 'Pending withdrawal approvals'],
  ['label' => 'KYC Review', 'count' => (int) ($alertCounts['kyc_review'] ?? 0), 'href' => 'kyc_review.php', 'hint' => 'Users waiting for verification'],
  ['label' => 'User Reports', 'count' => (int) ($alertCounts['reports'] ?? 0), 'href' => 'reports.php', 'hint' => 'Pending abuse / profile reports'],
  ['label' => 'Sound Reports', 'count' => (int) ($alertCounts['sound_reports'] ?? 0), 'href' => 'sound_reports.php', 'hint' => 'Pending reel audio reports'],
  ['label' => 'Admin Notifications', 'count' => (int) ($alertCounts['notifications'] ?? 0), 'href' => 'notifications.php', 'hint' => 'Total important checks'],
];

require __DIR__ . '/_layout_header.php';
?>
<style>
  .dash-grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(160px, 1fr));
    gap: 14px;
    margin-bottom: 28px
  }

  .dash-box {
    background: rgba(15, 27, 51, .5);
    border: 1px solid #223a66;
    border-radius: 10px;
    padding: 18px 16px;
    text-align: center
  }

  .dash-box .val {
    font-size: 28px;
    font-weight: 900;
    color: #D946EF
  }

  .dash-box .lbl {
    font-size: 12px;
    opacity: .7;
    margin-top: 4px
  }

  .alert-grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(220px, 1fr));
    gap: 14px
  }

  .alert-card {
    display: block;
    text-decoration: none;
    color: inherit;
    background: rgba(124, 58, 237, .09);
    border: 1px solid rgba(124, 58, 237, .25);
    border-radius: 14px;
    padding: 16px
  }

  .alert-card:hover {
    transform: translateY(-1px);
    border-color: rgba(124, 58, 237, .45)
  }

  .alert-top {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 10px;
    margin-bottom: 8px
  }

  .alert-count {
    display: inline-flex;
    min-width: 34px;
    height: 34px;
    align-items: center;
    justify-content: center;
    border-radius: 999px;
    background: #7c3aed;
    color: #fff;
    font-weight: 900
  }

  .alert-zero {
    background: #334155
  }

  .alert-hint {
    font-size: 12px;
    opacity: .75
  }
</style>
<div class="dash-grid">
  <?php
  $labels = [
    'users' => 'Total Users',
    'posts' => 'Posts',
    'stories' => 'Stories',
    'collections' => 'Collections',
    'comments' => 'Comments',
    'likes' => 'Likes',
    'total_calls' => 'Total Calls',
    'call_minutes' => 'Call Minutes',
    'pending_kyc' => 'Pending KYC',
    'pending_wallet' => 'Pending Wallet'
  ];
  foreach ($labels as $k => $lbl): ?>
    <div class="dash-box">
      <div class="val"><?= number_format($counts[$k]) ?></div>
      <div class="lbl"><?= $lbl ?></div>
    </div>
  <?php endforeach; ?>
</div>

<div class="section">
  <div class="head"><b>Important Admin Notifications</b><small>Things admin should check now</small></div>
  <div class="body">
    <div class="alert-grid">
      <?php foreach ($importantCards as $card): ?>
        <a class="alert-card" href="<?= htmlspecialchars($card['href']) ?>">
          <div class="alert-top">
            <strong><?= htmlspecialchars($card['label']) ?></strong>
            <span class="alert-count <?= $card['count'] <= 0 ? 'alert-zero' : '' ?>"><?= (int) $card['count'] ?></span>
          </div>
          <div class="alert-hint"><?= htmlspecialchars($card['hint']) ?></div>
        </a>
      <?php endforeach; ?>
    </div>
  </div>
</div>

<?php if ($videoApiInfo): ?>
<div class="section">
  <div class="head">
    <b>Video API Trial</b>
    <small><a href="video_apis.php" style="color:#a78bfa;text-decoration:none;">Manage &rarr;</a></small>
  </div>
  <div class="body">
    <div style="display:grid;grid-template-columns:1fr 1fr;gap:16px;">

      <!-- Provider + trial progress -->
      <div style="background:rgba(15,27,51,.6);border:1px solid #223a66;border-radius:12px;padding:20px;">
        <div style="display:flex;align-items:center;gap:10px;margin-bottom:14px;">
          <span style="width:10px;height:10px;border-radius:50%;background:<?= $videoApiInfo['name']==='Agora' ? '#2979FF' : '#D946EF' ?>;display:inline-block;flex-shrink:0;"></span>
          <span style="font-size:18px;font-weight:800;"><?= htmlspecialchars($videoApiInfo['name']) ?></span>
          <span style="font-size:11px;padding:2px 8px;border-radius:20px;background:#1b5e2044;color:#66bb6a;border:1px solid #2e7d32;font-weight:600;">ACTIVE</span>
        </div>

        <div style="font-size:12px;opacity:.65;margin-bottom:6px;">Trial started: <?= $videoApiInfo['start_date'] ?></div>

        <!-- Progress bar -->
        <?php
          $barColor = $videoApiInfo['days_left'] > 14 ? '#22c55e' : ($videoApiInfo['days_left'] > 6 ? '#f59e0b' : '#ef4444');
        ?>
        <div style="background:#1e293b;border-radius:999px;height:8px;margin-bottom:8px;overflow:hidden;">
          <div style="height:100%;width:<?= $videoApiInfo['pct_used'] ?>%;background:<?= $barColor ?>;border-radius:999px;transition:width .4s;"></div>
        </div>

        <div style="display:flex;justify-content:space-between;font-size:12px;">
          <span style="opacity:.6;"><?= $videoApiInfo['days_used'] ?> days used</span>
          <span style="font-weight:700;color:<?= $barColor ?>;">
            <?= $videoApiInfo['days_left'] ?> day<?= $videoApiInfo['days_left'] !== 1 ? 's' : '' ?> left
          </span>
        </div>

        <?php if ($videoApiInfo['days_left'] <= 7): ?>
          <div style="margin-top:12px;padding:8px 12px;background:#b71c1c33;border:1px solid #b71c1c;border-radius:8px;font-size:12px;color:#ef9a9a;">
            Trial ending soon — renew or switch provider to avoid disruption.
          </div>
        <?php endif; ?>
      </div>

      <!-- Call usage stats -->
      <div style="background:rgba(15,27,51,.6);border:1px solid #223a66;border-radius:12px;padding:20px;">
        <div style="font-size:12px;opacity:.65;margin-bottom:14px;font-weight:600;text-transform:uppercase;letter-spacing:.05em;">Usage via <?= htmlspecialchars($videoApiInfo['name']) ?></div>
        <div style="display:grid;grid-template-columns:1fr 1fr;gap:12px;">
          <div style="text-align:center;padding:14px;background:rgba(41,121,255,.1);border:1px solid rgba(41,121,255,.25);border-radius:10px;">
            <div style="font-size:26px;font-weight:900;color:#60a5fa;"><?= number_format($counts['call_minutes']) ?></div>
            <div style="font-size:11px;opacity:.7;margin-top:4px;">Total Minutes</div>
          </div>
          <div style="text-align:center;padding:14px;background:rgba(124,58,237,.1);border:1px solid rgba(124,58,237,.25);border-radius:10px;">
            <div style="font-size:26px;font-weight:900;color:#a78bfa;"><?= number_format($counts['total_calls']) ?></div>
            <div style="font-size:11px;opacity:.7;margin-top:4px;">Completed Calls</div>
          </div>
        </div>
        <div style="margin-top:12px;font-size:12px;opacity:.55;text-align:center;">
          Calculated from call logs &bull; <a href="video_apis.php" style="color:#a78bfa;">Update trial date &rarr;</a>
        </div>
      </div>

    </div>
  </div>
</div>
<?php endif; ?>

<div class="section">
  <div class="head"><b>Quick Actions</b></div>
  <div class="body" style="display:flex;gap:10px;flex-wrap:wrap;">
    <a class="btn" href="users.php">Users</a>
    <a class="btn" href="posts.php">Posts</a>
    <a class="btn" href="stories.php">Stories</a>
    <a class="btn" href="collections.php">Collections</a>
    <a class="btn" href="kyc_review.php">KYC Review</a>
    <a class="btn" href="wallet_requests.php">Wallet Requests</a>
    <a class="btn" href="withdrawals.php">Withdrawals</a>
    <a class="btn" href="reports.php">User Reports</a>
    <a class="btn" href="sound_reports.php">Sound Reports</a>
    <a class="btn" href="notifications.php">Notifications</a>
    <a class="btn" href="analytics.php">Analytics</a>
  </div>
</div>

<?php require __DIR__ . '/_layout_footer.php'; ?>