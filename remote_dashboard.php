<?php
require_once __DIR__ . '/_core.php';
admin_require_login();

function table_count(PDO $pdo, string $table): int {
  try {
    $stmt = $pdo->query("SELECT COUNT(*) AS c FROM `$table`");
    return (int)($stmt->fetch()['c'] ?? 0);
  } catch (Throwable $e) {
    return 0;
  }
}

$counts = [
  'users' => table_count($pdo, 'users'),
  'posts' => table_count($pdo, 'posts'),
  'stories' => table_count($pdo, 'stories'),
  'collections' => table_count($pdo, 'collections'),
  'comments' => table_count($pdo, 'comments'),
  'likes' => table_count($pdo, 'likes'),
];

$pageTitle = 'Dashboard';
$activeNav = 'dashboard';
require __DIR__ . '/_layout_header.php';
?>

<div class="grid">
  <div class="card">
    <div class="label">Users</div>
    <div class="value"><?php echo $counts['users']; ?></div>
    <div class="hint">Total registered users</div>
  </div>
  <div class="card">
    <div class="label">Posts</div>
    <div class="value"><?php echo $counts['posts']; ?></div>
    <div class="hint">Uploaded posts</div>
  </div>
  <div class="card">
    <div class="label">Stories</div>
    <div class="value"><?php echo $counts['stories']; ?></div>
    <div class="hint">Active stories</div>
  </div>
  <div class="card">
    <div class="label">Collections</div>
    <div class="value"><?php echo $counts['collections']; ?></div>
    <div class="hint">User collections</div>
  </div>
  <div class="card">
    <div class="label">Comments</div>
    <div class="value"><?php echo $counts['comments']; ?></div>
    <div class="hint">Engagement comments</div>
  </div>
  <div class="card">
    <div class="label">Likes</div>
    <div class="value"><?php echo $counts['likes']; ?></div>
    <div class="hint">Total likes</div>
  </div>
</div>

<div class="section">
  <div class="head">
    <b>Quick Actions</b>
    <small>Jump to a management page</small>
  </div>
  <div class="body" style="display:flex;gap:10px;flex-wrap:wrap;">
    <a class="btn primary" href="users.php">Manage Users</a>
    <a class="btn primary" href="posts.php">Manage Posts</a>
    <a class="btn primary" href="stories.php">Manage Stories</a>
    <a class="btn primary" href="collections.php">Manage Collections</a>
  </div>
</div>

<?php require __DIR__ . '/_layout_footer.php'; ?>

