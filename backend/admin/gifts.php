<?php
require_once __DIR__ . '/_core.php';
admin_require_login();
$pageTitle = 'Gifts';
$activeNav = 'gifts';

$msg = ''; $err = '';

// Handle add/toggle/delete gift item
//
// This page used to read and write `gift_items`, a table nothing else in the
// project touches. The app asks api/v1/gifts.php, which selects from `gifts`
// -- a different table with different column names. So every gift added here
// was invisible in the app, and the live room's gift tray stayed empty no
// matter how many were created. This now edits `gifts`.
//
// `gifts` also carries two columns the old form had no field for and the app
// needs: `category`, which drives the Love / Vibe / Luxury / Cute / Funny /
// Legend tabs, and `emoji`, which is what shows when a gift has no image yet.
$GIFT_CATEGORIES = ['love', 'vibe', 'luxury', 'cute', 'funny', 'legend'];

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $action = $_POST['action'] ?? '';
    try {
        if ($action === 'add') {
            $category = trim($_POST['category'] ?? 'love');
            if (!in_array($category, $GIFT_CATEGORIES, true)) {
                $category = 'love';
            }
            $name = trim($_POST['name'] ?? '');
            if ($name === '') {
                throw new RuntimeException('A gift needs a name.');
            }
            $coins = max(1, (int)($_POST['coins_cost'] ?? 10));

            $pdo->prepare(
                "INSERT INTO gifts
                   (name, emoji, thumb_image, gif_url, glb_url, coin_price,
                    category, animation_type, is_active, sort_order, created_at)
                 VALUES (?,?,?,?,?,?,?,?,?,?,NOW())"
            )->execute([
                $name,
                trim($_POST['emoji'] ?? '') ?: null,
                trim($_POST['icon_url'] ?? '') ?: null,
                trim($_POST['gif_url'] ?? '') ?: null,
                trim($_POST['model_url'] ?? '') ?: null,
                $coins,
                $category,
                trim($_POST['model_url'] ?? '') !== '' ? '3d' : 'lottie',
                !empty($_POST['is_active']) ? 1 : 0,
                (int)($_POST['sort_order'] ?? 0),
            ]);
            $msg = 'Gift added.';
        } elseif ($action === 'toggle' && isset($_POST['id'])) {
            $pdo->prepare("UPDATE gifts SET is_active = 1 - is_active WHERE id=?")->execute([(int)$_POST['id']]);
            $msg = 'Updated.';
        } elseif ($action === 'delete' && isset($_POST['id'])) {
            // gifts_received and gift_transactions keep pointing at this id on
            // purpose: they are a record of something that happened, and the
            // row is what a past gift was. Hiding it with Disable is almost
            // always what you want instead.
            $pdo->prepare("DELETE FROM gifts WHERE id=?")->execute([(int)$_POST['id']]);
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
//
// Read from the same table the app does. No CREATE TABLE here: `gifts` is
// part of the schema, and a stray CREATE IF NOT EXISTS with a guessed shape
// is how the two tables came to disagree in the first place.
$items = [];
try {
    $items = $pdo->query("SELECT * FROM gifts ORDER BY category ASC, sort_order ASC, id ASC")->fetchAll();
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
          <div class="gf"><label>Emoji</label><input name="emoji" maxlength="8" placeholder="ð¹ â shown when there is no image"></div>
          <div class="gf"><label>Category</label>
            <select name="category">
              <?php foreach ($GIFT_CATEGORIES as $c): ?>
                <option value="<?= $c ?>"><?= ucfirst($c) ?></option>
              <?php endforeach; ?>
            </select>
          </div>
          <div class="gf"><label>Icon URL</label><input name="icon_url" placeholder="https://... (image)"></div>
          <div class="gf"><label>Animated GIF URL</label><input name="gif_url" placeholder="https://... (plays on send)"></div>
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
    <h3 style="margin-bottom:12px">Gifts <span style="font-weight:400;color:#8aa">(what the app shows in the live gift tray)</span></h3>
    <div class="table-wrap"><table>
      <thead><tr><th>ID</th><th>Name</th><th>Category</th><th>Icon</th><th>Cost</th><th>Status</th><th>Actions</th></tr></thead>
      <tbody>
      <?php foreach ($items as $g): ?>
        <tr>
          <td>#<?= (int)$g['id'] ?></td>
          <td><b><?= htmlspecialchars($g['name']) ?></b> <?= htmlspecialchars((string)($g['emoji'] ?? '')) ?></td>
          <td><span class="badge"><?= htmlspecialchars((string)($g['category'] ?? '-')) ?></span></td>
          <td><?php if (!empty($g['thumb_image'])): ?><img src="<?= htmlspecialchars($g['thumb_image']) ?>" style="width:36px;height:36px;object-fit:contain;border-radius:6px"><?php else: ?><span style="font-size:22px"><?= htmlspecialchars((string)($g['emoji'] ?? '-')) ?></span><?php endif; ?></td>
          <td><b><?= number_format((int)$g['coin_price']) ?></b> coins</td>
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
