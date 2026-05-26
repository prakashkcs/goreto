<?php
require_once __DIR__ . '/_core.php';
admin_require_login();

$pageTitle = 'Group Chats';
$activeNav = 'groups';

function h($s) {
  return htmlspecialchars((string)$s, ENT_QUOTES, 'UTF-8');
}

function get_avatar_url($avatar) {
  if (empty($avatar)) return null;
  if (strpos($avatar, 'http') === 0) return $avatar;
  return 'https://goreto.org/ekloadmin' . $avatar;
}

function out_redirect($to = 'groups.php') {
  header("Location: " . $to);
  exit;
}

$action = $_GET['action'] ?? 'list';
$groupId = intval($_GET['group_id'] ?? 0);
$msg = '';

// POST Actions
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
  $postAction = $_POST['action'] ?? '';
  $groupId = intval($_POST['group_id'] ?? 0);
  
  // Bulk delete
  if ($postAction === 'bulk_delete' && !empty($_POST['group_ids'])) {
    $groupIds = array_map('intval', $_POST['group_ids']);
    foreach ($groupIds as $gid) {
      if ($gid > 0) {
        try { $pdo->prepare("DELETE FROM chat_group_messages WHERE group_id = ?")->execute([$gid]); } catch (Throwable $e) {}
        try { $pdo->prepare("DELETE FROM chat_group_members WHERE group_id = ?")->execute([$gid]); } catch (Throwable $e) {}
        try { $pdo->prepare("DELETE FROM chat_group_views WHERE group_id = ?")->execute([$gid]); } catch (Throwable $e) {}
        try { $pdo->prepare("DELETE FROM chat_group_bans WHERE group_id = ?")->execute([$gid]); } catch (Throwable $e) {}
        try { $pdo->prepare("DELETE FROM chat_groups WHERE id = ?")->execute([$gid]); } catch (Throwable $e) {}
      }
    }
    $msg = count($groupIds) . ' group(s) deleted';
  }

  if ($groupId > 0) {
    if ($postAction === 'delete_group') {
      try {
        $pdo->prepare("DELETE FROM chat_group_messages WHERE group_id = ?")->execute([$groupId]);
      } catch (Throwable $e) {}
      try {
        $pdo->prepare("DELETE FROM chat_group_members WHERE group_id = ?")->execute([$groupId]);
      } catch (Throwable $e) {}
      try {
        $pdo->prepare("DELETE FROM chat_group_views WHERE group_id = ?")->execute([$groupId]);
      } catch (Throwable $e) {}
      try {
        $pdo->prepare("DELETE FROM chat_group_bans WHERE group_id = ?")->execute([$groupId]);
      } catch (Throwable $e) {}
      try {
        $pdo->prepare("DELETE FROM chat_groups WHERE id = ?")->execute([$groupId]);
      } catch (Throwable $e) {}
      $msg = 'Group deleted successfully';
      $action = 'list';
      $groupId = 0;
    }
    elseif ($postAction === 'ban_user') {
      $userId = intval($_POST['user_id'] ?? 0);
      if ($userId > 0) {
        try {
          $pdo->prepare("INSERT IGNORE INTO chat_group_bans (group_id, user_id, banned_by, created_at) VALUES (?, ?, ?, NOW())")
              ->execute([$groupId, $userId, $_SESSION['admin_id'] ?? 0]);
        } catch (Throwable $e) {}
        try {
          $pdo->prepare("DELETE FROM chat_group_members WHERE group_id = ? AND user_id = ?")
              ->execute([$groupId, $userId]);
        } catch (Throwable $e) {}
        $msg = 'User banned from group';
      }
    }
    elseif ($postAction === 'unban_user') {
      $userId = intval($_POST['user_id'] ?? 0);
      if ($userId > 0) {
        $pdo->prepare("DELETE FROM chat_group_bans WHERE group_id = ? AND user_id = ?")->execute([$groupId, $userId]);
        $msg = 'User unbanned';
      }
    }
    elseif ($postAction === 'remove_member') {
      $userId = intval($_POST['user_id'] ?? 0);
      if ($userId > 0) {
        $pdo->prepare("DELETE FROM chat_group_members WHERE group_id = ? AND user_id = ?")->execute([$groupId, $userId]);
        $msg = 'Member removed';
      }
    }
    elseif ($postAction === 'set_admin') {
      $userId = intval($_POST['user_id'] ?? 0);
      if ($userId > 0) {
        $pdo->prepare("UPDATE chat_group_members SET role = 'admin' WHERE group_id = ? AND user_id = ?")->execute([$groupId, $userId]);
        $msg = 'User promoted to admin';
      }
    }
    elseif ($postAction === 'remove_admin') {
      $userId = intval($_POST['user_id'] ?? 0);
      if ($userId > 0) {
        $pdo->prepare("UPDATE chat_group_members SET role = 'member' WHERE group_id = ? AND user_id = ?")->execute([$groupId, $userId]);
        $msg = 'Admin demoted to member';
      }
    }
    elseif ($postAction === 'update_settings') {
      $name = trim($_POST['name'] ?? '');
      $username = trim($_POST['username'] ?? '');
      $bio = trim($_POST['bio'] ?? '');
      $joinFee = intval($_POST['join_fee'] ?? 0);
      $messageDelay = intval($_POST['message_delay'] ?? 0);
      $isPrivate = isset($_POST['is_private']) ? 1 : 0;
      
      $pdo->prepare("UPDATE chat_groups SET name = ?, username = ?, bio = ?, join_fee = ?, message_delay = ?, is_private = ? WHERE id = ?")
          ->execute([$name, $username ?: null, $bio ?: null, $joinFee, $messageDelay, $isPrivate, $groupId]);
      $msg = 'Group settings updated';
    }
  }
  
  if ($msg) {
    header("Location: ?action=view&group_id=$groupId&msg=" . urlencode($msg));
    exit;
  }
}

// Load group data for view
$group = null;
$members = [];
$bannedUsers = [];
$messageCount = 0;

if ($action === 'view' && $groupId > 0) {
  $stmt = $pdo->prepare("SELECT g.*, 
    (SELECT COUNT(*) FROM chat_group_members WHERE group_id = g.id) as member_count
    FROM chat_groups g WHERE g.id = ?");
  $stmt->execute([$groupId]);
  $group = $stmt->fetch(PDO::FETCH_ASSOC);
  
  if ($group) {
    $stmt = $pdo->prepare("SELECT u.id, u.name, u.username, u.profile_pic, u.email, m.role, m.joined_at
      FROM chat_group_members m 
      JOIN users u ON m.user_id = u.id 
      WHERE m.group_id = ?");
    $stmt->execute([$groupId]);
    $members = $stmt->fetchAll(PDO::FETCH_ASSOC);
    
    $stmt = $pdo->prepare("SELECT u.id, u.name, u.username, b.banned_by, b.created_at
      FROM chat_group_bans b 
      JOIN users u ON b.user_id = u.id 
      WHERE b.group_id = ?");
    $stmt->execute([$groupId]);
    $bannedUsers = $stmt->fetchAll(PDO::FETCH_ASSOC);
    
    $stmt = $pdo->prepare("SELECT COUNT(*) FROM chat_group_messages WHERE group_id = ?");
    $stmt->execute([$groupId]);
    $messageCount = $stmt->fetchColumn();
  }
}

// Get groups list
$search = trim($_GET['search'] ?? '');
$groups = [];
try {
  $where = '';
  $params = [];
  if ($search) {
    $where = "WHERE g.name LIKE ? OR g.username LIKE ? OR g.bio LIKE ?";
    $searchEsc = "%$search%";
    $params = [$searchEsc, $searchEsc, $searchEsc];
  }
  
  $query = "SELECT g.*, 
    (SELECT COUNT(*) FROM chat_group_members WHERE group_id = g.id) as member_count,
    (SELECT name FROM users WHERE id = g.created_by) as creator_name
    FROM chat_groups g $where ORDER BY g.id DESC LIMIT 100";
  
  if ($params) {
    $stmt = $pdo->prepare($query);
    $stmt->execute($params);
  } else {
    $stmt = $pdo->query($query);
  }
  $groups = $stmt->fetchAll();
} catch (Throwable $e) {
  $groups = [];
}

require __DIR__ . '/_layout_header.php';
?>

<?php if ($msg): ?>
  <div class="alert" style="background:#1e3a5f;color:#4fc3f7;padding:12px 16px;border-radius:8px;margin-bottom:16px;border:1px solid #1565c0;">
    <?php echo h($msg); ?>
  </div>
<?php endif; ?>

<?php if ($action === 'list'): ?>
  <div class="section">
    <div class="head">
      <b>All Group Chats</b>
      <form method="get" style="display:flex;gap:8px;align-items:center;">
        <input type="text" name="search" placeholder="Search groups..." value="<?php echo h($search); ?>" 
               style="background:#0d1b2a;border:1px solid #1e3a5f;color:#eee;padding:6px 12px;border-radius:6px;">
        <button type="submit" class="btn">Search</button>
        <?php if ($search): ?>
          <a href="groups.php" class="btn" style="opacity:0.7;">Clear</a>
        <?php endif; ?>
      </form>
    </div>
    
    <form method="post" id="bulkForm">
    <div style="margin-bottom:10px;display:flex;gap:10px;align-items:center;">
      <input type="checkbox" id="selectAll" onchange="document.querySelectorAll('.group-check').forEach(c => c.checked = this.checked)">
      <label for="selectAll">Select All</label>
      <button type="submit" name="action" value="bulk_delete" class="btn danger" style="background:#c62828;margin-left:auto;" onclick="return confirm('Delete selected groups?')">Delete Selected</button>
    </div>
    
    <table>
      <thead>
        <tr>
          <th style="width:40px;"></th>
          <th>ID</th>
          <th>Avatar</th>
          <th>Name</th>
          <th>Username</th>
          <th>Members</th>
          <th>Created By</th>
          <th>Created</th>
          <th>Actions</th>
        </tr>
      </thead>
      <tbody>
        <?php foreach ($groups as $g): ?>
        <tr>
          <td>
            <input type="checkbox" name="group_ids[]" value="<?php echo (int)$g['id']; ?>" class="group-check">
          </td>
          <td><?php echo (int)$g['id']; ?></td>
          <td>
            <?php $avatarUrl = get_avatar_url($g['avatar']); ?>
            <?php if ($avatarUrl): ?>
              <img src="<?php echo h($avatarUrl); ?>" style="width:36px;height:36px;border-radius:50%;object-fit:cover;">
            <?php else: ?>
              <div style="width:36px;height:36px;border-radius:50%;background:#1e3a5f;display:flex;align-items:center;justify-content:center;">
                <span style="font-size:14px;">👥</span>
              </div>
            <?php endif; ?>
          </td>
          <td><?php echo h($g['name']); ?></td>
          <td style="opacity:0.7;">@<?php echo h($g['username'] ?? '-'); ?></td>
          <td><span class="badge"><?php echo (int)$g['member_count']; ?></span></td>
          <td><?php echo h($g['creator_name'] ?? 'Unknown'); ?></td>
          <td style="font-size:12px;opacity:0.7;"><?php echo date('M d, Y', strtotime($g['created_at'] ?? 'now')); ?></td>
          <td>
            <a href="groups.php?action=view&group_id=<?php echo (int)$g['id']; ?>" class="btn" style="padding:4px 10px;font-size:12px;">Manage</a>
          </td>
        </tr>
        <?php endforeach; ?>
        
        <?php if (empty($groups)): ?>
        <tr>
          <td colspan="8" style="text-align:center;padding:30px;opacity:0.6;">
            No groups found<?php echo $search ? ' for search "'.h($search).'"' : ''; ?>
          </td>
        </tr>
        <?php endif; ?>
      </tbody>
    </table>
    </form>
  </div>

<?php elseif ($action === 'view' && $group): ?>
  <div class="section" style="border:1px solid #2a3f6e;">
    <div class="head">
      <div style="display:flex;align-items:center;gap:12px;">
        <a href="groups.php" class="btn" style="padding:4px 10px;">← Back</a>
        <b><?php echo h($group['name']); ?></b>
        <span style="opacity:0.6;">@<?php echo h($group['username'] ?? 'no username'); ?></span>
      </div>
      <form method="post" onsubmit="return confirm('Delete this group permanently?');" style="display:flex;gap:8px;">
        <input type="hidden" name="action" value="delete_group">
        <input type="hidden" name="group_id" value="<?php echo $groupId; ?>">
        <button type="submit" class="btn danger" style="background:#c62828;">Delete Group</button>
      </form>
    </div>
    
    <div class="body">
      <div style="display:grid;grid-template-columns:1fr 1fr;gap:20px;">
        <!-- Settings -->
        <div class="card" style="padding:16px;border:1px solid #223a66;border-radius:14px;">
          <b style="display:block;margin-bottom:14px;">Group Settings</b>
          <form method="post">
            <input type="hidden" name="action" value="update_settings">
            <input type="hidden" name="group_id" value="<?php echo $groupId; ?>">
            
            <div style="margin-bottom:12px;">
              <label style="display:block;font-size:12px;opacity:0.7;margin-bottom:4px;">Group Name</label>
              <input type="text" name="name" value="<?php echo h($group['name']); ?>" 
                     style="width:100%;background:#0d1b2a;border:1px solid #1e3a5f;color:#eee;padding:8px 12px;border-radius:6px;">
            </div>
            
            <div style="margin-bottom:12px;">
              <label style="display:block;font-size:12px;opacity:0.7;margin-bottom:4px;">Username</label>
              <input type="text" name="username" value="<?php echo h($group['username'] ?? ''); ?>" 
                     style="width:100%;background:#0d1b2a;border:1px solid #1e3a5f;color:#eee;padding:8px 12px;border-radius:6px;">
            </div>
            
            <div style="margin-bottom:12px;">
              <label style="display:block;font-size:12px;opacity:0.7;margin-bottom:4px;">Bio</label>
              <textarea name="bio" rows="2" 
                        style="width:100%;background:#0d1b2a;border:1px solid #1e3a5f;color:#eee;padding:8px 12px;border-radius:6px;"><?php echo h($group['bio'] ?? ''); ?></textarea>
            </div>
            
            <div style="display:grid;grid-template-columns:1fr 1fr;gap:10px;margin-bottom:12px;">
              <div>
                <label style="display:block;font-size:12px;opacity:0.7;margin-bottom:4px;">Join Fee (coins)</label>
                <input type="number" name="join_fee" value="<?php echo (int)$group['join_fee']; ?>" 
                       style="width:100%;background:#0d1b2a;border:1px solid #1e3a5f;color:#eee;padding:8px 12px;border-radius:6px;">
              </div>
            </div>
            
            <div style="display:grid;grid-template-columns:1fr 1fr;gap:10px;margin-bottom:12px;">
              <div>
                <label style="display:block;font-size:12px;opacity:0.7;margin-bottom:4px;">Message Delay (sec)</label>
                <input type="number" name="message_delay" value="<?php echo (int)$group['message_delay']; ?>" 
                       style="width:100%;background:#0d1b2a;border:1px solid #1e3a5f;color:#eee;padding:8px 12px;border-radius:6px;">
              </div>
              <div style="display:flex;align-items:center;padding-top:24px;">
                <input type="checkbox" name="is_private" id="isPrivate" <?php echo $group['is_private'] ? 'checked' : ''; ?>>
                <label for="isPrivate" style="margin-left:8px;">Private Group</label>
              </div>
            </div>
            
            <button type="submit" class="btn" style="width:100%;">Save Settings</button>
          </form>
        </div>
        
        <!-- Stats -->
        <div class="card" style="padding:16px;border:1px solid #223a66;border-radius:14px;">
          <b style="display:block;margin-bottom:14px;">Statistics</b>
          <div style="display:grid;grid-template-columns:1fr 1fr 1fr;gap:10px;text-align:center;">
            <div style="padding:12px;background:#0d1b2a;border-radius:8px;">
              <div style="font-size:20px;font-weight:bold;color:#4fc3f7;"><?php echo (int)$group['member_count']; ?></div>
              <div style="font-size:11px;opacity:0.7;">Members</div>
            </div>
            <div style="padding:12px;background:#0d1b2a;border-radius:8px;">
              <div style="font-size:20px;font-weight:bold;color:#81c784;"><?php echo (int)$messageCount; ?></div>
              <div style="font-size:11px;opacity:0.7;">Messages</div>
            </div>
            <div style="padding:12px;background:#0d1b2a;border-radius:8px;">
              <div style="font-size:20px;font-weight:bold;color:#ffb74d;"><?php echo (int)($group['views_count'] ?? 0); ?></div>
              <div style="font-size:11px;opacity:0.7;">Views</div>
            </div>
          </div>
          
          <hr style="border-color:#1e3a5f;margin:16px 0;">
          
          <b style="display:block;margin-bottom:10px;">Join Fee</b>
          <div style="font-size:13px;opacity:0.8;">
            <div>Join: <b><?php echo (int)$group['join_fee']; ?></b> coins</div>
          </div>
        </div>
      </div>
      
      <!-- Members -->
      <div class="card" style="padding:16px;border:1px solid #223a66;border-radius:14px;margin-top:20px;">
        <b style="display:block;margin-bottom:14px;">Members (<?php echo count($members); ?>)</b>
        <div style="max-height:300px;overflow-y:auto;">
          <?php foreach ($members as $m): ?>
          <div style="display:flex;align-items:center;justify-content:space-between;padding:10px;border-bottom:1px solid #1e3a5f;">
            <div style="display:flex;align-items:center;gap:10px;">
              <?php if (!empty($m['profile_pic'])): ?>
                <img src="<?php echo h($m['profile_pic']); ?>" style="width:36px;height:36px;border-radius:50%;object-fit:cover;">
              <?php else: ?>
                <div style="width:36px;height:36px;border-radius:50%;background:#1e3a5f;display:flex;align-items:center;justify-content:center;">
                  <?php echo strtoupper($m['name'][0] ?? 'U'); ?>
                </div>
              <?php endif; ?>
              <div>
                <div style="font-weight:500;"><?php echo h($m['name']); ?></div>
                <div style="font-size:11px;opacity:0.6;">@<?php echo h($m['username']); ?></div>
              </div>
            </div>
            <div style="display:flex;align-items:center;gap:8px;">
              <?php if ($m['role'] === 'admin'): ?>
                <span class="badge danger">Admin</span>
              <?php else: ?>
                <form method="post" style="display:inline;">
                  <input type="hidden" name="action" value="set_admin">
                  <input type="hidden" name="group_id" value="<?php echo $groupId; ?>">
                  <input type="hidden" name="user_id" value="<?php echo (int)$m['id']; ?>">
                  <button type="submit" class="btn" style="padding:2px 8px;font-size:11px;" title="Make Admin">⬆</button>
                </form>
                <form method="post" style="display:inline;" onsubmit="return confirm('Remove this member?')">
                  <input type="hidden" name="action" value="remove_member">
                  <input type="hidden" name="group_id" value="<?php echo $groupId; ?>">
                  <input type="hidden" name="user_id" value="<?php echo (int)$m['id']; ?>">
                  <button type="submit" class="btn danger" style="padding:2px 8px;font-size:11px;background:#c62828;" title="Remove">✕</button>
                </form>
                <form method="post" style="display:inline;" onsubmit="return confirm('Ban this user from group?')">
                  <input type="hidden" name="action" value="ban_user">
                  <input type="hidden" name="group_id" value="<?php echo $groupId; ?>">
                  <input type="hidden" name="user_id" value="<?php echo (int)$m['id']; ?>">

                  <button type="submit" class="btn" style="padding:2px 8px;font-size:11px;background:#e65100;" title="Ban">🚫</button>
                </form>
              <?php endif; ?>
            </div>
          </div>
          <?php endforeach; ?>
          
          <?php if (empty($members)): ?>
            <div style="padding:20px;text-align:center;opacity:0.6;">No members</div>
          <?php endif; ?>
        </div>
      </div>
      
      <!-- Banned -->
      <div class="card" style="padding:16px;border:1px solid #223a66;border-radius:14px;margin-top:20px;">
        <b style="display:block;margin-bottom:14px;">Banned Users (<?php echo count($bannedUsers); ?>)</b>
        <?php if (empty($bannedUsers)): ?>
          <div style="padding:10px;opacity:0.6;">No banned users</div>
        <?php else: ?>
          <div style="max-height:200px;overflow-y:auto;">
            <?php foreach ($bannedUsers as $b): ?>
            <div style="display:flex;align-items:center;justify-content:space-between;padding:10px;border-bottom:1px solid #1e3a5f;">
              <div>
                <div style="font-weight:500;"><?php echo h($b['name']); ?></div>
                <div style="font-size:11px;opacity:0.6;">@<?php echo h($b['username']); ?></div>
              </div>
              <form method="post">
                <input type="hidden" name="action" value="unban_user">
                <input type="hidden" name="group_id" value="<?php echo $groupId; ?>">
                <input type="hidden" name="user_id" value="<?php echo (int)$b['id']; ?>">
                <button type="submit" class="btn" style="padding:4px 12px;font-size:12px;background:#2e7d32;">Unban</button>
              </form>
            </div>
            <?php endforeach; ?>
          </div>
        <?php endif; ?>
      </div>
    </div>
  </div>

<?php endif; ?>

<?php require __DIR__ . '/_layout_footer.php'; ?>
