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

// ── Ensure video_providers table exists ───────────────────────────────────────
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
    try { $pdo->exec("ALTER TABLE video_providers ADD COLUMN trial_started_at DATETIME NULL"); } catch (Throwable $_) {}
    $pdo->beginTransaction();
    try {
        $pdo->exec("UPDATE video_providers SET is_active = 0");
        foreach (['zego','agora','dyte','twilio'] as $p) {
            $isActive    = !empty($_POST[$p.'_is_active']) ? 1 : 0;
            $trialRaw    = trim($_POST[$p.'_trial_started_at'] ?? '');
            $trialDate   = ($trialRaw !== '') ? date('Y-m-d H:i:s', strtotime($trialRaw)) : null;
            $stmt = $pdo->prepare("
                INSERT INTO video_providers (provider_name, is_active, auto_rotate, app_id, app_sign, server_secret, trial_started_at)
                VALUES (?,?,?,?,?,?,?)
                ON DUPLICATE KEY UPDATE
                    is_active        = VALUES(is_active),
                    auto_rotate      = VALUES(auto_rotate),
                    app_id           = VALUES(app_id),
                    app_sign         = VALUES(app_sign),
                    server_secret    = VALUES(server_secret),
                    trial_started_at = COALESCE(VALUES(trial_started_at), trial_started_at),
                    last_error_time  = NULL
            ");
            $stmt->execute([
                $p,
                $isActive,
                !empty($_POST[$p.'_auto_rotate']) ? 1 : 0,
                trim($_POST[$p.'_app_id']         ?? ''),
                trim($_POST[$p.'_app_sign']        ?? ''),
                trim($_POST[$p.'_server_secret']   ?? ''),
                $trialDate,
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

// ── Per-provider field definitions ───────────────────────────────────────────
// Each entry: label, hint, placeholder, is_password, hidden (optional)
$providerMeta = [
    'zego' => [
        'label' => 'ZegoCloud',
        'color' => '#D946EF',
        'docs'  => 'console.zegocloud.com',
        'fields' => [
            'app_id' => [
                'label'       => 'App ID',
                'hint'        => 'Numeric App ID from your Zego project',
                'placeholder' => 'e.g. 1234567890',
                'password'    => false,
            ],
            'app_sign' => [
                'label'       => 'App Sign',
                'hint'        => '64-char hex — client SDK authentication',
                'placeholder' => '0x1a2b3c4d... (64 chars)',
                'password'    => false,
            ],
            'server_secret' => [
                'label'       => 'Server Secret',
                'hint'        => '32-char hex — server-side token generation',
                'placeholder' => '32 character server secret',
                'password'    => true,
            ],
        ],
    ],
    'agora' => [
        'label' => 'Agora',
        'color' => '#2979FF',
        'docs'  => 'console.agora.io',
        'fields' => [
            'app_id' => [
                'label'       => 'App ID',
                'hint'        => '32-char hex string from Agora Console → Project Management',
                'placeholder' => 'e.g. a1b2c3d4e5f6... (32 chars)',
                'password'    => false,
            ],
            'app_sign' => [
                'label'       => 'App Sign',
                'hint'        => 'Not used by Agora — leave blank',
                'placeholder' => '(not applicable for Agora)',
                'password'    => false,
                'disabled'    => true,
            ],
            'server_secret' => [
                'label'       => 'App Certificate',
                'hint'        => 'From Agora Console → Project Management → Primary Certificate — used to generate RTC tokens',
                'placeholder' => 'Primary certificate from Agora Console',
                'password'    => true,
            ],
        ],
    ],
    'dyte' => [
        'label' => 'Dyte',
        'color' => '#00C853',
        'docs'  => 'dev.dyte.io',
        'fields' => [
            'app_id' => [
                'label'       => 'Organization ID',
                'hint'        => 'From Dyte Developer Portal → Settings',
                'placeholder' => 'e.g. xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx',
                'password'    => false,
            ],
            'app_sign' => [
                'label'       => 'App Sign',
                'hint'        => 'Not used by Dyte — leave blank',
                'placeholder' => '(not applicable for Dyte)',
                'password'    => false,
                'disabled'    => true,
            ],
            'server_secret' => [
                'label'       => 'API Key',
                'hint'        => 'From Dyte Developer Portal → API Keys',
                'placeholder' => 'Dyte API key',
                'password'    => true,
            ],
        ],
    ],
    'twilio' => [
        'label' => 'Twilio',
        'color' => '#FF5722',
        'docs'  => 'console.twilio.com',
        'fields' => [
            'app_id' => [
                'label'       => 'Account SID',
                'hint'        => 'From Twilio Console → Account Info',
                'placeholder' => 'ACxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx',
                'password'    => false,
            ],
            'app_sign' => [
                'label'       => 'API Key SID',
                'hint'        => 'From Twilio Console → API Keys',
                'placeholder' => 'SKxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx',
                'password'    => false,
            ],
            'server_secret' => [
                'label'       => 'API Key Secret',
                'hint'        => 'Secret for the API Key above',
                'placeholder' => 'API Key Secret',
                'password'    => true,
            ],
        ],
    ],
];

// ── Agora token builder (must be defined before use) ─────────────────────────
function _buildAgoraAccessToken2Test(string $appId, string $appCert, string $channel, int $uid, int $expireSec): ?string {
    if (strlen($appId) !== 32) return null;
    $issueTs    = time();
    $expire     = $issueTs + $expireSec;
    $salt       = rand(1, 0x7FFFFFFF);
    $signingKey = hash_hmac('sha256', pack('VV', $issueTs, $salt), $appCert, true);
    $privs      = [1 => $expire, 2 => $expire, 3 => $expire, 4 => $expire];
    ksort($privs);
    $privBuf = pack('v', count($privs));
    foreach ($privs as $k => $v) { $privBuf .= pack('v', (int)$k) . pack('V', (int)$v); }
    $svcBuf  = pack('v', 1) . pack('v', strlen($channel)) . $channel . pack('v', strlen((string)$uid)) . (string)$uid . $privBuf;
    $hdr     = pack('v', 1) . hex2bin($appId) . pack('V', $issueTs) . pack('V', $expire) . pack('V', $salt);
    $sig     = hash_hmac('sha256', $hdr . $svcBuf, $signingKey, true);
    $buf     = $hdr . pack('v', strlen($sig)) . $sig . pack('v', 1) . $svcBuf;
    return '007' . base64_encode(gzcompress($buf));
}

// ── Handle Agora token test ───────────────────────────────────────────────────
$agoraTestResult = null;
if ($_SERVER['REQUEST_METHOD'] === 'POST' && !empty($_POST['_test_agora']) && isset($pdo)) {
    $testRow = $pdo->query("SELECT app_id, server_secret FROM video_providers WHERE provider_name='agora' LIMIT 1")->fetch(PDO::FETCH_ASSOC);
    $testAppId   = trim($testRow['app_id']       ?? '');
    $testAppCert = trim($testRow['server_secret'] ?? '');

    if (strlen($testAppId) !== 32) {
        $agoraTestResult = ['ok' => false, 'msg' => 'App ID is not 32 characters. Got: ' . strlen($testAppId) . ' chars. Copy the exact App ID from Agora Console.'];
    } elseif (empty($testAppCert)) {
        $agoraTestResult = ['ok' => true, 'msg' => 'App ID valid (32 chars). No App Certificate — trial mode. Add Primary Certificate for production.'];
    } else {
        $tok = _buildAgoraAccessToken2Test($testAppId, $testAppCert, 'test_channel_admin', 0, 3600);
        if ($tok && str_starts_with($tok, '007')) {
            $agoraTestResult = ['ok' => true, 'msg' => 'Token OK: starts with "007", length ' . strlen($tok) . '. Credentials are valid.'];
        } else {
            $agoraTestResult = ['ok' => false, 'msg' => 'Token generation failed — App Certificate may be wrong.'];
        }
    }
}

// ── Layout header ─────────────────────────────────────────────────────────────
foreach ([__DIR__.'/_layout_header.php', __DIR__.'/../_layout_header.php'] as $f) {
    if (file_exists($f)) { include $f; break; }
}
?>

<style>
.vapi-grid    { display:grid; grid-template-columns:1fr 1fr; gap:20px; margin-bottom:24px; }
.vapi-card    { background:rgba(15,27,51,.5); border:1px solid #223a66; border-radius:12px; padding:20px; }
.vapi-card h3 { margin:0 0 14px; display:flex; align-items:center; gap:10px; font-size:16px; }
.vapi-badge   { font-size:11px; padding:2px 8px; border-radius:20px; font-weight:600; }
.vapi-active  { background:#1b5e2044; color:#66bb6a; border:1px solid #2e7d32; }
.vapi-inactive{ background:#37000044; color:#ef5350; border:1px solid #b71c1c; }
.vapi-label   { display:block; margin:10px 0 5px; font-size:13px; opacity:.85; }
.vapi-hint    { font-size:11px; color:#888; margin-left:6px; }
.vapi-input   { width:100%; padding:9px 12px; border-radius:6px; border:1px solid #334; background:#0a0a14; color:#fff; font-size:13px; box-sizing:border-box; }
.vapi-input:focus  { outline:none; border-color:#D946EF; }
.vapi-input:disabled { opacity:.38; cursor:not-allowed; background:#0d0d0d; }
.vapi-disabled-row { opacity:.45; }
.vapi-check   { display:flex; align-items:center; gap:8px; margin-bottom:10px; cursor:pointer; font-size:13px; }
.vapi-check input { accent-color:#D946EF; width:16px; height:16px; }
.vapi-save    { padding:12px 32px; background:linear-gradient(135deg,#FF007F,#D946EF); color:#fff; border:none; border-radius:8px; font-size:15px; font-weight:700; cursor:pointer; transition:.2s; }
.vapi-save:hover { opacity:.88; }
.vapi-msg-ok  { background:#1b5e2055; border:1px solid #2e7d32; color:#a5d6a7; padding:12px 16px; border-radius:8px; margin-bottom:18px; }
.vapi-msg-err { background:#b71c1c33; border:1px solid #b71c1c; color:#ef9a9a; padding:12px 16px; border-radius:8px; margin-bottom:18px; }
.vapi-divider { border:none; border-top:1px solid #223a66; margin:14px 0; }
.vapi-na-tag  { font-size:10px; background:#ffffff12; color:#888; padding:1px 6px; border-radius:4px; margin-left:6px; vertical-align:middle; }
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

<?php foreach ($providerMeta as $key => $meta):
    $d      = $providersMap[$key] ?? ['is_active'=>0,'auto_rotate'=>1,'app_id'=>'','app_sign'=>'','server_secret'=>'','trial_started_at'=>''];
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

<?php
    $colMap = ['app_id' => 'app_id', 'app_sign' => 'app_sign', 'server_secret' => 'server_secret'];
    foreach ($meta['fields'] as $col => $f):
        $disabled = !empty($f['disabled']);
        $dbVal    = $d[$col] ?? '';
        $rowClass = $disabled ? ' vapi-disabled-row' : '';
?>
        <div class="<?php echo ltrim($rowClass); ?>">
          <label class="vapi-label">
            <?php echo htmlspecialchars($f['label']); ?>
            <?php if ($disabled): ?>
              <span class="vapi-na-tag">N/A for <?php echo $meta['label']; ?></span>
            <?php else: ?>
              <span class="vapi-hint"><?php echo htmlspecialchars($f['hint']); ?></span>
            <?php endif; ?>
          </label>
          <input class="vapi-input"
                 type="<?php echo $f['password'] ? 'password' : 'text'; ?>"
                 name="<?php echo $key; ?>_<?php echo $col; ?>"
                 value="<?php echo $disabled ? '' : htmlspecialchars($dbVal); ?>"
                 placeholder="<?php echo htmlspecialchars($f['placeholder']); ?>"
                 <?php echo $disabled ? 'disabled' : ''; ?>
                 <?php echo $f['password'] ? 'autocomplete="new-password"' : ''; ?>>
        </div>
<?php endforeach; ?>

<?php if (in_array($key, ['agora','zego'])): ?>
        <div style="margin-top:12px;">
          <label class="vapi-label">
            Trial Started
            <span class="vapi-hint">Set once — used on dashboard to show days remaining in 30-day free trial</span>
          </label>
          <input class="vapi-input" type="date"
                 name="<?= $key ?>_trial_started_at"
                 value="<?= htmlspecialchars(substr($d['trial_started_at'] ?? '', 0, 10)) ?>"
                 placeholder="YYYY-MM-DD">
        </div>
<?php endif; ?>
<?php if ($key === 'agora'): ?>
        <hr class="vapi-divider" style="margin-top:16px;">
        <?php if ($agoraTestResult): ?>
          <div class="<?= $agoraTestResult['ok'] ? 'vapi-msg-ok' : 'vapi-msg-err'; ?>" style="margin:8px 0 10px;">
            <?= $agoraTestResult['ok'] ? '&#10003;' : '&#10007;'; ?> <?= htmlspecialchars($agoraTestResult['msg']); ?>
          </div>
        <?php endif; ?>
        <button type="submit" name="_test_agora" value="1"
                style="width:100%;margin-top:4px;background:linear-gradient(135deg,#667eea,#764ba2);color:#fff;border:none;padding:9px 0;border-radius:8px;font-size:13px;font-weight:600;cursor:pointer;">
          Test Agora Token
        </button>
<?php endif; ?>

      </div>
<?php endforeach; ?>

    </div><!-- /grid -->

    <div style="display:flex; align-items:center; gap:16px; flex-wrap:wrap;">
      <button type="submit" class="vapi-save">💾 Save Configuration</button>
      <span style="font-size:13px; opacity:.6;">Changes take effect immediately — no app restart needed.</span>
    </div>
  </form>

  <hr class="vapi-divider" style="margin-top:28px;">

  <?php if ($agoraTestResult): ?>
    <div class="<?= $agoraTestResult['ok'] ? 'vapi-msg-ok' : 'vapi-msg-err'; ?>" style="margin-bottom:18px;">
      <?= $agoraTestResult['ok'] ? '✓' : '✗'; ?> <strong>Agora Token Test:</strong> <?= htmlspecialchars($agoraTestResult['msg']); ?>
    </div>
  <?php endif; ?>

  <form method="post" style="margin-bottom:20px;">
    <input type="hidden" name="_test_agora" value="1">
    <button type="submit" style="background:linear-gradient(135deg,#667eea,#764ba2);color:#fff;border:none;padding:10px 22px;border-radius:8px;font-size:13px;font-weight:600;cursor:pointer;">
      🔑 Test Agora Token
    </button>
    <span style="font-size:12px;opacity:.6;margin-left:10px;">Generates a test token using saved App ID + Server Secret to verify credentials are correct.</span>
  </form>

  <hr class="vapi-divider">
  <div style="font-size:13px; opacity:.7; line-height:1.7;">
    <strong>Field guide:</strong><br>
    <strong>ZegoCloud</strong> — App ID (numeric), App Sign (64-char hex for client SDK), Server Secret (32-char hex for tokens).<br>
    <strong>Agora</strong> — App ID (32-char hex from <em>Project Management</em>), App Certificate (from <em>Primary Certificate</em> — used server-side to generate RTC tokens; leave App Sign blank).<br>
    <strong>Dyte</strong> — Organization ID + API Key (from Developer Portal).<br>
    <strong>Twilio</strong> — Account SID + API Key SID + API Key Secret.
  </div>
</div>

<?php
foreach ([__DIR__.'/_layout_footer.php', __DIR__.'/../_layout_footer.php'] as $f) {
    if (file_exists($f)) { include $f; break; }
}
?>
