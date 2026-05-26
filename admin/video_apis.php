<?php
// Resolve _core.php — works whether this file lives in admin/ or at root
$coreCandidates = [
    __DIR__ . '/_core.php',
    __DIR__ . '/../_core.php',
];
foreach ($coreCandidates as $c) {
    if (file_exists($c)) { require_once $c; break; }
}

if (function_exists('admin_require_login')) admin_require_login();

// ── Ensure video_providers table exists (with app_sign) ──────────────────────
if (isset($pdo)) {
    try {
        $pdo->exec("
            CREATE TABLE IF NOT EXISTS video_providers (
                id INT AUTO_INCREMENT PRIMARY KEY,
                provider_name  VARCHAR(50)  NOT NULL UNIQUE,
                is_active      TINYINT(1)   DEFAULT 0,
                auto_rotate    TINYINT(1)   DEFAULT 1,
                app_id         VARCHAR(255) DEFAULT '',
                app_sign       VARCHAR(255) DEFAULT '',
                server_secret  VARCHAR(255) DEFAULT '',
                additional_config TEXT,
                last_error_time DATETIME NULL,
                created_at  DATETIME DEFAULT CURRENT_TIMESTAMP,
                updated_at  DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        ");
        try { $pdo->exec("ALTER TABLE video_providers ADD COLUMN app_sign VARCHAR(255) DEFAULT '' AFTER app_id"); }
        catch (Throwable $_) {}
        // Seed default rows
        foreach (['zego','agora','dyte','twilio'] as $i => $p) {
            $pdo->prepare("INSERT IGNORE INTO video_providers (provider_name,is_active,auto_rotate) VALUES (?,?,1)")
                ->execute([$p, $i === 0 ? 1 : 0]);
        }
    } catch (Throwable $e) { /* table already exists */ }
}

$pageTitle = 'Video API Settings';
$activeNav = 'video_settings';
$msg = '';

// ── Handle form POST ─────────────────────────────────────────────────────────
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($pdo)) {
    $pdo->beginTransaction();
    try {
        $pdo->exec("UPDATE video_providers SET is_active = 0");
        foreach (['zego','agora','dyte','twilio'] as $p) {
            $stmt = $pdo->prepare("
                INSERT INTO video_providers (provider_name, is_active, auto_rotate, app_id, app_sign, server_secret)
                VALUES (?,?,?,?,?,?)
                ON DUPLICATE KEY UPDATE
                    is_active     = VALUES(is_active),
                    auto_rotate   = VALUES(auto_rotate),
                    app_id        = VALUES(app_id),
                    app_sign      = VALUES(app_sign),
                    server_secret = VALUES(server_secret),
                    last_error_time = NULL
            ");
            $stmt->execute([
                $p,
                !empty($_POST[$p.'_is_active'])   ? 1 : 0,
                !empty($_POST[$p.'_auto_rotate'])  ? 1 : 0,
                trim($_POST[$p.'_app_id']          ?? ''),
                trim($_POST[$p.'_app_sign']        ?? ''),
                trim($_POST[$p.'_server_secret']   ?? ''),
            ]);
        }
        $pdo->commit();
        $msg = 'success';
    } catch (Throwable $e) {
        $pdo->rollBack();
        $msg = 'error:' . $e->getMessage();
    }
}

// ── Fetch current values ─────────────────────────────────────────────────────
$providersMap = [];
if (isset($pdo)) {
    foreach ($pdo->query("SELECT * FROM video_providers ORDER BY id ASC")->fetchAll(PDO::FETCH_ASSOC) as $row) {
        $providersMap[$row['provider_name']] = $row;
    }
}

// ── Layout header ─────────────────────────────────────────────────────────────
foreach ([__DIR__.'/_layout_header.php', __DIR__.'/../_layout_header.php'] as $f) {
    if (file_exists($f)) { include $f; break; }
}
?>

<style>
.vapi-grid   { display:grid; grid-template-columns:1fr 1fr; gap:20px; margin-bottom:24px; }
.vapi-card   { background:rgba(15,27,51,.5); border:1px solid #223a66; border-radius:12px; padding:20px; }
.vapi-card h3{ margin:0 0 14px; display:flex; align-items:center; gap:10px; font-size:16px; }
.vapi-badge  { font-size:11px; padding:2px 8px; border-radius:20px; font-weight:600; }
.vapi-active { background:#1b5e2044; color:#66bb6a; border:1px solid #2e7d32; }
.vapi-inactive{ background:#37000044; color:#ef5350; border:1px solid #b71c1c; }
.vapi-label  { display:block; margin:10px 0 5px; font-size:13px; opacity:.85; }
.vapi-hint   { font-size:11px; color:#888; margin-left:6px; }
.vapi-input  { width:100%; padding:9px 12px; border-radius:6px; border:1px solid #334; background:#0a0a14; color:#fff; font-size:13px; box-sizing:border-box; }
.vapi-input:focus { outline:none; border-color:#D946EF; }
.vapi-check  { display:flex; align-items:center; gap:8px; margin-bottom:10px; cursor:pointer; font-size:13px; }
.vapi-check input{ accent-color:#D946EF; width:16px; height:16px; }
.vapi-save   { padding:12px 32px; background:linear-gradient(135deg,#FF007F,#D946EF); color:#fff; border:none; border-radius:8px; font-size:15px; font-weight:700; cursor:pointer; transition:.2s; }
.vapi-save:hover{ opacity:.88; }
.vapi-msg-ok  { background:#1b5e2055; border:1px solid #2e7d32; color:#a5d6a7; padding:12px 16px; border-radius:8px; margin-bottom:18px; }
.vapi-msg-err { background:#b71c1c33; border:1px solid #b71c1c; color:#ef9a9a; padding:12px 16px; border-radius:8px; margin-bottom:18px; }
.vapi-divider { border:none; border-top:1px solid #223a66; margin:14px 0; }
@media(max-width:700px){ .vapi-grid{ grid-template-columns:1fr; } }
</style>

<div class="card" style="padding:24px;">
  <h2 style="margin-bottom:6px;">📡 Video API Providers</h2>
  <p style="opacity:.7; margin-bottom:20px; font-size:14px;">
    Configure your live streaming &amp; video call SDK credentials.
    The app fetches the active provider at runtime and auto-switches when one fails.
  </p>

<?php if ($msg === 'success'): ?>
  <div class="vapi-msg-ok">✓ Settings saved. App will use the updated credentials immediately.</div>
<?php elseif (str_starts_with($msg, 'error:')): ?>
  <div class="vapi-msg-err">✗ <?php echo htmlspecialchars(substr($msg, 6)); ?></div>
<?php endif; ?>

  <form method="post">
    <div class="vapi-grid">

<?php
$providerMeta = [
    'zego'   => ['label' => 'ZegoCloud',  'color' => '#D946EF', 'docs' => 'console.zegocloud.com'],
    'agora'  => ['label' => 'Agora',      'color' => '#2979FF', 'docs' => 'console.agora.io'],
    'dyte'   => ['label' => 'Dyte',       'color' => '#00C853', 'docs' => 'dev.dyte.io'],
    'twilio' => ['label' => 'Twilio',     'color' => '#FF5722', 'docs' => 'console.twilio.com'],
];
foreach ($providerMeta as $key => $meta):
    $d = $providersMap[$key] ?? ['is_active'=>0,'auto_rotate'=>1,'app_id'=>'','app_sign'=>'','server_secret'=>''];
    $active = !empty($d['is_active']);
?>
      <div class="vapi-card">
        <h3>
          <span style="width:10px;height:10px;border-radius:50%;background:<?php echo $meta['color']; ?>;display:inline-block;"></span>
          <?php echo $meta['label']; ?>
          <span class="vapi-badge <?php echo $active ? 'vapi-active' : 'vapi-inactive'; ?>">
            <?php echo $active ? 'ACTIVE' : 'INACTIVE'; ?>
          </span>
        </h3>

        <label class="vapi-check">
          <input type="checkbox" name="<?php echo $key; ?>_is_active" value="1" <?php echo $active ? 'checked' : ''; ?>>
          Set as active provider
        </label>
        <label class="vapi-check">
          <input type="checkbox" name="<?php echo $key; ?>_auto_rotate" value="1" <?php echo !empty($d['auto_rotate']) ? 'checked' : ''; ?>>
          Auto-rotate when this fails
        </label>

        <hr class="vapi-divider">

        <label class="vapi-label">
          App ID
          <span class="vapi-hint">Numeric ID from <?php echo $meta['docs']; ?></span>
        </label>
        <input class="vapi-input" type="text" name="<?php echo $key; ?>_app_id"
               value="<?php echo htmlspecialchars($d['app_id'] ?? ''); ?>"
               placeholder="e.g. 1234567890">

        <label class="vapi-label">
          App Sign
          <span class="vapi-hint">64-char hex — client SDK credential</span>
        </label>
        <input class="vapi-input" type="text" name="<?php echo $key; ?>_app_sign"
               value="<?php echo htmlspecialchars($d['app_sign'] ?? ''); ?>"
               placeholder="64 character hex string">

        <label class="vapi-label">
          Server Secret
          <span class="vapi-hint">32-char hex — server-side token generation</span>
        </label>
        <input class="vapi-input" type="password" name="<?php echo $key; ?>_server_secret"
               value="<?php echo htmlspecialchars($d['server_secret'] ?? ''); ?>"
               placeholder="32 character server secret"
               autocomplete="new-password">
      </div>
<?php endforeach; ?>

    </div><!-- /grid -->

    <div style="display:flex; align-items:center; gap:16px; flex-wrap:wrap;">
      <button type="submit" class="vapi-save">💾 Save Configuration</button>
      <span style="font-size:13px; opacity:.6;">Changes take effect immediately — no app restart needed.</span>
    </div>
  </form>

  <hr class="vapi-divider" style="margin-top:28px;">
  <div style="font-size:12px; opacity:.55;">
    <strong>Tip:</strong> For ZegoCloud — App ID is numeric (e.g. <code>1234567890</code>), App Sign is the 64-char hex from the
    <em>Basic Info</em> section of your project (NOT the Server Secret). Keep both safe.
  </div>
</div>

<?php
foreach ([__DIR__.'/_layout_footer.php', __DIR__.'/../_layout_footer.php'] as $f) {
    if (file_exists($f)) { include $f; break; }
}
?>
