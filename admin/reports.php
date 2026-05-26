<?php
require_once __DIR__ . '/_core.php';
admin_require_login();
$pageTitle = 'User Reports';
$activeNav = 'reports';

// ── Ensure table has all new columns ─────────────────────────────────────────
$addCols = [
    'report_type' => "ENUM('user','post','system') NOT NULL DEFAULT 'user' AFTER `reported_id`",
    'post_id'     => "INT UNSIGNED NULL DEFAULT NULL AFTER `report_type`",
    'image_url'   => "VARCHAR(500) NULL DEFAULT NULL AFTER `details`",
];
foreach ($addCols as $col => $def) {
    try {
        $colCheck = $pdo->prepare("SHOW COLUMNS FROM `user_reports` LIKE ?");
        $colCheck->execute([$col]);
        if (!$colCheck->fetch()) {
            $pdo->exec("ALTER TABLE `user_reports` ADD COLUMN `$col` $def");
        }
    } catch (Throwable $_) {
    }
}

// ── AJAX endpoint ─────────────────────────────────────────────────────────────
if (isset($_GET['ajax'])) {
    header('Content-Type: application/json');
    if ($_GET['ajax'] === 'update_status') {
        $rid    = (int)($_POST['report_id'] ?? 0);
        $status = $_POST['status'] ?? '';
        $notes  = trim($_POST['admin_notes'] ?? '');
        if (!$rid || !in_array($status, ['pending','reviewed','resolved','dismissed'])) {
            echo json_encode(['status'=>'error','message'=>'Invalid parameters']); exit;
        }
        $pdo->prepare("UPDATE user_reports SET status=?,admin_notes=?,updated_at=NOW() WHERE id=?")->execute([$status,$notes,$rid]);
        echo json_encode(['status'=>'success']); exit;
    }
    if ($_GET['ajax'] === 'delete_report') {
        $rid = (int)($_POST['report_id'] ?? 0);
        if ($rid) $pdo->prepare("DELETE FROM user_reports WHERE id=?")->execute([$rid]);
        echo json_encode(['status'=>'success']); exit;
    }
    echo json_encode(['status'=>'error']); exit;
}

$msg = ''; $err = '';

if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['report_id'])) {
    $rid    = (int)$_POST['report_id'];
    $status = $_POST['status'] ?? '';
    $notes  = trim($_POST['admin_notes'] ?? '');
    if (in_array($status, ['pending','reviewed','resolved','dismissed'])) {
        try {
            $pdo->prepare("UPDATE user_reports SET status=?,admin_notes=?,updated_at=NOW() WHERE id=?")->execute([$status,$notes,$rid]);
            $msg = "Report #{$rid} updated.";
        } catch (Throwable $e) { $err = $e->getMessage(); }
    }
}

// ── Filters ───────────────────────────────────────────────────────────────────
$filter     = in_array($_GET['filter']??'', ['pending','reviewed','resolved','dismissed','all']) ? $_GET['filter'] : 'pending';
$typeFilter = in_array($_GET['type_filter']??'', ['user','post','system','all']) ? $_GET['type_filter'] : 'all';

$whereParts = [];
if ($filter !== 'all') {
    $whereParts[] = "r.status = " . $pdo->quote($filter);
}
if ($typeFilter !== 'all') {
    $whereParts[] = "r.report_type = " . $pdo->quote($typeFilter);
}
$where = $whereParts ? 'WHERE ' . implode(' AND ', $whereParts) : '';

// ── Pending count for checklist widget ───────────────────────────────────────
$pendingCount = 0;
try {
    $pendingCount = (int) $pdo->query("SELECT COUNT(*) FROM user_reports WHERE status='pending'")->fetchColumn();
} catch (Throwable $_) {}

// ── Fetch rows ────────────────────────────────────────────────────────────────
$rows = [];
try {
    $rows = $pdo->query("
        SELECT r.*,
               reporter.name AS reporter_name,
               reported.name AS reported_name
        FROM user_reports r
        LEFT JOIN users reporter ON reporter.id = r.reporter_id
        LEFT JOIN users reported ON reported.id = r.reported_id
        $where
        ORDER BY r.id DESC LIMIT 300
    ")->fetchAll();
} catch (Throwable $e) { $err = $e->getMessage(); }

require __DIR__ . '/_layout_header.php';
?>

<?php /* ── Pending reports checklist widget ── */ ?>
<div class="section" style="margin-bottom:18px">
  <div class="head" style="background:<?= $pendingCount > 0 ? 'rgba(220,38,38,.18)' : 'rgba(15,27,51,.5)' ?>;border-color:<?= $pendingCount > 0 ? '#ef4444' : '#223a66' ?>">
    <b style="display:flex;align-items:center;gap:10px">
      <span>Pending Reports</span>
      <?php if ($pendingCount > 0): ?>
        <span style="background:#ef4444;color:#fff;font-size:13px;font-weight:700;padding:2px 10px;border-radius:20px;min-width:28px;text-align:center"><?= $pendingCount ?></span>
      <?php else: ?>
        <span style="background:#22c55e;color:#fff;font-size:12px;font-weight:600;padding:2px 10px;border-radius:20px">All clear</span>
      <?php endif; ?>
    </b>
    <?php if ($pendingCount > 0): ?>
      <a class="btn" href="?filter=pending" style="font-size:12px">View Pending</a>
    <?php endif; ?>
  </div>
  <div class="body" style="padding:14px 18px">
    <?php if ($pendingCount > 0): ?>
      <p style="margin:0;color:#fbbf24;font-size:14px">
        There <?= $pendingCount === 1 ? 'is' : 'are' ?> <strong><?= $pendingCount ?></strong> pending report<?= $pendingCount === 1 ? '' : 's' ?> awaiting review.
        Use the filters below to review and update each one.
      </p>
    <?php else: ?>
      <p style="margin:0;color:#86efac;font-size:14px">No pending reports — inbox is clear.</p>
    <?php endif; ?>
  </div>
</div>

<div class="section">
  <div class="head">
    <b>User Reports</b>
    <div class="search" style="display:flex;flex-wrap:wrap;gap:6px;align-items:center">
      <?php /* Status filters */ ?>
      <?php foreach (['pending','reviewed','resolved','dismissed','all'] as $f): ?>
        <a class="btn <?= $filter===$f?'ok':'' ?>" href="?filter=<?= $f ?>&type_filter=<?= urlencode($typeFilter) ?>"><?= ucfirst($f) ?></a>
      <?php endforeach; ?>
      <span style="opacity:.4;font-size:11px">|</span>
      <?php /* Type filters */ ?>
      <?php foreach (['all','user','post','system'] as $t): ?>
        <a class="btn <?= $typeFilter===$t?'warn':'' ?>" href="?filter=<?= urlencode($filter) ?>&type_filter=<?= $t ?>"
           style="<?= $typeFilter===$t?'':'opacity:.75' ?>">
          <?= ucfirst($t === 'all' ? 'All Types' : $t) ?>
        </a>
      <?php endforeach; ?>
      <small style="opacity:.55"><?= count($rows) ?> rows</small>
    </div>
  </div>
  <div class="body">
    <?php if ($msg): ?><div class="badge ok" style="margin-bottom:10px"><?= htmlspecialchars($msg) ?></div><?php endif; ?>
    <?php if ($err): ?><div class="badge danger" style="margin-bottom:10px"><?= htmlspecialchars($err) ?></div><?php endif; ?>
    <div class="table-wrap"><table>
      <thead>
        <tr>
          <th>ID</th>
          <th>Reporter</th>
          <th>Reported</th>
          <th>Type</th>
          <th>Reason</th>
          <th>Evidence</th>
          <th>Status</th>
          <th>Date</th>
          <th>Actions</th>
        </tr>
      </thead>
      <tbody>
      <?php foreach ($rows as $r): ?>
        <?php
          $rtype = $r['report_type'] ?? 'user';
          $typeCls = match($rtype) { 'post' => 'warn', 'system' => '', default => 'ok' };
        ?>
        <tr>
          <td>#<?= (int)$r['id'] ?></td>
          <td>
            <b><?= htmlspecialchars($r['reporter_name'] ?? 'User '.$r['reporter_id']) ?></b><br>
            <small>ID:<?= (int)($r['reporter_id']??0) ?></small>
          </td>
          <td>
            <?php if (!empty($r['reported_id']) && (int)$r['reported_id'] > 0): ?>
              <b><?= htmlspecialchars($r['reported_name'] ?? 'User '.($r['reported_id']??'?')) ?></b><br>
              <small>ID:<?= (int)($r['reported_id']??0) ?></small>
            <?php else: ?>
              <span style="opacity:.45">—</span>
            <?php endif; ?>
            <?php if (!empty($r['post_id'])): ?>
              <br><small style="opacity:.6">Post #<?= (int)$r['post_id'] ?></small>
            <?php endif; ?>
          </td>
          <td>
            <span class="badge <?= $typeCls ?>" style="text-transform:uppercase;font-size:11px;letter-spacing:.5px"><?= htmlspecialchars($rtype) ?></span>
          </td>
          <td style="max-width:180px">
            <b><?= htmlspecialchars($r['reason'] ?? '') ?></b>
            <?php if (!empty($r['details'])): ?>
              <br><small><?= htmlspecialchars(substr($r['details'],0,80)) ?><?= strlen($r['details'])>80?'…':'' ?></small>
            <?php elseif (!empty($r['description'])): ?>
              <br><small><?= htmlspecialchars(substr($r['description'],0,80)) ?></small>
            <?php endif; ?>
          </td>
          <td style="text-align:center">
            <?php if (!empty($r['image_url'])): ?>
              <a href="<?= htmlspecialchars($r['image_url']) ?>" target="_blank" title="View full image">
                <img src="<?= htmlspecialchars($r['image_url']) ?>"
                     alt="evidence"
                     style="width:60px;height:60px;object-fit:cover;border-radius:6px;border:1px solid #334;cursor:zoom-in"
                     onerror="this.style.display='none';this.nextElementSibling.style.display='inline'">
                <span style="display:none;font-size:11px;color:#60a5fa">View</span>
              </a>
            <?php else: ?>
              <span style="opacity:.3;font-size:12px">—</span>
            <?php endif; ?>
          </td>
          <td>
            <?php $cls = match($r['status']??'pending') { 'pending'=>'warn', 'resolved'=>'ok', 'dismissed'=>'danger', default=>'' }; ?>
            <span class="badge <?= $cls ?>"><?= htmlspecialchars($r['status']??'pending') ?></span>
            <?php if (!empty($r['admin_notes'])): ?><br><small style="opacity:.7"><?= htmlspecialchars(substr($r['admin_notes'],0,60)) ?><?= strlen($r['admin_notes'])>60?'…':'' ?></small><?php endif; ?>
          </td>
          <td><small><?= htmlspecialchars(substr($r['created_at']??'',0,10)) ?></small></td>
          <td>
            <form method="post" style="display:flex;gap:6px;flex-wrap:wrap;align-items:center">
              <input type="hidden" name="report_id" value="<?= (int)$r['id'] ?>">
              <select name="status" style="padding:4px 8px;border-radius:4px;border:1px solid #334;background:#111;color:#fff;font-size:12px">
                <?php foreach (['pending','reviewed','resolved','dismissed'] as $s): ?>
                  <option value="<?= $s ?>" <?= ($r['status']??'')===$s?'selected':'' ?>><?= ucfirst($s) ?></option>
                <?php endforeach; ?>
              </select>
              <input name="admin_notes" value="<?= htmlspecialchars($r['admin_notes']??'') ?>" placeholder="Notes" style="padding:4px 8px;border-radius:4px;border:1px solid #334;background:#111;color:#fff;font-size:12px;min-width:100px">
              <button class="btn ok" type="submit">Update</button>
              <?php if (!empty($r['image_url'])): ?>
                <a href="<?= htmlspecialchars($r['image_url']) ?>" target="_blank" class="btn" style="font-size:11px;padding:4px 8px">Evidence</a>
              <?php endif; ?>
            </form>
          </td>
        </tr>
      <?php endforeach; ?>
      <?php if (empty($rows)): ?>
        <tr><td colspan="9"><div style="padding:20px;text-align:center;opacity:.5">No <?= $filter !== 'all' ? $filter : '' ?> reports<?= $typeFilter !== 'all' ? ' of type '.$typeFilter : '' ?>.</div></td></tr>
      <?php endif; ?>
      </tbody>
    </table></div>
  </div>
</div>
<?php require __DIR__ . '/_layout_footer.php'; ?>
