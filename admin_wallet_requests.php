<?php
require_once __DIR__ . '/_core.php';
admin_require_login();

$pageTitle = 'Wallet Requests';
$activeNav = 'wallet_requests';

$pdo->exec("
CREATE TABLE IF NOT EXISTS user_wallets (
  user_id INT NOT NULL PRIMARY KEY,
  balance_coins BIGINT NOT NULL DEFAULT 0,
  locked_coins BIGINT NOT NULL DEFAULT 0,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX (updated_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
");

$pdo->exec("
CREATE TABLE IF NOT EXISTS wallet_transactions (
  id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  user_id INT NOT NULL,
  type VARCHAR(30) NOT NULL,
  direction ENUM('credit','debit') NOT NULL,
  coins BIGINT NOT NULL,
  currency_amount DECIMAL(18,4) NULL,
  currency_code VARCHAR(10) NULL,
  status ENUM('pending','approved','rejected','completed') NOT NULL DEFAULT 'completed',
  reference VARCHAR(64) NULL,
  note VARCHAR(255) NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX (user_id),
  INDEX (type),
  INDEX (status),
  INDEX (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
");

$pdo->exec("
CREATE TABLE IF NOT EXISTS wallet_requests (
  id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  user_id INT NOT NULL,
  req_type ENUM('deposit','withdraw') NOT NULL,
  coins BIGINT NOT NULL,
  currency_amount DECIMAL(18,4) NULL,
  currency_code VARCHAR(10) NULL,
  method VARCHAR(50) NULL,
  proof_url VARCHAR(255) NULL,
  status ENUM('pending','approved','rejected') NOT NULL DEFAULT 'pending',
  admin_note VARCHAR(255) NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  decided_at DATETIME NULL,
  INDEX (user_id),
  INDEX (req_type),
  INDEX (status),
  INDEX (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
");

$pdo->exec("
CREATE TABLE IF NOT EXISTS wallet_deposits (
  id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  user_id INT NOT NULL,
  method_id INT NOT NULL,
  coins BIGINT NOT NULL,
  currency_amount DECIMAL(18,4) NOT NULL,
  currency_code VARCHAR(10) NOT NULL,
  status ENUM('initiated','reviewing','approved','rejected') NOT NULL DEFAULT 'initiated',
  click_count INT NOT NULL DEFAULT 0,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NULL,
  INDEX (user_id),
  INDEX (status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
");

function ensure_wallet(PDO $pdo, int $userId): void {
  $pdo->prepare("INSERT IGNORE INTO user_wallets (user_id, balance_coins, locked_coins) VALUES (?,0,0)")
      ->execute([$userId]);
}

function find_or_create_tx(PDO $pdo, array $req): int {
  $ref = 'req:' . $req['id'];
  $st = $pdo->prepare("SELECT id FROM wallet_transactions WHERE reference=? AND user_id=? ORDER BY id DESC LIMIT 1");
  $st->execute([$ref, (int)$req['user_id']]);
  $id = (int)($st->fetchColumn() ?: 0);
  if ($id > 0) return $id;

  $type = (string)$req['req_type'];
  $direction = ($type === 'deposit') ? 'credit' : 'debit';
  $st2 = $pdo->prepare("INSERT INTO wallet_transactions (user_id,type,direction,coins,currency_amount,currency_code,status,reference,note)
                        VALUES (?,?,?,?,?,?,?,?,?)");
  $st2->execute([
    (int)$req['user_id'],
    $type,
    $direction,
    (int)$req['coins'],
    $req['currency_amount'] !== null ? (float)$req['currency_amount'] : null,
    $req['currency_code'] !== null ? (string)$req['currency_code'] : null,
    'pending',
    $ref,
    null
  ]);
  return (int)$pdo->lastInsertId();
}

$msg = '';
$err = '';

/* ============================================================
   ORIGINAL DEPOSIT / WITHDRAW APPROVE / REJECT (UNCHANGED)
============================================================ */

if (isset($_POST['action'], $_POST['request_id'])) {
  $action = (string)$_POST['action'];
  $rid = (int)$_POST['request_id'];
  $note = trim((string)($_POST['admin_note'] ?? ''));

  try {
    $req = $pdo->prepare("SELECT * FROM wallet_requests WHERE id=? LIMIT 1");
    $req->execute([$rid]);
    $r = $req->fetch();
    if (!$r) throw new Exception("Request not found");

    ensure_wallet($pdo, (int)$r['user_id']);
    $txId = find_or_create_tx($pdo, $r);

    if ($action === 'approve') {
      $pdo->beginTransaction();

      if ($r['status'] !== 'pending') {
        $pdo->rollBack();
        throw new Exception("Request already processed.");
      }

      $coins = (int)$r['coins'];
      $uid = (int)$r['user_id'];

      if ($r['req_type'] === 'deposit') {
        $pdo->prepare("UPDATE user_wallets SET balance_coins = balance_coins + ?, updated_at=NOW() WHERE user_id=?")
            ->execute([$coins, $uid]);
      } else {
        $bal = (int)$pdo->query("SELECT balance_coins FROM user_wallets WHERE user_id=".intval($uid)." LIMIT 1")->fetchColumn();
        if ($bal < $coins) {
          $pdo->rollBack();
          throw new Exception("Insufficient balance. User has {$bal} coins but withdraw requested {$coins}.");
        }
        $pdo->prepare("UPDATE user_wallets SET balance_coins = balance_coins - ?, updated_at=NOW() WHERE user_id=?")
            ->execute([$coins, $uid]);
      }

      $pdo->prepare("UPDATE wallet_requests SET status='approved', admin_note=?, decided_at=NOW() WHERE id=?")
          ->execute([$note ?: null, $rid]);

      $pdo->prepare("UPDATE wallet_transactions SET status='completed', note=? WHERE id=?")
          ->execute([$note ?: null, $txId]);

      $pdo->commit();
      $msg = "Approved request #{$rid}";

    } elseif ($action === 'reject') {
      $pdo->beginTransaction();

      if ($r['status'] !== 'pending') {
        $pdo->rollBack();
        throw new Exception("Request already processed.");
      }

      $pdo->prepare("UPDATE wallet_requests SET status='rejected', admin_note=?, decided_at=NOW() WHERE id=?")
          ->execute([$note ?: null, $rid]);

      $pdo->prepare("UPDATE wallet_transactions SET status='rejected', note=? WHERE id=?")
          ->execute([$note ?: null, $txId]);

      $pdo->commit();
      $msg = "Rejected request #{$rid}";
    }
  } catch (Throwable $e) {
    if ($pdo->inTransaction()) $pdo->rollBack();
    $err = $e->getMessage();
  }
}

/* ============================================================
   QR DEPOSIT APPROVE / REJECT
============================================================ */
if (isset($_POST['qr_action'], $_POST['deposit_id'])) {
  $depositId = (int)$_POST['deposit_id'];

  try {
    $d = $pdo->prepare("SELECT * FROM wallet_deposits WHERE id=? LIMIT 1");
    $d->execute([$depositId]);
    $deposit = $d->fetch();
    if (!$deposit) throw new Exception("Deposit not found");

    if ($_POST['qr_action'] === 'approve_qr') {
      if ($deposit['status'] !== 'reviewing') throw new Exception("Not in reviewing state");

      $pdo->beginTransaction();
      ensure_wallet($pdo,(int)$deposit['user_id']);

      $pdo->prepare("UPDATE user_wallets SET balance_coins = balance_coins + ?, updated_at=NOW() WHERE user_id=?")
          ->execute([(int)$deposit['coins'], (int)$deposit['user_id']]);

      $pdo->prepare("INSERT INTO wallet_transactions (user_id,type,direction,coins,currency_amount,currency_code,status,reference,note)
        VALUES (?,?,?,?,?,?, 'completed', ?, ?)")
        ->execute([
          (int)$deposit['user_id'],
          'deposit',
          'credit',
          (int)$deposit['coins'],
          (float)$deposit['currency_amount'],
          $deposit['currency_code'],
          'qr:'.$depositId,
          'QR deposit approved'
        ]);

      $pdo->prepare("UPDATE wallet_deposits SET status='approved', updated_at=NOW() WHERE id=?")
          ->execute([$depositId]);

      $pdo->commit();
      $msg = "QR Deposit Approved";
    }

    if ($_POST['qr_action'] === 'reject_qr') {
      $pdo->prepare("UPDATE wallet_deposits SET status='rejected', updated_at=NOW() WHERE id=?")
          ->execute([$depositId]);
      $msg = "QR Deposit Rejected";
    }

  } catch(Throwable $e){
    if ($pdo->inTransaction()) $pdo->rollBack();
    $err = $e->getMessage();
  }
}

/* ============================================================
   FETCH NORMAL REQUESTS
============================================================ */
$filter = strtolower(trim((string)($_GET['filter'] ?? 'pending')));
if (!in_array($filter, ['pending','approved','rejected','all'], true)) $filter = 'pending';

$where = "";
if ($filter !== 'all') $where = "WHERE r.status=" . $pdo->quote($filter);

$userCols = [];
$stmt = $pdo->query("SHOW COLUMNS FROM users");
while ($r = $stmt->fetch(PDO::FETCH_ASSOC)) $userCols[] = $r['Field'];

$colName = in_array('name',$userCols,true) ? 'name' : (in_array('full_name',$userCols,true) ? 'full_name' : null);
$colUsername = in_array('username',$userCols,true) ? 'username' : (in_array('user_name',$userCols,true) ? 'user_name' : (in_array('handle',$userCols,true) ? 'handle' : null));

$selectName = $colName ? "u.$colName AS u_name" : "'' AS u_name";
$selectUsername = $colUsername ? "u.$colUsername AS u_username" : "'' AS u_username";

$sql = "
SELECT r.*,
       u.id AS u_id,
       $selectName,
       $selectUsername
FROM wallet_requests r
LEFT JOIN users u ON u.id = r.user_id
{$where}
ORDER BY r.id DESC
LIMIT 500
";

$rows = [];
try { $rows = $pdo->query($sql)->fetchAll(PDO::FETCH_ASSOC); } catch(Throwable $e){}

/* ============================================================
   FETCH QR DEPOSITS (reviewing)
============================================================ */
$qrDeposits = $pdo->query("
SELECT d.*, $selectName, $selectUsername
FROM wallet_deposits d
LEFT JOIN users u ON u.id=d.user_id
WHERE d.status='reviewing'
ORDER BY d.id DESC
")->fetchAll(PDO::FETCH_ASSOC);

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
.lv-empty{padding:14px;border-radius:14px;border:1px dashed rgba(255,255,255,.15);opacity:.8}
.lv-subhead{display:flex;justify-content:space-between;align-items:center;gap:10px;flex-wrap:wrap;margin:4px 0 10px}
</style>

<div class="section">
  <div class="head"><b>Wallet Requests</b></div>
  <div class="body">

  <div class="lv-subhead">
    <span class="lv-pill">Approve / reject wallet activity</span>
    <span class="lv-pill lv-muted">Latest 500</span>
  </div>

  <?php if($msg): ?><div class="badge" style="margin-bottom:10px;"><?= htmlspecialchars($msg) ?></div><?php endif; ?>
  <?php if($err): ?><div class="badge warn" style="margin-bottom:10px;"><?= htmlspecialchars($err) ?></div><?php endif; ?>

<div class="lv-card">
  <div class="lv-subhead">
    <h3 style="margin:0">QR Deposits</h3>
    <span class="lv-pill lv-muted">Reviewing</span>
  </div>

  <div class="table-wrap">
    <table class="lv-table">
      <thead>
        <tr>
          <th style="width:80px;">ID</th>
          <th>User</th>
          <th style="width:120px;">Coins</th>
          <th style="width:170px;">Amount</th>
          <th style="width:220px;">Action</th>
        </tr>
      </thead>
      <tbody>
        <?php foreach($qrDeposits as $d): ?>
          <tr>
            <td><span class="lv-pill">#<?= (int)$d['id'] ?></span></td>
            <td>
              <div style="display:flex;flex-direction:column;gap:2px;">
                <b><?= htmlspecialchars($d['u_name'] ?: ('User '.$d['user_id'])) ?></b>
                <small class="lv-muted">User ID: <?= (int)$d['user_id'] ?></small>
              </div>
            </td>
            <td><b><?= (int)$d['coins'] ?></b></td>
            <td><?= htmlspecialchars($d['currency_amount'].' '.$d['currency_code']) ?></td>
            <td>
              <div class="lv-actions">
                <form method="post">
                  <input type="hidden" name="deposit_id" value="<?= (int)$d['id'] ?>">
                  <button class="btn" name="qr_action" value="approve_qr" type="submit"
                    onclick="return confirm('Approve this QR deposit?');">Approve</button>
                  <button class="btn danger" name="qr_action" value="reject_qr" type="submit"
                    onclick="return confirm('Reject this QR deposit?');">Reject</button>
                </form>
              </div>
            </td>
          </tr>
        <?php endforeach; ?>

        <?php if (empty($qrDeposits)): ?>
          <tr><td colspan="5"><div class="lv-empty">No QR deposits in reviewing right now.</div></td></tr>
        <?php endif; ?>
      </tbody>
    </table>
  </div>
</div>

<div style="height:12px"></div>

<div class="lv-card">
  <div class="lv-subhead">
    <h3 style="margin:0">Manual Requests</h3>
    <div class="lv-actions">
      <a class="btn" href="?filter=pending">Pending</a>
      <a class="btn" href="?filter=approved">Approved</a>
      <a class="btn" href="?filter=rejected">Rejected</a>
      <a class="btn" href="?filter=all">All</a>
      <span class="lv-pill lv-muted"><?php echo count($rows); ?> rows</span>
    </div>
  </div>

  <div class="table-wrap">
    <table class="lv-table">
      <thead>
        <tr>
          <th style="width:80px;">ID</th>
          <th>User</th>
          <th style="width:120px;">Type</th>
          <th style="width:120px;">Coins</th>
          <th>Method</th>
          <th style="width:110px;">Proof</th>
          <th style="width:120px;">Status</th>
          <th>Admin Note</th>
          <th style="width:280px;">Actions</th>
        </tr>
      </thead>
      <tbody>
        <?php foreach($rows as $r): ?>
          <tr>
            <td><span class="lv-pill">#<?= (int)$r['id'] ?></span></td>
            <td>
              <div style="display:flex;flex-direction:column;gap:2px;">
                <b><?= htmlspecialchars(($r['u_name'] ?? '') ?: ('User '.$r['user_id'])) ?></b>
                <small class="lv-muted">ID: <?= (int)$r['user_id'] ?> <?= !empty($r['u_username']) ? '@'.htmlspecialchars($r['u_username']) : '' ?></small>
              </div>
            </td>
            <td><span class="lv-pill"><?= htmlspecialchars($r['req_type']) ?></span></td>
            <td><b><?= (int)$r['coins'] ?></b></td>
            <td><?= htmlspecialchars($r['method'] ?? '') ?></td>
            <td>
              <?php if (!empty($r['proof_url'])): ?>
                <a class="btn" target="_blank" href="<?= htmlspecialchars($r['proof_url']) ?>">View</a>
              <?php else: ?>
                <span class="lv-pill lv-muted">None</span>
              <?php endif; ?>
            </td>
            <td>
              <?php
                $st = (string)($r['status'] ?? '');
                $cls = ($st==='pending') ? 'warn' : (($st==='approved') ? '' : 'danger');
              ?>
              <span class="badge <?= $cls ?>"><?= htmlspecialchars($st) ?></span>
            </td>
            <td><?= htmlspecialchars($r['admin_note'] ?? '') ?></td>
            <td>
              <?php if (($r['status'] ?? '') === 'pending'): ?>
                <form method="post" class="lv-actions" style="gap:8px;flex-wrap:wrap;">
                  <input type="hidden" name="request_id" value="<?= (int)$r['id'] ?>">
                  <input name="admin_note" placeholder="Reason / note" style="min-width:160px;">
                  <button class="btn" name="action" value="approve" type="submit"
                    onclick="return confirm('Approve this request?');">Approve</button>
                  <button class="btn danger" name="action" value="reject" type="submit"
                    onclick="return confirm('Reject this request?');">Reject</button>
                </form>
              <?php else: ?>
                <span class="lv-pill lv-muted">No actions</span>
              <?php endif; ?>
            </td>
          </tr>
        <?php endforeach; ?>

        <?php if (empty($rows)): ?>
          <tr><td colspan="9"><div class="lv-empty">No requests found.</div></td></tr>
        <?php endif; ?>
      </tbody>
    </table>
  </div>
</div>

  </div>
</div>

<?php require __DIR__ . '/_layout_footer.php'; ?>