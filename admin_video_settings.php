<?php
header('Content-Type: text/html; charset=utf-8');

// Resilient path resolution
foreach ([
    __DIR__ . '/_core.php',
    __DIR__ . '/../_core.php',
    __DIR__ . '/admin/_core.php',
    __DIR__ . '/db_connect.php',
    __DIR__ . '/../db_connect.php',
    __DIR__ . '/api/v1/db_connect.php',
] as $p) {
    if (file_exists($p)) { require_once $p; break; }
}

if (function_exists('admin_require_login')) admin_require_login();

// Ensure table and all columns exist
if (isset($pdo)) {
    $pdo->exec("
        CREATE TABLE IF NOT EXISTS video_providers (
            id INT AUTO_INCREMENT PRIMARY KEY,
            provider_name VARCHAR(50) NOT NULL UNIQUE,
            is_active TINYINT(1) DEFAULT 0,
            auto_rotate TINYINT(1) DEFAULT 1,
            app_id VARCHAR(255) DEFAULT '',
            app_sign VARCHAR(255) DEFAULT '',
            server_secret VARCHAR(255) DEFAULT '',
            additional_config TEXT,
            last_error_time DATETIME NULL,
            last_error_message TEXT NULL,
            error_count INT DEFAULT 0,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ");
    // Safe migrations for existing installs
    foreach ([
        "ALTER TABLE video_providers ADD COLUMN app_sign VARCHAR(255) DEFAULT '' AFTER app_id",
        "ALTER TABLE video_providers ADD COLUMN last_error_message TEXT NULL AFTER last_error_time",
        "ALTER TABLE video_providers ADD COLUMN error_count INT DEFAULT 0 AFTER last_error_message",
    ] as $sql) {
        try { $pdo->exec($sql); } catch (Throwable $_) {}
    }
}

$pageTitle  = 'Video API Settings';
$activeNav  = 'video_settings';
$msg        = '';

// Handle POST
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($pdo)) {
    $act = $_POST['action'] ?? '';

    if ($act === 'update_providers') {
        $pdo->beginTransaction();
        try {
            $pdo->exec("UPDATE video_providers SET is_active = 0");
            foreach (['zego', 'agora', 'dyte', 'twilio'] as $p) {
                $isActive   = !empty($_POST[$p . '_is_active'])   ? 1 : 0;
                $autoRotate = !empty($_POST[$p . '_auto_rotate'])  ? 1 : 0;
                $appId      = trim($_POST[$p . '_app_id']      ?? '');
                $appSign    = trim($_POST[$p . '_app_sign']    ?? '');
                $secret     = trim($_POST[$p . '_server_secret'] ?? '');
                $stmt = $pdo->prepare("
                    INSERT INTO video_providers (provider_name, is_active, auto_rotate, app_id, app_sign, server_secret, last_error_time, error_count)
                    VALUES (?, ?, ?, ?, ?, ?, NULL, 0)
                    ON DUPLICATE KEY UPDATE
                        is_active=VALUES(is_active), auto_rotate=VALUES(auto_rotate),
                        app_id=VALUES(app_id), app_sign=VALUES(app_sign),
                        server_secret=VALUES(server_secret),
                        last_error_time=NULL, last_error_message=NULL, error_count=0
                ");
                $stmt->execute([$p, $isActive, $autoRotate, $appId, $appSign, $secret]);
            }
            $pdo->commit();
            $msg = '<div class="alert-ok">✓ Settings saved. Error counters reset.</div>';
        } catch (Exception $e) {
            $pdo->rollBack();
            $msg = '<div class="alert-err">Error: ' . htmlspecialchars($e->getMessage()) . '</div>';
        }
    } elseif ($act === 'clear_error') {
        $provider = trim($_POST['provider'] ?? '');
        if ($provider && isset($pdo)) {
            $stmt = $pdo->prepare("UPDATE video_providers SET last_error_time=NULL, last_error_message=NULL, error_count=0 WHERE provider_name=?");
            $stmt->execute([$provider]);
            $msg = '<div class="alert-ok">✓ Error log cleared for ' . htmlspecialchars($provider) . '.</div>';
        }
    }
}

// Fetch current state
$providersMap = [];
if (isset($pdo)) {
    $stmt = $pdo->query("SELECT * FROM video_providers ORDER BY id ASC");
    foreach ($stmt->fetchAll(PDO::FETCH_ASSOC) as $row) {
        $providersMap[$row['provider_name']] = $row;
    }
}

foreach (['zego', 'agora', 'dyte', 'twilio'] as $p) {
    if (!isset($providersMap[$p])) {
        $providersMap[$p] = ['is_active' => 0, 'auto_rotate' => 1, 'app_id' => '', 'app_sign' => '', 'server_secret' => '', 'last_error_time' => null, 'last_error_message' => null, 'error_count' => 0];
    }
}

// Load layout
foreach (['_layout_header.php', 'admin/_layout_header.php', '../_layout_header.php'] as $lh) {
    if (file_exists($lh)) { include $lh; break; }
}
?>

<style>
.vp-grid   { display:grid; grid-template-columns:1fr 1fr; gap:20px; }
.vp-card   { background:rgba(15,27,51,.45); border:1px solid #223a66; padding:18px; border-radius:10px; position:relative; }
.vp-card h3{ text-transform:capitalize; margin-bottom:14px; color:#fff; font-size:16px; }
.vp-label  { display:block; margin:10px 0 4px; opacity:.85; font-size:13px; color:#ccc; }
.vp-input  { width:100%; padding:9px 10px; border-radius:5px; border:1px solid #334; background:#0a0a0a; color:#fff; font-size:13px; font-family:monospace; box-sizing:border-box; }
.vp-check  { display:flex; align-items:center; gap:8px; margin-bottom:10px; cursor:pointer; font-size:13px; }
.vp-hint   { font-size:11px; opacity:.55; margin-top:3px; }
.badge-active { display:inline-block; background:#16a34a; color:#fff; font-size:11px; padding:2px 8px; border-radius:20px; margin-left:8px; }
.badge-err    { display:inline-block; background:#dc2626; color:#fff; font-size:11px; padding:2px 8px; border-radius:20px; margin-left:8px; }
.err-box   { background:rgba(220,38,38,.15); border:1px solid #dc2626; border-radius:6px; padding:10px 12px; margin-top:12px; font-size:12px; color:#fca5a5; }
.err-box strong { display:block; margin-bottom:4px; color:#f87171; }
.btn-clear { background:none; border:1px solid #dc2626; color:#f87171; border-radius:4px; padding:3px 10px; font-size:11px; cursor:pointer; margin-top:6px; }
.btn-save  { margin-top:22px; font-size:15px; padding:11px 28px; background:#D946EF; color:#fff; border:none; border-radius:6px; cursor:pointer; }
.alert-ok  { background:rgba(22,163,74,.2); border:1px solid #16a34a; color:#86efac; padding:10px 14px; border-radius:6px; margin-bottom:16px; }
.alert-err { background:rgba(220,38,38,.2); border:1px solid #dc2626; color:#fca5a5; padding:10px 14px; border-radius:6px; margin-bottom:16px; }
@media(max-width:700px){ .vp-grid { grid-template-columns:1fr; } }
</style>

<div class="card" style="padding:20px;background:#1a1a1a;color:#fff;border-radius:10px;">
  <h2>Video API Settings</h2>
  <p style="opacity:.7;margin-top:6px;font-size:13px;">
    Configure SDK credentials for calls and live streams. The app fetches the active provider on each call start.
    <br><strong style="color:#f59e0b;">Zego:</strong> App ID + App Sign (64-char hex from ZegoCloud dashboard → Project → App Sign). Server Secret is for server-side token generation only.
  </p>
  <br>

  <?php echo $msg; ?>

  <form method="post">
    <input type="hidden" name="action" value="update_providers">
    <div class="vp-grid">
      <?php foreach (['zego', 'agora', 'dyte', 'twilio'] as $engine):
        $d = $providersMap[$engine];
        $hasError   = !empty($d['last_error_time']);
        $errCount   = (int)($d['error_count'] ?? 0);
        $errMsg     = $d['last_error_message'] ?? '';
        $errTime    = $d['last_error_time'] ?? '';
      ?>
      <div class="vp-card">
        <h3>
          <?php echo ucfirst($engine); ?>
          <?php if (!empty($d['is_active'])): ?><span class="badge-active">ACTIVE</span><?php endif; ?>
          <?php if ($hasError): ?><span class="badge-err"><?php echo $errCount; ?> error<?php echo $errCount !== 1 ? 's' : ''; ?></span><?php endif; ?>
        </h3>

        <label class="vp-check">
          <input type="checkbox" name="<?php echo $engine; ?>_is_active" value="1" <?php echo !empty($d['is_active']) ? 'checked' : ''; ?>>
          <span>Set as Active Provider</span>
        </label>
        <label class="vp-check">
          <input type="checkbox" name="<?php echo $engine; ?>_auto_rotate" value="1" <?php echo !empty($d['auto_rotate']) ? 'checked' : ''; ?>>
          <span style="opacity:.7;font-size:12px;">Auto-rotate on error</span>
        </label>

        <label class="vp-label">App ID</label>
        <input class="vp-input" type="text" name="<?php echo $engine; ?>_app_id"
               value="<?php echo htmlspecialchars($d['app_id'] ?? ''); ?>"
               placeholder="e.g. 459273576">

        <label class="vp-label">App Sign <span style="color:#f59e0b;">(64-char hex — used by mobile SDK)</span></label>
        <input class="vp-input" type="text" name="<?php echo $engine; ?>_app_sign"
               value="<?php echo htmlspecialchars($d['app_sign'] ?? ''); ?>"
               placeholder="64-character hex string from ZegoCloud dashboard">
        <div class="vp-hint">Get from ZegoCloud Console → your project → App Sign. Must be exactly 64 hex chars.</div>

        <label class="vp-label">Server Secret <span style="opacity:.6;">(32-char hex — server-side token generation only)</span></label>
        <input class="vp-input" type="text" name="<?php echo $engine; ?>_server_secret"
               value="<?php echo htmlspecialchars($d['server_secret'] ?? ''); ?>"
               placeholder="32-character server secret">

        <?php if ($hasError): ?>
        <div class="err-box">
          <strong>⚠ Last SDK Error (<?php echo htmlspecialchars($errTime); ?>)</strong>
          <?php echo $errMsg ? htmlspecialchars($errMsg) : 'Connection/login failure reported by mobile app.'; ?>
          <br>
          <form method="post" style="display:inline;">
            <input type="hidden" name="action" value="clear_error">
            <input type="hidden" name="provider" value="<?php echo htmlspecialchars($engine); ?>">
            <button class="btn-clear" type="submit">Clear error log</button>
          </form>
        </div>
        <?php endif; ?>
      </div>
      <?php endforeach; ?>
    </div>

    <button class="btn-save" type="submit">Save Configuration</button>
  </form>
</div>

<?php
foreach (['_layout_footer.php', 'admin/_layout_footer.php', '../_layout_footer.php'] as $lf) {
    if (file_exists($lf)) { include $lf; break; }
}
?>
