<?php
if (!isset($pageTitle))
  $pageTitle = 'Dashboard';
if (!isset($activeNav))
  $activeNav = 'dashboard';
$adminUser = $_SESSION['admin_username'] ?? 'admin';

$adminAlertCounts = function_exists('admin_alert_counts') ? admin_alert_counts($pdo) : [];

// Helper: nav link
function nav_link(string $href, string $nav_key, string $active, string $label, string $badge = ''): string
{
  $cls = $active === $nav_key ? ' class="active"' : '';
  return "<a href=\"{$href}\"{$cls}><span class=\"dot\"></span><span class=\"nav-text\"> {$label}</span>{$badge}</a>";
}
?>
<!doctype html>
<html>

<head>
  <meta charset="utf-8">
  <title><?= htmlspecialchars($pageTitle) ?> — Goreto Admin</title>
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800;900&display=swap"
    rel="stylesheet">
  <link rel="stylesheet" href="../assets/admin.css">
  <style>
    .nav a {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 10px
    }

    .nav-text {
      flex: 1
    }

    .nav-badge {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      min-width: 22px;
      height: 22px;
      padding: 0 7px;
      border-radius: 999px;
      background: #ff4d6d;
      color: #fff;
      font-size: 11px;
      font-weight: 800;
      line-height: 1;
      box-shadow: 0 0 0 2px rgba(255, 77, 109, .18)
    }

    .nav-badge.total {
      background: #7c3aed
    }

    .top-alert-chip {
      display: inline-flex;
      align-items: center;
      gap: 8px;
      padding: 8px 12px;
      border-radius: 999px;
      background: rgba(124, 58, 237, .14);
      border: 1px solid rgba(124, 58, 237, .35);
      color: #efe7ff;
      font-weight: 700;
      font-size: 12px
    }
  </style>
</head>

<body>
  <div class="sidebar-overlay"></div>
  <div class="wrap">

    <aside class="sidebar">
      <div class="brand">
        <div class="logo">G</div>
        <div>
          <div class="title">Goreto</div>
          <div class="sub"><?= htmlspecialchars($adminUser) ?></div>
        </div>
      </div>

      <nav class="nav">
        <div class="nav-label">Overview</div>
        <?= nav_link('dashboard.php', 'dashboard', $activeNav, 'Dashboard', admin_badge_html((int) ($adminAlertCounts['important_total'] ?? 0), 'total')) ?>
        <?= nav_link('analytics.php', 'analytics', $activeNav, 'Analytics') ?>
        <?= nav_link('user_analytics.php', 'user_analytics', $activeNav, '🔥 Deep Analytics') ?>

        <div class="nav-label">Content</div>
        <?= nav_link('users.php', 'users', $activeNav, 'Users') ?>
        <?= nav_link('posts.php', 'posts', $activeNav, 'Posts') ?>
        <?= nav_link('stories.php', 'stories', $activeNav, 'Stories') ?>
        <?= nav_link('collections.php', 'collections', $activeNav, 'Collections') ?>
        <?= nav_link('groups.php', 'groups', $activeNav, 'Group Chats') ?>
        <?= nav_link('gifts.php', 'gifts', $activeNav, 'Gifts') ?>
        <?= nav_link('reports.php', 'reports', $activeNav, 'User Reports', admin_badge_html((int) ($adminAlertCounts['reports'] ?? 0))) ?>
        <?= nav_link('sound_reports.php', 'sound_reports', $activeNav, 'Sound Reports', admin_badge_html((int) ($adminAlertCounts['sound_reports'] ?? 0))) ?>

        <div class="nav-label">Monetization</div>
        <?= nav_link('ads_settings.php', 'ads_settings', $activeNav, '💰 Ads & Revenue') ?>

        <div class="nav-label">Finance</div>
        <?= nav_link('wallet_requests.php', 'wallet_requests', $activeNav, 'Wallet Requests', admin_badge_html((int) ($adminAlertCounts['wallet_requests'] ?? 0))) ?>
        <?= nav_link('withdrawals.php', 'withdrawals', $activeNav, 'Withdrawals', admin_badge_html((int) ($adminAlertCounts['withdrawals'] ?? 0))) ?>
        <?= nav_link('wallet_methods.php', 'wallet_methods', $activeNav, 'Payment Methods') ?>
        <?= nav_link('wallet_settings.php', 'wallet_settings', $activeNav, 'Wallet Settings') ?>
        <?= nav_link('withdrawal_settings.php', 'withdrawal_settings', $activeNav, 'Withdraw Settings') ?>
        <?= nav_link('referral_settings.php', 'referral_settings', $activeNav, 'Referral Settings') ?>

        <div class="nav-label">Review</div>
        <?= nav_link('kyc_review.php', 'kyc_review', $activeNav, 'KYC Review', admin_badge_html((int) ($adminAlertCounts['kyc_review'] ?? 0))) ?>
        <?= nav_link('income_review.php', 'income_review', $activeNav, 'Income Review') ?>

        <div class="nav-label">System</div>
        <?= nav_link('notifications.php', 'notifications', $activeNav, 'Notifications', admin_badge_html((int) ($adminAlertCounts['notifications'] ?? 0), 'total')) ?>
        <?= nav_link('video_apis.php', 'video_settings', $activeNav, 'Video APIs') ?>
        <?= nav_link('onesignal_settings.php', 'onesignal_settings', $activeNav, 'OneSignal Push') ?>
        <?= nav_link('legal.php', 'legal', $activeNav, 'Legal Pages') ?>
        <?= nav_link('email_inbox.php', 'email_inbox', $activeNav, 'Email Inbox') ?>
        <?= nav_link('app_store_settings.php', 'app_store_settings', $activeNav, 'App Store Links') ?>
        <?= nav_link('seo_settings.php', 'seo_settings', $activeNav, 'SEO Settings') ?>
      </nav>
    </aside>

    <main class="main">
      <div class="topbar">
        <div style="display:flex;align-items:center;gap:12px">
          <button class="menu-toggle" aria-label="Menu">&#9776;</button>
          <div class="page-title">
            <b><?= htmlspecialchars($pageTitle) ?></b>
            <span>Goreto Admin Panel</span>
          </div>
        </div>
        <div class="actions">
          <?php if (!empty($adminAlertCounts['important_total'])): ?>
            <span class="top-alert-chip">🔔 <?= (int) $adminAlertCounts['important_total'] ?> pending admin checks</span>
          <?php endif; ?>
          <a class="btn" href="dashboard.php">Home</a>
          <a class="btn danger" href="logout.php">Logout</a>
        </div>
      </div>
      <div style="padding:24px">