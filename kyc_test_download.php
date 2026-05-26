<?php
require_once __DIR__ . '/_core.php';
admin_require_login();

$pageTitle = 'KYC Review';
$activeNav = 'kyc_review';

$pdo->exec("
CREATE TABLE IF NOT EXISTS user_kyc (
  user_id INT NOT NULL PRIMARY KEY,
  basic_status ENUM('none','pending','approved','rejected') NOT NULL DEFAULT 'none',
  full_status  ENUM('none','pending','approved','rejected') NOT NULL DEFAULT 'none',
  full_name VARCHAR(120) NULL,
  basic_video_url VARCHAR(255) NULL,
  full_video_url VARCHAR(255) NULL,
  basic_task_id INT NULL,
  full_task_id INT NULL,
  basic_submitted_at DATETIME NULL,
  full_submitted_at DATETIME NULL,
  basic_admin_note VARCHAR(255) NULL,
  full_admin_note VARCHAR(255) NULL,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
");

$pdo->exec("
CREATE TABLE IF NOT EXISTS kyc_submissions (
  id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  user_id INT NOT NULL,
  level ENUM('basic','full') NOT NULL,
  task_id INT NULL,
  full_name VARCHAR(120) NULL,
  video_url VARCHAR(255) NOT NULL,
  status ENUM('pending','approved','rejected') NOT NULL DEFAULT 'pending',
  admin_note VARCHAR(255) NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  decided_at DATETIME NULL,
  INDEX (user_id),
  INDEX (level),
  INDEX (status),
  INDEX (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
");

$msg = '';
$err = '';

if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['verification_id'], $_POST['action'])) {
  $sid = (int)$_POST['verification_id'];
  $action = (string)$_POST['action'];
  $note = trim((string)($_POST['admin_note'] ?? ''));

  try {
    $st = $pdo->prepare("SELECT * FROM kyc_verifications WHERE id=? LIMIT 1");
    $st->execute([$sid]);
    $sub = $st->fetch();
    if (!$sub)
      throw new Exception("Verification not found.");

    if ($sub['status'] !== 'pending')
      throw new Exception("Already processed.");

    $uid = (int)$sub['user_id'];

    $pdo->beginTransaction();

    if ($action === 'approve') {
      $pdo->prepare("UPDATE kyc_verifications SET status='approved' WHERE id=?")
        ->execute([$sid]);

      $pdo->prepare("UPDATE users SET kyc_status='approved' WHERE id=?")
        ->execute([$uid]);

      $pdo->commit();
      require_once __DIR__ . '/../../notification_helper.php';
      send_app_notification($pdo, $uid, 0, 'kyc_accept', 'KYC Approved', 'Your identity verification has been approved.');
      $msg = "Approved KYC #{$sid}";

    }
    elseif ($action === 'reject') {
      $pdo->prepare("UPDATE kyc_verifications SET status='rejected' WHERE id=?")
        ->execute([$sid]);

      $pdo->prepare("UPDATE users SET kyc_status='rejected' WHERE id=?")
        ->execute([$uid]);

      $pdo->commit();
      require_once __DIR__ . '/../../notification_helper.php';
      send_app_notification($pdo, $uid, 0, 'kyc_reject', 'KYC Rejected', 'Your identity verification was rejected. Please try again.');
      $msg = "Rejected KYC #{$sid}";
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
  $where = "WHERE v.status=" . $pdo->quote($filter);

$sql = "
SELECT v.*,
       u.id AS u_id,
       u.name AS u_name,
       u.username AS u_username
FROM kyc_verifications v
LEFT JOIN users u ON u.id = v.user_id
{$where}
ORDER BY v.id DESC
LIMIT 500
";
$rows = [];
try {
  $rows = $pdo->query($sql)->fetchAll();
}
catch (Throwable $e) {
}

require __DIR__ . '/_layout_header.php';
?>

<div class="section">
  <div class="head">
    <b>KYC Review</b>
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
            <th>First Name</th>
            <th>Last Name</th>
            <th>ID Documents</th>
            <th>Selfie / Video</th>
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
              <td><?php echo htmlspecialchars($r['first_name'] ?? ''); ?></td>
              <td><?php echo htmlspecialchars($r['last_name'] ?? ''); ?></td>
              <td>
                <div style="display:flex;flex-direction:column;gap:4px;">
                  <?php if (!empty($r['id_front'])): ?>
                    <a class="btn" target="_blank" href="<?php echo htmlspecialchars($r['id_front']); ?>">Front ID</a>
                  <?php
  endif; ?>
                  <?php if (!empty($r['id_back'])): ?>
                    <a class="btn" target="_blank" href="<?php echo htmlspecialchars($r['id_back']); ?>">Back ID</a>
                  <?php
  endif; ?>
                </div>
              </td>
              <td>
                <div style="display:flex;flex-direction:column;gap:4px;">
                  <?php if (!empty($r['selfie_pic'])): ?>
                    <a class="btn" target="_blank" href="<?php echo htmlspecialchars($r['selfie_pic']); ?>">Selfie Pic</a>
                  <?php
  endif; ?>
                  <?php if (!empty($r['liveness_video'])): ?>
                    <video width="160" height="120" controls preload="metadata" style="background-color: #000; border-radius: 4px;">
                      <source src="<?php echo htmlspecialchars($r['liveness_video']); ?>#t=0.1" type="video/mp4">
                      Your browser does not support the video tag.
                    </video>
                    <a class="btn" target="_blank" href="<?php echo htmlspecialchars($r['liveness_video']); ?>" style="margin-top: 4px;">Open Video Full</a>
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
                    <input type="hidden" name="verification_id" value="<?php echo (int)$r['id']; ?>">
                    <button class="btn" name="action" value="approve" type="submit"
                      onclick="return confirm('Approve this KYC submission?');">Approve</button>
                    <button class="btn danger" name="action" value="reject" type="submit"
                      onclick="return confirm('Reject this KYC submission?');">Reject</button>
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
            <tr><td colspan="8"><span class="badge warn">No submissions found.</span></td></tr>
          <?php
endif; ?>
        </tbody>
      </table>
    </div>

  </div>
</div>

<?php require __DIR__ . '/_layout_footer.php'; ?>
