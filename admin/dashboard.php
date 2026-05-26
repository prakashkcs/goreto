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
];
try {
  $counts['pending_kyc'] = (int) $pdo->query("SELECT COUNT(*) FROM kyc_submissions WHERE status='pending'")->fetchColumn();
} catch (Throwable $_) {
}
try {
  $counts['pending_wallet'] = (int) $pdo->query("SELECT COUNT(*) FROM wallet_requests WHERE status='pending'")->fetchColumn();
} catch (Throwable $_) {
}

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