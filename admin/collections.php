<?php
require_once __DIR__ . '/_core.php';
admin_require_login();
$pageTitle = 'Collections';
$activeNav = 'collections';

$msg = ''; $err = '';

if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['action'], $_POST['collection_id'])) {
    $cid = (int)$_POST['collection_id'];
    try {
        if ($_POST['action'] === 'delete') {
            $pdo->prepare("DELETE FROM collection_items WHERE collection_id=?")->execute([$cid]);
            $pdo->prepare("DELETE FROM collections WHERE id=?")->execute([$cid]);
            $msg = "Collection #{$cid} deleted.";
        }
    } catch (Throwable $e) { $err = $e->getMessage(); }
}

$rows = [];
try {
    $rows = $pdo->query("
        SELECT c.id, c.user_id, c.name, c.description, c.cover_url, c.is_private, c.created_at,
               u.name AS u_name, u.username AS u_username,
               (SELECT COUNT(*) FROM collection_items ci WHERE ci.collection_id = c.id) AS item_count
        FROM collections c
        LEFT JOIN users u ON u.id = c.user_id
        ORDER BY c.id DESC LIMIT 500
    ")->fetchAll();
} catch (Throwable $_) {}

require __DIR__ . '/_layout_header.php';
?>
<div class="section">
  <div class="head">
    <b>Collections</b>
    <small><?= count($rows) ?> rows</small>
  </div>
  <div class="body">
    <?php if ($msg): ?><div class="badge ok" style="margin-bottom:10px"><?= htmlspecialchars($msg) ?></div><?php endif; ?>
    <?php if ($err): ?><div class="badge danger" style="margin-bottom:10px"><?= htmlspecialchars($err) ?></div><?php endif; ?>
    <div class="table-wrap"><table>
      <thead><tr><th>ID</th><th>User</th><th>Name</th><th>Items</th><th>Privacy</th><th>Created</th><th>Actions</th></tr></thead>
      <tbody>
      <?php foreach ($rows as $c): ?>
        <tr>
          <td>#<?= (int)$c['id'] ?></td>
          <td>
            <b><?= htmlspecialchars($c['u_name'] ?? 'User '.$c['user_id']) ?></b><br>
            <small>ID:<?= (int)$c['user_id'] ?></small>
          </td>
          <td>
            <b><?= htmlspecialchars($c['name'] ?? '') ?></b>
            <?php if ($c['description']): ?><br><small><?= htmlspecialchars(substr($c['description'],0,60)) ?></small><?php endif; ?>
          </td>
          <td><?= (int)($c['item_count'] ?? 0) ?></td>
          <td><span class="badge <?= !empty($c['is_private'])?'warn':'' ?>"><?= !empty($c['is_private'])?'Private':'Public' ?></span></td>
          <td><small><?= htmlspecialchars(substr($c['created_at'] ?? '', 0, 10)) ?></small></td>
          <td>
            <form method="post" style="display:inline">
              <input type="hidden" name="collection_id" value="<?= (int)$c['id'] ?>">
              <button class="btn danger" name="action" value="delete" onclick="return confirm('Delete collection #<?= (int)$c['id'] ?> and all its items?')">Delete</button>
            </form>
          </td>
        </tr>
      <?php endforeach; ?>
      <?php if (empty($rows)): ?><tr><td colspan="7"><div style="padding:20px;text-align:center;opacity:.5">No collections found.</div></td></tr><?php endif; ?>
      </tbody>
    </table></div>
  </div>
</div>
<?php require __DIR__ . '/_layout_footer.php'; ?>
