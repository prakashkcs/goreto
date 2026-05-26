<?php
error_reporting(E_ALL);
ini_set('display_errors', 1);
header('Content-Type: text/html; charset=utf-8');

// RESILIENT PATH RESOLUTION
$found = false;
$candidates = [
    __DIR__ . '/_core.php',
    __DIR__ . '/../_core.php',
    __DIR__ . '/admin/_core.php',
    __DIR__ . '/db_connect.php',
    __DIR__ . '/../db_connect.php',
    __DIR__ . '/api/v1/db_connect.php',
];

foreach ($candidates as $p) {
    if (file_exists($p)) {
        require_once $p;
        $found = true;
        break;
    }
}

if (!$found) {
    // If nothing else, try basic db_connect if we are in api context
    @include_once 'db_connect.php';
}

if (function_exists('admin_require_login')) {
    admin_require_login();
}

// Auto-create video provider settings table
if (isset($pdo)) {
    try {
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
                created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
                updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        ");
        // Add app_sign column if missing (for existing tables)
        try {
            $pdo->exec("ALTER TABLE video_providers ADD COLUMN app_sign VARCHAR(255) DEFAULT '' AFTER app_id");
        }
        catch (Exception $e) {
        }
    }
    catch (Exception $e) {
        echo "Table creation error: " . $e->getMessage();
    }
}

$pageTitle = "Video API Settings";
$activeNav = "video_settings";

$msg = '';

// Handle form submission
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($pdo)) {
    $action = $_POST['action'] ?? '';

    if ($action === 'update_providers') {
        $pdo->beginTransaction();
        try {
            // Deactivate all first
            $pdo->exec("UPDATE video_providers SET is_active = 0");

            $providers = ['zego', 'agora', 'dyte', 'twilio'];
            foreach ($providers as $p) {
                // If checkbox submitted
                $isActive = !empty($_POST[$p . '_is_active']) ? 1 : 0;
                $autoRotate = !empty($_POST[$p . '_auto_rotate']) ? 1 : 0;
                $appId = $_POST[$p . '_app_id'] ?? '';
                $appSign = $_POST[$p . '_app_sign'] ?? '';
                $secret = $_POST[$p . '_server_secret'] ?? '';

                $stmt = $pdo->prepare("
                    INSERT INTO video_providers (provider_name, is_active, auto_rotate, app_id, app_sign, server_secret)
                    VALUES (?, ?, ?, ?, ?, ?)
                    ON DUPLICATE KEY UPDATE 
                    is_active=VALUES(is_active), 
                    auto_rotate=VALUES(auto_rotate), 
                    app_id=VALUES(app_id), 
                    app_sign=VALUES(app_sign),
                    server_secret=VALUES(server_secret), 
                    last_error_time=NULL
                ");
                $stmt->execute([$p, $isActive, $autoRotate, $appId, $appSign, $secret]);
            }
            $pdo->commit();
            $msg = '<div class="badge ok" style="padding:10px;margin-bottom:15px;display:block;background: #2e7d32; color: #fff;">Settings saved successfully.</div>';
        }
        catch (Exception $e) {
            $pdo->rollBack();
            $msg = '<div class="badge danger" style="padding:10px;margin-bottom:15px;display:block;background: #c62828; color: #fff;">Error saving settings: ' . $e->getMessage() . '</div>';
        }
    }
}

// Fetch current providers
if (isset($pdo)) {
    $stmt = $pdo->query("SELECT * FROM video_providers ORDER BY id ASC");
    $allProviders = $stmt->fetchAll(PDO::FETCH_ASSOC);

    $providersMap = [];
    foreach ($allProviders as $p) {
        $providersMap[$p['provider_name']] = $p;
    }
}
else {
    $allProviders = [];
    $providersMap = [];
}

if (file_exists('_layout_header.php')) {
    include '_layout_header.php';
}
else if (file_exists('admin/_layout_header.php')) {
    include 'admin/_layout_header.php';
}
else if (file_exists('../_layout_header.php')) {
    include '../_layout_header.php';
}
?>

<div class="card" style="padding: 20px; background: #1a1a1a; color: #fff; border-radius: 10px;">
  <h2>Multi-Provider Video SDK Backend</h2>
  <p style="opacity:0.8; margin-top:10px;">
    Enable and configure API keys for ZegoCloud, Agora, Dyte, and Twilio. 
    The app will request the "active" provider dynamically.
  </p>
  <br>

  <?php echo $msg; ?>

  <form method="post">
    <input type="hidden" name="action" value="update_providers">
    
    <div style="display:grid; grid-template-columns:1fr 1fr; gap:20px;">
      
      <?php foreach (['zego', 'agora', 'dyte', 'twilio'] as $engine):
    $pData = $providersMap[$engine] ?? ['is_active' => 0, 'auto_rotate' => 1, 'app_id' => '', 'app_sign' => '', 'server_secret' => ''];
?>
      <div style="background: rgba(15,27,51,.35); border: 1px solid #223a66; padding:15px; border-radius:10px;">
        <h3 style="text-transform: capitalize; margin-bottom: 15px; color: #fff;"><?php echo $engine; ?></h3>
        
        <label style="display:flex; align-items:center; gap:8px; margin-bottom:10px; cursor:pointer;">
            <input type="checkbox" name="<?php echo $engine; ?>_is_active" value="1" <?php echo !empty($pData['is_active']) ? 'checked' : ''; ?>>
            <span>Set Active</span>
        </label>

        <label style="display:flex; align-items:center; gap:8px; margin-bottom:10px; cursor:pointer;">
            <input type="checkbox" name="<?php echo $engine; ?>_auto_rotate" value="1" <?php echo !empty($pData['auto_rotate']) ? 'checked' : ''; ?>>
            <span style="opacity:0.8; font-size:12px;">Auto-rotate if quota exhausted</span>
        </label>

        <label style="display:block; margin: 10px 0 5px; opacity:0.9;">App ID</label>
        <input type="text" name="<?php echo $engine; ?>_app_id" value="<?php echo htmlspecialchars($pData['app_id'] ?? ''); ?>" style="width:100%; padding:10px; border-radius:5px; border:1px solid #223a66; background:#000; color:#fff;" placeholder="Numeric App ID">

        <label style="display:block; margin: 10px 0 5px; opacity:0.9;">App Sign <span style='color:#D946EF;font-size:11px;'>(64 hex chars - from Zego console)</span></label>
        <input type="text" name="<?php echo $engine; ?>_app_sign" value="<?php echo htmlspecialchars($pData['app_sign'] ?? ''); ?>" style="width:100%; padding:10px; border-radius:5px; border:1px solid #223a66; background:#000; color:#fff;" placeholder="64 character hex string for client SDK">

        <label style="display:block; margin: 10px 0 5px; opacity:0.9;">Server Secret <span style='color:#888;font-size:11px;'>(32 chars - for server-side tokens)</span></label>
        <input type="text" name="<?php echo $engine; ?>_server_secret" value="<?php echo htmlspecialchars($pData['server_secret'] ?? ''); ?>" style="width:100%; padding:10px; border-radius:5px; border:1px solid #223a66; background:#000; color:#fff;" placeholder="32 character server secret">
      </div>
      <?php
endforeach; ?>
      
    </div>

    <button type="submit" class="btn ok" style="margin-top:20px; font-size: 16px; padding: 12px 24px; background: #D946EF; color: #fff; border: none; border-radius: 5px; cursor: pointer;">Save Configuration</button>
  </form>
</div>

<?php

if (file_exists('_layout_footer.php')) {
    include '_layout_footer.php';
}
else if (file_exists('admin/_layout_footer.php')) {
    include 'admin/_layout_footer.php';
}
else if (file_exists('../_layout_footer.php')) {
    include '../_layout_footer.php';
}
?>
