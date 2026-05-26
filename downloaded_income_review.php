<?php
require_once __DIR__ . '/_core.php';
admin_require_login();

$pageTitle = 'Income Review';
$activeNav = 'income_review';

$msg = '';
$err = '';

if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['proof_id'], $_POST['action'])) {
    $pid = (int)$_POST['proof_id'];
    $action = (string)$_POST['action'];

    try {
        $st = $pdo->prepare("SELECT * FROM income_proofs WHERE id=? LIMIT 1");
        $st->execute([$pid]);
        $proof = $st->fetch();
        if (!$proof)
            throw new Exception("Income proof not found.");

        if ($proof['status'] !== 'pending')
            throw new Exception("Already processed.");

        $uid = (int)$proof['user_id'];

        $pdo->beginTransaction();

        if ($action === 'approve') {
            $pdo->prepare("UPDATE income_proofs SET status='approved' WHERE id=?")
                ->execute([$pid]);

            // If approved, set the match profile income_status to 'verified'
            $pdo->prepare("UPDATE match_profiles SET income_status='verified' WHERE user_id=?")
                ->execute([$uid]);

            $pdo->commit();
            $msg = "Approved Income Proof #{$pid}";

        }
        elseif ($action === 'reject') {
            $pdo->prepare("UPDATE income_proofs SET status='rejected' WHERE id=?")
                ->execute([$pid]);

            // Optional: count pending proofs for user to see if any are left
            $stPending = $pdo->prepare("SELECT COUNT(*) FROM income_proofs WHERE user_id=? AND status='pending'");
            $stPending->execute([$uid]);
            $pendingCount = $stPending->fetchColumn();

            if ($pendingCount == 0) {
                // If no pending proofs left, set income_status to 'none'
                $pdo->prepare("UPDATE match_profiles SET income_status='none' WHERE user_id=?")
                    ->execute([$uid]);
            }

            $pdo->commit();
            $msg = "Rejected Income Proof #{$pid}";
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
SELECT p.*,
       u.id AS u_id,
       u.name AS u_name,
       u.username AS u_username,
       m.income AS u_income
FROM income_proofs p
LEFT JOIN users u ON u.id = p.user_id
LEFT JOIN match_profiles m ON m.user_id = p.user_id
{$where}
ORDER BY p.id DESC
LIMIT 500
";

$rows = [];
try {
    $rows = $pdo->query($sql)->fetchAll();
}
catch (Throwable $e) {
    $err = "Could not fetch income proofs: " . $e->getMessage();
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
              <td>#<?php echo (int)$r['id']; ?></td>
              <td>
                <div style="display:flex;flex-direction:column;gap:2px;">
                  <b><?php echo htmlspecialchars($r['u_name'] ?? ('User ' . $r['user_id'])); ?></b>
                  <small style="opacity:.75;">ID: <?php echo (int)$r['user_id']; ?> @<?php echo htmlspecialchars($r['u_username'] ?? ''); ?></small>
                </div>
              </td>
              <td><?php echo htmlspecialchars($r['u_income'] ?? 'Not Specified'); ?></td>
              <td>
                <div style="display:flex;flex-direction:column;gap:4px;">
                  <?php if (!empty($r['file_url'])): ?>
                    <?php
        $url = $r['file_url'];
        if (!str_starts_with($url, 'http')) {
            $url = "https://coinzop.com/ekloadmin/" . ltrim($url, '/');
        }
?>
                    <a class="btn" target="_blank" href="<?php echo htmlspecialchars($url); ?>">View Document</a>
                  <?php
    else: ?>
                    <span style="opacity:0.5;">No Document</span>
                  <?php
    endif; ?>
                </div>
              </td>
              <td>
                <?php
    $st = (string)$r['status'];
    $cls = ($st === 'pending') ? 'warn' : (($st === 'approved') ? '' : 'danger');
?>
                <span class="badge <?php echo $cls; ?>"><?php echo htmlspecialchars($st); ?></span>
              </td>
              <td>
                <?php if ($r['status'] === 'pending'): ?>
                  <form method="post" style="display:flex;gap:8px;flex-wrap:wrap;">
                    <input type="hidden" name="proof_id" value="<?php echo (int)$r['id']; ?>">
                    <button class="btn" name="action" value="approve" type="submit"
                      onclick="return confirm('Approve this Income Proof?');">Approve</button>
                    <button class="btn danger" name="action" value="reject" type="submit"
                      onclick="return confirm('Reject this Income Proof?');">Reject</button>
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
