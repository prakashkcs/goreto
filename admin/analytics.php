<?php
require_once __DIR__ . '/_core.php';
admin_require_login();
$pageTitle = 'Analytics';
$activeNav = 'analytics';

function safe_count(PDO $pdo, string $q): int {
    try { return (int)$pdo->query($q)->fetchColumn(); } catch (Throwable $_) { return 0; }
}

$stats = [
    'Total Users'        => safe_count($pdo, "SELECT COUNT(*) FROM users"),
    'Active Today'       => safe_count($pdo, "SELECT COUNT(*) FROM users WHERE updated_at >= CURDATE()"),
    'Total Posts'        => safe_count($pdo, "SELECT COUNT(*) FROM posts"),
    'Total Stories'      => safe_count($pdo, "SELECT COUNT(*) FROM stories"),
    'Total Collections'  => safe_count($pdo, "SELECT COUNT(*) FROM collections"),
    'Total Comments'     => safe_count($pdo, "SELECT COUNT(*) FROM comments"),
    'Total Likes'        => safe_count($pdo, "SELECT COUNT(*) FROM likes"),
    'Total Groups'       => safe_count($pdo, "SELECT COUNT(*) FROM chat_groups"),
    'Pending KYC'        => safe_count($pdo, "SELECT COUNT(*) FROM kyc_submissions WHERE status='pending'"),
    'Pending Wallet Req' => safe_count($pdo, "SELECT COUNT(*) FROM wallet_requests WHERE status='pending'"),
    'Live Streams Now'   => safe_count($pdo, "SELECT COUNT(*) FROM live_streams WHERE last_heartbeat > DATE_SUB(NOW(), INTERVAL 45 SECOND)"),
    'Gifts Sent (All)'   => safe_count($pdo, "SELECT COUNT(*) FROM wallet_transactions WHERE type='gift'"),
];

// New signups per day (last 7 days)
$signups = [];
try {
    $rows = $pdo->query("
        SELECT DATE(created_at) as d, COUNT(*) as c
        FROM users WHERE created_at >= DATE_SUB(CURDATE(), INTERVAL 7 DAY)
        GROUP BY DATE(created_at) ORDER BY d ASC
    ")->fetchAll();
    foreach ($rows as $r) $signups[$r['d']] = $r['c'];
} catch (Throwable $_) {}

// Top active users
$topUsers = [];
try {
    $topUsers = $pdo->query("
        SELECT u.id, u.name, u.username,
               COUNT(p.id) AS post_count
        FROM users u
        LEFT JOIN posts p ON p.user_id = u.id
        GROUP BY u.id ORDER BY post_count DESC LIMIT 10
    ")->fetchAll();
} catch (Throwable $_) {}

require __DIR__ . '/_layout_header.php';
?>
<style>
.stat-grid { display:grid; grid-template-columns:repeat(auto-fill,minmax(160px,1fr)); gap:14px; margin-bottom:28px; }
.stat-box { background:rgba(15,27,51,.5); border:1px solid #223a66; border-radius:10px; padding:18px 16px; text-align:center; }
.stat-box .val { font-size:28px; font-weight:900; color:#D946EF; }
.stat-box .lbl { font-size:12px; opacity:.7; margin-top:4px; }
.bar-wrap { display:flex; align-items:flex-end; gap:8px; height:80px; }
.bar { flex:1; background:linear-gradient(to top,#FF007F,#D946EF); border-radius:4px 4px 0 0; min-height:4px; position:relative; }
.bar span { position:absolute; bottom:-20px; left:50%; transform:translateX(-50%); font-size:10px; white-space:nowrap; opacity:.6; }
</style>

<div class="section">
  <div class="head"><b>Analytics Overview</b></div>
  <div class="body">

    <div class="stat-grid">
      <?php foreach ($stats as $label => $val): ?>
        <div class="stat-box">
          <div class="val"><?= number_format($val) ?></div>
          <div class="lbl"><?= htmlspecialchars($label) ?></div>
        </div>
      <?php endforeach; ?>
    </div>

    <?php if ($signups): ?>
    <h3 style="margin-bottom:12px">New Signups — Last 7 Days</h3>
    <?php $max = max(array_values($signups)); ?>
    <div style="background:rgba(15,27,51,.5);border:1px solid #223a66;border-radius:10px;padding:20px 16px 36px;margin-bottom:28px;">
      <div class="bar-wrap">
        <?php foreach ($signups as $date => $count): ?>
          <div class="bar" style="height:<?= $max>0 ? round($count/$max*80) : 4 ?>px" title="<?= $count ?> signups">
            <span><?= date('D', strtotime($date)) ?></span>
          </div>
        <?php endforeach; ?>
      </div>
    </div>
    <?php endif; ?>

    <?php if ($topUsers): ?>
    <h3 style="margin-bottom:12px">Top Content Creators</h3>
    <div class="table-wrap"><table>
      <thead><tr><th>#</th><th>User</th><th>Posts</th></tr></thead>
      <tbody>
        <?php foreach ($topUsers as $i => $u): ?>
          <tr>
            <td><?= $i+1 ?></td>
            <td><b><?= htmlspecialchars($u['name'] ?? '') ?></b> <small>@<?= htmlspecialchars($u['username'] ?? '') ?></small></td>
            <td><?= (int)$u['post_count'] ?></td>
          </tr>
        <?php endforeach; ?>
      </tbody>
    </table></div>
    <?php endif; ?>
  </div>
</div>
<?php require __DIR__ . '/_layout_footer.php'; ?>
