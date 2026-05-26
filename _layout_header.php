<?php
// admin/_layout_header.php
if (!isset($pageTitle))
  $pageTitle = 'Dashboard';
if (!isset($activeNav))
  $activeNav = 'dashboard';
$adminUser = $_SESSION['admin_username'] ?? 'admin';
?>
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <title><?php echo htmlspecialchars($pageTitle); ?> - Love Vibe Admin</title>
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <link rel="stylesheet" href="assets/admin.css">
  <script src="assets/admin.js" defer></script>
</head>
<body>
<div class="wrap">

  <aside class="sidebar">
    <div class="brand">
      <div class="logo">LV</div>
      <div>
        <div class="title">Love Vibe Admin</div>
        <div class="sub">Logged in: <?php echo htmlspecialchars($adminUser); ?></div>
      </div>
    </div>

    <nav class="nav">
      <a href="dashboard.php" class="<?php echo $activeNav === 'dashboard' ? 'active' : ''; ?>"><span class="dot"></span> Dashboard</a>
      <a href="users.php" class="<?php echo $activeNav === 'users' ? 'active' : ''; ?>"><span class="dot"></span> Users</a>
      <a href="groups.php" class="<?php echo $activeNav === 'groups' ? 'active' : ''; ?>"><span class="dot"></span> Group Chats</a>
      <a href="posts.php" class="<?php echo $activeNav === 'posts' ? 'active' : ''; ?>"><span class="dot"></span> Posts</a>
      <a href="stories.php" class="<?php echo $activeNav === 'stories' ? 'active' : ''; ?>"><span class="dot"></span> Stories</a>
      <a href="collections.php" class="<?php echo $activeNav === 'collections' ? 'active' : ''; ?>"><span class="dot"></span> Collections</a>
      <a href="gifts.php" class="<?php echo $activeNav === 'gifts' ? 'active' : ''; ?>"><span class="dot"></span> Gifts (3D)</a>
      <a href="analytics.php" class="<?php echo $activeNav === 'analytics' ? 'active' : ''; ?>"><span class="dot"></span> Analytics</a>
      <a href="kyc_review.php" class="<?php echo $activeNav === 'kyc_review' ? 'active' : ''; ?>"><span class="dot"></span> KYC Review</a>
      <a href="income_review.php" class="<?php echo $activeNav === 'income_review' ? 'active' : ''; ?>"><span class="dot"></span> Income Review</a>
      <a href="wallet_settings.php" class="<?php echo $activeNav === 'wallet_settings' ? 'active' : ''; ?>"><span class="dot"></span> Wallet Settings</a>
      <a href="video_apis.php" class="<?php echo $activeNav === 'video_settings' ? 'active' : ''; ?>"><span class="dot"></span> Video APIs</a>
      <a href="wallet_methods.php" class="<?php echo $activeNav === 'wallet_methods' ? 'active' : ''; ?>"><span class="dot"></span> Wallet Methods</a>
      <a href="wallet_requests.php" class="<?php echo $activeNav === 'wallet_requests' ? 'active' : ''; ?>"><span class="dot"></span> Wallet Requests</a>
      <a href="withdrawals.php" class="<?php echo $activeNav === 'withdrawals' ? 'active' : ''; ?>"><span class="dot"></span> Withdrawals</a>
      <a href="withdrawal_settings.php" class="<?php echo $activeNav === 'withdrawal_settings' ? 'active' : ''; ?>"><span class="dot"></span> Withdraw Settings</a>
      <a href="notifications.php" class="<?php echo $activeNav === 'notifications' ? 'active' : ''; ?>"><span class="dot"></span> Notifications</a>
      <a href="reports.php" class="<?php echo $activeNav === 'reports' ? 'active' : ''; ?>"><span class="dot"></span> User Reports</a>
    </nav>
  </aside>

  <main class="main">
    <div class="topbar">
      <div class="page-title">
        <b><?php echo htmlspecialchars($pageTitle); ?></b>
        <span>Manage your app content safely</span>
      </div>
      <div class="actions">
        <a class="btn" href="dashboard.php">Home</a>
        <a class="btn danger" href="logout.php">Logout</a>
      </div>
    </div>