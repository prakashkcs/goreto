<?php
require_once __DIR__ . '/_core.php';
admin_require_login();
$pageTitle = 'Group Chats';
$activeNav = 'groups';

function h_g($s) { return htmlspecialchars((string)$s, ENT_QUOTES, 'UTF-8'); }

$msg = '';
$action  = $_GET['action']   ?? 'list';
$groupId = (int)($_GET['group_id'] ?? 0);

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $postAction = $_POST['action'] ?? '';
    $groupId    = (int)($_POST['group_id'] ?? 0);

    if ($postAction === 'bulk_delete' && !empty($_POST['group_ids'])) {
        foreach (array_map('intval', $_POST['group_ids']) as $gid) {
            if (!$gid) continue;
            foreach (['chat_group_messages','chat_group_members','chat_group_views','chat_group_bans'] as $t)
                try { $pdo->prepare("DELETE FROM $t WHERE group_id=?")->execute([$gid]); } catch (Throwable $_) {}
            try { $pdo->prepare("DELETE FROM chat_groups WHERE id=?")->execute([$gid]); } catch (Throwable $_) {}
        }
        $msg = count($_POST['group_ids']).' group(s) deleted';
        $action = 'list';
    } elseif ($groupId > 0) {
        if ($postAction === 'delete_group') {
            foreach (['chat_group_messages','chat_group_members','chat_group_views','chat_group_bans'] as $t)
                try { $pdo->prepare("DELETE FROM $t WHERE group_id=?")->execute([$groupId]); } catch (Throwable $_) {}
            try { $pdo->prepare("DELETE FROM chat_groups WHERE id=?")->execute([$groupId]); } catch (Throwable $_) {}
            header("Location: groups.php?msg=".urlencode('Group deleted')); exit;
        } elseif ($postAction === 'ban_user' && ($uid = (int)($_POST['user_id']??0)) > 0) {
            try { $pdo->prepare("INSERT IGNORE INTO chat_group_bans (group_id,user_id,banned_by,created_at) VALUES (?,?,?,NOW())")->execute([$groupId,$uid,$_SESSION['admin_id']??0]); } catch (Throwable $_) {}
            try { $pdo->prepare("DELETE FROM chat_group_members WHERE group_id=? AND user_id=?")->execute([$groupId,$uid]); } catch (Throwable $_) {}
            $msg = 'User banned';
        } elseif ($postAction === 'unban_user' && ($uid = (int)($_POST['user_id']??0)) > 0) {
            try { $pdo->prepare("DELETE FROM chat_group_bans WHERE group_id=? AND user_id=?")->execute([$groupId,$uid]); } catch (Throwable $_) {}
            $msg = 'User unbanned';
        } elseif ($postAction === 'remove_member' && ($uid = (int)($_POST['user_id']??0)) > 0) {
            try { $pdo->prepare("DELETE FROM chat_group_members WHERE group_id=? AND user_id=?")->execute([$groupId,$uid]); } catch (Throwable $_) {}
            $msg = 'Member removed';
        } elseif ($postAction === 'update_settings') {
            $pdo->prepare("UPDATE chat_groups SET name=?,username=?,bio=?,join_fee=?,message_delay=?,is_private=? WHERE id=?")
                ->execute([trim($_POST['name']??''),trim($_POST['username']??'')?:null,trim($_POST['bio']??'')?:null,
                           (int)($_POST['join_fee']??0),(int)($_POST['message_delay']??0),isset($_POST['is_private'])?1:0,$groupId]);
            $msg = 'Settings updated';
        }
        if ($msg) { header("Location: ?action=view&group_id={$groupId}&msg=".urlencode($msg)); exit; }
    }
}

if (isset($_GET['msg'])) $msg = htmlspecialchars($_GET['msg']);

// View single group
if ($action === 'view' && $groupId > 0) {
    $group = null;
    try { $st = $pdo->prepare("SELECT * FROM chat_groups WHERE id=? LIMIT 1"); $st->execute([$groupId]); $group = $st->fetch(); } catch (Throwable $_) {}
    if (!$group) { header("Location: groups.php"); exit; }
    $members = [];
    try {
        $members = $pdo->query("SELECT m.*,u.name,u.username FROM chat_group_members m LEFT JOIN users u ON u.id=m.user_id WHERE m.group_id=$groupId ORDER BY m.role DESC,m.joined_at ASC LIMIT 200")->fetchAll();
    } catch (Throwable $_) {}
    $bans = [];
    try { $bans = $pdo->query("SELECT b.*,u.name FROM chat_group_bans b LEFT JOIN users u ON u.id=b.user_id WHERE b.group_id=$groupId LIMIT 100")->fetchAll(); } catch (Throwable $_) {}

    require __DIR__ . '/_layout_header.php';
    ?>
    <div class="section">
      <div class="head"><b><?= h_g($group['name']) ?></b><a class="btn" href="groups.php">Back to List</a></div>
      <div class="body">
        <?php if ($msg): ?><div class="badge ok" style="margin-bottom:10px"><?= $msg ?></div><?php endif; ?>
        <div style="display:grid;grid-template-columns:1fr 1fr;gap:14px;margin-bottom:20px">
          <div>
            <div style="margin-bottom:8px"><b>ID:</b> <?= (int)$group['id'] ?></div>
            <div style="margin-bottom:8px"><b>Username:</b> @<?= h_g($group['username']??'') ?></div>
            <div style="margin-bottom:8px"><b>Join Fee:</b> <?= (int)($group['join_fee']??0) ?> coins</div>
            <div><b>Private:</b> <?= !empty($group['is_private'])?'Yes':'No' ?></div>
          </div>
          <form method="post">
            <input type="hidden" name="action" value="update_settings">
            <input type="hidden" name="group_id" value="<?= (int)$group['id'] ?>">
            <input name="name" value="<?= h_g($group['name']) ?>" placeholder="Name" style="width:100%;padding:8px;border-radius:6px;border:1px solid #334;background:#0a0a14;color:#fff;margin-bottom:8px">
            <input name="username" value="<?= h_g($group['username']??'') ?>" placeholder="Username" style="width:100%;padding:8px;border-radius:6px;border:1px solid #334;background:#0a0a14;color:#fff;margin-bottom:8px">
            <input name="join_fee" type="number" value="<?= (int)($group['join_fee']??0) ?>" placeholder="Join Fee" style="width:100%;padding:8px;border-radius:6px;border:1px solid #334;background:#0a0a14;color:#fff;margin-bottom:8px">
            <label style="display:flex;align-items:center;gap:8px;margin-bottom:10px"><input type="checkbox" name="is_private" value="1" <?= !empty($group['is_private'])?'checked':'' ?>> Private</label>
            <button class="btn ok" type="submit">Update Settings</button>
          </form>
        </div>
        <h3 style="margin-bottom:10px">Members (<?= count($members) ?>)</h3>
        <div class="table-wrap"><table>
          <thead><tr><th>User</th><th>Role</th><th>Joined</th><th>Actions</th></tr></thead>
          <tbody>
          <?php foreach ($members as $m): ?>
            <tr>
              <td><b><?= h_g($m['name']??'User '.$m['user_id']) ?></b> <small>ID:<?= (int)$m['user_id'] ?></small></td>
              <td><span class="badge <?= ($m['role']??'')==='admin'?'ok':'' ?>"><?= h_g($m['role']??'member') ?></span></td>
              <td><small><?= h_g(substr($m['joined_at']??'',0,10)) ?></small></td>
              <td style="display:flex;gap:6px">
                <form method="post" style="display:inline"><input type="hidden" name="action" value="remove_member"><input type="hidden" name="group_id" value="<?= (int)$group['id'] ?>"><input type="hidden" name="user_id" value="<?= (int)$m['user_id'] ?>"><button class="btn danger" onclick="return confirm('Remove member?')">Remove</button></form>
                <form method="post" style="display:inline"><input type="hidden" name="action" value="ban_user"><input type="hidden" name="group_id" value="<?= (int)$group['id'] ?>"><input type="hidden" name="user_id" value="<?= (int)$m['user_id'] ?>"><button class="btn warn" onclick="return confirm('Ban user?')">Ban</button></form>
              </td>
            </tr>
          <?php endforeach; ?>
          </tbody>
        </table></div>
        <?php if ($bans): ?>
        <h3 style="margin:20px 0 10px">Bans (<?= count($bans) ?>)</h3>
        <div class="table-wrap"><table>
          <thead><tr><th>User</th><th>Banned</th><th>Actions</th></tr></thead>
          <tbody>
          <?php foreach ($bans as $b): ?>
            <tr>
              <td><b><?= h_g($b['name']??'User '.$b['user_id']) ?></b></td>
              <td><small><?= h_g(substr($b['created_at']??'',0,10)) ?></small></td>
              <td><form method="post" style="display:inline"><input type="hidden" name="action" value="unban_user"><input type="hidden" name="group_id" value="<?= (int)$group['id'] ?>"><input type="hidden" name="user_id" value="<?= (int)$b['user_id'] ?>"><button class="btn">Unban</button></form></td>
            </tr>
          <?php endforeach; ?>
          </tbody>
        </table></div>
        <?php endif; ?>
        <div style="margin-top:20px">
          <form method="post" onsubmit="return confirm('Delete this group?')">
            <input type="hidden" name="action" value="delete_group">
            <input type="hidden" name="group_id" value="<?= (int)$group['id'] ?>">
            <button class="btn danger" type="submit">Delete Group</button>
          </form>
        </div>
      </div>
    </div>
    <?php require __DIR__ . '/_layout_footer.php'; ?>
    <?php exit;
}

// Group list
$groups = [];
try {
    $groups = $pdo->query("
        SELECT g.*, u.name AS owner_name,
               (SELECT COUNT(*) FROM chat_group_members m WHERE m.group_id=g.id) AS member_count
        FROM chat_groups g
        LEFT JOIN users u ON u.id = g.creator_id
        ORDER BY g.id DESC LIMIT 500
    ")->fetchAll();
} catch (Throwable $_) {}

require __DIR__ . '/_layout_header.php';
?>
<div class="section">
  <div class="head">
    <b>Group Chats</b>
    <small><?= count($groups) ?> groups</small>
  </div>
  <div class="body">
    <?php if ($msg): ?><div class="badge ok" style="margin-bottom:10px"><?= $msg ?></div><?php endif; ?>
    <form method="post" id="bulkForm">
    <div style="margin-bottom:10px">
      <button class="btn danger" type="submit" name="action" value="bulk_delete" onclick="return confirm('Delete selected groups?')">Delete Selected</button>
    </div>
    <div class="table-wrap"><table>
      <thead><tr><th><input type="checkbox" onclick="document.querySelectorAll('.chk-g').forEach(c=>c.checked=this.checked)"></th><th>ID</th><th>Name</th><th>Owner</th><th>Members</th><th>Fee</th><th>Private</th><th>Created</th><th>Actions</th></tr></thead>
      <tbody>
      <?php foreach ($groups as $g): ?>
        <tr>
          <td><input type="checkbox" name="group_ids[]" value="<?= (int)$g['id'] ?>" class="chk-g"></td>
          <td>#<?= (int)$g['id'] ?></td>
          <td><b><?= h_g($g['name']) ?></b><?php if ($g['username']??''): ?><br><small>@<?= h_g($g['username']) ?></small><?php endif; ?></td>
          <td><?= h_g($g['owner_name']??'—') ?></td>
          <td><?= (int)($g['member_count']??0) ?></td>
          <td><?= (int)($g['join_fee']??0) ?> coins</td>
          <td><?= !empty($g['is_private'])?'<span class="badge warn">Yes</span>':'No' ?></td>
          <td><small><?= h_g(substr($g['created_at']??'',0,10)) ?></small></td>
          <td><a class="btn ok" href="?action=view&group_id=<?= (int)$g['id'] ?>">View</a></td>
        </tr>
      <?php endforeach; ?>
      <?php if (empty($groups)): ?><tr><td colspan="9"><div style="padding:20px;text-align:center;opacity:.5">No groups found.</div></td></tr><?php endif; ?>
      </tbody>
    </table></div>
    </form>
  </div>
</div>
<?php require __DIR__ . '/_layout_footer.php'; ?>
