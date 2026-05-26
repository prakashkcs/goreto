<?php
require_once __DIR__ . '/_core.php';
admin_require_login();

$pageTitle = 'KYC Tasks';
$activeNav = 'kyc_tasks';

$pdo->exec("
CREATE TABLE IF NOT EXISTS kyc_tasks (
  id INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  level ENUM('basic','full') NOT NULL DEFAULT 'basic',
  title VARCHAR(80) NOT NULL,
  instructions TEXT NOT NULL,
  is_active TINYINT(1) NOT NULL DEFAULT 1,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
");

$msg = '';
$err = '';

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
  $title = trim($_POST['title'] ?? '');
  $instructions = trim($_POST['instructions'] ?? '');
  $level = ($_POST['level'] ?? 'basic') === 'full' ? 'full' : 'basic';

  if ($title === '' || $instructions === '') {
    $err = "Title and instructions required.";
  } else {
    try {
      $st = $pdo->prepare("INSERT INTO kyc_tasks (level,title,instructions,is_active) VALUES (?,?,?,1)");
      $st->execute([$level, $title, $instructions]);
      $msg = "Task Added.";
    } catch(Throwable $e) {
      $err = $e->getMessage();
    }
  }
}

if (isset($_GET['toggle'])) {
  $id = (int)$_GET['toggle'];
  try {
    $pdo->exec("UPDATE kyc_tasks SET is_active = IF(is_active=1,0,1) WHERE id=".$id);
    $msg = "Task Updated.";
  } catch(Throwable $e) {
    $err = $e->getMessage();
  }
}

$rows = [];
try {
  $rows = $pdo->query("SELECT * FROM kyc_tasks ORDER BY id DESC")->fetchAll(PDO::FETCH_ASSOC);
} catch(Throwable $e) {}

require __DIR__ . '/_layout_header.php';
?>

<style>
/* Page-local polish (keeps existing admin theme intact) */
.section .body h2,.section .body h3{margin:14px 0 10px 0}
.lv-card{background:rgba(255,255,255,.03);border:1px solid rgba(255,255,255,.08);border-radius:16px;padding:14px;margin:12px 0;backdrop-filter: blur(8px);}
.lv-grid{display:grid;gap:12px}
.lv-grid-2{display:grid;grid-template-columns: 1fr 1fr;gap:12px}
@media (max-width: 900px){.lv-grid-2{grid-template-columns:1fr}}
.lv-table{width:100%;border-collapse:collapse;overflow:hidden;border-radius:14px}
.lv-table th{font-size:12px;letter-spacing:.04em;text-transform:uppercase;opacity:.8;padding:12px 10px;border-bottom:1px solid rgba(255,255,255,.08)}
.lv-table td{padding:12px 10px;border-bottom:1px solid rgba(255,255,255,.06);vertical-align:middle}
.lv-table tr:hover td{background:rgba(255,255,255,.03)}
.lv-pill{display:inline-flex;align-items:center;gap:6px;padding:6px 10px;border-radius:999px;border:1px solid rgba(255,255,255,.12);background:rgba(255,255,255,.04);font-size:12px}
.lv-muted{opacity:.75}
.lv-actions{display:flex;gap:8px;flex-wrap:wrap;align-items:center}
.lv-actions form{display:inline-flex;gap:8px;align-items:center;margin:0}
.lv-form input,.lv-form select,.lv-form textarea{width:100%}
.lv-empty{padding:14px;border-radius:14px;border:1px dashed rgba(255,255,255,.15);opacity:.8}
.lv-subhead{display:flex;justify-content:space-between;align-items:center;gap:10px;flex-wrap:wrap;margin:4px 0 10px}
</style>

<div class="section">
  <div class="head"><b>KYC Tasks</b></div>
  <div class="body">

  <div class="lv-subhead">
    <span class="lv-pill">Create random liveness tasks for Basic & Full KYC</span>
    <span class="lv-pill lv-muted"><?php echo count($rows); ?> tasks</span>
  </div>

<?php if ($msg): ?><div class="badge" style="margin-bottom:10px;"><?php echo htmlspecialchars($msg); ?></div><?php endif; ?>
<?php if ($err): ?><div class="badge warn" style="margin-bottom:10px;"><?php echo htmlspecialchars($err); ?></div><?php endif; ?>

<div class="lv-card lv-form">
<form method="post">
  <div class="lv-grid-2">
    <div>
      <label class="lv-muted">Task title</label>
      <input name="title" placeholder="Task title (e.g. Blink + Smile)" required>
    </div>
    <div>
      <label class="lv-muted">Level</label>
      <select name="level">
        <option value="basic">Basic</option>
        <option value="full">Full</option>
      </select>
    </div>
    <div style="grid-column:1/-1;">
      <label class="lv-muted">Instructions</label>
      <textarea name="instructions" rows="4" placeholder="Instructions shown to user (pose/phrase/liveness)..." required></textarea>
    </div>
  </div>
  <div style="height:10px"></div>
  <button class="btn" type="submit" style="min-width:160px;">Add Task</button>
</form>
</div>

<div class="lv-card">
  <div class="lv-subhead">
    <h3 style="margin:0">Existing Tasks</h3>
    <span class="lv-muted">Disable tasks instead of deleting</span>
  </div>
  <div class="table-wrap">
  <table class="lv-table">
    <thead>
      <tr>
        <th style="width:70px;">ID</th>
        <th style="width:110px;">Level</th>
        <th style="width:220px;">Title</th>
        <th>Instructions</th>
        <th style="width:120px;">Active</th>
        <th style="width:160px;">Actions</th>
      </tr>
    </thead>
    <tbody>
      <?php foreach($rows as $r): ?>
      <tr>
        <td><span class="lv-pill">#<?= (int)$r['id'] ?></span></td>
        <td><span class="lv-pill"><?= htmlspecialchars($r['level']) ?></span></td>
        <td><b><?= htmlspecialchars($r['title']) ?></b></td>
        <td><div class="lv-muted" style="line-height:1.35"><?= nl2br(htmlspecialchars($r['instructions'])) ?></div></td>
        <td><?= !empty($r['is_active']) ? '<span class="badge">Yes</span>' : '<span class="badge warn">No</span>' ?></td>
        <td>
          <a class="btn" href="?toggle=<?= (int)$r['id'] ?>">
            <?= !empty($r['is_active']) ? 'Disable' : 'Enable' ?>
          </a>
        </td>
      </tr>
      <?php endforeach; ?>

      <?php if (empty($rows)): ?>
        <tr><td colspan="6"><div class="lv-empty">No tasks yet. Add one above.</div></td></tr>
      <?php endif; ?>
    </tbody>
  </table>
  </div>
</div>

</div>
</div>

<?php require __DIR__ . '/_layout_footer.php'; ?>