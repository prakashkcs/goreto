<?php
require_once __DIR__ . '/_core.php';
admin_require_login();
$pageTitle = 'Gifts Management';
$activeNav = 'gifts';

$msg = '';
$err = '';

// Ensure table has all needed columns
try {
  $pdo->exec("CREATE TABLE IF NOT EXISTS gift_items (
        id INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
        name VARCHAR(80) NOT NULL,
        emoji VARCHAR(10) NOT NULL DEFAULT '🎁',
        category VARCHAR(40) NOT NULL DEFAULT 'general',
        icon_url VARCHAR(255) NULL,
        model_url VARCHAR(255) NULL,
        animation_type VARCHAR(30) NOT NULL DEFAULT 'float',
        coins_cost INT NOT NULL DEFAULT 10,
        is_active TINYINT(1) NOT NULL DEFAULT 1,
        is_featured TINYINT(1) NOT NULL DEFAULT 0,
        sort_order INT NOT NULL DEFAULT 0,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
  // Add missing columns if upgrading
  foreach ([
    'emoji VARCHAR(10) NOT NULL DEFAULT \'🎁\'',
    'category VARCHAR(40) NOT NULL DEFAULT \'general\'',
    'animation_type VARCHAR(30) NOT NULL DEFAULT \'float\'',
    'is_featured TINYINT(1) NOT NULL DEFAULT 0'
  ] as $colDef) {
    $col = explode(' ', $colDef)[0];
    try {
      $pdo->exec("ALTER TABLE gift_items ADD COLUMN $colDef");
    } catch (Throwable $_) {
    }
  }
} catch (Throwable $e) {
  $err = $e->getMessage();
}

// Handle actions
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
  $action = $_POST['action'] ?? '';
  try {
    if ($action === 'add') {
      $pdo->prepare("INSERT INTO gift_items (name,emoji,category,icon_url,model_url,animation_type,coins_cost,is_active,is_featured,sort_order)
                VALUES (?,?,?,?,?,?,?,?,?,?)")
        ->execute([
          trim($_POST['name'] ?? ''),
          trim($_POST['emoji'] ?? '🎁'),
          trim($_POST['category'] ?? 'general'),
          trim($_POST['icon_url'] ?? '') ?: null,
          trim($_POST['model_url'] ?? '') ?: null,
          trim($_POST['animation_type'] ?? 'float'),
          (int) ($_POST['coins_cost'] ?? 10),
          !empty($_POST['is_active']) ? 1 : 0,
          !empty($_POST['is_featured']) ? 1 : 0,
          (int) ($_POST['sort_order'] ?? 0),
        ]);
      $msg = 'Gift added.';
    } elseif ($action === 'edit' && isset($_POST['id'])) {
      $pdo->prepare("UPDATE gift_items SET name=?,emoji=?,category=?,icon_url=?,model_url=?,animation_type=?,coins_cost=?,is_active=?,is_featured=?,sort_order=? WHERE id=?")
        ->execute([
          trim($_POST['name'] ?? ''),
          trim($_POST['emoji'] ?? '🎁'),
          trim($_POST['category'] ?? 'general'),
          trim($_POST['icon_url'] ?? '') ?: null,
          trim($_POST['model_url'] ?? '') ?: null,
          trim($_POST['animation_type'] ?? 'float'),
          (int) ($_POST['coins_cost'] ?? 10),
          !empty($_POST['is_active']) ? 1 : 0,
          !empty($_POST['is_featured']) ? 1 : 0,
          (int) ($_POST['sort_order'] ?? 0),
          (int) $_POST['id'],
        ]);
      $msg = 'Gift updated.';
    } elseif ($action === 'toggle' && isset($_POST['id'])) {
      $pdo->prepare("UPDATE gift_items SET is_active = 1 - is_active WHERE id=?")->execute([(int) $_POST['id']]);
      $msg = 'Status toggled.';
    } elseif ($action === 'feature' && isset($_POST['id'])) {
      $pdo->prepare("UPDATE gift_items SET is_featured = 1 - is_featured WHERE id=?")->execute([(int) $_POST['id']]);
      $msg = 'Featured status toggled.';
    } elseif ($action === 'delete' && isset($_POST['id'])) {
      $pdo->prepare("DELETE FROM gift_items WHERE id=?")->execute([(int) $_POST['id']]);
      $msg = 'Deleted.';
    } elseif ($action === 'seed_all') {
      // 100+ Love Vibe gifts seed
      $seeds = [
        // ── LOVE (1-25) ──────────────────────────────────────────
        ['Red Rose', '🌹', 'love', 'float', 5],
        ['Pink Rose', '🌸', 'love', 'float', 5],
        ['Bouquet', '💐', 'love', 'float', 8],
        ['Heart', '❤️', 'love', 'pulse', 3],
        ['Sparkling Heart', '💖', 'love', 'pulse', 5],
        ['Growing Heart', '💗', 'love', 'pulse', 6],
        ['Two Hearts', '💕', 'love', 'float', 7],
        ['Heart with Arrow', '💘', 'love', 'pulse', 8],
        ['Heart Ribbon', '💝', 'love', 'float', 10],
        ['Kiss Mark', '💋', 'love', 'pop', 6],
        ['Love Letter', '💌', 'love', 'float', 8],
        ['Cupid Arrow', '💘', 'love', 'shoot', 12],
        ['Love Potion', '🧪', 'love', 'shake', 15],
        ['Engagement Ring', '💍', 'love', 'sparkle', 50],
        ['Wedding Cake', '🎂', 'love', 'float', 30],
        ['Couple Hearts', '👫', 'love', 'pulse', 20],
        ['Love Balloon', '🎈', 'love', 'float', 10],
        ['Heart Lollipop', '🍭', 'love', 'bounce', 8],
        ['Chocolate Box', '🍫', 'love', 'float', 12],
        ['Strawberry', '🍓', 'love', 'bounce', 6],
        ['Cherry', '🍒', 'love', 'bounce', 5],
        ['Love Teddy', '🧸', 'love', 'float', 18],
        ['Dove', '🕊️', 'love', 'fly', 15],
        ['Butterfly Kiss', '🦋', 'love', 'fly', 12],
        ['Infinity Love', '♾️', 'love', 'spin', 25],
        // ── VIBE (26-50) ─────────────────────────────────────────
        ['Fire', '🔥', 'vibe', 'burst', 5],
        ['Lightning', '⚡', 'vibe', 'zap', 6],
        ['Star', '⭐', 'vibe', 'sparkle', 4],
        ['Shooting Star', '🌠', 'vibe', 'shoot', 8],
        ['Rainbow', '🌈', 'vibe', 'float', 10],
        ['Disco Ball', '🪩', 'vibe', 'spin', 15],
        ['Party Popper', '🎉', 'vibe', 'burst', 8],
        ['Confetti', '🎊', 'vibe', 'burst', 7],
        ['Crown', '👑', 'vibe', 'sparkle', 20],
        ['Diamond', '💎', 'vibe', 'sparkle', 30],
        ['Trophy', '🏆', 'vibe', 'float', 25],
        ['Rocket', '🚀', 'vibe', 'shoot', 18],
        ['Alien', '👽', 'vibe', 'bounce', 12],
        ['Ghost', '👻', 'vibe', 'float', 10],
        ['Neon Sign', '💡', 'vibe', 'pulse', 14],
        ['Microphone', '🎤', 'vibe', 'bounce', 10],
        ['Headphones', '🎧', 'vibe', 'bounce', 12],
        ['Music Note', '🎵', 'vibe', 'float', 6],
        ['Guitar', '🎸', 'vibe', 'shake', 15],
        ['Drum', '🥁', 'vibe', 'shake', 14],
        ['DJ Turntable', '🎛️', 'vibe', 'spin', 20],
        ['Sunglasses', '😎', 'vibe', 'bounce', 8],
        ['Unicorn', '🦄', 'vibe', 'float', 22],
        ['Dragon', '🐉', 'vibe', 'fly', 28],
        ['Phoenix', '🦅', 'vibe', 'fly', 35],
        // ── LUXURY (51-70) ───────────────────────────────────────
        ['Gold Bar', '🥇', 'luxury', 'sparkle', 40],
        ['Money Bag', '💰', 'luxury', 'bounce', 35],
        ['Gem Stone', '💎', 'luxury', 'sparkle', 50],
        ['Luxury Car', '🏎️', 'luxury', 'shoot', 80],
        ['Yacht', '⛵', 'luxury', 'float', 100],
        ['Private Jet', '✈️', 'luxury', 'fly', 120],
        ['Castle', '🏰', 'luxury', 'float', 150],
        ['Crown Jewels', '👑', 'luxury', 'sparkle', 200],
        ['Champagne', '🍾', 'luxury', 'burst', 45],
        ['Caviar', '🫧', 'luxury', 'float', 60],
        ['Rolex', '⌚', 'luxury', 'sparkle', 90],
        ['Penthouse', '🏙️', 'luxury', 'float', 180],
        ['Helicopter', '🚁', 'luxury', 'fly', 130],
        ['Space Rocket', '🛸', 'luxury', 'shoot', 160],
        ['Supernova', '💥', 'luxury', 'burst', 250],
        ['Galaxy', '🌌', 'luxury', 'spin', 300],
        ['Black Diamond', '🖤', 'luxury', 'sparkle', 500],
        ['Infinity Diamond', '♾️', 'luxury', 'sparkle', 1000],
        ['Golden Rose', '🌹', 'luxury', 'sparkle', 75],
        ['Platinum Heart', '💜', 'luxury', 'pulse', 400],
        // ── CUTE (71-85) ─────────────────────────────────────────
        ['Baby Chick', '🐣', 'cute', 'bounce', 4],
        ['Bunny', '🐰', 'cute', 'bounce', 5],
        ['Panda', '🐼', 'cute', 'bounce', 6],
        ['Koala', '🐨', 'cute', 'float', 7],
        ['Penguin', '🐧', 'cute', 'bounce', 5],
        ['Cat', '🐱', 'cute', 'bounce', 4],
        ['Dog', '🐶', 'cute', 'bounce', 4],
        ['Hamster', '🐹', 'cute', 'bounce', 5],
        ['Frog', '🐸', 'cute', 'bounce', 4],
        ['Hedgehog', '🦔', 'cute', 'bounce', 6],
        ['Sloth', '🦥', 'cute', 'float', 8],
        ['Otter', '🦦', 'cute', 'float', 7],
        ['Seal', '🦭', 'cute', 'bounce', 6],
        ['Flamingo', '🦩', 'cute', 'float', 9],
        ['Peacock', '🦚', 'cute', 'spin', 12],
        // ── FUNNY (86-100) ───────────────────────────────────────
        ['Clown', '🤡', 'funny', 'bounce', 5],
        ['Poop', '💩', 'funny', 'bounce', 3],
        ['Banana', '🍌', 'funny', 'bounce', 4],
        ['Eggplant', '🍆', 'funny', 'bounce', 5],
        ['Cactus', '🌵', 'funny', 'bounce', 4],
        ['Taco', '🌮', 'funny', 'bounce', 5],
        ['Pizza', '🍕', 'funny', 'float', 6],
        ['Burger', '🍔', 'funny', 'bounce', 5],
        ['Hot Dog', '🌭', 'funny', 'bounce', 4],
        ['Donut', '🍩', 'funny', 'spin', 5],
        ['Ice Cream', '🍦', 'funny', 'float', 6],
        ['Watermelon', '🍉', 'funny', 'bounce', 5],
        ['Avocado', '🥑', 'funny', 'bounce', 6],
        ['Broccoli', '🥦', 'funny', 'bounce', 4],
        ['Mushroom', '🍄', 'funny', 'bounce', 5],
      ];
      $stmt = $pdo->prepare("INSERT IGNORE INTO gift_items (name,emoji,category,animation_type,coins_cost,is_active,sort_order) VALUES (?,?,?,?,?,1,?)");
      $count = 0;
      foreach ($seeds as $i => $s) {
        // Check if name already exists
        $exists = $pdo->prepare("SELECT id FROM gift_items WHERE name=? LIMIT 1");
        $exists->execute([$s[0]]);
        if (!$exists->fetchColumn()) {
          $stmt->execute([$s[0], $s[1], $s[2], $s[3], $s[4], $i]);
          $count++;
        }
      }
      $msg = "Seeded $count new gifts (skipped existing).";
    }
  } catch (Throwable $e) {
    $err = $e->getMessage();
  }
}

// Stats
$totalGifts = 0;
$totalCoins = 0;
$totalItems = 0;
try {
  $totalGifts = (int) $pdo->query("SELECT COUNT(*) FROM wallet_transactions WHERE type='gift'")->fetchColumn();
} catch (Throwable $_) {
}
try {
  $totalCoins = (int) $pdo->query("SELECT COALESCE(SUM(coins),0) FROM wallet_transactions WHERE type='gift' AND direction='debit'")->fetchColumn();
} catch (Throwable $_) {
}
try {
  $totalItems = (int) $pdo->query("SELECT COUNT(*) FROM gift_items WHERE is_active=1")->fetchColumn();
} catch (Throwable $_) {
}

// Filter
$filterCat = $_GET['cat'] ?? '';
$filterQ = trim($_GET['q'] ?? '');
$cats = ['all' => 'All', 'love' => 'Love', 'vibe' => 'Vibe', 'luxury' => 'Luxury', 'cute' => 'Cute', 'funny' => 'Funny', 'general' => 'General'];

$where = '1=1';
$params = [];
if ($filterCat && $filterCat !== 'all') {
  $where .= ' AND category=?';
  $params[] = $filterCat;
}
if ($filterQ) {
  $where .= ' AND name LIKE ?';
  $params[] = '%' . $filterQ . '%';
}

$items = [];
try {
  $st = $pdo->prepare("SELECT * FROM gift_items WHERE $where ORDER BY sort_order ASC, coins_cost ASC, id ASC");
  $st->execute($params);
  $items = $st->fetchAll();
} catch (Throwable $_) {
}

// Recent transactions
$recent = [];
try {
  $recent = $pdo->query("
        SELECT t.*, u.name AS sender_name
        FROM wallet_transactions t
        LEFT JOIN users u ON u.id = t.user_id
        WHERE t.type = 'gift' AND t.direction = 'debit'
        ORDER BY t.id DESC LIMIT 30
    ")->fetchAll();
} catch (Throwable $_) {
}

// Edit item
$editItem = null;
if (isset($_GET['edit'])) {
  try {
    $editItem = $pdo->prepare("SELECT * FROM gift_items WHERE id=?")->execute([(int) $_GET['edit']]) ? null : null;
  } catch (Throwable $_) {
  }
  try {
    $st = $pdo->prepare("SELECT * FROM gift_items WHERE id=?");
    $st->execute([(int) $_GET['edit']]);
    $editItem = $st->fetch();
  } catch (Throwable $_) {
  }
}

require __DIR__ . '/_layout_header.php';
?>
<style>
  .gift-grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(200px, 1fr));
    gap: 14px;
    margin-top: 16px
  }

  .gift-card {
    background: rgba(15, 10, 30, .7);
    border: 1px solid rgba(255, 255, 255, .08);
    border-radius: 14px;
    padding: 14px;
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 8px;
    position: relative;
    transition: border-color .2s
  }

  .gift-card:hover {
    border-color: rgba(217, 70, 239, .4)
  }

  .gift-card .emoji {
    font-size: 42px;
    line-height: 1;
    filter: drop-shadow(0 0 8px rgba(217, 70, 239, .5))
  }

  .gift-card .gname {
    font-weight: 700;
    font-size: 13px;
    text-align: center
  }

  .gift-card .gcost {
    color: #22C55E;
    font-weight: 800;
    font-size: 13px
  }

  .gift-card .gbadge {
    position: absolute;
    top: 8px;
    right: 8px;
    font-size: 10px;
    padding: 2px 7px;
    border-radius: 999px;
    font-weight: 700
  }

  .gift-card .gcat {
    font-size: 10px;
    opacity: .6;
    text-transform: uppercase;
    letter-spacing: .5px
  }

  .gift-card .gactions {
    display: flex;
    gap: 6px;
    flex-wrap: wrap;
    justify-content: center;
    margin-top: 4px
  }

  .gift-card .gactions form {
    display: inline
  }

  .gift-card .gactions button {
    padding: 4px 10px;
    font-size: 11px;
    border-radius: 6px;
    border: none;
    cursor: pointer;
    font-weight: 600
  }

  .btn-toggle {
    background: rgba(255, 255, 255, .1);
    color: #fff
  }

  .btn-feat {
    background: rgba(234, 179, 8, .15);
    color: #EAB308
  }

  .btn-edit {
    background: rgba(99, 102, 241, .2);
    color: #818CF8
  }

  .btn-del {
    background: rgba(239, 68, 68, .15);
    color: #F87171
  }

  .cat-tabs {
    display: flex;
    gap: 8px;
    flex-wrap: wrap;
    margin-bottom: 16px
  }

  .cat-tab {
    padding: 6px 16px;
    border-radius: 999px;
    border: 1px solid rgba(255, 255, 255, .12);
    background: rgba(255, 255, 255, .05);
    color: #fff;
    font-size: 12px;
    font-weight: 600;
    cursor: pointer;
    text-decoration: none;
    transition: all .2s
  }

  .cat-tab.active,
  .cat-tab:hover {
    background: linear-gradient(135deg, #FF007F, #D946EF);
    border-color: transparent
  }

  .anim-badge {
    font-size: 10px;
    padding: 2px 6px;
    border-radius: 4px;
    background: rgba(99, 102, 241, .2);
    color: #818CF8;
    font-weight: 600
  }

  .form-grid {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 12px
  }

  .form-grid .full {
    grid-column: 1/-1
  }

  .gf {
    margin-bottom: 0
  }

  .gf label {
    display: block;
    margin-bottom: 4px;
    font-size: 12px;
    opacity: .8
  }

  .gf input,
  .gf select {
    width: 100%;
    padding: 8px 10px;
    border-radius: 6px;
    border: 1px solid #334;
    background: #0a0a14;
    color: #fff;
    font-size: 13px;
    box-sizing: border-box
  }

  .section-box {
    background: rgba(15, 10, 30, .5);
    border: 1px solid rgba(255, 255, 255, .08);
    border-radius: 12px;
    padding: 20px;
    margin-bottom: 20px
  }
</style>

<div class="section">
  <div class="head"><b>Gifts Management</b></div>
  <div class="body">

    <?php if ($msg): ?>
      <div class="badge ok" style="margin-bottom:12px;padding:10px 14px"><?= htmlspecialchars($msg) ?></div>
    <?php endif; ?>
    <?php if ($err): ?>
      <div class="badge danger" style="margin-bottom:12px;padding:10px 14px"><?= htmlspecialchars($err) ?></div>
    <?php endif; ?>

    <!-- Stats -->
    <div style="display:flex;gap:12px;flex-wrap:wrap;margin-bottom:20px">
      <?php foreach ([
        ['Active Gifts', $totalItems, '#D946EF'],
        ['Total Sent', number_format($totalGifts), '#F97316'],
        ['Coins Spent', number_format($totalCoins), '#22C55E'],
      ] as [$label, $val, $color]): ?>
        <div
          style="background:rgba(15,10,30,.6);border:1px solid rgba(255,255,255,.08);border-radius:10px;padding:14px 20px;text-align:center;min-width:120px">
          <div style="font-size:22px;font-weight:900;color:<?= $color ?>"><?= $val ?></div>
          <div style="font-size:11px;opacity:.6"><?= $label ?></div>
        </div>
      <?php endforeach; ?>
      <!-- Seed button -->
      <form method="post" style="display:flex;align-items:center">
        <input type="hidden" name="action" value="seed_all">
        <button type="submit"
          style="padding:10px 20px;background:linear-gradient(135deg,#7C3AED,#D946EF);color:#fff;border:none;border-radius:10px;font-weight:700;cursor:pointer;font-size:13px"
          onclick="return confirm('Seed 100+ love vibe gifts? Existing names will be skipped.')">
          + Seed 100+ Gifts
        </button>
      </form>
    </div>

    <!-- Add / Edit Form -->
    <div class="section-box">
      <h3 style="margin-bottom:16px"><?= $editItem ? 'Edit Gift' : 'Add Gift' ?></h3>
      <form method="post" action="gifts.php">
        <input type="hidden" name="action" value="<?= $editItem ? 'edit' : 'add' ?>">
        <?php if ($editItem): ?><input type="hidden" name="id" value="<?= (int) $editItem['id'] ?>"><?php endif; ?>
        <div class="form-grid">
          <div class="gf"><label>Name</label><input name="name" required placeholder="e.g. Red Rose"
              value="<?= htmlspecialchars($editItem['name'] ?? '') ?>"></div>
          <div class="gf"><label>Emoji</label><input name="emoji" placeholder="🌹"
              value="<?= htmlspecialchars($editItem['emoji'] ?? '🎁') ?>"></div>
          <div class="gf"><label>Category</label>
            <select name="category">
              <?php foreach (['love', 'vibe', 'luxury', 'cute', 'funny', 'general'] as $c): ?>
                <option value="<?= $c ?>" <?= ($editItem['category'] ?? 'general') === $c ? 'selected' : '' ?>>
                  <?= ucfirst($c) ?></option>
              <?php endforeach; ?>
            </select>
          </div>
          <div class="gf"><label>Animation Type</label>
            <select name="animation_type">
              <?php foreach (['float', 'pulse', 'bounce', 'spin', 'burst', 'shoot', 'fly', 'sparkle', 'zap', 'shake', 'pop'] as $a): ?>
                <option value="<?= $a ?>" <?= ($editItem['animation_type'] ?? 'float') === $a ? 'selected' : '' ?>>
                  <?= ucfirst($a) ?></option>
              <?php endforeach; ?>
            </select>
          </div>
          <div class="gf"><label>Coins Cost</label><input name="coins_cost" type="number" min="1"
              value="<?= (int) ($editItem['coins_cost'] ?? 10) ?>"></div>
          <div class="gf"><label>Sort Order</label><input name="sort_order" type="number"
              value="<?= (int) ($editItem['sort_order'] ?? 0) ?>"></div>
          <div class="gf"><label>Icon URL (optional)</label><input name="icon_url" placeholder="https://..."
              value="<?= htmlspecialchars($editItem['icon_url'] ?? '') ?>"></div>
          <div class="gf"><label>3D Model URL (optional)</label><input name="model_url" placeholder="https://... (.glb)"
              value="<?= htmlspecialchars($editItem['model_url'] ?? '') ?>"></div>
          <div class="gf"><label>Active</label>
            <select name="is_active">
              <option value="1" <?= ($editItem['is_active'] ?? 1) ? 'selected' : '' ?>>Yes</option>
              <option value="0" <?= !($editItem['is_active'] ?? 1) ? 'selected' : '' ?>>No</option>
            </select>
          </div>
          <div class="gf"><label>Featured</label>
            <select name="is_featured">
              <option value="0" <?= !($editItem['is_featured'] ?? 0) ? 'selected' : '' ?>>No</option>
              <option value="1" <?= ($editItem['is_featured'] ?? 0) ? 'selected' : '' ?>>Yes</option>
            </select>
          </div>
        </div>
        <div style="margin-top:14px;display:flex;gap:10px">
          <button type="submit"
            style="padding:9px 24px;background:linear-gradient(135deg,#FF007F,#D946EF);color:#fff;border:none;border-radius:8px;font-weight:700;cursor:pointer">
            <?= $editItem ? 'Save Changes' : 'Add Gift' ?>
          </button>
          <?php if ($editItem): ?><a href="gifts.php" class="btn">Cancel</a><?php endif; ?>
        </div>
      </form>
    </div>

    <!-- Category filter + search -->
    <div style="display:flex;align-items:center;gap:12px;flex-wrap:wrap;margin-bottom:12px">
      <div class="cat-tabs">
        <?php foreach ($cats as $k => $label): ?>
          <a href="?cat=<?= $k ?>&q=<?= urlencode($filterQ) ?>"
            class="cat-tab <?= ($filterCat === $k || ($k === 'all' && !$filterCat)) ? 'active' : '' ?>"><?= $label ?></a>
        <?php endforeach; ?>
      </div>
      <form method="get" style="display:flex;gap:6px">
        <input type="hidden" name="cat" value="<?= htmlspecialchars($filterCat) ?>">
        <input name="q" placeholder="Search gifts..." value="<?= htmlspecialchars($filterQ) ?>"
          style="padding:6px 12px;border-radius:8px;border:1px solid #334;background:#0a0a14;color:#fff;font-size:13px">
        <button type="submit" class="btn">Search</button>
      </form>
    </div>

    <div style="font-size:12px;opacity:.5;margin-bottom:10px"><?= count($items) ?> gifts shown</div>

    <!-- Gift grid -->
    <?php if ($items): ?>
      <div class="gift-grid">
        <?php foreach ($items as $g): ?>
          <div class="gift-card">
            <?php if ($g['is_featured']): ?><span class="gbadge"
                style="background:rgba(234,179,8,.2);color:#EAB308">Featured</span><?php endif; ?>
            <?php if (!$g['is_active']): ?><span class="gbadge"
                style="background:rgba(239,68,68,.2);color:#F87171;<?= $g['is_featured'] ? 'top:28px' : '' ?>">Off</span><?php endif; ?>
            <div class="emoji"><?= htmlspecialchars($g['emoji'] ?? '🎁') ?></div>
            <div class="gname"><?= htmlspecialchars($g['name']) ?></div>
            <div class="gcat"><?= htmlspecialchars($g['category']) ?></div>
            <div class="gcost"><?= number_format((int) $g['coins_cost']) ?> coins</div>
            <span class="anim-badge"><?= htmlspecialchars($g['animation_type']) ?></span>
            <div class="gactions">
              <a href="?edit=<?= $g['id'] ?>&cat=<?= urlencode($filterCat) ?>&q=<?= urlencode($filterQ) ?>"
                style="text-decoration:none"><button class="btn-edit">Edit</button></a>
              <form method="post"><input type="hidden" name="id" value="<?= $g['id'] ?>"><button class="btn-toggle"
                  name="action" value="toggle"><?= $g['is_active'] ? 'Disable' : 'Enable' ?></button></form>
              <form method="post"><input type="hidden" name="id" value="<?= $g['id'] ?>"><button class="btn-feat"
                  name="action" value="feature"><?= $g['is_featured'] ? 'Unfeature' : 'Feature' ?></button></form>
              <form method="post" onsubmit="return confirm('Delete this gift?')"><input type="hidden" name="id"
                  value="<?= $g['id'] ?>"><button class="btn-del" name="action" value="delete">Del</button></form>
            </div>
          </div>
        <?php endforeach; ?>
      </div>
    <?php else: ?>
      <div style="padding:40px;text-align:center;opacity:.4">No gifts found. Use "Seed 100+ Gifts" to populate.</div>
    <?php endif; ?>

    <!-- Recent transactions -->
    <?php if ($recent): ?>
      <h3 style="margin:28px 0 12px">Recent Gift Transactions</h3>
      <div class="table-wrap">
        <table>
          <thead>
            <tr>
              <th>ID</th>
              <th>Sender</th>
              <th>Coins</th>
              <th>Reference</th>
              <th>Date</th>
            </tr>
          </thead>
          <tbody>
            <?php foreach ($recent as $t): ?>
              <tr>
                <td>#<?= (int) $t['id'] ?></td>
                <td><?= htmlspecialchars($t['sender_name'] ?? 'User ' . $t['user_id']) ?></td>
                <td><b style="color:#22C55E"><?= number_format((int) $t['coins']) ?></b></td>
                <td><small><?= htmlspecialchars($t['reference'] ?? '') ?></small></td>
                <td><small><?= htmlspecialchars($t['created_at'] ?? '') ?></small></td>
              </tr>
            <?php endforeach; ?>
          </tbody>
        </table>
      </div>
    <?php endif; ?>

  </div>
</div>
<?php require __DIR__ . '/_layout_footer.php'; ?>