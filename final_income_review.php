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
    $st = $pdo->prepare("SELECT income_status FROM match_profiles WHERE user_id=?");
    $st->execute([$uid]);
    $mStatus = $st->fetchColumn();

    if ($mStatus !== 'pending') {
      // It's possible the admin is rejecting something that was already 'approved' or 'none'. 
      // But typically we only process 'pending'. Let's relax the throw if action is reject.
      if ($action === 'approve') {
        throw new Exception("User income is not currently pending verification.");
      }
    }

    $pdo->beginTransaction();

    if ($action === 'approve') {
      $pdo->prepare("UPDATE income_proofs SET status='approved' WHERE user_id=? AND status='pending'")
        ->execute([$uid]);

      // If approved, set the match profile income_status to 'verified'
      $pdo->prepare("UPDATE match_profiles SET income_status='verified' WHERE user_id=?")
        ->execute([$uid]);

      $pdo->commit();

      // Notify user
      try {
        require_once __DIR__ . '/../api/v1/notification_helper.php';
        send_app_notification($pdo, $uid, 0, 'income_accept', 'Income Review Approved', 'Your income proof submission has been approved.');
      }
      catch (Throwable $notifErr) {
        // Log or ignore notification errors to not block the main action
        error_log("FCM Notification Error: " . $notifErr->getMessage());
      }

      $msg = "Approved Income for User #{$uid}";

    }
    elseif ($action === 'reject') {
      $pdo->prepare("UPDATE income_proofs SET status='rejected' WHERE user_id=? AND status='pending'")
        ->execute([$uid]);

      // Make them start over
      $pdo->prepare("UPDATE match_profiles SET income_status='none' WHERE user_id=?")
        ->execute([$uid]);

      $pdo->commit();

      // Notify user
      try {
        require_once __DIR__ . '/../api/v1/notification_helper.php';
        send_app_notification($pdo, $uid, 0, 'income_reject', 'Income Review Rejected', 'Your income proof submission was rejected.');
      }
      catch (Throwable $notifErr) {
        error_log("FCM Notification Error: " . $notifErr->getMessage());
      }

      $msg = "Rejected Income for User #{$uid}";
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
if ($filter === 'pending')
  $where = "WHERE m.income_status='pending'";
elseif ($filter === 'approved')
  $where = "WHERE m.income_status='verified'";
elseif ($filter === 'rejected')
  $where = "WHERE m.income_status='none' AND p.id IS NOT NULL";

$sql = "
SELECT m.user_id,
       m.income_status AS status,
       GROUP_CONCAT(p.file_url SEPARATOR ',') as file_urls,
       COUNT(p.id) as proof_count,
       u.id AS u_id,
       u.name AS u_name,
       m.income
FROM match_profiles m
LEFT JOIN users u ON u.id = m.user_id
LEFT JOIN income_proofs p ON p.user_id = m.user_id 
       AND p.status = (CASE WHEN m.income_status='pending' THEN 'pending' ELSE 'approved' END)
";

if ($where !== "") {
  $sql .= $where;
}
else if ($filter === 'all') {
  // Show everyone who has attempted income verification
  $sql .= " WHERE m.income_status IN ('pending', 'verified') OR p.id IS NOT NULL ";
}

$sql .= " GROUP BY m.user_id, m.income_status, u.id, u.name, m.income ORDER BY m.user_id DESC LIMIT 500";

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
                <span class="badge" style="background:rgba(0,0,0,0.1);color:#333;font-size:14px;border:1px solid rgba(0,0,0,0.2);">
                  Npr. <?php echo htmlspecialchars($r['income'] ?? '0'); ?>
                </span>
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
        $url = "https://coinzop.com/ekloadmin/api/v1/" . ltrim($url, '/');
      }
?>
                    <a class="btn" target="_blank" href="<?php echo htmlspecialchars($url); ?>">Document <?php echo $idx + 1; ?></a>
                  <?php
    endforeach;
  else: ?>
                    <span class="badge warn">No Documents Provided</span>
                  <?php
  endif; ?>
                </div>
              </td>
              <td>
                <?php
  $st = (string)$r['status'];
  $cls = ($st === 'pending') ? 'warn' : (($st === 'verified') ? '' : 'danger');
?>
                <span class="badge <?php echo $cls; ?>"><?php echo htmlspecialchars($st); ?> (<?php echo (int)$r['proof_count']; ?> docs)</span>
              </td>
              <td>
                <?php if ($r['status'] === 'pending'): ?>
                  <form method="post" style="display:flex;gap:8px;flex-wrap:wrap;">
                    <input type="hidden" name="user_id" value="<?php echo (int)$r['user_id']; ?>">
                    <button class="btn" name="action" value="approve" type="submit"
                      onclick="return confirm('Approve income update for User #<?php echo (int)$r['user_id']; ?>?');">Approve</button>
                    <button class="btn danger" name="action" value="reject" type="submit"
                      onclick="return confirm('Reject income update for User #<?php echo (int)$r['user_id']; ?>?');">Reject</button>
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
            <tr><td colspan="6"><span class="badge warn">No income verification requests found.</span></td></tr>
          <?php
endif; ?>
        </tbody>
      </table>
    </div>

  </div>
</div>

<?php require __DIR__ . '/_layout_footer.php'; ?>
