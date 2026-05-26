<?php
require_once __DIR__ . '/_core.php';
admin_require_login();

$pageTitle = 'Users';
$activeNav = 'users';

function h($s)
{
  return htmlspecialchars((string) $s, ENT_QUOTES, 'UTF-8');
}

function ensure_wallet_u(PDO $pdo, int $userId): void
{
  try {
    $pdo->prepare("INSERT IGNORE INTO user_wallets (user_id, balance_coins, locked_coins) VALUES (?,0,0)")->execute([$userId]);
  } catch (Throwable $_) {
  }
}

function get_wallet_u(PDO $pdo, int $userId): array
{
  ensure_wallet_u($pdo, $userId);
  try {
    $st = $pdo->prepare("SELECT balance_coins, locked_coins, updated_at FROM user_wallets WHERE user_id=? LIMIT 1");
    $st->execute([$userId]);
    $w = $st->fetch();
    return ['balance_coins' => (int) ($w['balance_coins'] ?? 0), 'locked_coins' => (int) ($w['locked_coins'] ?? 0), 'updated_at' => $w['updated_at'] ?? null];
  } catch (Throwable $_) {
    return ['balance_coins' => 0, 'locked_coins' => 0, 'updated_at' => null];
  }
}

function log_wallet_u(PDO $pdo, int $uid, string $type, string $dir, int $coins, string $note): void
{
  try {
    $pdo->prepare("INSERT INTO wallet_transactions (user_id,type,direction,coins,status,reference,note) VALUES (?,?,?,?,'completed',?,?)")
      ->execute([$uid, $type, $dir, $coins, 'admin_' . time(), $note]);
  } catch (Throwable $_) {
  }
}

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
  $action = $_POST['action'] ?? '';
  $id = (int) ($_POST['user_id'] ?? 0);

  if ($id > 0 && $action === 'ban') {
    $reason = trim($_POST['ban_reason'] ?? '') ?: 'Violation of app rules';
    $pdo->prepare("UPDATE users SET is_banned=1, ban_reason=?, banned_at=NOW() WHERE id=?")->execute([$reason, $id]);
    try {
      send_notif($pdo, $id, 'system', 'Account Suspended', 'Your account has been suspended. Reason: ' . $reason);
    } catch (Throwable $_) {
    }
    header("Location: users.php?edit=$id");
    exit;
  }
  if ($id > 0 && $action === 'unban') {
    $pdo->prepare("UPDATE users SET is_banned=0, ban_reason=NULL, banned_at=NULL WHERE id=?")->execute([$id]);
    header("Location: users.php?edit=$id");
    exit;
  }
  if ($id > 0 && $action === 'device_ban') {
    $reason = trim($_POST['device_ban_reason'] ?? '') ?: 'Device banned by admin';
    try {
      $pdo->prepare("UPDATE users SET device_ban=1, device_ban_reason=?, device_banned_at=NOW() WHERE id=?")->execute([$reason, $id]);
    } catch (Throwable $_) {
    }
    try {
      send_notif($pdo, $id, 'system', 'Device Banned', 'Your device has been banned. Reason: ' . $reason);
    } catch (Throwable $_) {
    }
    header("Location: users.php?edit=$id");
    exit;
  }
  if ($id > 0 && $action === 'device_unban') {
    try {
      $pdo->prepare("UPDATE users SET device_ban=0, device_ban_reason=NULL, device_banned_at=NULL WHERE id=?")->execute([$id]);
    } catch (Throwable $_) {
    }
    header("Location: users.php?edit=$id");
    exit;
  }
  if ($id > 0 && $action === 'update_user') {
    $name = trim($_POST['name'] ?? '') ?: 'User ' . $id;
    $email = trim($_POST['email'] ?? '') ?: 'user' . $id . '@example.com';
    $bio = trim($_POST['bio'] ?? '');
    $pic = trim($_POST['profile_pic'] ?? '');
    $token = trim($_POST['api_token'] ?? '');
    $sub = in_array($_POST['subscription_status'] ?? '', ['active', 'inactive', 'disabled']) ? $_POST['subscription_status'] : 'inactive';
    $pdo->prepare("UPDATE users SET name=?,email=?,bio=?,profile_pic=?,api_token=?,subscription_status=? WHERE id=?")
      ->execute([$name, $email, $bio ?: null, $pic ?: null, $token ?: null, $sub, $id]);
    header("Location: users.php?edit=$id");
    exit;
  }
  if ($id > 0 && $action === 'wallet_adjust') {
    $mode = $_POST['mode'] ?? 'add';
    $coins = (int) ($_POST['coins'] ?? 0);
    $note = trim($_POST['note'] ?? '');
    if ($coins > 0) {
      ensure_wallet_u($pdo, $id);
      $w = get_wallet_u($pdo, $id);
      if ($mode === 'subtract') {
        $newBal = max(0, $w['balance_coins'] - $coins);
        $pdo->prepare("UPDATE user_wallets SET balance_coins=?,updated_at=NOW() WHERE user_id=?")->execute([$newBal, $id]);
        log_wallet_u($pdo, $id, 'admin_adjust', 'debit', $coins, $note ?: 'Admin decreased coins');
      } else {
        $newBal = $w['balance_coins'] + $coins;
        $pdo->prepare("UPDATE user_wallets SET balance_coins=?,updated_at=NOW() WHERE user_id=?")->execute([$newBal, $id]);
        log_wallet_u($pdo, $id, 'admin_adjust', 'credit', $coins, $note ?: 'Admin added coins');
      }
    }
    header("Location: users.php?edit=$id");
    exit;
  }
  header("Location: users.php");
  exit;
}

if (isset($_GET['delete'])) {
  $id = (int) $_GET['delete'];
  if ($id > 0) {
    foreach (['post_likes', 'post_comments', 'posts', 'stories', 'collections', 'user_sessions', 'wallet_transactions', 'user_wallets'] as $t)
      try {
        $pdo->prepare("DELETE FROM $t WHERE user_id=?")->execute([$id]);
      } catch (Throwable $_) {
      }
    try {
      $pdo->prepare("DELETE FROM users WHERE id=?")->execute([$id]);
    } catch (Throwable $_) {
    }
  }
  header("Location: users.php");
  exit;
}

$editId = (int) ($_GET['edit'] ?? 0);
$editUser = null;
$editWallet = null;
$editTx = [];

if ($editId > 0) {
  try {
    $st = $pdo->prepare("SELECT * FROM users WHERE id=? LIMIT 1");
    $st->execute([$editId]);
    $editUser = $st->fetch() ?: null;
  } catch (Throwable $_) {
  }
  if ($editUser) {
    $editWallet = get_wallet_u($pdo, $editId);
    try {
      $st = $pdo->prepare("SELECT id,type,direction,coins,status,note,created_at FROM wallet_transactions WHERE user_id=? ORDER BY created_at DESC LIMIT 30");
      $st->execute([$editId]);
      $editTx = $st->fetchAll();
    } catch (Throwable $_) {
    }
  }
}

// Build dynamic select
$cols = [];
try {
  foreach ($pdo->query("SHOW COLUMNS FROM users")->fetchAll() as $r)
    $cols[] = $r['Field'];
} catch (Throwable $_) {
}
$pick = fn(array $c) => array_values(array_filter($c, fn($f) => in_array($f, $cols, true)))[0] ?? null;
$colId = $pick(['id', 'user_id', 'uid']);
$colName = $pick(['name', 'full_name']);
$colUsername = $pick(['username', 'user_name', 'handle']);
$colEmail = $pick(['email', 'mail']);
$colAvatar = $pick(['avatar', 'profile_pic', 'profile_image']);
$colCreated = $pick(['created_at', 'created', 'joined_at']);
$colBanned = $pick(['is_banned']);
$colReason = $pick(['ban_reason']);
$sel = implode(',', array_filter([
  $colId ? "$colId AS id" : 'NULL AS id',
  $colName ? "$colName AS name" : "'' AS name",
  $colUsername ? "$colUsername AS username" : "'' AS username",
  $colEmail ? "$colEmail AS email" : "'' AS email",
  $colAvatar ? "$colAvatar AS avatar" : "NULL AS avatar",
  $colCreated ? "$colCreated AS created_at" : "NULL AS created_at",
  $colBanned ? "$colBanned AS is_banned" : "0 AS is_banned",
  $colReason ? "$colReason AS ban_reason" : "'' AS ban_reason",
  "subscription_status",
]));

$users = [];
if ($colId) {
  try {
    $users = $pdo->query("SELECT $sel FROM users ORDER BY id DESC LIMIT 1000")->fetchAll();
  } catch (Throwable $_) {
  }
}

require __DIR__ . '/_layout_header.php';
?>

<?php if ($editUser): ?>
  <div class="section" style="border:1px solid #2a3f6e">
    <div class="head">
      <b>Edit User #<?= (int) $editUser['id'] ?></b>
      <div style="display:flex;gap:10px;align-items:center">
        <?php if ((int) ($editUser['is_banned'] ?? 0)): ?><span class="badge danger">BANNED</span><?php else: ?><span
            class="badge ok">ACTIVE</span><?php endif; ?>
        <a class="btn" href="users.php">Back</a>
      </div>
    </div>
    <div class="body" style="display:grid;grid-template-columns:1fr 1fr;gap:14px">
      <div style="background:rgba(15,27,51,.35);padding:14px;border:1px solid #223a66;border-radius:14px">
        <b style="display:block;margin-bottom:10px">Profile</b>
        <?php if (!empty($editUser['profile_pic'])): ?>
          <img src="<?= h($editUser['profile_pic']) ?>"
            style="width:54px;height:54px;border-radius:999px;object-fit:cover;border:1px solid #1b2a4a;margin-bottom:10px">
        <?php endif; ?>
        <form method="post">
          <input type="hidden" name="action" value="update_user">
          <input type="hidden" name="user_id" value="<?= (int) $editUser['id'] ?>">
          <?php foreach (['name' => 'Name', 'email' => 'Email', 'bio' => 'Bio', 'profile_pic' => 'Profile Pic URL', 'api_token' => 'API Token'] as $f => $lbl): ?>
            <label style="display:block;margin:8px 0 5px"><?= $lbl ?></label>
            <?php if ($f === 'bio'): ?>
              <textarea name="bio" rows="2"
                style="width:100%;padding:9px;border-radius:8px;border:1px solid #233a66;background:#0a0a14;color:#fff"><?= h($editUser['bio'] ?? '') ?></textarea>
            <?php else: ?>
              <input name="<?= $f ?>" value="<?= h($editUser[$f] ?? '') ?>"
                style="width:100%;padding:9px;border-radius:8px;border:1px solid #233a66;background:#0a0a14;color:#fff">
            <?php endif; ?>
          <?php endforeach; ?>
          <label style="display:block;margin:8px 0 5px">Subscription</label>
          <select name="subscription_status"
            style="width:100%;padding:9px;border-radius:8px;border:1px solid #233a66;background:#0a0a14;color:#fff">
            <?php foreach (['inactive', 'active', 'disabled'] as $s): ?>
              <option value="<?= $s ?>" <?= ($editUser['subscription_status'] ?? '') === $s ? 'selected' : '' ?>>
                <?= ucfirst($s) ?>
              </option>
            <?php endforeach; ?>
          </select>
          <button class="btn ok" type="submit" style="margin-top:12px">Save Profile</button>
        </form>
      </div>
      <div style="background:rgba(15,27,51,.35);padding:14px;border:1px solid #223a66;border-radius:14px">
        <b style="display:block;margin-bottom:10px">Wallet & Moderation</b>
        <div style="display:flex;gap:8px;flex-wrap:wrap;margin-bottom:12px">
          <span class="badge ok">Balance: <?= number_format((int) ($editWallet['balance_coins'] ?? 0)) ?> coins</span>
          <span class="badge">Locked: <?= number_format((int) ($editWallet['locked_coins'] ?? 0)) ?> coins</span>
        </div>
        <form method="post" style="margin-bottom:14px">
          <input type="hidden" name="action" value="wallet_adjust">
          <input type="hidden" name="user_id" value="<?= (int) $editUser['id'] ?>">
          <div style="display:flex;gap:8px;flex-wrap:wrap">
            <select name="mode"
              style="padding:9px;border-radius:8px;border:1px solid #233a66;background:#0a0a14;color:#fff">
              <option value="add">Add</option>
              <option value="subtract">Subtract</option>
            </select>
            <input name="coins" type="number" min="1" placeholder="Coins"
              style="flex:1;min-width:100px;padding:9px;border-radius:8px;border:1px solid #233a66;background:#0a0a14;color:#fff">
            <input name="note" placeholder="Note"
              style="flex:2;min-width:160px;padding:9px;border-radius:8px;border:1px solid #233a66;background:#0a0a14;color:#fff">
          </div>
          <button class="btn ok" type="submit" style="margin-top:10px" onclick="return confirm('Apply?')">Apply</button>
        </form>
        <div style="border-top:1px solid #223a66;padding-top:12px">
          <b style="display:block;margin-bottom:8px">Account Ban</b>
          <?php if ((int) ($editUser['is_banned'] ?? 0)): ?>
            <form method="post" style="display:flex;gap:8px;align-items:center;flex-wrap:wrap">
              <input type="hidden" name="action" value="unban">
              <input type="hidden" name="user_id" value="<?= (int) $editUser['id'] ?>">
              <button class="btn" type="submit">Unban Account</button>
              <small style="color:#f87171">Banned: <?= h($editUser['ban_reason'] ?? '') ?></small>
            </form>
          <?php else: ?>
            <form method="post" style="display:flex;gap:8px;align-items:center;flex-wrap:wrap">
              <input type="hidden" name="action" value="ban">
              <input type="hidden" name="user_id" value="<?= (int) $editUser['id'] ?>">
              <input name="ban_reason" placeholder="Ban reason..."
                style="flex:1;min-width:200px;padding:9px;border-radius:8px;border:1px solid #233a66;background:#0a0a14;color:#fff">
              <button class="btn danger" type="submit" onclick="return confirm('Ban this account?')">Ban Account</button>
            </form>
          <?php endif; ?>
        </div>
        <div style="border-top:1px solid #223a66;padding-top:12px;margin-top:12px">
          <b style="display:block;margin-bottom:8px">Device Ban</b>
          <?php
          $deviceBanned = (int) ($editUser['device_ban'] ?? 0);
          $deviceBanReason = $editUser['device_ban_reason'] ?? '';
          $deviceBannedAt = $editUser['device_banned_at'] ?? '';
          $deviceId = $editUser['device_id'] ?? '';
          ?>
          <?php if ($deviceId): ?>
            <small style="display:block;margin-bottom:8px;opacity:.6">Device ID:
              <?= h(substr($deviceId, 0, 32)) ?>...</small>
          <?php else: ?>
            <small style="display:block;margin-bottom:8px;opacity:.5">No device ID recorded yet.</small>
          <?php endif; ?>
          <?php if ($deviceBanned): ?>
            <form method="post" style="display:flex;gap:8px;align-items:center;flex-wrap:wrap">
              <input type="hidden" name="action" value="device_unban">
              <input type="hidden" name="user_id" value="<?= (int) $editUser['id'] ?>">
              <button class="btn" type="submit">Remove Device Ban</button>
              <small style="color:#f87171">Reason: <?= h($deviceBanReason) ?></small>
            </form>
          <?php else: ?>
            <form method="post" style="display:flex;gap:8px;align-items:center;flex-wrap:wrap">
              <input type="hidden" name="action" value="device_ban">
              <input type="hidden" name="user_id" value="<?= (int) $editUser['id'] ?>">
              <input name="device_ban_reason" placeholder="Device ban reason..."
                style="flex:1;min-width:200px;padding:9px;border-radius:8px;border:1px solid #233a66;background:#0a0a14;color:#fff">
              <button class="btn danger" type="submit"
                onclick="return confirm('Ban this device? User will be force-logged out.')">Ban Device</button>
            </form>
          <?php endif; ?>
        </div>
      </div>
      <div
        style="grid-column:1/-1;background:rgba(15,27,51,.35);padding:14px;border:1px solid #223a66;border-radius:14px">
        <b style="display:block;margin-bottom:10px">Wallet Transactions (Last 30)</b>
        <div class="table-wrap">
          <table>
            <thead>
              <tr>
                <th>ID</th>
                <th>Type</th>
                <th>Dir</th>
                <th>Coins</th>
                <th>Status</th>
                <th>Note</th>
                <th>Date</th>
              </tr>
            </thead>
            <tbody>
              <?php foreach ($editTx as $tx): ?>
                <tr>
                  <td><?= h($tx['id']) ?></td>
                  <td><?= h($tx['type']) ?></td>
                  <td><?= h($tx['direction']) ?></td>
                  <td><?= h($tx['coins']) ?></td>
                  <td><?= h($tx['status']) ?></td>
                  <td><?= h($tx['note']) ?></td>
                  <td><?= h($tx['created_at']) ?></td>
                </tr>
              <?php endforeach; ?>
              <?php if (empty($editTx)): ?>
                <tr>
                  <td colspan="7"><span class="badge">No transactions.</span></td>
                </tr><?php endif; ?>
            </tbody>
          </table>
        </div>
      </div>
    </div>
  </div>
<?php endif; ?>

<div class="section">
  <div class="head">
    <b>All Users</b>
    <div class="search">
      <input id="searchUsers" placeholder="Search name / email / ID...">
      <small><?= count($users) ?> users</small>
    </div>
  </div>
  <div class="body">
    <div class="table-wrap">
      <table id="tableUsers">
        <thead>
          <tr>
            <th>ID</th>
            <th>Avatar</th>
            <th>Name</th>
            <th>Username</th>
            <th>Email</th>
            <th>Sub</th>
            <th>Status</th>
            <th>Created</th>
            <th>Actions</th>
          </tr>
        </thead>
        <tbody>
          <?php foreach ($users as $u):
            $banned = (int) ($u['is_banned'] ?? 0); ?>
            <tr>
              <td><?= h($u['id'] ?? '') ?></td>
              <td><?php if (!empty($u['avatar'])): ?><img src="<?= h($u['avatar']) ?>"
                    style="width:34px;height:34px;border-radius:999px;object-fit:cover"><?php else: ?><span
                    class="badge">—</span><?php endif; ?></td>
              <td><?= h($u['name'] ?? '') ?></td>
              <td><?= h($u['username'] ?? '') ?></td>
              <td><?= h($u['email'] ?? '') ?></td>
              <td><span
                  class="badge <?= ($u['subscription_status'] ?? '') === 'active' ? 'ok' : '' ?>"><?= h($u['subscription_status'] ?? 'inactive') ?></span>
              </td>
              <td><?= $banned ? '<span class="badge danger">BANNED</span>' : '<span class="badge ok">ACTIVE</span>' ?>
              </td>
              <td><small><?= h(substr($u['created_at'] ?? '', 0, 10)) ?></small></td>
              <td style="display:flex;gap:6px;flex-wrap:wrap">
                <a class="btn ok" href="?edit=<?= (int) $u['id'] ?>">Edit</a>
                <?php if ($banned): ?>
                  <form method="post" style="display:inline"><input type="hidden" name="action" value="unban"><input
                      type="hidden" name="user_id" value="<?= (int) $u['id'] ?>"><button class="btn"
                      type="submit">Unban</button></form>
                <?php else: ?>
                  <form method="post" style="display:inline"><input type="hidden" name="action" value="ban"><input
                      type="hidden" name="user_id" value="<?= (int) $u['id'] ?>"><input name="ban_reason"
                      placeholder="Reason"
                      style="padding:4px 8px;border-radius:4px;border:1px solid #334;background:#111;color:#fff;font-size:12px"><button
                      class="btn danger" type="submit" onclick="return confirm('Ban?')">Ban</button></form>
                <?php endif; ?>
                <a class="btn danger" href="?delete=<?= (int) $u['id'] ?>"
                  onclick="return confirm('Delete user and all their data?')">Delete</a>
              </td>
            </tr>
          <?php endforeach; ?>
          <?php if (empty($users)): ?>
            <tr>
              <td colspan="9">
                <div style="padding:20px;text-align:center;opacity:.5">No users found.</div>
              </td>
            </tr><?php endif; ?>
        </tbody>
      </table>
    </div>
  </div>
</div>

<script>
  document.addEventListener('DOMContentLoaded', () => { if (typeof bindTableSearch === 'function') bindTableSearch('searchUsers', 'tableUsers'); });
</script>
<?php require __DIR__ . '/_layout_footer.php'; ?>