<?php
require_once __DIR__ . '/_core.php';

if (!empty($_SESSION['admin_id'])) {
    header('Location: dashboard.php'); exit;
}

$err = '';
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $u = trim($_POST['username'] ?? '');
    $p = trim($_POST['password'] ?? '');
    try {
        $st = $pdo->prepare("SELECT id, username, password_hash FROM admin_users WHERE username=? LIMIT 1");
        $st->execute([$u]);
        $row = $st->fetch();
        if ($row && password_verify($p, $row['password_hash'])) {
            $_SESSION['admin_id']       = $row['id'];
            $_SESSION['admin_username'] = $row['username'];
            header('Location: dashboard.php'); exit;
        } else {
            $err = 'Invalid username or password.';
        }
    } catch (Throwable $e) {
        $err = 'Login error: ' . $e->getMessage();
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

    <?php if ($err): ?>
      <div class="alert danger"><?= htmlspecialchars($err) ?></div>
    <?php endif; ?>

    <form method="post">
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
