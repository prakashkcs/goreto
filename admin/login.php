<?php
require_once __DIR__ . '/_core.php';

if (!empty($_SESSION['admin_id'])) {
    header('Location: dashboard.php'); exit;
}

$csrfToken = admin_csrf_token();
$ip        = $_SERVER['REMOTE_ADDR'] ?? '0.0.0.0';

$err = '';
$isTimeout = !empty($_GET['timeout']);

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    // CSRF check first — rejects forged cross-site form submissions
    admin_verify_csrf();

    // Brute-force check
    if (!admin_check_ip_allowed($pdo, $ip)) {
        $err = 'Too many failed attempts. Please wait 15 minutes before trying again.';
    } else {
        $u = trim($_POST['username'] ?? '');
        $p = trim($_POST['password'] ?? '');
        try {
            $st = $pdo->prepare("SELECT id, username, password_hash FROM admin_users WHERE username = ? LIMIT 1");
            $st->execute([$u]);
            $row = $st->fetch();
            if ($row && password_verify($p, $row['password_hash'])) {
                admin_clear_login_attempts($pdo, $ip);
                session_regenerate_id(true); // Prevent session fixation
                $_SESSION['admin_id']       = $row['id'];
                $_SESSION['admin_username'] = $row['username'];
                $_SESSION['_last_active']   = time();
                unset($_SESSION['csrf_token']); // Rotate token after login
                header('Location: dashboard.php'); exit;
            } else {
                admin_record_failed_login($pdo, $ip);
                $err = 'Invalid username or password.';
            }
        } catch (Throwable $e) {
            $err = 'Login error. Please try again.';
        }
    }
}
?>
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <title>Admin Login – Love Vibe</title>
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <link rel="stylesheet" href="../assets/admin.css">
</head>
<body class="login-page">
<div class="login-wrap">
  <div class="login-box">
    <div class="login-logo">LV</div>
    <h2>Love Vibe Admin</h2>
    <p class="sub">Sign in to manage your platform</p>

    <?php if ($isTimeout): ?>
      <div class="alert warning">Session expired. Please sign in again.</div>
    <?php endif; ?>

    <?php if ($err): ?>
      <div class="alert danger"><?= htmlspecialchars($err) ?></div>
    <?php endif; ?>

    <form method="post" autocomplete="off">
      <input type="hidden" name="csrf_token" value="<?= htmlspecialchars($csrfToken) ?>">
      <div class="login-field">
        <label>Username</label>
        <input type="text" name="username" autofocus autocomplete="username" required placeholder="admin">
      </div>
      <div class="login-field">
        <label>Password</label>
        <input type="password" name="password" autocomplete="current-password" required placeholder="••••••••">
      </div>
      <button class="login-btn" type="submit">Sign In</button>
    </form>
  </div>
</div>
<script src="../assets/admin.js" defer></script>
</body>
</html>
