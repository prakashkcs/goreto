<?php
require_once __DIR__ . '/_core.php';
admin_require_login();
$pageTitle = 'KYC Review';
$activeNav = 'kyc_review';

$pdo->exec("CREATE TABLE IF NOT EXISTS kyc_submissions (
    id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    level ENUM('basic','full') NOT NULL DEFAULT 'basic',
    full_name VARCHAR(120) NULL,
    video_url VARCHAR(255) NULL,
    id_front VARCHAR(255) NULL,
    id_back  VARCHAR(255) NULL,
    selfie_pic VARCHAR(255) NULL,
    status ENUM('pending','approved','rejected') NOT NULL DEFAULT 'pending',
    admin_note VARCHAR(255) NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    decided_at DATETIME NULL,
    INDEX(user_id), INDEX(status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

// Add missing columns to existing table safely
foreach (['id_front VARCHAR(255) NULL', 'id_back VARCHAR(255) NULL', 'selfie_pic VARCHAR(255) NULL'] as $col) {
  try {
    $pdo->exec("ALTER TABLE kyc_submissions ADD COLUMN $col");
  } catch (Throwable $_) {
  }
}

$msg = '';
$err = '';

if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['submission_id'], $_POST['action'])) {
  $sid = (int) $_POST['submission_id'];
  $action = (string) $_POST['action'];
  $note = trim((string) ($_POST['admin_note'] ?? ''));

  try {
    $sub = $pdo->prepare("SELECT * FROM kyc_submissions WHERE id=? LIMIT 1");
    $sub->execute([$sid]);
    $sub = $sub->fetch();
    if (!$sub)
      throw new Exception("Submission not found.");

    $uid = (int) $sub['user_id'];
    $pdo->beginTransaction();

    if ($action === 'approve') {
      if ($sub['status'] !== 'pending')
        throw new Exception("Only pending submissions can be approved.");
      $pdo->prepare("UPDATE kyc_submissions SET status='approved', admin_note=?, decided_at=NOW() WHERE id=?")
        ->execute([$note ?: null, $sid]);
      $pdo->prepare("UPDATE users SET kyc_status='verified' WHERE id=?")->execute([$uid]);
      try {
        $pdo->prepare("UPDATE user_kyc SET basic_status='verified', full_status='verified' WHERE user_id=?")
          ->execute([$uid]);
      } catch (Throwable $_) {
      }
      $pdo->commit();
      $msg = "Approved KYC #{$sid}";
      send_notif($pdo, $uid, 'kyc_accept', 'KYC Approved ✓', 'Your identity has been verified.');
    } elseif ($action === 'reject') {
      if ($sub['status'] !== 'pending')
        throw new Exception("Only pending submissions can be rejected.");
      $pdo->prepare("UPDATE kyc_submissions SET status='rejected', admin_note=?, decided_at=NOW() WHERE id=?")
        ->execute([$note ?: null, $sid]);
      $pdo->prepare("UPDATE users SET kyc_status='rejected' WHERE id=?")->execute([$uid]);
      try {
        $pdo->prepare("UPDATE user_kyc SET basic_status='rejected', full_status='rejected' WHERE user_id=?")
          ->execute([$uid]);
      } catch (Throwable $_) {
      }
      $pdo->commit();
      $msg = "Rejected KYC #{$sid}";
      send_notif($pdo, $uid, 'kyc_reject', 'KYC Not Approved', $note ?: 'Your submission was rejected. Please re-submit.');
    } elseif ($action === 'deactivate') {
      if ($sub['status'] !== 'approved')
        throw new Exception("Only approved KYC can be deactivated.");
      $pdo->prepare("UPDATE users SET kyc_status='none' WHERE id=?")->execute([$uid]);
      try {
        $pdo->prepare("UPDATE user_kyc SET basic_status='none', full_status='none' WHERE user_id=?")
          ->execute([$uid]);
      } catch (Throwable $_) {
      }
      $pdo->commit();
      $msg = "Deactivated verified KYC for user #{$uid}";
      send_notif($pdo, $uid, 'kyc_reject', 'KYC Deactivated', $note ?: 'Your KYC verification has been deactivated by admin.');
    } else {
      $pdo->rollBack();
      throw new Exception("Invalid action.");
    }
  } catch (Throwable $e) {
    if ($pdo->inTransaction())
      $pdo->rollBack();
    $err = $e->getMessage();
  }
}

$filter = in_array($_GET['filter'] ?? '', ['pending', 'approved', 'rejected', 'all']) ? $_GET['filter'] : 'pending';
$where = $filter !== 'all' ? "WHERE s.status = " . $pdo->quote($filter) : '';

$rows = [];
try {
  $rows = $pdo->query("
        SELECT s.*, u.name AS u_name, u.username AS u_username
        FROM kyc_submissions s
        LEFT JOIN users u ON u.id = s.user_id
        $where ORDER BY s.id DESC LIMIT 500
    ")->fetchAll();
} catch (Throwable $_) {
}

require __DIR__ . '/_layout_header.php';
?>
<div class="section">
  <div class="head">
    <b>KYC Review</b>
    <div class="search">
      <?php foreach (['pending', 'approved', 'rejected', 'all'] as $f): ?>
        <a class="btn <?= $filter === $f ? 'ok' : '' ?>" href="?filter=<?= $f ?>"><?= ucfirst($f) ?></a>
      <?php endforeach; ?>
      <small><?= count($rows) ?> rows</small>
    </div>
  </div>
  <div class="body">
    <?php if ($msg): ?>
      <div class="badge ok" style="margin-bottom:10px"><?= htmlspecialchars($msg) ?></div><?php endif; ?>
    <?php if ($err): ?>
      <div class="badge danger" style="margin-bottom:10px"><?= htmlspecialchars($err) ?></div><?php endif; ?>
    <div class="table-wrap">
      <table>
        <thead>
          <tr>
            <th>ID</th>
            <th>User</th>
            <th>Level</th>
            <th>Full Name</th>
            <th>Documents</th>
            <th>Video / Selfie</th>
            <th>Status</th>
            <th>Actions</th>
          </tr>
        </thead>
        <tbody>
          <?php foreach ($rows as $r): ?>
            <tr>
              <td>#<?= (int) $r['id'] ?></td>
              <td>
                <b><?= htmlspecialchars($r['u_name'] ?? 'User ' . $r['user_id']) ?></b><br>
                <small>ID:<?= (int) $r['user_id'] ?> @<?= htmlspecialchars($r['u_username'] ?? '') ?></small>
              </td>
              <td><span class="badge"><?= htmlspecialchars($r['level']) ?></span></td>
              <td><?= htmlspecialchars($r['full_name'] ?? '') ?></td>
              <td>
                <?php if (!empty($r['id_front'])): ?>
                  <a class="btn" target="_blank" href="<?= htmlspecialchars($r['id_front']) ?>">Front</a>
                <?php endif; ?>
                <?php if (!empty($r['id_back'])): ?>
                  <a class="btn" target="_blank" href="<?= htmlspecialchars($r['id_back']) ?>">Back</a>
                <?php endif; ?>
              </td>
              <td>
                <?php if (!empty($r['selfie_pic'])): ?>
                  <a class="btn" target="_blank" href="<?= htmlspecialchars($r['selfie_pic']) ?>">Selfie</a>
                <?php endif; ?>
                <?php if (!empty($r['video_url'])): ?>
                  <a class="btn" target="_blank" href="<?= htmlspecialchars($r['video_url']) ?>">Video</a>
                <?php endif; ?>
              </td>
              <td>
                <?php $cls = $r['status'] === 'pending' ? 'warn' : ($r['status'] === 'approved' ? 'ok' : 'danger'); ?>
                <span class="badge <?= $cls ?>"><?= htmlspecialchars($r['status']) ?></span>
                <?php if ($r['admin_note']): ?>
                  <br><small><?= htmlspecialchars($r['admin_note']) ?></small>
                <?php endif; ?>
              </td>
              <td>
                <?php if ($r['status'] === 'pending'): ?>
                  <form method="post" style="display:flex;gap:6px;flex-wrap:wrap">
                    <input type="hidden" name="submission_id" value="<?= (int) $r['id'] ?>">
                    <input type="text" name="admin_note" placeholder="Note (optional)"
                      style="padding:4px 8px;border-radius:4px;border:1px solid #334;background:#111;color:#fff;font-size:12px">
                    <button class="btn ok" name="action" value="approve"
                      onclick="return confirm('Approve?')">Approve</button>
                    <button class="btn danger" name="action" value="reject"
                      onclick="return confirm('Reject?')">Reject</button>
                  </form>
                <?php elseif ($r['status'] === 'approved'): ?>
                  <form method="post" style="display:flex;gap:6px;flex-wrap:wrap">
                    <input type="hidden" name="submission_id" value="<?= (int) $r['id'] ?>">
                    <input type="text" name="admin_note" placeholder="Reason (optional)"
                      style="padding:4px 8px;border-radius:4px;border:1px solid #334;background:#111;color:#fff;font-size:12px">
                    <button class="btn danger" name="action" value="deactivate"
                      onclick="return confirm('Deactivate verified KYC for this user?')">Deactivate KYC</button>
                  </form>
                <?php else: ?>
                  <span class="badge">Done</span>
                <?php endif; ?>
              </td>
            </tr>
          <?php endforeach; ?>
          <?php if (empty($rows)): ?>
            <tr>
              <td colspan="8">
                <div style="padding:20px;text-align:center;opacity:.5">No <?= $filter ?> submissions.</div>
              </td>
            </tr>
          <?php endif; ?>
        </tbody>
      </table>
    </div>
  </div>
</div>
<?php require __DIR__ . '/_layout_footer.php'; ?>