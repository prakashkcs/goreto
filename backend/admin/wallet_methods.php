<?php
require_once __DIR__ . '/_core.php';
admin_require_login();
$pageTitle = 'Wallet Methods';
$activeNav = 'wallet_methods';

$pdo->exec("CREATE TABLE IF NOT EXISTS wallet_payment_methods (
    id INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(80) NOT NULL,
    type ENUM('deposit','withdraw','both') NOT NULL DEFAULT 'both',
    instructions TEXT NULL,
    qr_code_url VARCHAR(255) NULL,
    account_number VARCHAR(120) NULL,
    is_active TINYINT(1) NOT NULL DEFAULT 1,
    sort_order INT NOT NULL DEFAULT 0,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

$msg = ''; $err = '';

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $action = $_POST['action'] ?? '';
    try {
        if ($action === 'add') {
            $pdo->prepare("INSERT INTO wallet_payment_methods (name,type,instructions,qr_code_url,account_number,is_active,sort_order) VALUES (?,?,?,?,?,?,?)")
                ->execute([
                    trim($_POST['name'] ?? ''),
                    $_POST['type'] ?? 'both',
                    trim($_POST['instructions'] ?? ''),
                    trim($_POST['qr_code_url'] ?? ''),
                    trim($_POST['account_number'] ?? ''),
                    !empty($_POST['is_active']) ? 1 : 0,
                    (int)($_POST['sort_order'] ?? 0),
                ]);
            $msg = 'Method added.';
        } elseif ($action === 'toggle' && isset($_POST['id'])) {
            $pdo->prepare("UPDATE wallet_payment_methods SET is_active = 1 - is_active WHERE id=?")->execute([(int)$_POST['id']]);
            $msg = 'Updated.';
        } elseif ($action === 'delete' && isset($_POST['id'])) {
            $pdo->prepare("DELETE FROM wallet_payment_methods WHERE id=?")->execute([(int)$_POST['id']]);
            $msg = 'Deleted.';
        }
    } catch (Throwable $e) { $err = $e->getMessage(); }
}

$methods = [];
try { $methods = $pdo->query("SELECT * FROM wallet_payment_methods ORDER BY sort_order ASC, id ASC")->fetchAll(); } catch (Throwable $_) {}

require __DIR__ . '/_layout_header.php';
?>
<style>
.method-form{background:rgba(15,27,51,.5);border:1px solid #223a66;border-radius:10px;padding:20px;margin-bottom:24px}
.method-row{display:grid;grid-template-columns:1fr 1fr;gap:12px}
.field{margin-bottom:12px}
.field label{display:block;margin-bottom:4px;font-size:13px;opacity:.85}
.field input,.field select,.field textarea{width:100%;padding:8px 12px;border-radius:6px;border:1px solid #334;background:#0a0a14;color:#fff;font-size:13px;box-sizing:border-box}
</style>
<div class="section">
  <div class="head"><b>Payment Methods</b></div>
  <div class="body">
    <?php if ($msg): ?><div class="badge ok" style="margin-bottom:14px"><?= htmlspecialchars($msg) ?></div><?php endif; ?>
    <?php if ($err): ?><div class="badge danger" style="margin-bottom:14px"><?= htmlspecialchars($err) ?></div><?php endif; ?>

    <div class="method-form">
      <h3 style="margin-bottom:16px">Add New Method</h3>
      <form method="post">
        <input type="hidden" name="action" value="add">
        <div class="method-row">
          <div class="field"><label>Name</label><input name="name" required placeholder="e.g. eSewa"></div>
          <div class="field"><label>Type</label>
            <select name="type"><option value="both">Deposit & Withdraw</option><option value="deposit">Deposit Only</option><option value="withdraw">Withdraw Only</option></select>
          </div>
          <div class="field"><label>Account Number / ID</label><input name="account_number" placeholder="9800000000"></div>
          <div class="field"><label>QR Code URL</label><input name="qr_code_url" placeholder="https://..."></div>
          <div class="field"><label>Sort Order</label><input name="sort_order" type="number" value="0"></div>
          <div class="field"><label>Active</label>
            <select name="is_active"><option value="1">Yes</option><option value="0">No</option></select>
          </div>
        </div>
        <div class="field"><label>Instructions</label><textarea name="instructions" rows="3" placeholder="Payment instructions for users..."></textarea></div>
        <button type="submit" style="padding:9px 24px;background:linear-gradient(135deg,#FF007F,#D946EF);color:#fff;border:none;border-radius:8px;font-weight:700;cursor:pointer">Add Method</button>
      </form>
    </div>

    <div class="table-wrap"><table>
      <thead><tr><th>ID</th><th>Name</th><th>Type</th><th>Account</th><th>QR</th><th>Status</th><th>Actions</th></tr></thead>
      <tbody>
      <?php foreach ($methods as $m): ?>
        <tr>
          <td>#<?= (int)$m['id'] ?></td>
          <td><b><?= htmlspecialchars($m['name']) ?></b><?php if ($m['instructions']): ?><br><small><?= htmlspecialchars(substr($m['instructions'],0,60)) ?></small><?php endif; ?></td>
          <td><span class="badge"><?= $m['type'] ?></span></td>
          <td><?= htmlspecialchars($m['account_number'] ?? '-') ?></td>
          <td><?php if ($m['qr_code_url']): ?><a class="btn" target="_blank" href="<?= htmlspecialchars($m['qr_code_url']) ?>">View QR</a><?php else: ?>-<?php endif; ?></td>
          <td><span class="badge <?= $m['is_active']?'ok':'danger' ?>"><?= $m['is_active']?'Active':'Inactive' ?></span></td>
          <td style="display:flex;gap:6px">
            <form method="post" style="display:inline"><input type="hidden" name="id" value="<?= $m['id'] ?>"><button class="btn" name="action" value="toggle"><?= $m['is_active']?'Disable':'Enable' ?></button></form>
            <form method="post" style="display:inline"><input type="hidden" name="id" value="<?= $m['id'] ?>"><button class="btn danger" name="action" value="delete" onclick="return confirm('Delete?')">Delete</button></form>
          </td>
        </tr>
      <?php endforeach; ?>
      <?php if (empty($methods)): ?><tr><td colspan="7"><div style="padding:20px;text-align:center;opacity:.5">No methods yet.</div></td></tr><?php endif; ?>
      </tbody>
    </table></div>
  </div>
</div>
<?php require __DIR__ . '/_layout_footer.php'; ?>
