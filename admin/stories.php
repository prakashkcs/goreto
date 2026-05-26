<?php
require_once __DIR__ . '/_core.php';
admin_require_login();
$pageTitle = 'Stories';
$activeNav = 'stories';

$msg = ''; $err = '';

if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['action'], $_POST['story_id'])) {
    $sid = (int)$_POST['story_id'];
    try {
        if ($_POST['action'] === 'delete') {
            $pdo->prepare("DELETE FROM stories WHERE id=?")->execute([$sid]);
            $msg = "Story #{$sid} deleted.";
        }
    } catch (Throwable $e) { $err = $e->getMessage(); }
}

$rows = [];
try {
    $rows = $pdo->query("
        SELECT s.id, s.user_id, s.media_url, s.type, s.view_count, s.created_at, s.expires_at,
               u.name AS u_name, u.username AS u_username
        FROM stories s
        LEFT JOIN users u ON u.id = s.user_id
        ORDER BY s.id DESC LIMIT 500
    ")->fetchAll();
} catch (Throwable $_) {}

require __DIR__ . '/_layout_header.php';
?>
<div class="section">
  <div class="head">
    <b>Stories</b>
    <small><?= count($rows) ?> rows</small>
  </div>
  <div class="body">
    <?php if ($msg): ?><div class="badge ok" style="margin-bottom:10px"><?= htmlspecialchars($msg) ?></div><?php endif; ?>
    <?php if ($err): ?><div class="badge danger" style="margin-bottom:10px"><?= htmlspecialchars($err) ?></div><?php endif; ?>
    <div class="table-wrap"><table>
      <thead><tr><th>ID</th><th>User</th><th>Type</th><th>Media</th><th>Views</th><th>Created</th><th>Expires</th><th>Actions</th></tr></thead>
      <tbody>
      <?php foreach ($rows as $s): ?>
        <tr>
          <td>#<?= (int)$s['id'] ?></td>
          <td>
            <b><?= htmlspecialchars($s['u_name'] ?? 'User '.$s['user_id']) ?></b><br>
            <small>ID:<?= (int)$s['user_id'] ?></small>
          </td>
          <td><span class="badge"><?= htmlspecialchars($s['type'] ?? 'story') ?></span></td>
          <td><?php if (!empty($s['media_url'])): ?><a class="btn" target="_blank" href="<?= htmlspecialchars($s['media_url']) ?>">View</a><?php else: ?>-<?php endif; ?></td>
          <td><?= number_format((int)($s['view_count'] ?? 0)) ?></td>
          <td><small><?= htmlspecialchars(substr($s['created_at'] ?? '', 0, 10)) ?></small></td>
          <td><small><?= htmlspecialchars(substr($s['expires_at'] ?? '', 0, 10)) ?></small></td>
          <td>
            <form method="post" style="display:inline">
              <input type="hidden" name="story_id" value="<?= (int)$s['id'] ?>">
              <button class="btn danger" name="action" value="delete" onclick="return confirm('Delete story #<?= (int)$s['id'] ?>?')">Delete</button>
            </form>
          </td>
        </tr>
      <?php endforeach; ?>
      <?php if (empty($rows)): ?><tr><td colspan="8"><div style="padding:20px;text-align:center;opacity:.5">No stories found.</div></td></tr><?php endif; ?>
      </tbody>
    </table></div>
  </div>
</div>
<?php require __DIR__ . '/_layout_footer.php'; ?>
