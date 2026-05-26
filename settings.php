<?php
require_once __DIR__ . '/_core.php';
admin_require_login();
$pageTitle = 'Admin Settings';
$activeNav = 'settings';

$msg = '';
$err = '';

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $action = $_POST['action'] ?? '';

    if ($action === 'change_username') {
        $newUsername = trim($_POST['new_username'] ?? '');
        $currentPass = $_POST['current_password'] ?? '';

        if (strlen($newUsername) < 3) {
            $err = 'Username must be at least 3 characters.';
        } elseif (!preg_match('/^[a-zA-Z0-9_]+$/', $newUsername)) {
            $err = 'Username can only contain letters, numbers, and underscores.';
        } else {
            $row = $pdo->prepare("SELECT password_hash FROM admin_users WHERE id=?")->execute([$_SESSION['admin_id']]) ? null : null;
            $stmt = $pdo->prepare("SELECT password_hash FROM admin_users WHERE id=?");
            $stmt->execute([$_SESSION['admin_id']]);
            $row = $stmt->fetch();
            if (!$row || !password_verify($currentPass, $row['password_hash'])) {
                $err = 'Current password is incorrect.';
            } else {
                $exists = $pdo->prepare("SELECT id FROM admin_users WHERE username=? AND id!=?");
                $exists->execute([$newUsername, $_SESSION['admin_id']]);
                if ($exists->fetch()) {
                    $err = 'Username already taken.';
                } else {
                    $pdo->prepare("UPDATE admin_users SET username=? WHERE id=?")->execute([$newUsername, $_SESSION['admin_id']]);
                    $_SESSION['admin_username'] = $newUsername;
                    $msg = 'Username updated successfully.';
                }
            }
        }
    }

    if ($action === 'change_password') {
        $currentPass = $_POST['current_password'] ?? '';
        $newPass     = $_POST['new_password'] ?? '';
        $confirmPass = $_POST['confirm_password'] ?? '';

        $stmt = $pdo->prepare("SELECT password_hash FROM admin_users WHERE id=?");
        $stmt->execute([$_SESSION['admin_id']]);
        $row = $stmt->fetch();

        if (!$row || !password_verify($currentPass, $row['password_hash'])) {
            $err = 'Current password is incorrect.';
        } elseif (strlen($newPass) < 6) {
            $err = 'New password must be at least 6 characters.';
        } elseif ($newPass !== $confirmPass) {
            $err = 'New passwords do not match.';
        } else {
            $hash = password_hash($newPass, PASSWORD_DEFAULT);
            $pdo->prepare("UPDATE admin_users SET password_hash=? WHERE id=?")->execute([$hash, $_SESSION['admin_id']]);
            $msg = 'Password updated successfully.';
        }
    }
}

$stmt = $pdo->prepare("SELECT username FROM admin_users WHERE id=?");
$stmt->execute([$_SESSION['admin_id']]);
$adminRow = $stmt->fetch();
$currentUsername = $adminRow['username'] ?? $_SESSION['admin_username'] ?? 'admin';

require __DIR__ . '/_layout_header.php';
?>

<div class="section" style="max-width:520px">
  <div class="head"><b>Admin Account Settings</b></div>
  <div class="body" style="padding:20px 24px">

    <?php if ($msg): ?>
      <div class="badge ok" style="margin-bottom:16px;padding:10px 14px"><?= htmlspecialchars($msg) ?></div>
    <?php endif; ?>
    <?php if ($err): ?>
      <div class="badge danger" style="margin-bottom:16px;padding:10px 14px"><?= htmlspecialchars($err) ?></div>
    <?php endif; ?>

    <p style="color:#aaa;font-size:13px;margin-bottom:20px">
      Logged in as: <strong style="color:#fff"><?= htmlspecialchars($currentUsername) ?></strong>
    </p>

    <!-- Change Username -->
    <form method="post" style="margin-bottom:32px">
      <input type="hidden" name="action" value="change_username">
      <h3 style="font-size:15px;margin-bottom:14px;color:#e2e8f0">Change Username</h3>
      <div style="display:flex;flex-direction:column;gap:10px">
        <input name="new_username" placeholder="New username" value="<?= htmlspecialchars($currentUsername) ?>"
               style="padding:10px 12px;border-radius:6px;border:1px solid #334;background:#111;color:#fff;font-size:14px">
        <input type="password" name="current_password" placeholder="Current password (to confirm)"
               style="padding:10px 12px;border-radius:6px;border:1px solid #334;background:#111;color:#fff;font-size:14px">
        <button class="btn ok" type="submit" style="width:fit-content;padding:8px 20px">Update Username</button>
      </div>
    </form>

    <hr style="border-color:#223;margin-bottom:28px">

    <!-- Change Password -->
    <form method="post">
      <input type="hidden" name="action" value="change_password">
      <h3 style="font-size:15px;margin-bottom:14px;color:#e2e8f0">Change Password</h3>
      <div style="display:flex;flex-direction:column;gap:10px">
        <input type="password" name="current_password" placeholder="Current password"
               style="padding:10px 12px;border-radius:6px;border:1px solid #334;background:#111;color:#fff;font-size:14px">
        <input type="password" name="new_password" placeholder="New password (min 6 chars)"
               style="padding:10px 12px;border-radius:6px;border:1px solid #334;background:#111;color:#fff;font-size:14px">
        <input type="password" name="confirm_password" placeholder="Confirm new password"
               style="padding:10px 12px;border-radius:6px;border:1px solid #334;background:#111;color:#fff;font-size:14px">
        <button class="btn ok" type="submit" style="width:fit-content;padding:8px 20px">Update Password</button>
      </div>
    </form>

  </div>
</div>

<?php require __DIR__ . '/_layout_footer.php'; ?>
