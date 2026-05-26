<?php
require_once __DIR__ . '/_core.php';
admin_require_login();

$pageTitle = 'Income Review';
$activeNav = 'income_review';

$msg = '';
$err = '';

if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['user_id'], $_POST['action'])) {
  $uid = (int)$_POST['user_id'];
  $action = (string)$_POST['action'];

  try {
    $st = $pdo->prepare("SELECT COUNT(*) FROM income_proofs WHERE user_id=? AND status='pending'");
    $st->execute([$uid]);
    $pendingCount = $st->fetchColumn();

    if ($pendingCount == 0)
      throw new Exception("No pending proofs found for this user.");

    $pdo->beginTransaction();

    if ($action === 'approve') {
      $pdo->prepare("UPDATE income_proofs SET status='approved' WHERE user_id=? AND status='pending'")
        ->execute([$uid]);

      // If approved, set the match profile income_status to 'verified'
      $pdo->prepare("UPDATE match_profiles SET income_status='verified' WHERE user_id=?")
        ->execute([$uid]);

      $pdo->commit();
      require_once __DIR__ . '/../api/v1/notification_helper.php';
      send_app_notification($pdo, $uid, 0, 'income_accept', 'Income Review Approved', 'Your income proof submission has been approved.');
      $msg = "Approved {$pendingCount} Income Proof(s) for User #{$uid}";

    }
    elseif ($action === 'reject') {
      $pdo->prepare("UPDATE income_proofs SET status='rejected' WHERE user_id=? AND status='pending'")
        ->execute([$uid]);

      // Since we rejected all pendings, check if any approved exist. If not, set to none.
      // (Usually if rejecting the latest batch we reset to 'none')
      $pdo->prepare("UPDATE match_profiles SET income_status='none' WHERE user_id=?")
        ->execute([$uid]);

      $pdo->commit();
      require_once __DIR__ . '/../api/v1/notification_helper.php';
      send_app_notification($pdo, $uid, 0, 'income_reject', 'Income Review Rejected', 'Your income proof submission was rejected.');
      $msg = "Rejected {$pendingCount} Income Proof(s) for User #{$uid}";
    }
    else {
      $pdo->rollBack();
      throw new Exception("Invalid action.");
    }

  }
  catch (Throwable $e) {
    if ($pdo->inTransaction())
      $pdo->rollBack();
    $err = $e->getMessage();
  }
}

$filter = strtolower(trim((string)($_GET['filter'] ?? 'pending')));
if (!in_array($filter, ['pending', 'approved', 'rejected', 'all'], true))
  $filter = 'pending';

$where = "";
if ($filter !== 'all')
  $where = "WHERE p.status=" . $pdo->quote($filter);

$sql = "
SELECT p.user_id,
       p.status,
       GROUP_CONCAT(p.file_url SEPARATOR ',') as file_urls,
       count(p.id) as proof_count,
       u.id AS u_id,
       u.name AS u_name
FROM income_proofs p
LEFT JOIN users u ON u.id = p.user_id
{$where}
GROUP BY p.user_id, p.status
ORDER BY p.id DESC
LIMIT 500
";

$rows = [];
try {
  $rows = $pdo->query($sql)->fetchAll();
}
catch (Throwable $e) {
  $err = "DB Error: " . $e->getMessage() . " | SQL: " . $sql;
}

require __DIR__ . '/_layout_header.php';
?>

<div class="section">
  <div class="head">
    <b>Income Review</b>
    <div class="search">
      <a class="btn" href="?filter=pending">Pending</a>
      <a class="btn" href="?filter=approved">Approved</a>
      <a class="btn" href="?filter=rejected">Rejected</a>
      <a class="btn" href="?filter=all">All</a>
      <small><?php echo count($rows); ?> rows</small>
    </div>
  </div>

  <div class="body">
    <?php if ($msg): ?><div class="badge" style="margin-bottom:10px;"><?php echo htmlspecialchars($msg); ?></div><?php
endif; ?>
    <?php if ($err): ?><div class="badge warn" style="margin-bottom:10px;"><?php echo htmlspecialchars($err); ?></div><?php
endif; ?>

    <div class="table-wrap">
      <table>
        <thead>
          <tr>
            <th style="width:90px;">ID</th>
            <th>User</th>
            <th>Claimed Income</th>
            <th>Document</th>
            <th style="width:120px;">Status</th>
            <th style="width:180px;">Actions</th>
          </tr>
        </thead>
        <tbody>
          <?php foreach ($rows as $r): ?>
            <tr>
              <td>#<?php echo (int)$r['user_id']; ?></td>
              <td>
                <div style="display:flex;flex-direction:column;gap:2px;">
                  <b><?php echo htmlspecialchars($r['u_name'] ?? ('User ' . $r['user_id'])); ?></b>
                  <small style="opacity:.75;">ID: <?php echo (int)$r['user_id']; ?></small>
                </div>
              </td>
              <td>
                <div style="display:flex;flex-direction:column;gap:4px;">
                  <?php if (!empty($r['file_urls'])):
    $urls = explode(',', $r['file_urls']);
    foreach ($urls as $idx => $url):
      $url = trim($url);
      if (empty($url))
        continue;
      if (!str_starts_with($url, 'http')) {
        // Prepend api/v1/ so local images load properly
        $url = "https://goreto.org/ekloadmin/api/v1/" . ltrim($url, '/');
      }
?>
                    <a class="btn" target="_blank" href="<?php echo htmlspecialchars($url); ?>">Document <?php echo $idx + 1; ?></a>
                  <?php
    endforeach;
  else: ?>
                    <span style="opacity:0.5;">No Documents</span>
                  <?php
  endif; ?>
                </div>
              </td>
              <td>
                <?php
  $st = (string)$r['status'];
  $cls = ($st === 'pending') ? 'warn' : (($st === 'approved') ? '' : 'danger');
?>
                <span class="badge <?php echo $cls; ?>"><?php echo htmlspecialchars($st); ?> (<?php echo (int)$r['proof_count']; ?> docs)</span>
              </td>
              <td>
                <?php if ($r['status'] === 'pending'): ?>
                  <form method="post" style="display:flex;gap:8px;flex-wrap:wrap;">
                    <input type="hidden" name="user_id" value="<?php echo (int)$r['user_id']; ?>">
                    <button class="btn" name="action" value="approve" type="submit"
                      onclick="return confirm('Approve ALL pending proofs for User #<?php echo (int)$r['user_id']; ?>?');">Approve All</button>
                    <button class="btn danger" name="action" value="reject" type="submit"
                      onclick="return confirm('Reject ALL pending proofs for User #<?php echo (int)$r['user_id']; ?>?');">Reject All</button>
                  </form>
                <?php
  else: ?>
                  <span class="badge">No actions</span>
                <?php
  endif; ?>
              </td>
            </tr>
          <?php
endforeach; ?>
          <?php if (empty($rows)): ?>
            <tr><td colspan="6"><span class="badge warn">No income proofs found.</span></td></tr>
          <?php
endif; ?>
        </tbody>
      </table>
    </div>

  </div>
</div>

<?php require __DIR__ . '/_layout_footer.php'; ?>
