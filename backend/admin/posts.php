<?php
require_once __DIR__ . '/_core.php';
admin_require_login();
$pageTitle = 'Posts';
$activeNav = 'posts';

$msg = ''; $err = '';

// Add missing columns to posts table if needed
$existing_cols = [];
foreach ($pdo->query("SHOW COLUMNS FROM posts")->fetchAll(PDO::FETCH_ASSOC) as $row) {
    $existing_cols[] = $row['Field'];
}
$add_cols = [
    'is_featured' => "TINYINT(1) NOT NULL DEFAULT 0",
    'is_flagged'  => "TINYINT(1) NOT NULL DEFAULT 0",
    'view_count'  => "INT NOT NULL DEFAULT 0",
    'like_count'  => "INT NOT NULL DEFAULT 0",
];
foreach ($add_cols as $col => $def) {
    if (!in_array($col, $existing_cols)) {
        try { $pdo->exec("ALTER TABLE posts ADD COLUMN `{$col}` {$def}"); } catch (Throwable $e) {}
    }
}
// Alias for media_url — the column is file_url in this schema
$media_col = in_array('media_url', $existing_cols) ? 'p.media_url' : 'p.file_url AS media_url';

if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['action'], $_POST['post_id'])) {
    $pid = (int)$_POST['post_id'];
    try {
        if ($_POST['action'] === 'delete') {
            foreach (['post_likes','post_comments','likes','comments'] as $t) {
                try { $pdo->prepare("DELETE FROM {$t} WHERE post_id=?")->execute([$pid]); } catch (Throwable $e) {}
            }
            $pdo->prepare("DELETE FROM posts WHERE id=?")->execute([$pid]);
            $msg = "Post #{$pid} deleted.";
        } elseif ($_POST['action'] === 'feature') {
            $pdo->prepare("UPDATE posts SET is_featured = 1 - COALESCE(is_featured,0) WHERE id=?")->execute([$pid]);
            $msg = "Toggled featured for #{$pid}.";
        } elseif ($_POST['action'] === 'flag') {
            $pdo->prepare("UPDATE posts SET is_flagged = 1 - COALESCE(is_flagged,0) WHERE id=?")->execute([$pid]);
            $msg = "Toggled flagged for #{$pid}.";
        }
    } catch (Throwable $e) { $err = $e->getMessage(); }
}

$search = trim($_GET['q'] ?? '');
$filter = in_array($_GET['filter'] ?? '', ['all','flagged','featured']) ? ($_GET['filter'] ?? 'all') : 'all';

$where = '1=1';
if ($search) $where .= " AND (u.name LIKE ".$pdo->quote('%'.$search.'%')." OR p.caption LIKE ".$pdo->quote('%'.$search.'%').")";
if ($filter === 'flagged')  $where .= " AND p.is_flagged = 1";
if ($filter === 'featured') $where .= " AND p.is_featured = 1";

// Count likes per post from post_likes or likes table
$has_post_likes = in_array('post_likes', array_column($pdo->query("SHOW TABLES")->fetchAll(PDO::FETCH_NUM), 0));
$likes_join = $has_post_likes
    ? "LEFT JOIN (SELECT post_id, COUNT(*) AS dyn_likes FROM post_likes GROUP BY post_id) lk ON lk.post_id = p.id"
    : "";
$likes_col = $has_post_likes ? "COALESCE(lk.dyn_likes, p.like_count, 0)" : "COALESCE(p.like_count, 0)";

$rows = [];
try {
    $rows = $pdo->query("
        SELECT p.id, p.user_id, p.caption, {$media_col}, p.type,
               COALESCE(p.view_count, 0) AS view_count,
               {$likes_col} AS like_count,
               p.created_at, COALESCE(p.is_featured,0) AS is_featured,
               COALESCE(p.is_flagged,0) AS is_flagged,
               u.name AS u_name,
               COALESCE(u.username, u.email, CONCAT('user_', p.user_id)) AS u_username
        FROM posts p
        LEFT JOIN users u ON u.id = p.user_id
        {$likes_join}
        WHERE {$where}
        ORDER BY p.id DESC LIMIT 500
    ")->fetchAll();
} catch (Throwable $e) {
    $err = 'Query error: ' . $e->getMessage();
}

require __DIR__ . '/_layout_header.php';
?>
<div class="section">
  <div class="head">
    <b>Posts</b>
    <div class="search">
      <form method="get" style="display:flex;gap:8px;align-items:center;flex-wrap:wrap">
        <input name="q" value="<?= htmlspecialchars($search) ?>" placeholder="Search caption / user...">
        <?php foreach (['all','flagged','featured'] as $f): ?>
          <a class="btn <?= $filter===$f?'ok':'' ?>" href="?filter=<?= $f ?>&q=<?= urlencode($search) ?>"><?= ucfirst($f) ?></a>
        <?php endforeach; ?>
        <small><?= count($rows) ?> rows</small>
      </form>
    </div>
  </div>
  <div class="body">
    <?php if ($msg): ?><div class="badge ok" style="margin-bottom:10px"><?= htmlspecialchars($msg) ?></div><?php endif; ?>
    <?php if ($err): ?><div class="badge danger" style="margin-bottom:10px"><?= htmlspecialchars($err) ?></div><?php endif; ?>
    <div class="table-wrap"><table>
      <thead><tr><th>ID</th><th>User</th><th>Type</th><th>Caption</th><th>Views</th><th>Likes</th><th>Date</th><th>Actions</th></tr></thead>
      <tbody>
      <?php foreach ($rows as $p): ?>
        <tr<?= $p['is_flagged'] ? ' style="background:rgba(255,80,80,.07)"' : '' ?>>
          <td>#<?= (int)$p['id'] ?></td>
          <td>
            <b><?= htmlspecialchars($p['u_name'] ?? 'User '.$p['user_id']) ?></b><br>
            <small>@<?= htmlspecialchars($p['u_username'] ?? '') ?></small>
          </td>
          <td><span class="badge"><?= htmlspecialchars($p['type'] ?? 'post') ?></span></td>
          <td style="max-width:220px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap">
            <?= htmlspecialchars(substr($p['caption'] ?? '', 0, 100)) ?>
            <?php if (!empty($p['media_url'])): ?>
              <br><a class="btn" target="_blank" href="<?= htmlspecialchars($p['media_url']) ?>">Media</a>
            <?php endif; ?>
          </td>
          <td><?= number_format((int)($p['view_count'] ?? 0)) ?></td>
          <td><?= number_format((int)($p['like_count'] ?? 0)) ?></td>
          <td><small><?= htmlspecialchars(substr($p['created_at'] ?? '', 0, 10)) ?></small></td>
          <td style="display:flex;gap:5px;flex-wrap:wrap">
            <form method="post" style="display:inline">
              <input type="hidden" name="post_id" value="<?= (int)$p['id'] ?>">
              <button class="btn <?= !empty($p['is_featured'])?'ok':'' ?>" name="action" value="feature">
                <?= !empty($p['is_featured'])?'Unfeature':'Feature' ?>
              </button>
            </form>
            <form method="post" style="display:inline">
              <input type="hidden" name="post_id" value="<?= (int)$p['id'] ?>">
              <button class="btn <?= !empty($p['is_flagged'])?'danger':'' ?>" name="action" value="flag">
                <?= !empty($p['is_flagged'])?'Unflag':'Flag' ?>
              </button>
            </form>
            <form method="post" style="display:inline">
              <input type="hidden" name="post_id" value="<?= (int)$p['id'] ?>">
              <button class="btn danger" name="action" value="delete"
                onclick="return confirm('Delete post #<?= (int)$p['id'] ?>?')">Delete</button>
            </form>
          </td>
        </tr>
      <?php endforeach; ?>
      <?php if (empty($rows)): ?>
        <tr><td colspan="8"><div style="padding:20px;text-align:center;opacity:.5">No posts found.</div></td></tr>
      <?php endif; ?>
      </tbody>
    </table></div>
  </div>
</div>
<?php require __DIR__ . '/_layout_footer.php'; ?>
