<?php
require_once __DIR__ . '/_core.php';
admin_require_login();
$pageTitle = 'Income Review';
$activeNav = 'income_review';

$msg = ''; $err = '';

if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['user_id'], $_POST['action'])) {
    $uid    = (int)$_POST['user_id'];
    $action = (string)$_POST['action'];
    try {
        $pending = (int)$pdo->prepare("SELECT COUNT(*) FROM income_proofs WHERE user_id=? AND status='pending'")->execute([$uid])
            ? $pdo->query("SELECT COUNT(*) FROM income_proofs WHERE user_id=$uid AND status='pending'")->fetchColumn() : 0;
        if (!$pending) throw new Exception("No pending proofs for this user.");

        $pdo->beginTransaction();
        if ($action === 'approve') {
            $pdo->prepare("UPDATE income_proofs SET status='approved' WHERE user_id=? AND status='pending'")->execute([$uid]);
            $pdo->prepare("UPDATE match_profiles SET income_status='verified' WHERE user_id=?")->execute([$uid]);
            $pdo->commit();
            send_notif($pdo, $uid, 'income_accept', 'Income Approved', 'Your income proof has been approved.');
            $msg = "Approved {$pending} proof(s) for User #{$uid}";
        } elseif ($action === 'reject') {
            $pdo->prepare("UPDATE income_proofs SET status='rejected' WHERE user_id=? AND status='pending'")->execute([$uid]);
            $pdo->prepare("UPDATE match_profiles SET income_status='none' WHERE user_id=?")->execute([$uid]);
            $pdo->commit();
            send_notif($pdo, $uid, 'income_reject', 'Income Rejected', 'Your income proof was rejected.');
            $msg = "Rejected {$pending} proof(s) for User #{$uid}";
        } else {
            $pdo->rollBack();
        }
    } catch (Throwable $e) {
        if ($pdo->inTransaction()) $pdo->rollBack();
        $err = $e->getMessage();
    }
}

$filter = in_array($_GET['filter']??'', ['pending','approved','rejected','all']) ? $_GET['filter'] : 'pending';
$where  = $filter !== 'all' ? "WHERE p.status=".$pdo->quote($filter) : '';

$rows = [];
try {
    $rows = $pdo->query("
        SELECT p.user_id, p.status,
               GROUP_CONCAT(p.file_url SEPARATOR ',') AS file_urls,
               COUNT(p.id) AS proof_count,
               u.name AS u_name
        FROM income_proofs p
        LEFT JOIN users u ON u.id = p.user_id
        $where
        GROUP BY p.user_id, p.status
        ORDER BY MAX(p.id) DESC LIMIT 500
    ")->fetchAll();
} catch (Throwable $e) { $err = $e->getMessage(); }

require __DIR__ . '/_layout_header.php';
?>
<div class="section">
  <div class="head">
    <b>Income Review</b>
    <div class="search">
      <?php foreach (['pending','approved','rejected','all'] as $f): ?>
        <a class="btn <?= $filter===$f?'ok':'' ?>" href="?filter=<?= $f ?>"><?= ucfirst($f) ?></a>
      <?php endforeach; ?>
      <small><?= count($rows) ?> rows</small>
    </div>
  </div>
  <div class="body">
    <?php if ($msg): ?><div class="badge ok" style="margin-bottom:10px"><?= htmlspecialchars($msg) ?></div><?php endif; ?>
    <?php if ($err): ?><div class="badge danger" style="margin-bottom:10px"><?= htmlspecialchars($err) ?></div><?php endif; ?>
    <div class="table-wrap"><table>
      <thead><tr><th>User ID</th><th>User</th><th>Documents</th><th>Status</th><th>Actions</th></tr></thead>
      <tbody>
      <?php foreach ($rows as $r): ?>
        <tr>
          <td>#<?= (int)$r['user_id'] ?></td>
          <td><b><?= htmlspecialchars($r['u_name'] ?? 'User '.$r['user_id']) ?></b></td>
          <td>
            <?php if (!empty($r['file_urls'])):
                foreach (explode(',', $r['file_urls']) as $i => $url):
                    $url = trim($url);
                    if (!$url) continue;
                    if (!str_starts_with($url, 'http')) $url = 'https://goreto.org/ekloadmin/api/v1/'.ltrim($url,'/');
            ?>
              <a class="btn" target="_blank" href="<?= htmlspecialchars($url) ?>">Doc <?= $i+1 ?></a>
            <?php endforeach; else: ?><span style="opacity:.5">None</span><?php endif; ?>
          </td>
          <td>
            <?php $cls = $r['status']==='pending'?'warn':($r['status']==='approved'?'ok':'danger'); ?>
            <span class="badge <?= $cls ?>"><?= htmlspecialchars($r['status']) ?> (<?= (int)$r['proof_count'] ?>)</span>
          </td>
          <td>
            <?php if ($r['status'] === 'pending'): ?>
              <form method="post" style="display:flex;gap:8px">
                <input type="hidden" name="user_id" value="<?= (int)$r['user_id'] ?>">
                <button class="btn ok" name="action" value="approve" onclick="return confirm('Approve all for User #<?= (int)$r['user_id'] ?>?')">Approve All</button>
                <button class="btn danger" name="action" value="reject" onclick="return confirm('Reject all for User #<?= (int)$r['user_id'] ?>?')">Reject All</button>
              </form>
            <?php else: ?><span class="badge">—</span><?php endif; ?>
          </td>
        </tr>
      <?php endforeach; ?>
      <?php if (empty($rows)): ?><tr><td colspan="5"><div style="padding:20px;text-align:center;opacity:.5">No income proofs found.</div></td></tr><?php endif; ?>
      </tbody>
    </table></div>
  </div>
</div>
<?php require __DIR__ . '/_layout_footer.php'; ?>
