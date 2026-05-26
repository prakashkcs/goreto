<?php
require_once __DIR__ . '/_core.php';
admin_require_login();

$pageTitle = 'Wallet Requests';
$activeNav = 'wallet_requests';

foreach (["
CREATE TABLE IF NOT EXISTS user_wallets (
  user_id INT NOT NULL PRIMARY KEY,
  balance_coins BIGINT NOT NULL DEFAULT 0,
  locked_coins BIGINT NOT NULL DEFAULT 0,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
","
CREATE TABLE IF NOT EXISTS wallet_transactions (
  id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  user_id INT NOT NULL, type VARCHAR(30) NOT NULL,
  direction ENUM('credit','debit') NOT NULL,
  coins BIGINT NOT NULL,
  currency_amount DECIMAL(18,4) NULL,
  currency_code VARCHAR(10) NULL,
  status ENUM('pending','approved','rejected','completed') NOT NULL DEFAULT 'completed',
  reference VARCHAR(64) NULL, note VARCHAR(255) NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX (user_id), INDEX (type), INDEX (status), INDEX (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
","
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
  INDEX (user_id), INDEX (req_type), INDEX (status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
","
CREATE TABLE IF NOT EXISTS wallet_deposits (
  id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  user_id INT NOT NULL, method_id INT NOT NULL,
  coins BIGINT NOT NULL,
  currency_amount DECIMAL(18,4) NOT NULL,
  currency_code VARCHAR(10) NOT NULL,
  status ENUM('initiated','reviewing','approved','rejected') NOT NULL DEFAULT 'initiated',
  click_count INT NOT NULL DEFAULT 0,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NULL,
  INDEX (user_id), INDEX (status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
"] as $ddl) { try { $pdo->exec($ddl); } catch (Throwable $_) {} }

function wr_ensure_wallet(PDO $pdo, int $uid): void {
    try { $pdo->prepare("INSERT IGNORE INTO user_wallets (user_id,balance_coins,locked_coins) VALUES (?,0,0)")->execute([$uid]); } catch (Throwable $_) {}
}

function wr_find_or_create_tx(PDO $pdo, array $req): int {
    $ref = 'req:'.$req['id'];
    $st  = $pdo->prepare("SELECT id FROM wallet_transactions WHERE reference=? AND user_id=? ORDER BY id DESC LIMIT 1");
    $st->execute([$ref,(int)$req['user_id']]);
    $id = (int)($st->fetchColumn() ?: 0);
    if ($id) return $id;
    $dir = $req['req_type']==='deposit' ? 'credit' : 'debit';
    $pdo->prepare("INSERT INTO wallet_transactions (user_id,type,direction,coins,currency_amount,currency_code,status,reference,note) VALUES (?,?,?,?,?,?,'pending',?,?)")
        ->execute([(int)$req['user_id'],$req['req_type'],$dir,(int)$req['coins'],$req['currency_amount']??null,$req['currency_code']??null,$ref,null]);
    return (int)$pdo->lastInsertId();
}

$msg = ''; $err = '';

// Normal request approve/reject
if (isset($_POST['action'], $_POST['request_id'])) {
    $action = (string)$_POST['action'];
    $rid    = (int)$_POST['request_id'];
    $note   = trim($_POST['admin_note'] ?? '');
    try {
        $st = $pdo->prepare("SELECT * FROM wallet_requests WHERE id=? LIMIT 1");
        $st->execute([$rid]);
        $r = $st->fetch();
        if (!$r) throw new Exception("Request not found");
        wr_ensure_wallet($pdo, (int)$r['user_id']);
        $txId = wr_find_or_create_tx($pdo, $r);
        if ($action === 'approve') {
            $pdo->beginTransaction();
            if ($r['status'] !== 'pending') { $pdo->rollBack(); throw new Exception("Already processed."); }
            $coins = (int)$r['coins'];
            $uid   = (int)$r['user_id'];
            if ($r['req_type'] === 'deposit') {
                $pdo->prepare("UPDATE user_wallets SET balance_coins=balance_coins+?,updated_at=NOW() WHERE user_id=?")->execute([$coins,$uid]);
            } else {
                $bal = (int)$pdo->query("SELECT balance_coins FROM user_wallets WHERE user_id=".intval($uid)." LIMIT 1")->fetchColumn();
                if ($bal < $coins) { $pdo->rollBack(); throw new Exception("Insufficient balance ({$bal} coins)."); }
                $pdo->prepare("UPDATE user_wallets SET balance_coins=balance_coins-?,updated_at=NOW() WHERE user_id=?")->execute([$coins,$uid]);
            }
            $pdo->prepare("UPDATE wallet_requests SET status='approved',admin_note=?,decided_at=NOW() WHERE id=?")->execute([$note?:null,$rid]);
            $pdo->prepare("UPDATE wallet_transactions SET status='completed',note=? WHERE id=?")->execute([$note?:null,$txId]);
            $pdo->commit();
            send_notif($pdo,$uid,'wallet_accept',ucfirst($r['req_type']).' Approved',"Your {$r['req_type']} of {$coins} coins was approved.");
            $msg = "Approved request #{$rid}";
        } elseif ($action === 'reject') {
            $pdo->beginTransaction();
            if ($r['status'] !== 'pending') { $pdo->rollBack(); throw new Exception("Already processed."); }
            $pdo->prepare("UPDATE wallet_requests SET status='rejected',admin_note=?,decided_at=NOW() WHERE id=?")->execute([$note?:null,$rid]);
            $pdo->prepare("UPDATE wallet_transactions SET status='rejected',note=? WHERE id=?")->execute([$note?:null,$txId]);
            $pdo->commit();
            send_notif($pdo,(int)$r['user_id'],'wallet_reject',ucfirst($r['req_type']).' Rejected',$note?:'Your request was rejected.');
            $msg = "Rejected request #{$rid}";
        }
    } catch (Throwable $e) { if ($pdo->inTransaction()) $pdo->rollBack(); $err = $e->getMessage(); }
}

// QR deposit approve/reject
if (isset($_POST['qr_action'], $_POST['deposit_id'])) {
    $did = (int)$_POST['deposit_id'];
    try {
        $st = $pdo->prepare("SELECT * FROM wallet_deposits WHERE id=? LIMIT 1");
        $st->execute([$did]);
        $d = $st->fetch();
        if (!$d) throw new Exception("Deposit not found");
        if ($_POST['qr_action'] === 'approve_qr') {
            if ($d['status'] !== 'reviewing') throw new Exception("Not in reviewing state");
            $pdo->beginTransaction();
            wr_ensure_wallet($pdo,(int)$d['user_id']);
            $pdo->prepare("UPDATE user_wallets SET balance_coins=balance_coins+?,updated_at=NOW() WHERE user_id=?")->execute([(int)$d['coins'],(int)$d['user_id']]);
            $pdo->prepare("INSERT INTO wallet_transactions (user_id,type,direction,coins,currency_amount,currency_code,status,reference,note) VALUES (?,?,?,?,?,?,'completed',?,?)")
                ->execute([(int)$d['user_id'],'deposit','credit',(int)$d['coins'],(float)$d['currency_amount'],$d['currency_code'],'qr:'.$did,'QR deposit approved']);
            $pdo->prepare("UPDATE wallet_deposits SET status='approved',updated_at=NOW() WHERE id=?")->execute([$did]);
            $pdo->commit();
            send_notif($pdo,(int)$d['user_id'],'deposit_accept','QR Deposit Approved',"Your deposit of {$d['coins']} coins was approved.");
            $msg = "QR Deposit #{$did} approved";
        } elseif ($_POST['qr_action'] === 'reject_qr') {
            $pdo->beginTransaction();
            $pdo->prepare("UPDATE wallet_deposits SET status='rejected',updated_at=NOW() WHERE id=?")->execute([$did]);
            $pdo->prepare("INSERT INTO wallet_transactions (user_id,type,direction,coins,currency_amount,currency_code,status,reference,note) VALUES (?,?,?,?,?,?,'rejected',?,?)")
                ->execute([(int)$d['user_id'],'deposit','credit',(int)$d['coins'],(float)$d['currency_amount'],$d['currency_code'],'qr:'.$did,'QR deposit rejected']);
            $pdo->commit();
            send_notif($pdo,(int)$d['user_id'],'deposit_reject','QR Deposit Rejected',"Your deposit of {$d['coins']} coins was rejected.");
            $msg = "QR Deposit #{$did} rejected";
        }
    } catch (Throwable $e) { if ($pdo->inTransaction()) $pdo->rollBack(); $err = $e->getMessage(); }
}

// Detect user columns
$ucols = [];
try { foreach ($pdo->query("SHOW COLUMNS FROM users")->fetchAll() as $r) $ucols[] = $r['Field']; } catch (Throwable $_) {}
$sName     = in_array('name',$ucols)     ? "u.name AS u_name"     : "'' AS u_name";
$sUsername = in_array('username',$ucols) ? "u.username AS u_username" : "'' AS u_username";

$filter = in_array($_GET['filter']??'',['pending','approved','rejected','all']) ? $_GET['filter'] : 'pending';
$where  = $filter !== 'all' ? "WHERE r.status=".$pdo->quote($filter) : '';
$rows   = [];
try {
    $rows = $pdo->query("SELECT r.*,$sName,$sUsername FROM wallet_requests r LEFT JOIN users u ON u.id=r.user_id $where ORDER BY r.id DESC LIMIT 500")->fetchAll();
} catch (Throwable $_) {}

$qrDeposits = [];
try {
    $qrDeposits = $pdo->query("SELECT d.*,$sName,$sUsername FROM wallet_deposits d LEFT JOIN users u ON u.id=d.user_id WHERE d.status='reviewing' ORDER BY d.id DESC")->fetchAll();
} catch (Throwable $_) {}

require __DIR__ . '/_layout_header.php';
?>
<style>
.lv-card{background:rgba(255,255,255,.03);border:1px solid rgba(255,255,255,.08);border-radius:16px;padding:14px;margin:12px 0}
.lv-subhead{display:flex;justify-content:space-between;align-items:center;gap:10px;flex-wrap:wrap;margin-bottom:10px}
.lv-pill{display:inline-flex;align-items:center;padding:4px 10px;border-radius:999px;border:1px solid rgba(255,255,255,.12);background:rgba(255,255,255,.04);font-size:12px}
.lv-actions{display:flex;gap:8px;flex-wrap:wrap;align-items:center}
</style>
<div class="section">
  <div class="head"><b>Wallet Requests</b></div>
  <div class="body">
    <?php if ($msg): ?><div class="badge ok" style="margin-bottom:10px"><?= htmlspecialchars($msg) ?></div><?php endif; ?>
    <?php if ($err): ?><div class="badge danger" style="margin-bottom:10px"><?= htmlspecialchars($err) ?></div><?php endif; ?>

    <div class="lv-card">
      <div class="lv-subhead"><h3 style="margin:0">QR Deposits — Reviewing</h3></div>
      <div class="table-wrap"><table>
        <thead><tr><th>ID</th><th>User</th><th>Coins</th><th>Amount</th><th>Method</th><th>Date</th><th>Actions</th></tr></thead>
        <tbody>
        <?php foreach ($qrDeposits as $d): ?>
          <tr>
            <td>#<?= (int)$d['id'] ?></td>
            <td><b><?= htmlspecialchars($d['u_name']??'User '.$d['user_id']) ?></b><br><small>ID:<?= (int)$d['user_id'] ?></small></td>
            <td><b><?= number_format((int)$d['coins']) ?></b></td>
            <td><?= htmlspecialchars($d['currency_amount'].' '.$d['currency_code']) ?></td>
            <td><?= htmlspecialchars((string)($d['method_id'] ?? '—')) ?></td>
            <td><small><?= htmlspecialchars($d['created_at'] ?? '') ?></small></td>
            <td>
              <div class="lv-actions">
                <form method="post"><input type="hidden" name="deposit_id" value="<?= (int)$d['id'] ?>">
                  <button class="btn ok" name="qr_action" value="approve_qr" onclick="return confirm('Approve QR deposit?')">Approve</button>
                  <button class="btn danger" name="qr_action" value="reject_qr" onclick="return confirm('Reject?')">Reject</button>
                </form>
              </div>
            </td>
          </tr>
        <?php endforeach; ?>
        <?php if (empty($qrDeposits)): ?><tr><td colspan="6"><div style="padding:16px;text-align:center;opacity:.5">No QR deposits in reviewing.</div></td></tr><?php endif; ?>
        </tbody>
      </table></div>
    </div>

    <div class="lv-card">
      <div class="lv-subhead">
        <h3 style="margin:0">Manual Requests</h3>
        <div class="lv-actions">
          <?php foreach (['pending','approved','rejected','all'] as $f): ?>
            <a class="btn <?= $filter===$f?'ok':'' ?>" href="?filter=<?= $f ?>"><?= ucfirst($f) ?></a>
          <?php endforeach; ?>
          <span class="lv-pill"><?= count($rows) ?> rows</span>
        </div>
      </div>
      <div class="table-wrap"><table>
        <thead><tr><th>ID</th><th>User</th><th>Type</th><th>Coins</th><th>Method</th><th>Proof</th><th>Status</th><th>Note</th><th>Actions</th></tr></thead>
        <tbody>
        <?php foreach ($rows as $r): ?>
          <tr>
            <td>#<?= (int)$r['id'] ?></td>
            <td><b><?= htmlspecialchars(($r['u_name']??'')?:'User '.$r['user_id']) ?></b><br><small>ID:<?= (int)$r['user_id'] ?></small></td>
            <td><span class="badge"><?= htmlspecialchars($r['req_type']) ?></span></td>
            <td><b><?= number_format((int)$r['coins']) ?></b></td>
            <td><?= htmlspecialchars($r['method']??'') ?></td>
            <td><?php if (!empty($r['proof_url'])): ?><a class="btn" target="_blank" href="<?= htmlspecialchars($r['proof_url']) ?>">View</a><?php else: ?>—<?php endif; ?></td>
            <td>
              <?php $sc = $r['status']==='pending'?'warn':($r['status']==='approved'?'ok':'danger'); ?>
              <span class="badge <?= $sc ?>"><?= $r['status'] ?></span>
            </td>
            <td><?= htmlspecialchars($r['admin_note']??'') ?></td>
            <td>
              <?php if ($r['status']==='pending'): ?>
                <form method="post" class="lv-actions">
                  <input type="hidden" name="request_id" value="<?= (int)$r['id'] ?>">
                  <input name="admin_note" placeholder="Note" style="padding:4px 8px;border-radius:4px;border:1px solid #334;background:#111;color:#fff;font-size:12px;min-width:120px">
                  <button class="btn ok" name="action" value="approve" onclick="return confirm('Approve?')">Approve</button>
                  <button class="btn danger" name="action" value="reject" onclick="return confirm('Reject?')">Reject</button>
                </form>
              <?php else: ?><span class="lv-pill">—</span><?php endif; ?>
            </td>
          </tr>
        <?php endforeach; ?>
        <?php if (empty($rows)): ?><tr><td colspan="9"><div style="padding:20px;text-align:center;opacity:.5">No <?= $filter ?> requests.</div></td></tr><?php endif; ?>
        </tbody>
      </table></div>
    </div>
  </div>
</div>
<?php require __DIR__ . '/_layout_footer.php'; ?>
