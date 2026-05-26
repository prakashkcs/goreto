<?php
require_once __DIR__ . '/_core.php';
admin_require_login();

$pageTitle = 'Users';
$activeNav = 'users';

/**
 * Helpers
 */
function h($s)
{
  return htmlspecialchars((string)$s, ENT_QUOTES, 'UTF-8');
}
function out_redirect($to = 'users.php')
{
  header("Location: " . $to);
  exit;
}

function ensure_wallet(PDO $pdo, int $userId): void
{
  // Your table user_wallets is MyISAM (no PK), but user_id exists.
  $stmt = $pdo->prepare("SELECT user_id FROM user_wallets WHERE user_id=? LIMIT 1");
  $stmt->execute([$userId]);
  $row = $stmt->fetch();
  if (!$row) {
    try {
      $pdo->prepare("INSERT INTO user_wallets (user_id, balance_coins, locked_coins) VALUES (?,0,0)")
        ->execute([$userId]);
    }
    catch (Throwable $e) {
    // ignore
    }
  }
}

function get_last_login(PDO $pdo, int $userId): ?string
{
  try {
    $stmt = $pdo->prepare("SELECT MAX(started_at) AS last_login FROM user_sessions WHERE user_id=?");
    $stmt->execute([$userId]);
    $v = $stmt->fetchColumn();
    return $v ? (string)$v : null;
  }
  catch (Throwable $e) {
    return null;
  }
}

function get_wallet(PDO $pdo, int $userId): array
{
  ensure_wallet($pdo, $userId);
  try {
    $stmt = $pdo->prepare("SELECT balance_coins, locked_coins, updated_at FROM user_wallets WHERE user_id=? LIMIT 1");
    $stmt->execute([$userId]);
    $w = $stmt->fetch(PDO::FETCH_ASSOC);
    return [
      'balance_coins' => (int)($w['balance_coins'] ?? 0),
      'locked_coins' => (int)($w['locked_coins'] ?? 0),
      'updated_at' => $w['updated_at'] ?? null,
    ];
  }
  catch (Throwable $e) {
    return ['balance_coins' => 0, 'locked_coins' => 0, 'updated_at' => null];
  }
}

function log_wallet_tx(PDO $pdo, int $userId, string $type, string $direction, int $coins, string $note = ''): void
{
  // wallet_transactions columns in your SQL:
  // id (no auto in dump, but likely has AUTO_INCREMENT in live). We'll insert without id.
  // user_id, type, direction ('credit'/'debit'), coins, status default completed, created_at default current_timestamp
  try {
    $ref = 'admin_' . $type . '_' . time();
    $stmt = $pdo->prepare("INSERT INTO wallet_transactions (user_id, type, direction, coins, status, reference, note) VALUES (?,?,?,?, 'completed', ?, ?)");
    $stmt->execute([$userId, $type, $direction, $coins, $ref, $note]);
  }
  catch (Throwable $e) {
  // ignore logging failures
  }
}

/**
 * POST Actions
 */
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
  $action = $_POST['action'] ?? '';
  $id = intval($_POST['user_id'] ?? 0);

  // ---- Ban / Unban ----
  if ($id > 0 && ($action === 'ban' || $action === 'unban')) {
    if ($action === 'ban') {
      $reason = trim((string)($_POST['ban_reason'] ?? ''));
      if ($reason === '')
        $reason = 'Violation of app rules';
      $stmt = $pdo->prepare("UPDATE users SET is_banned=1, ban_reason=?, banned_at=NOW() WHERE id=?");
      $stmt->execute([$reason, $id]);
    }
    else {
      $stmt = $pdo->prepare("UPDATE users SET is_banned=0, ban_reason=NULL, banned_at=NULL WHERE id=?");
      $stmt->execute([$id]);
    }
    out_redirect('users.php?edit=' . $id);
  }

  // ---- Update User Profile ----
  if ($id > 0 && $action === 'update_user') {
    $name = trim((string)($_POST['name'] ?? ''));
    $email = trim((string)($_POST['email'] ?? ''));
    $bio = trim((string)($_POST['bio'] ?? ''));
    $pic = trim((string)($_POST['profile_pic'] ?? ''));
    $token = trim((string)($_POST['api_token'] ?? ''));

    // Allow empty optional fields, but name/email usually required in your schema.
    if ($name === '')
      $name = 'User ' . $id;
    if ($email === '')
      $email = 'user' . $id . '@example.com';

    $subStatus = trim((string)($_POST['subscription_status'] ?? 'inactive'));
    if (!in_array($subStatus, ['active', 'inactive', 'disabled']))
      $subStatus = 'inactive';

    $stmt = $pdo->prepare("UPDATE users SET name=?, email=?, bio=?, profile_pic=?, api_token=?, subscription_status=? WHERE id=?");
    $stmt->execute([$name, $email, ($bio === '' ? null : $bio), ($pic === '' ? null : $pic), ($token === '' ? null : $token), $subStatus, $id]);

    out_redirect('users.php?edit=' . $id);
  }

  // ---- Wallet Adjust (Add / Decrease coins) ----
  if ($id > 0 && $action === 'wallet_adjust') {
    $mode = $_POST['mode'] ?? 'add'; // add | subtract
    $coins = (int)($_POST['coins'] ?? 0);
    $note = trim((string)($_POST['note'] ?? ''));

    if ($coins <= 0)
      out_redirect('users.php?edit=' . $id);

    ensure_wallet($pdo, $id);
    $w = get_wallet($pdo, $id);
    $bal = (int)$w['balance_coins'];

    if ($mode === 'subtract') {
      $newBal = $bal - $coins;
      if ($newBal < 0)
        $newBal = 0;

      $stmt = $pdo->prepare("UPDATE user_wallets SET balance_coins=?, updated_at=NOW() WHERE user_id=?");
      $stmt->execute([$newBal, $id]);

      log_wallet_tx($pdo, $id, 'admin_adjust', 'debit', $coins, $note ?: 'Admin decreased coins');
    }
    else {
      $newBal = $bal + $coins;

      $stmt = $pdo->prepare("UPDATE user_wallets SET balance_coins=?, updated_at=NOW() WHERE user_id=?");
      $stmt->execute([$newBal, $id]);

      log_wallet_tx($pdo, $id, 'admin_adjust', 'credit', $coins, $note ?: 'Admin added coins');
    }

    out_redirect('users.php?edit=' . $id);
  }

  out_redirect('users.php');
}

/**
 * Delete user (keep your existing behavior)
 */
if (isset($_GET['delete'])) {
  $id = intval($_GET['delete']);
  if ($id > 0) {
    try {
      $pdo->prepare("DELETE FROM post_likes WHERE user_id=?")->execute([$id]);
    }
    catch (Throwable $e) {
    }
    try {
      $pdo->prepare("DELETE FROM post_comments WHERE user_id=?")->execute([$id]);
    }
    catch (Throwable $e) {
    }
    try {
      $pdo->prepare("DELETE FROM posts WHERE user_id=?")->execute([$id]);
    }
    catch (Throwable $e) {
    }
    try {
      $pdo->prepare("DELETE FROM stories WHERE user_id=?")->execute([$id]);
    }
    catch (Throwable $e) {
    }
    try {
      $pdo->prepare("DELETE FROM collections WHERE user_id=?")->execute([$id]);
    }
    catch (Throwable $e) {
    }
    try {
      $pdo->prepare("DELETE FROM user_sessions WHERE user_id=?")->execute([$id]);
    }
    catch (Throwable $e) {
    }
    try {
      $pdo->prepare("DELETE FROM wallet_transactions WHERE user_id=?")->execute([$id]);
    }
    catch (Throwable $e) {
    }
    try {
      $pdo->prepare("DELETE FROM user_wallets WHERE user_id=?")->execute([$id]);
    }
    catch (Throwable $e) {
    }
    try {
      $pdo->prepare("DELETE FROM users WHERE id=?")->execute([$id]);
    }
    catch (Throwable $e) {
    }
  }
  out_redirect("users.php");
}

/**
 * Load edit user if requested
 */
$editId = intval($_GET['edit'] ?? 0);
$editUser = null;
$editWallet = null;
$editLastLogin = null;
$editTx = [];

if ($editId > 0) {
  try {
    $stmt = $pdo->prepare("SELECT * FROM users WHERE id=? LIMIT 1");
    $stmt->execute([$editId]);
    $editUser = $stmt->fetch(PDO::FETCH_ASSOC) ?: null;
  }
  catch (Throwable $e) {
    $editUser = null;
  }

  if ($editUser) {
    $editWallet = get_wallet($pdo, $editId);
    $editLastLogin = get_last_login($pdo, $editId);

    try {
      $stmt = $pdo->prepare("SELECT id, type, direction, coins, status, note, created_at
                             FROM wallet_transactions
                             WHERE user_id=?
                             ORDER BY created_at DESC
                             LIMIT 30");
      $stmt->execute([$editId]);
      $editTx = $stmt->fetchAll(PDO::FETCH_ASSOC);
    }
    catch (Throwable $e) {
      $editTx = [];
    }
  }
}

/**
 * Detect columns for list (keep your dynamic detection)
 */
$cols = [];
try {
  $stmt = $pdo->query("SHOW COLUMNS FROM users");
  while ($r = $stmt->fetch())
    $cols[] = $r['Field'];
}
catch (Throwable $e) {
}

$pick = function (array $cands) use ($cols) {
  foreach ($cands as $c)
    if (in_array($c, $cols, true))
      return $c;
  return null;
};

$colId = $pick(['id', 'user_id', 'uid']);
$colName = $pick(['name', 'full_name', 'fullname']);
$colUsername = $pick(['username', 'user_name', 'uname', 'handle', 'user_handle']);
$colEmail = $pick(['email', 'mail']);
$colAvatar = $pick(['avatar', 'profile_pic', 'profile_image', 'photo']);
$colCreated = $pick(['created_at', 'created', 'date_created', 'joined_at']);
$colBanned = $pick(['is_banned']);
$colReason = $pick(['ban_reason']);

$select = [];
$select[] = ($colId ? "$colId AS id" : "NULL AS id");
$select[] = ($colName ? "$colName AS name" : "NULL AS name");
$select[] = ($colUsername ? "$colUsername AS username" : "NULL AS username");
$select[] = ($colEmail ? "$colEmail AS email" : "NULL AS email");
$select[] = ($colAvatar ? "$colAvatar AS avatar" : "NULL AS avatar");
$select[] = ($colCreated ? "$colCreated AS created_at" : "NULL AS created_at");
$select[] = ($colBanned ? "$colBanned AS is_banned" : "0 AS is_banned");
$select[] = ($colReason ? "$colReason AS ban_reason" : "'' AS ban_reason");
$select[] = "subscription_status";

$users = [];
if ($colId) {
  $sql = "SELECT " . implode(", ", $select) . " FROM users ORDER BY $colId DESC LIMIT 1000";
  $users = $pdo->query($sql)->fetchAll();
}

require __DIR__ . '/_layout_header.php';
?>

<?php if ($editUser): ?>
  <div class="section" style="border:1px solid #2a3f6e;">
    <div class="head">
      <b>Edit User #<?php echo (int)$editUser['id']; ?></b>
      <div style="display:flex;gap:10px;align-items:center;flex-wrap:wrap;">
        <?php if ((int)($editUser['is_banned'] ?? 0) === 1): ?>
          <span class="badge danger">BANNED</span>
        <?php
  else: ?>
          <span class="badge ok">ACTIVE</span>
        <?php
  endif; ?>
        <a class="btn" href="users.php">Back to list</a>
      </div>
    </div>

    <div class="body" style="display:grid;grid-template-columns:1fr 1fr;gap:14px;">
      <!-- Profile edit -->
      <div class="card" style="padding:14px;border:1px solid #223a66;border-radius:14px;">
        <b style="display:block;margin-bottom:10px;">Profile</b>

        <div style="display:flex;gap:12px;align-items:center;margin-bottom:12px;">
          <?php if (!empty($editUser['profile_pic'])): ?>
            <img src="<?php echo h($editUser['profile_pic']); ?>" style="width:54px;height:54px;border-radius:999px;object-fit:cover;border:1px solid #1b2a4a;">
          <?php
  else: ?>
            <div class="badge">No Avatar</div>
          <?php
  endif; ?>
          <div style="font-size:13px;opacity:.9;">
            <div><b>Created:</b> <?php echo h($editUser['created_at'] ?? ''); ?></div>
            <div><b>Last login:</b> <?php echo h($editLastLogin ?: 'N/A'); ?></div>
          </div>
        </div>

        <form method="post">
          <input type="hidden" name="action" value="update_user">
          <input type="hidden" name="user_id" value="<?php echo (int)$editUser['id']; ?>">

          <label style="display:block;margin:8px 0 6px;">Name</label>
          <input name="name" value="<?php echo h($editUser['name'] ?? ''); ?>" style="width:100%;padding:10px;border-radius:10px;border:1px solid #233a66;">

          <label style="display:block;margin:8px 0 6px;">Email</label>
          <input name="email" value="<?php echo h($editUser['email'] ?? ''); ?>" style="width:100%;padding:10px;border-radius:10px;border:1px solid #233a66;">

          <label style="display:block;margin:8px 0 6px;">Bio</label>
          <textarea name="bio" rows="3" style="width:100%;padding:10px;border-radius:10px;border:1px solid #233a66;"><?php echo h($editUser['bio'] ?? ''); ?></textarea>

          <label style="display:block;margin:8px 0 6px;">Profile Pic (URL)</label>
          <input name="profile_pic" value="<?php echo h($editUser['profile_pic'] ?? ''); ?>" style="width:100%;padding:10px;border-radius:10px;border:1px solid #233a66;">

          <label style="display:block;margin:8px 0 6px;">API Token</label>
          <input name="api_token" value="<?php echo h($editUser['api_token'] ?? ''); ?>" style="width:100%;padding:10px;border-radius:10px;border:1px solid #233a66;">

          <label style="display:block;margin:8px 0 6px;">Subscription Status</label>
          <select name="subscription_status" style="width:100%;padding:10px;border-radius:10px;border:1px solid #233a66;background:#0f1b33;color:#fff;">
            <option value="inactive" <?php echo($editUser['subscription_status'] ?? '') === 'inactive' ? 'selected' : ''; ?>>Inactive (Locked)</option>
            <option value="active" <?php echo($editUser['subscription_status'] ?? '') === 'active' ? 'selected' : ''; ?>>Active (Monetized)</option>
            <option value="disabled" <?php echo($editUser['subscription_status'] ?? '') === 'disabled' ? 'selected' : ''; ?>>Disabled (Forbidden)</option>
          </select>

          <div style="display:flex;gap:10px;align-items:center;margin-top:12px;flex-wrap:wrap;">
            <button class="btn ok" type="submit">Save Profile</button>
            <button class="btn warn" type="submit" name="reset_token" value="1" onclick="return confirm('Reset API token for this user?')">Reset Token</button>
          </div>
        </form>
      </div>

      <!-- Wallet + status -->
      <div class="card" style="padding:14px;border:1px solid #223a66;border-radius:14px;">
        <b style="display:block;margin-bottom:10px;">Wallet & Moderation</b>

        <div style="display:flex;gap:10px;flex-wrap:wrap;margin-bottom:12px;">
          <div class="badge ok">Balance: <?php echo (int)($editWallet['balance_coins'] ?? 0); ?> coins</div>
          <div class="badge">Locked: <?php echo (int)($editWallet['locked_coins'] ?? 0); ?> coins</div>
          <div class="badge">Updated: <?php echo h($editWallet['updated_at'] ?? ''); ?></div>
        </div>

        <form method="post" style="margin-bottom:14px;">
          <input type="hidden" name="action" value="wallet_adjust">
          <input type="hidden" name="user_id" value="<?php echo (int)$editUser['id']; ?>">

          <label style="display:block;margin:8px 0 6px;">Adjust coins</label>

          <div style="display:flex;gap:10px;flex-wrap:wrap;">
            <select name="mode" style="padding:10px;border-radius:10px;border:1px solid #233a66;">
              <option value="add">Add</option>
              <option value="subtract">Decrease</option>
            </select>

            <input name="coins" type="number" min="1" placeholder="Coins" style="flex:1;min-width:160px;padding:10px;border-radius:10px;border:1px solid #233a66;">

            <input name="note" placeholder="Note (optional)" style="flex:2;min-width:220px;padding:10px;border-radius:10px;border:1px solid #233a66;">
          </div>

          <div style="display:flex;gap:10px;margin-top:12px;flex-wrap:wrap;">
            <button class="btn ok" type="submit" onclick="return confirm('Apply wallet adjustment?')">Apply</button>
          </div>
        </form>

        <div style="border-top:1px solid #223a66;padding-top:12px;">
          <b style="display:block;margin-bottom:8px;">Moderation</b>

          <?php if ((int)($editUser['is_banned'] ?? 0) === 1): ?>
            <form method="post" style="display:flex;gap:10px;flex-wrap:wrap;align-items:center;">
              <input type="hidden" name="action" value="unban">
              <input type="hidden" name="user_id" value="<?php echo (int)$editUser['id']; ?>">
              <button class="btn" type="submit" onclick="return confirm('Unban this user?')">Unban</button>
              <div style="font-size:12px;opacity:.85;">Reason: <?php echo h($editUser['ban_reason'] ?? ''); ?></div>
            </form>
          <?php
  else: ?>
            <form method="post" style="display:flex;gap:10px;flex-wrap:wrap;align-items:center;">
              <input type="hidden" name="action" value="ban">
              <input type="hidden" name="user_id" value="<?php echo (int)$editUser['id']; ?>">
              <input name="ban_reason" placeholder="Ban reason..." style="flex:1;min-width:220px;padding:10px;border-radius:10px;border:1px solid #233a66;">
              <button class="btn warn" type="submit" onclick="return confirm('Ban this user?')">Ban</button>
            </form>
          <?php
  endif; ?>
        </div>
      </div>

      <!-- Coin activity -->
      <div class="card" style="grid-column:1 / -1;padding:14px;border:1px solid #223a66;border-radius:14px;">
        <b style="display:block;margin-bottom:10px;">Coin Activities (Last 30)</b>

        <div class="table-wrap">
          <table>
            <thead>
              <tr>
                <th style="width:90px;">ID</th>
                <th>Type</th>
                <th>Direction</th>
                <th>Coins</th>
                <th>Status</th>
                <th>Note</th>
                <th style="width:180px;">Date</th>
              </tr>
            </thead>
            <tbody>
              <?php foreach ($editTx as $tx): ?>
                <tr>
                  <td><?php echo h($tx['id'] ?? ''); ?></td>
                  <td><?php echo h($tx['type'] ?? ''); ?></td>
                  <td><?php echo h($tx['direction'] ?? ''); ?></td>
                  <td><?php echo h($tx['coins'] ?? ''); ?></td>
                  <td><?php echo h($tx['status'] ?? ''); ?></td>
                  <td><?php echo h($tx['note'] ?? ''); ?></td>
                  <td><?php echo h($tx['created_at'] ?? ''); ?></td>
                </tr>
              <?php
  endforeach; ?>
              <?php if (empty($editTx)): ?>
                <tr><td colspan="7"><span class="badge warn">No wallet transactions found for this user.</span></td></tr>
              <?php
  endif; ?>
            </tbody>
          </table>
        </div>
      </div>

    </div>
  </div>
<?php
endif; ?>


<div class="section">
  <div class="head">
    <b>All Users</b>
    <div class="search">
      <input id="searchUsers" placeholder="Search users... (name, email, id)">
      <small><?php echo count($users); ?> rows</small>
    </div>
  </div>

  <div class="body">
    <div class="table-wrap">
      <table id="tableUsers">
        <thead>
          <tr>
            <th style="width:80px;">ID</th>
            <th>Avatar</th>
            <th>Name</th>
            <th>Username</th>
            <th>Email</th>
            <th>Status</th>
            <th>Created</th>
            <th style="width:320px;">Actions</th>
          </tr>
        </thead>
        <tbody>
          <?php foreach ($users as $u): ?>
            <?php $b = intval($u['is_banned'] ?? 0); ?>
            <tr>
              <td><?php echo h($u['id'] ?? ''); ?></td>
              <td>
                <?php if (!empty($u['avatar'])): ?>
                  <img src="<?php echo h($u['avatar']); ?>" style="width:34px;height:34px;border-radius:999px;object-fit:cover;border:1px solid #1b2a4a;">
                <?php
  else: ?>
                  <span class="badge">None</span>
                <?php
  endif; ?>
              </td>
              <td><?php echo h($u['name'] ?? ''); ?></td>
              <td><?php echo h($u['username'] ?? ''); ?></td>
              <td><?php echo h($u['email'] ?? ''); ?></td>
              <td>
                <?php if ($b === 1): ?>
                  <span class="badge danger">BANNED</span>
                  <div style="font-size:12px;opacity:.8;margin-top:4px;">
                    <?php echo h($u['ban_reason'] ?? ''); ?>
                  </div>
                <?php
  else: ?>
                  <span class="badge ok">ACTIVE</span>
                <?php
  endif; ?>
              </td>
              <td><?php echo h($u['created_at'] ?? ''); ?></td>
              <td style="display:flex;gap:8px;flex-wrap:wrap;">
                <a class="btn ok" href="?edit=<?php echo (int)$u['id']; ?>">Edit</a>

                <?php if ($b === 1): ?>
                  <form method="post" style="display:inline;">
                    <input type="hidden" name="action" value="unban">
                    <input type="hidden" name="user_id" value="<?php echo (int)$u['id']; ?>">
                    <button class="btn" type="submit" onclick="return confirm('Unban this user?')">Unban</button>
                  </form>
                <?php
  else: ?>
                  <button class="btn warn" onclick="openBanModal(<?php echo (int)$u['id']; ?>,'<?php echo h(addslashes($u['name'] ?? '')); ?>')">Ban</button>
                <?php
  endif; ?>

                <a class="btn danger" href="?delete=<?php echo (int)$u['id']; ?>" onclick="return confirmDelete('Delete this user and related content?');">Delete</a>
              </td>
            </tr>
          <?php
endforeach; ?>
          <?php if (empty($users)): ?>
            <tr><td colspan="8"><span class="badge warn">No users found or table columns missing.</span></td></tr>
          <?php
endif; ?>
        </tbody>
      </table>
    </div>
  </div>
</div>

<!-- Ban Modal (kept) -->
<div id="banModal" class="modal" style="display:none;">
  <div class="modal-card">
    <div class="modal-head">
      <b>Ban User</b>
      <button class="btn" onclick="closeBanModal()">X</button>
    </div>
    <div class="modal-body">
      <div style="margin-bottom:10px;">User ID: <b id="banUserIdText"></b> <span id="banUserNameText" style="opacity:.8;"></span></div>
      <form method="post">
        <input type="hidden" name="action" value="ban">
        <input type="hidden" name="user_id" id="banUserIdInput" value="">
        <label style="display:block;margin-bottom:6px;">Reason</label>
        <input name="ban_reason" id="banReasonInput" placeholder="Enter ban reason..." style="width:100%;padding:10px;border-radius:10px;border:1px solid #233a66;">
        <div style="display:flex;gap:10px;margin-top:12px;">
          <button class="btn warn" type="submit">Ban</button>
          <button class="btn" type="button" onclick="closeBanModal()">Cancel</button>
        </div>
      </form>
    </div>
  </div>
</div>

<style>
.modal{position:fixed;inset:0;background:rgba(0,0,0,.5);display:flex;align-items:center;justify-content:center;padding:16px;z-index:9999;}
.modal-card{background:#0f1b33;color:#dce6ff;width:520px;max-width:100%;border-radius:16px;border:1px solid #223a66;box-shadow:0 20px 60px rgba(0,0,0,.5);}
.modal-head{display:flex;justify-content:space-between;align-items:center;padding:14px 14px;border-bottom:1px solid #223a66;}
.modal-body{padding:14px;}
.card{background:rgba(15,27,51,.35);}
</style>

<script>
document.addEventListener("DOMContentLoaded", () => {
  bindTableSearch("searchUsers","tableUsers");
});
function openBanModal(id,name){
  document.getElementById('banUserIdText').innerText = id;
  document.getElementById('banUserNameText').innerText = name ? (' - '+name) : '';
  document.getElementById('banUserIdInput').value = id;
  document.getElementById('banReasonInput').value = '';
  document.getElementById('banModal').style.display = 'flex';
}
function closeBanModal(){
  document.getElementById('banModal').style.display = 'none';
}
</script>

<?php require __DIR__ . '/_layout_footer.php'; ?>