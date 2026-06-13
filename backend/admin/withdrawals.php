<?php
require_once __DIR__ . '/_core.php';
admin_require_login();
$pageTitle = 'Withdrawal Requests';
$activeNav = 'withdrawals';

// Same tables as wallet_requests — just filtered for withdrawals
$msg = ''; $err = '';

if (isset($_POST['action'], $_POST['request_id'])) {
    $action = (string)$_POST['action'];
    $rid    = (int)$_POST['request_id'];
    $note   = trim((string)($_POST['admin_note'] ?? ''));

    try {
        $r = $pdo->prepare("SELECT * FROM wallet_requests WHERE id=? AND req_type='withdraw' LIMIT 1");
        $r->execute([$rid]);
        $r = $r->fetch();
        if (!$r) throw new Exception("Request not found");
        if ($r['status'] !== 'pending') throw new Exception("Already processed.");

        $uid   = (int)$r['user_id'];
        $coins = (int)$r['coins'];
        $pdo->beginTransaction();

        if ($action === 'approve') {
            $bal = (int)$pdo->prepare("SELECT balance_coins FROM user_wallets WHERE user_id=? LIMIT 1")
                ->execute([$uid]) ? $pdo->query("SELECT balance_coins FROM user_wallets WHERE user_id=$uid LIMIT 1")->fetchColumn() : 0;
            if ($bal < $coins) { $pdo->rollBack(); throw new Exception("Insufficient balance ({$bal} coins, need {$coins})."); }

            $pdo->prepare("UPDATE user_wallets SET balance_coins = balance_coins - ?, updated_at=NOW() WHERE user_id=?")
                ->execute([$coins, $uid]);
            $pdo->prepare("UPDATE wallet_requests SET status='approved', admin_note=?, decided_at=NOW() WHERE id=?")
                ->execute([$note ?: null, $rid]);
            $pdo->prepare("INSERT INTO wallet_transactions (user_id,type,direction,coins,currency_amount,currency_code,status,reference,note) VALUES (?,?,?,?,?,?,'completed',?,?)")
                ->execute([$uid,'withdraw','debit',$coins,$r['currency_amount'],$r['currency_code'],'req:'.$rid,$note ?: 'Withdrawal approved']);
            $pdo->commit();
            $msg = "Approved withdrawal #{$rid}";
            send_notif($pdo, $uid, 'wallet', 'Withdrawal Approved ✓', "Your withdrawal of {$coins} coins has been approved.");
        } elseif ($action === 'reject') {
            $pdo->prepare("UPDATE wallet_requests SET status='rejected', admin_note=?, decided_at=NOW() WHERE id=?")
                ->execute([$note ?: null, $rid]);
            $pdo->commit();
            $msg = "Rejected withdrawal #{$rid}";
            send_notif($pdo, $uid, 'wallet', 'Withdrawal Rejected', $note ?: 'Your withdrawal request was not approved.');
        } else { $pdo->rollBack(); }
    } catch (Throwable $e) {
        if ($pdo->inTransaction()) $pdo->rollBack();
        $err = $e->getMessage();
    }
}

$filter = in_array($_GET['filter'] ?? '', ['pending','approved','rejected','all']) ? $_GET['filter'] : 'pending';
$wStatus = $filter !== 'all' ? "AND r.status = " . $pdo->quote($filter) : '';

$rows = [];
try {
    $rows = $pdo->query("
        SELECT r.*, u.name AS u_name, u.username AS u_username
        FROM wallet_requests r
        LEFT JOIN users u ON u.id = r.user_id
        WHERE r.req_type = 'withdraw' $wStatus
        ORDER BY r.id DESC LIMIT 300
    ")->fetchAll();
} catch (Throwable $_) {}

require __DIR__ . '/_layout_header.php';
?>
<div class="section">
  <div class="head">
    <b>Withdrawal Requests</b>
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
      <thead><tr><th>ID</th><th>User</th><th>Coins</th><th>Amount</th><th>Method</th><th>Proof</th><th>Status</th><th>Actions</th></tr></thead>
      <tbody>
      <?php foreach ($rows as $r): ?>
        <tr>
          <td>#<?= (int)$r['id'] ?></td>
          <td><b><?= htmlspecialchars($r['u_name'] ?? 'User '.$r['user_id']) ?></b><br><small>ID:<?= (int)$r['user_id'] ?></small></td>
          <td><b><?= number_format((int)$r['coins']) ?></b></td>
          <td><?= htmlspecialchars(($r['currency_amount'] ?? '').' '.($r['currency_code'] ?? '')) ?></td>
          <td><?= htmlspecialchars($r['method'] ?? '-') ?></td>
          <td><?php if (!empty($r['proof_url'])): ?><a class="btn" target="_blank" href="<?= htmlspecialchars($r['proof_url']) ?>">View</a><?php else: ?>-<?php endif; ?></td>
          <td><span class="badge <?= $r['status']==='pending'?'warn':($r['status']==='approved'?'ok':'danger') ?>"><?= $r['status'] ?></span></td>
          <td>
            <?php if ($r['status']==='pending'): ?>
              <form method="post" style="display:flex;gap:6px;flex-wrap:wrap">
                <input type="hidden" name="request_id" value="<?= (int)$r['id'] ?>">
                <input type="text" name="admin_note" placeholder="Note" style="padding:4px 8px;border-radius:4px;border:1px solid #334;background:#111;color:#fff;font-size:12px">
                <button class="btn ok" name="action" value="approve" onclick="return confirm('Approve this withdrawal?')">Approve</button>
                <button class="btn danger" name="action" value="reject" onclick="return confirm('Reject?')">Reject</button>
              </form>
            <?php else: ?>
              <span class="badge"><?= htmlspecialchars($r['admin_note'] ?? '') ?></span>
            <?php endif; ?>
          </td>
        </tr>
      <?php endforeach; ?>
      <?php if (empty($rows)): ?><tr><td colspan="8"><div style="padding:20px;text-align:center;opacity:.5">No <?= $filter ?> withdrawals.</div></td></tr><?php endif; ?>
      </tbody>
    </table></div>
  </div>
</div>
<?php require __DIR__ . '/_layout_footer.php'; ?>
