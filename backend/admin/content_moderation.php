<?php
require_once __DIR__ . '/_core.php';
admin_require_login();

require_once __DIR__ . '/../api/v1/content_moderation.php';

$pageTitle = 'Content Moderation';
$activeNav = 'content_moderation';

$settings = cm_load_settings($pdo);
$msg = '';

// ── Handle form save ──────────────────────────────────────────────────────────
if ($_SERVER['REQUEST_METHOD'] === 'POST' && ($_POST['_action'] ?? '') === 'save') {
    $provider    = in_array($_POST['provider'] ?? '', ['none', 'google', 'aws'], true) ? $_POST['provider'] : 'none';
    $sensitivity = in_array($_POST['sensitivity'] ?? '', ['strict', 'moderate', 'relaxed'], true) ? $_POST['sensitivity'] : 'moderate';

    $data = [
        'enabled'        => empty($_POST['enabled']) ? 0 : 1,
        'provider'       => $provider,
        'sensitivity'    => $sensitivity,
        'block_adult'    => empty($_POST['block_adult'])    ? 0 : 1,
        'block_violence' => empty($_POST['block_violence']) ? 0 : 1,
        'block_racy'     => empty($_POST['block_racy'])     ? 0 : 1,
        'google_api_key' => trim($_POST['google_api_key'] ?? ''),
        'aws_access_key' => trim($_POST['aws_access_key'] ?? ''),
        'aws_secret_key' => trim($_POST['aws_secret_key'] ?? ''),
        'aws_region'     => trim($_POST['aws_region']     ?? 'us-east-1'),
    ];

    try {
        $existing = $pdo->query("SELECT id FROM content_moderation_settings LIMIT 1")->fetch(PDO::FETCH_ASSOC);
        if ($existing) {
            $pdo->prepare("UPDATE content_moderation_settings SET
                enabled=:enabled, provider=:provider, sensitivity=:sensitivity,
                block_adult=:block_adult, block_violence=:block_violence, block_racy=:block_racy,
                google_api_key=:google_api_key,
                aws_access_key=:aws_access_key, aws_secret_key=:aws_secret_key, aws_region=:aws_region
                WHERE id=:id"
            )->execute(array_merge($data, ['id' => $existing['id']]));
        } else {
            $cols = implode(',', array_keys($data));
            $vals = ':' . implode(',:', array_keys($data));
            $pdo->prepare("INSERT INTO content_moderation_settings ($cols) VALUES ($vals)")->execute($data);
        }
        $settings = array_merge($settings, $data);
        $msg = '<div class="msg ok">Settings saved successfully.</div>';
    } catch (Throwable $e) {
        $msg = '<div class="msg err">Error: ' . htmlspecialchars($e->getMessage()) . '</div>';
    }
}

// ── Handle test moderation ────────────────────────────────────────────────────
$testResult = null;
if ($_SERVER['REQUEST_METHOD'] === 'POST' && ($_POST['_action'] ?? '') === 'test' && isset($_FILES['test_file'])) {
    $tmpPath = $_FILES['test_file']['tmp_name'];
    $origExt = strtolower(pathinfo($_FILES['test_file']['name'], PATHINFO_EXTENSION));
    $testPath = sys_get_temp_dir() . '/cm_test_' . uniqid() . '.' . $origExt;
    if (move_uploaded_file($tmpPath, $testPath)) {
        $testResult = cm_moderate($testPath, $origExt, $settings);
        @unlink($testPath);
    } else {
        $testResult = ['safe' => true, 'error' => 'Could not move uploaded test file'];
    }
}

// ── Stats ─────────────────────────────────────────────────────────────────────
$stats = ['total' => 0, 'blocked' => 0, 'safe' => 0, 'error' => 0, 'skipped' => 0];
try {
    $rows = $pdo->query("SELECT result, COUNT(*) AS cnt FROM moderation_log GROUP BY result")->fetchAll(PDO::FETCH_ASSOC);
    foreach ($rows as $r) {
        $stats[$r['result']] = (int)$r['cnt'];
        $stats['total'] += (int)$r['cnt'];
    }
} catch (Throwable $e) {}

$recentLogs = [];
try {
    $recentLogs = $pdo->query("
        SELECT ml.*, u.name as user_name, u.username
        FROM moderation_log ml
        LEFT JOIN users u ON ml.user_id = u.id
        ORDER BY ml.id DESC LIMIT 30
    ")->fetchAll(PDO::FETCH_ASSOC);
} catch (Throwable $e) {}

include __DIR__ . '/_layout_header.php';
?>

<style>
  .cm-grid { display:grid; grid-template-columns:1fr 1fr; gap:20px; margin-bottom:20px }
  .cm-card { background:#111827; border:1px solid #1f2937; border-radius:12px; padding:20px }
  .cm-card h3 { color:#d946ef; font-size:14px; font-weight:700; letter-spacing:1px; text-transform:uppercase; margin-bottom:16px }
  .field { margin-bottom:14px }
  .field label { display:block; color:#9ca3af; font-size:12px; font-weight:600; margin-bottom:6px; text-transform:uppercase; letter-spacing:.5px }
  .field input[type=text], .field input[type=password], .field select {
    width:100%; padding:10px 12px; background:#0d1117; border:1px solid #374151;
    border-radius:8px; color:#f9fafb; font-size:14px; outline:none;
    transition: border-color .2s;
  }
  .field input:focus, .field select:focus { border-color:#d946ef }
  .toggle-row { display:flex; align-items:center; gap:10px; padding:10px 0; border-bottom:1px solid #1f2937 }
  .toggle-row:last-child { border-bottom:none }
  .toggle-row label { flex:1; color:#e5e7eb; font-size:14px; cursor:pointer }
  .toggle-row small { color:#6b7280; font-size:12px; display:block; margin-top:2px }
  input[type=checkbox] { width:18px; height:18px; accent-color:#d946ef; cursor:pointer; flex-shrink:0 }
  .btn-save { background:linear-gradient(135deg,#d946ef,#8b5cf6); color:#fff; border:none; padding:12px 28px;
              border-radius:8px; font-size:14px; font-weight:700; cursor:pointer; margin-top:4px }
  .btn-test { background:#1f2937; color:#e5e7eb; border:1px solid #374151; padding:10px 20px;
              border-radius:8px; font-size:13px; font-weight:600; cursor:pointer }
  .msg { padding:12px 16px; border-radius:8px; margin-bottom:16px; font-weight:600; font-size:14px }
  .msg.ok  { background:rgba(34,197,94,.12); color:#4ade80; border:1px solid rgba(34,197,94,.3) }
  .msg.err { background:rgba(239,68,68,.12);  color:#f87171; border:1px solid rgba(239,68,68,.3) }
  .stat-grid { display:grid; grid-template-columns:repeat(5,1fr); gap:12px; margin-bottom:24px }
  .stat-box { background:#111827; border:1px solid #1f2937; border-radius:10px; padding:16px; text-align:center }
  .stat-box .num { font-size:28px; font-weight:900; margin-bottom:4px }
  .stat-box .lbl { font-size:11px; color:#6b7280; text-transform:uppercase; letter-spacing:.5px }
  .stat-box.blocked .num { color:#f87171 }
  .stat-box.safe    .num { color:#4ade80 }
  .stat-box.skip    .num { color:#fbbf24 }
  .stat-box.err     .num { color:#fb923c }
  .stat-box.total   .num { color:#a78bfa }
  .log-table { width:100%; border-collapse:collapse; font-size:13px }
  .log-table th { background:#0d1117; color:#6b7280; padding:10px 12px; text-align:left; font-size:11px; text-transform:uppercase; letter-spacing:.5px }
  .log-table td { padding:10px 12px; border-bottom:1px solid #1f2937; color:#e5e7eb; vertical-align:middle }
  .badge { display:inline-block; padding:3px 8px; border-radius:5px; font-size:11px; font-weight:700 }
  .badge.safe    { background:rgba(34,197,94,.15);  color:#4ade80 }
  .badge.blocked { background:rgba(239,68,68,.15);  color:#f87171 }
  .badge.skipped { background:rgba(251,191,36,.12); color:#fbbf24 }
  .badge.error   { background:rgba(251,146,60,.15); color:#fb923c }
  .provider-tabs { display:flex; gap:8px; margin-bottom:16px }
  .provider-tab  { padding:8px 16px; border-radius:8px; border:1px solid #374151; background:#0d1117;
                   color:#9ca3af; font-size:13px; font-weight:600; cursor:pointer; transition:all .2s }
  .provider-tab.active { background:rgba(217,70,239,.15); border-color:#d946ef; color:#d946ef }
  .test-result { margin-top:16px; padding:14px; border-radius:8px; font-size:14px }
  .test-result.safe    { background:rgba(34,197,94,.1);  border:1px solid rgba(34,197,94,.3);  color:#4ade80 }
  .test-result.blocked { background:rgba(239,68,68,.1);  border:1px solid rgba(239,68,68,.3);  color:#f87171 }
  .test-result.skipped { background:rgba(251,191,36,.1); border:1px solid rgba(251,191,36,.3); color:#fbbf24 }
  @media(max-width:900px){.cm-grid{grid-template-columns:1fr}.stat-grid{grid-template-columns:repeat(3,1fr)}}
</style>

<div style="color:#f9fafb">

  <!-- Stats -->
  <div class="stat-grid">
    <div class="stat-box total"><div class="num"><?= number_format($stats['total']) ?></div><div class="lbl">Total Checked</div></div>
    <div class="stat-box blocked"><div class="num"><?= number_format($stats['blocked']) ?></div><div class="lbl">Blocked</div></div>
    <div class="stat-box safe"><div class="num"><?= number_format($stats['safe']) ?></div><div class="lbl">Safe</div></div>
    <div class="stat-box skip"><div class="num"><?= number_format($stats['skipped']) ?></div><div class="lbl">Skipped</div></div>
    <div class="stat-box err"><div class="num"><?= number_format($stats['error']) ?></div><div class="lbl">Errors</div></div>
  </div>

  <?= $msg ?>

  <form method="post" enctype="multipart/form-data">
  <input type="hidden" name="_action" value="save">

  <div class="cm-grid">

    <!-- Left: Master toggle + sensitivity -->
    <div>
      <div class="cm-card">
        <h3>Moderation Settings</h3>

        <div class="toggle-row">
          <input type="checkbox" id="enabled" name="enabled" value="1" <?= !empty($settings['enabled']) ? 'checked' : '' ?>>
          <label for="enabled">
            Enable Content Moderation
            <small>Scan every uploaded image / video before publishing</small>
          </label>
        </div>

        <div class="toggle-row" style="margin-top:8px">
          <input type="checkbox" id="block_adult" name="block_adult" value="1" <?= !empty($settings['block_adult']) ? 'checked' : '' ?>>
          <label for="block_adult">Block Adult / Explicit Content</label>
        </div>

        <div class="toggle-row">
          <input type="checkbox" id="block_violence" name="block_violence" value="1" <?= !empty($settings['block_violence']) ? 'checked' : '' ?>>
          <label for="block_violence">Block Violent Content</label>
        </div>

        <div class="toggle-row">
          <input type="checkbox" id="block_racy" name="block_racy" value="1" <?= !empty($settings['block_racy']) ? 'checked' : '' ?>>
          <label for="block_racy">
            Block Racy / Suggestive Content
            <small>Only applies to Google Vision provider</small>
          </label>
        </div>

        <div class="field" style="margin-top:16px">
          <label>Detection Sensitivity</label>
          <select name="sensitivity">
            <?php foreach (['strict' => 'Strict — block POSSIBLE and above',
                             'moderate' => 'Moderate — block LIKELY and above (recommended)',
                             'relaxed'  => 'Relaxed — block VERY_LIKELY only'] as $val => $label): ?>
            <option value="<?= $val ?>" <?= ($settings['sensitivity'] ?? 'moderate') === $val ? 'selected' : '' ?>><?= $label ?></option>
            <?php endforeach ?>
          </select>
        </div>

        <div class="field">
          <label>Active Provider</label>
          <select name="provider" id="providerSelect" onchange="showProvider(this.value)">
            <option value="none"   <?= ($settings['provider'] ?? 'none') === 'none'   ? 'selected' : '' ?>>None (disabled)</option>
            <option value="google" <?= ($settings['provider'] ?? 'none') === 'google' ? 'selected' : '' ?>>Google Cloud Vision</option>
            <option value="aws"    <?= ($settings['provider'] ?? 'none') === 'aws'    ? 'selected' : '' ?>>Amazon Rekognition</option>
          </select>
        </div>

        <button type="submit" class="btn-save">Save Settings</button>
      </div>
    </div>

    <!-- Right: API credentials -->
    <div>
      <!-- Google Vision -->
      <div class="cm-card" id="panel-google" style="<?= ($settings['provider'] ?? 'none') !== 'google' ? 'opacity:.5' : '' ?>">
        <h3>Google Cloud Vision API</h3>
        <p style="color:#6b7280;font-size:13px;margin-bottom:14px">
          Uses SafeSearch Detection. Get your key at
          <a href="https://console.cloud.google.com/apis/credentials" target="_blank" style="color:#d946ef">console.cloud.google.com</a>.
          Enable the <b>Cloud Vision API</b> in your project.
        </p>
        <div class="field">
          <label>API Key</label>
          <input type="password" name="google_api_key" value="<?= htmlspecialchars($settings['google_api_key'] ?? '') ?>" placeholder="AIza…">
        </div>
        <div style="background:#0d1117;border:1px solid #1f2937;border-radius:8px;padding:12px;font-size:12px;color:#6b7280">
          <b style="color:#9ca3af">Billing note:</b> SafeSearch detection is ~$1.50 per 1000 images. First 1000/month free.
        </div>
      </div>

      <!-- AWS Rekognition -->
      <div class="cm-card" id="panel-aws" style="margin-top:16px;<?= ($settings['provider'] ?? 'none') !== 'aws' ? 'opacity:.5' : '' ?>">
        <h3>Amazon Rekognition</h3>
        <p style="color:#6b7280;font-size:13px;margin-bottom:14px">
          Uses DetectModerationLabels. Create IAM credentials with
          <code style="color:#d946ef">rekognition:DetectModerationLabels</code> permission.
        </p>
        <div class="field">
          <label>Access Key ID</label>
          <input type="text" name="aws_access_key" value="<?= htmlspecialchars($settings['aws_access_key'] ?? '') ?>" placeholder="AKIA…">
        </div>
        <div class="field">
          <label>Secret Access Key</label>
          <input type="password" name="aws_secret_key" value="<?= htmlspecialchars($settings['aws_secret_key'] ?? '') ?>" placeholder="…">
        </div>
        <div class="field">
          <label>AWS Region</label>
          <select name="aws_region">
            <?php
            $regions = ['us-east-1','us-east-2','us-west-1','us-west-2','eu-west-1','eu-west-2','eu-central-1','ap-southeast-1','ap-southeast-2','ap-northeast-1'];
            foreach ($regions as $r): ?>
            <option value="<?= $r ?>" <?= ($settings['aws_region'] ?? 'us-east-1') === $r ? 'selected' : '' ?>><?= $r ?></option>
            <?php endforeach ?>
          </select>
        </div>
        <div style="background:#0d1117;border:1px solid #1f2937;border-radius:8px;padding:12px;font-size:12px;color:#6b7280">
          <b style="color:#9ca3af">Billing note:</b> ~$0.001 per image. First 5000/month free for first 12 months.
        </div>
      </div>
    </div>

  </div>
  </form>

  <!-- Test Upload -->
  <div class="cm-card" style="margin-bottom:24px">
    <h3>Test Moderation</h3>
    <p style="color:#9ca3af;font-size:13px;margin-bottom:14px">Upload an image or video to test the current moderation configuration.</p>
    <form method="post" enctype="multipart/form-data" style="display:flex;align-items:center;gap:12px;flex-wrap:wrap">
      <input type="hidden" name="_action" value="test">
      <input type="file" name="test_file" accept="image/*,video/*"
             style="background:#0d1117;border:1px solid #374151;border-radius:8px;padding:8px 12px;color:#e5e7eb;font-size:13px">
      <button type="submit" class="btn-test">Run Test</button>
    </form>
    <?php if ($testResult !== null):
      $cls = ($testResult['safe'] ?? true) ? (empty($testResult['skipped']) ? 'safe' : 'skipped') : 'blocked';
    ?>
    <div class="test-result <?= $cls ?>">
      <?php if ($cls === 'safe'): ?>
        ✅ <b>Content is safe</b> — Provider: <?= htmlspecialchars($testResult['provider'] ?? 'n/a') ?>
      <?php elseif ($cls === 'skipped'): ?>
        ⏭️ <b>Skipped</b> — <?= htmlspecialchars($testResult['reason'] ?? $testResult['error'] ?? '') ?>
      <?php else: ?>
        🚫 <b>Blocked:</b> <?= htmlspecialchars($testResult['reason'] ?? '') ?>
        <?php if (!empty($testResult['label'])): ?> — Label: <code><?= htmlspecialchars($testResult['label']) ?></code><?php endif ?>
        <?php if (!empty($testResult['confidence'])): ?> (confidence: <?= round($testResult['confidence'], 1) ?>%)<?php endif ?>
      <?php endif ?>
      <?php if (!empty($testResult['error'])): ?>
        <br><small style="opacity:.7">Error: <?= htmlspecialchars($testResult['error']) ?></small>
      <?php endif ?>
    </div>
    <?php endif ?>
  </div>

  <!-- Recent Moderation Log -->
  <div class="cm-card">
    <h3>Recent Moderation Log</h3>
    <?php if (empty($recentLogs)): ?>
      <p style="color:#6b7280;font-size:13px">No moderation events yet. Logs appear here once content is uploaded.</p>
    <?php else: ?>
    <div style="overflow-x:auto">
    <table class="log-table">
      <thead>
        <tr>
          <th>Time</th>
          <th>User</th>
          <th>Post</th>
          <th>File</th>
          <th>Provider</th>
          <th>Result</th>
          <th>Reason</th>
        </tr>
      </thead>
      <tbody>
        <?php foreach ($recentLogs as $log): ?>
        <tr>
          <td style="white-space:nowrap;color:#6b7280"><?= htmlspecialchars(substr($log['created_at'] ?? '', 0, 16)) ?></td>
          <td><?= htmlspecialchars($log['user_name'] ?? '—') ?><?= !empty($log['username']) ? '<br><small style="color:#6b7280">@'.$log['username'].'</small>' : '' ?></td>
          <td><?= $log['post_id'] ? '<a href="posts.php?id='.(int)$log['post_id'].'" style="color:#d946ef">#'.(int)$log['post_id'].'</a>' : '—' ?></td>
          <td style="font-family:monospace;font-size:11px;color:#6b7280"><?= htmlspecialchars(substr($log['file_path'] ?? '', -30)) ?></td>
          <td><span style="color:#a78bfa"><?= htmlspecialchars($log['provider'] ?: '—') ?></span></td>
          <td><span class="badge <?= $log['result'] ?>"><?= $log['result'] ?></span></td>
          <td style="color:#9ca3af"><?= htmlspecialchars($log['reason'] ?? '') ?></td>
        </tr>
        <?php endforeach ?>
      </tbody>
    </table>
    </div>
    <?php endif ?>
  </div>

</div>

<script>
function showProvider(v) {
  ['google','aws'].forEach(p => {
    const el = document.getElementById('panel-' + p);
    if (el) el.style.opacity = (v === p) ? '1' : '.5';
  });
}
</script>

<?php include __DIR__ . '/_layout_footer.php'; ?>
