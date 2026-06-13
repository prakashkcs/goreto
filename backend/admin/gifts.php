<?php
require_once __DIR__ . '/_core.php';
admin_require_login();
$pageTitle = 'Gifts';
$activeNav = 'gifts';

$msg = ''; $err = '';

// Handle add/toggle/delete gift item
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $action = $_POST['action'] ?? '';
    try {
        if ($action === 'add') {
            $pdo->exec("CREATE TABLE IF NOT EXISTS gift_items (
                id INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
                name VARCHAR(80) NOT NULL,
                icon_url VARCHAR(255) NULL,
                model_url VARCHAR(255) NULL,
                coins_cost INT NOT NULL DEFAULT 10,
                is_active TINYINT(1) NOT NULL DEFAULT 1,
                sort_order INT NOT NULL DEFAULT 0,
                created_at DATETIME DEFAULT CURRENT_TIMESTAMP
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
            $pdo->prepare("INSERT INTO gift_items (name,icon_url,model_url,coins_cost,is_active,sort_order) VALUES (?,?,?,?,?,?)")
                ->execute([
                    trim($_POST['name'] ?? ''),
                    trim($_POST['icon_url'] ?? '') ?: null,
                    trim($_POST['model_url'] ?? '') ?: null,
                    (int)($_POST['coins_cost'] ?? 10),
                    !empty($_POST['is_active']) ? 1 : 0,
                    (int)($_POST['sort_order'] ?? 0),
                ]);
            $msg = 'Gift added.';
        } elseif ($action === 'toggle' && isset($_POST['id'])) {
            $pdo->prepare("UPDATE gift_items SET is_active = 1 - is_active WHERE id=?")->execute([(int)$_POST['id']]);
            $msg = 'Updated.';
        } elseif ($action === 'delete' && isset($_POST['id'])) {
            $pdo->prepare("DELETE FROM gift_items WHERE id=?")->execute([(int)$_POST['id']]);
            $msg = 'Deleted.';
        }
    } catch (Throwable $e) { $err = $e->getMessage(); }
}

// Gift stats
$totalGifts = 0; $totalCoins = 0;
try { $totalGifts = (int)$pdo->query("SELECT COUNT(*) FROM wallet_transactions WHERE type='gift'")->fetchColumn(); } catch (Throwable $_) {}
try { $totalCoins = (int)$pdo->query("SELECT COALESCE(SUM(coins),0) FROM wallet_transactions WHERE type='gift' AND direction='debit'")->fetchColumn(); } catch (Throwable $_) {}

// Recent gift transactions
$recent = [];
try {
    $recent = $pdo->query("
        SELECT t.*, u.name AS sender_name, r.name AS receiver_name
        FROM wallet_transactions t
        LEFT JOIN users u ON u.id = t.user_id
        LEFT JOIN users r ON r.id = CAST(SUBSTRING_INDEX(t.reference, ':', -1) AS UNSIGNED)
        WHERE t.type = 'gift' AND t.direction = 'debit'
        ORDER BY t.id DESC LIMIT 50
    ")->fetchAll();
} catch (Throwable $_) {}

// Gift items
$items = [];
try {
    $pdo->exec("CREATE TABLE IF NOT EXISTS gift_items (
        id INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
        name VARCHAR(80) NOT NULL,
        icon_url VARCHAR(255) NULL,
        model_url VARCHAR(255) NULL,
        coins_cost INT NOT NULL DEFAULT 10,
        is_active TINYINT(1) NOT NULL DEFAULT 1,
        sort_order INT NOT NULL DEFAULT 0,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
    $items = $pdo->query("SELECT * FROM gift_items ORDER BY sort_order ASC, id ASC")->fetchAll();
} catch (Throwable $_) {}

require __DIR__ . '/_layout_header.php';
?>
<style>
.gift-form{background:rgba(15,27,51,.5);border:1px solid #223a66;border-radius:10px;padding:20px;margin-bottom:24px}
.g2{display:grid;grid-template-columns:1fr 1fr;gap:12px}
.gf{margin-bottom:12px}
.gf label{display:block;margin-bottom:4px;font-size:13px;opacity:.85}
.gf input,.gf select{width:100%;padding:8px 12px;border-radius:6px;border:1px solid #334;background:#0a0a14;color:#fff;font-size:13px;box-sizing:border-box}
</style>
<div class="section">
  <div class="head"><b>Gifts Management</b></div>
  <div class="body">
    <?php if ($msg): ?><div class="badge ok" style="margin-bottom:12px"><?= htmlspecialchars($msg) ?></div><?php endif; ?>
    <?php if ($err): ?><div class="badge danger" style="margin-bottom:12px"><?= htmlspecialchars($err) ?></div><?php endif; ?>

    <div style="display:flex;gap:14px;flex-wrap:wrap;margin-bottom:24px">
      <div style="background:rgba(15,27,51,.5);border:1px solid #223a66;border-radius:10px;padding:16px 20px;text-align:center">
        <div style="font-size:24px;font-weight:900;color:#D946EF"><?= number_format($totalGifts) ?></div>
        <div style="font-size:12px;opacity:.7">Total Gifts Sent</div>
      </div>
      <div style="background:rgba(15,27,51,.5);border:1px solid #223a66;border-radius:10px;padding:16px 20px;text-align:center">
        <div style="font-size:24px;font-weight:900;color:#D946EF"><?= number_format($totalCoins) ?></div>
        <div style="font-size:12px;opacity:.7">Total Coins Spent</div>
      </div>
    </div>

    <div class="gift-form">
      <h3 style="margin-bottom:16px">Add Gift Item</h3>
      <form method="post">
        <input type="hidden" name="action" value="add">
        <div class="g2">
          <div class="gf"><label>Name</label><input name="name" required placeholder="e.g. Red Rose"></div>
          <div class="gf"><label>Coins Cost</label><input name="coins_cost" type="number" value="10" min="1"></div>
          <div class="gf"><label>Icon URL</label><input name="icon_url" placeholder="https://... (image)"></div>
          <div class="gf"><label>3D Model URL</label><input name="model_url" placeholder="https://... (.glb/.gltf)"></div>
          <div class="gf"><label>Sort Order</label><input name="sort_order" type="number" value="0"></div>
          <div class="gf"><label>Active</label>
            <select name="is_active"><option value="1">Yes</option><option value="0">No</option></select>
          </div>
        </div>
        <button type="submit" style="padding:9px 24px;background:linear-gradient(135deg,#FF007F,#D946EF);color:#fff;border:none;border-radius:8px;font-weight:700;cursor:pointer">Add Gift</button>
      </form>
    </div>

    <?php if ($items): ?>
    <h3 style="margin-bottom:12px">Gift Items</h3>
    <div class="table-wrap"><table>
      <thead><tr><th>ID</th><th>Name</th><th>Icon</th><th>Cost</th><th>Status</th><th>Actions</th></tr></thead>
      <tbody>
      <?php foreach ($items as $g): ?>
        <tr>
          <td>#<?= (int)$g['id'] ?></td>
          <td><b><?= htmlspecialchars($g['name']) ?></b></td>
          <td><?php if ($g['icon_url']): ?><img src="<?= htmlspecialchars($g['icon_url']) ?>" style="width:36px;height:36px;object-fit:contain;border-radius:6px"><?php else: ?>-<?php endif; ?></td>
          <td><b><?= number_format((int)$g['coins_cost']) ?></b> coins</td>
          <td><span class="badge <?= $g['is_active']?'ok':'danger' ?>"><?= $g['is_active']?'Active':'Inactive' ?></span></td>
          <td style="display:flex;gap:6px">
            <form method="post" style="display:inline"><input type="hidden" name="id" value="<?= $g['id'] ?>"><button class="btn" name="action" value="toggle"><?= $g['is_active']?'Disable':'Enable' ?></button></form>
            <form method="post" style="display:inline"><input type="hidden" name="id" value="<?= $g['id'] ?>"><button class="btn danger" name="action" value="delete" onclick="return confirm('Delete gift?')">Delete</button></form>
          </td>
        </tr>
      <?php endforeach; ?>
      </tbody>
    </table></div>
    <?php else: ?>
    <div style="padding:20px;text-align:center;opacity:.5">No gift items yet. Add one above.</div>
    <?php endif; ?>

    <?php if ($recent): ?>
    <h3 style="margin:24px 0 12px">Recent Gift Transactions</h3>
    <div class="table-wrap"><table>
      <thead><tr><th>ID</th><th>Sender</th><th>Coins</th><th>Reference</th><th>Date</th></tr></thead>
      <tbody>
      <?php foreach ($recent as $t): ?>
        <tr>
          <td>#<?= (int)$t['id'] ?></td>
          <td><?= htmlspecialchars($t['sender_name'] ?? 'User '.$t['user_id']) ?></td>
          <td><b><?= number_format((int)$t['coins']) ?></b></td>
          <td><small><?= htmlspecialchars($t['reference'] ?? '') ?></small></td>
          <td><small><?= htmlspecialchars($t['created_at'] ?? '') ?></small></td>
        </tr>
      <?php endforeach; ?>
      </tbody>
    </table></div>
    <?php endif; ?>
  </div>
</div>
<?php require __DIR__ . '/_layout_footer.php'; ?>
