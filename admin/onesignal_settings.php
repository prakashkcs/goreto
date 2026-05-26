<?php
require_once __DIR__ . '/_core.php';
admin_require_login();
$pageTitle = 'OneSignal Settings';
$activeNav = 'onesignal_settings';

$pdo->exec("CREATE TABLE IF NOT EXISTS notification_settings (
    id INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    setting_key VARCHAR(80) NOT NULL UNIQUE,
    setting_value TEXT NULL,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

$defaults = [
    'onesignal_enabled' => '0',
    'onesignal_app_id' => '',
    'onesignal_api_key' => '',
    'onesignal_target_mode' => 'segments',
];

$msg = '';
$err = '';
$settings = admin_get_settings($pdo, 'notification_settings', $defaults);

// ── Test send ──────────────────────────────────────────────────────────────
$testResult = null;
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $formAction = $_POST['form_action'] ?? 'save';

    if ($formAction === 'save') {
        try {
            admin_upsert_settings($pdo, 'notification_settings', [
                'onesignal_enabled' => !empty($_POST['onesignal_enabled']) ? '1' : '0',
                'onesignal_app_id' => trim($_POST['onesignal_app_id'] ?? ''),
                'onesignal_api_key' => trim($_POST['onesignal_api_key'] ?? ''),
                'onesignal_target_mode' => $_POST['onesignal_target_mode'] ?? 'segments',
            ]);
            $settings = admin_get_settings($pdo, 'notification_settings', $defaults);
            $msg = 'OneSignal settings saved successfully.';
        } catch (Throwable $e) {
            $err = $e->getMessage();
        }
    } elseif ($formAction === 'test') {
        try {
            $resp = admin_send_push_via_onesignal(
                $settings,
                trim($_POST['test_title'] ?? 'Test Notification'),
                trim($_POST['test_body'] ?? 'This is a test from Love Vibe admin.'),
                [],
                ['type' => 'admin', 'action' => 'test']
            );
            $testResult = ['ok' => true, 'data' => $resp];
        } catch (Throwable $e) {
            $testResult = ['ok' => false, 'error' => $e->getMessage()];
        }
    }
}

// ── Player ID stats ────────────────────────────────────────────────────────
$totalUsers = 0;
$withPlayerId = 0;
try {
    $totalUsers = (int) $pdo->query("SELECT COUNT(*) FROM users")->fetchColumn();
    $col = $pdo->query("SHOW COLUMNS FROM users LIKE 'onesignal_player_id'")->fetch();
    if ($col) {
        $withPlayerId = (int) $pdo->query("SELECT COUNT(*) FROM users WHERE onesignal_player_id IS NOT NULL AND onesignal_player_id != ''")->fetchColumn();
    }
} catch (Throwable $_) {
}

require_once __DIR__ . '/_layout_header.php';
?>

<style>
    .os-card {
        background: #161622;
        border: 1px solid #2a2a3a;
        border-radius: 14px;
        padding: 28px;
        margin-bottom: 24px;
    }

    .os-card h3 {
        margin: 0 0 18px;
        font-size: 16px;
        font-weight: 700;
        color: #e2e8f0;
        display: flex;
        align-items: center;
        gap: 8px;
    }

    .form-row {
        display: grid;
        grid-template-columns: 1fr 1fr;
        gap: 16px;
    }

    .form-group {
        display: flex;
        flex-direction: column;
        gap: 6px;
    }

    .form-group label {
        font-size: 12px;
        font-weight: 600;
        color: #94a3b8;
        text-transform: uppercase;
        letter-spacing: .5px;
    }

    .form-group input,
    .form-group select,
    .form-group textarea {
        background: #0f0f1a;
        border: 1px solid #2a2a3a;
        border-radius: 8px;
        color: #e2e8f0;
        padding: 10px 14px;
        font-size: 14px;
        width: 100%;
        box-sizing: border-box;
    }

    .form-group input:focus,
    .form-group select:focus {
        outline: none;
        border-color: #7c3aed;
    }

    .toggle-row {
        display: flex;
        align-items: center;
        gap: 12px;
        padding: 14px 0;
        border-bottom: 1px solid #1e1e2e;
    }

    .toggle-row:last-child {
        border-bottom: none;
    }

    .toggle-row label {
        flex: 1;
        font-size: 14px;
        color: #e2e8f0;
    }

    .toggle-row small {
        color: #64748b;
        font-size: 12px;
        display: block;
        margin-top: 2px;
    }

    .stat-grid {
        display: grid;
        grid-template-columns: repeat(3, 1fr);
        gap: 16px;
        margin-bottom: 24px;
    }

    .stat-box {
        background: #161622;
        border: 1px solid #2a2a3a;
        border-radius: 12px;
        padding: 20px;
        text-align: center;
    }

    .stat-box .num {
        font-size: 28px;
        font-weight: 800;
        color: #7c3aed;
    }

    .stat-box .lbl {
        font-size: 12px;
        color: #64748b;
        margin-top: 4px;
    }

    .badge-on {
        background: #16a34a22;
        color: #4ade80;
        border: 1px solid #16a34a44;
        padding: 3px 10px;
        border-radius: 999px;
        font-size: 12px;
        font-weight: 700;
    }

    .badge-off {
        background: #dc262622;
        color: #f87171;
        border: 1px solid #dc262644;
        padding: 3px 10px;
        border-radius: 999px;
        font-size: 12px;
        font-weight: 700;
    }

    .alert-ok {
        background: #16a34a22;
        border: 1px solid #16a34a44;
        color: #4ade80;
        padding: 12px 16px;
        border-radius: 8px;
        margin-bottom: 16px;
    }

    .alert-err {
        background: #dc262622;
        border: 1px solid #dc262644;
        color: #f87171;
        padding: 12px 16px;
        border-radius: 8px;
        margin-bottom: 16px;
    }

    pre.json-out {
        background: #0a0a14;
        border: 1px solid #2a2a3a;
        border-radius: 8px;
        padding: 14px;
        font-size: 12px;
        color: #94a3b8;
        overflow-x: auto;
        max-height: 200px;
    }
</style>

<?php if ($msg): ?>
    <div class="alert-ok">✅ <?= htmlspecialchars($msg) ?></div><?php endif; ?>
<?php if ($err): ?>
    <div class="alert-err">❌ <?= htmlspecialchars($err) ?></div><?php endif; ?>

<!-- Stats -->
<div class="stat-grid">
    <div class="stat-box">
        <div class="num"><?= number_format($totalUsers) ?></div>
        <div class="lbl">Total Users</div>
    </div>
    <div class="stat-box">
        <div class="num"><?= number_format($withPlayerId) ?></div>
        <div class="lbl">OneSignal Subscribers</div>
    </div>
    <div class="stat-box">
        <div class="num"><?= $totalUsers > 0 ? round($withPlayerId / $totalUsers * 100) : 0 ?>%</div>
        <div class="lbl">Coverage</div>
    </div>
</div>

<!-- Configuration -->
<form method="POST">
    <input type="hidden" name="form_action" value="save">
    <div class="os-card">
        <h3>🔔 OneSignal Configuration
            <span class="<?= $settings['onesignal_enabled'] === '1' ? 'badge-on' : 'badge-off' ?>">
                <?= $settings['onesignal_enabled'] === '1' ? 'Enabled' : 'Disabled' ?>
            </span>
        </h3>

        <div class="toggle-row">
            <div>
                <label>Enable OneSignal Push</label>
                <small>When enabled, push notifications can be sent via OneSignal in addition to FCM.</small>
            </div>
            <input type="checkbox" name="onesignal_enabled" value="1" <?= $settings['onesignal_enabled'] === '1' ? 'checked' : '' ?>>
        </div>

        <div style="height:16px"></div>

        <div class="form-row">
            <div class="form-group">
                <label>OneSignal App ID</label>
                <input type="text" name="onesignal_app_id"
                    value="<?= htmlspecialchars($settings['onesignal_app_id']) ?>"
                    placeholder="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx">
            </div>
            <div class="form-group">
                <label>REST API Key</label>
                <input type="password" name="onesignal_api_key"
                    value="<?= htmlspecialchars($settings['onesignal_api_key']) ?>"
                    placeholder="Your OneSignal REST API Key">
            </div>
        </div>

        <div style="height:16px"></div>

        <div class="form-group">
            <label>Default Target Mode</label>
            <select name="onesignal_target_mode">
                <option value="segments" <?= $settings['onesignal_target_mode'] === 'segments' ? 'selected' : '' ?>>All
                    Subscribers (Segments)</option>
                <option value="player_ids" <?= $settings['onesignal_target_mode'] === 'player_ids' ? 'selected' : '' ?>>
                    Specific Player IDs</option>
            </select>
        </div>

        <div style="height:20px"></div>
        <button type="submit" class="btn">💾 Save Settings</button>
    </div>
</form>

<!-- Test Send -->
<div class="os-card">
    <h3>🧪 Send Test Notification</h3>
    <p style="color:#64748b;font-size:13px;margin:0 0 16px">
        Sends a test push to <strong>all subscribers</strong> via OneSignal. Requires App ID and API Key to be saved
        first.
    </p>

    <?php if ($testResult !== null): ?>
        <?php if ($testResult['ok']): ?>
            <div class="alert-ok">✅ Test sent successfully!</div>
            <pre class="json-out"><?= htmlspecialchars(json_encode($testResult['data'], JSON_PRETTY_PRINT)) ?></pre>
        <?php else: ?>
            <div class="alert-err">❌ <?= htmlspecialchars($testResult['error']) ?></div>
        <?php endif; ?>
    <?php endif; ?>

    <form method="POST">
        <input type="hidden" name="form_action" value="test">
        <div class="form-row" style="margin-bottom:16px">
            <div class="form-group">
                <label>Title</label>
                <input type="text" name="test_title" value="Test Notification" required>
            </div>
            <div class="form-group">
                <label>Message</label>
                <input type="text" name="test_body" value="Hello from Love Vibe admin!" required>
            </div>
        </div>
        <button type="submit" class="btn" <?= $settings['onesignal_app_id'] === '' ? 'disabled title="Save App ID first"' : '' ?>>
            🚀 Send Test Push
        </button>
    </form>
</div>

<!-- Setup Guide -->
<div class="os-card">
    <h3>📖 Setup Guide</h3>
    <ol style="color:#94a3b8;font-size:13px;line-height:2;padding-left:20px;margin:0">
        <li>Create a free account at <a href="https://onesignal.com" target="_blank"
                style="color:#7c3aed">onesignal.com</a></li>
        <li>Create a new app → choose <strong>Google Android (FCM)</strong> and/or <strong>Apple iOS (APNs)</strong>
        </li>
        <li>Copy your <strong>App ID</strong> and <strong>REST API Key</strong> from Settings → Keys & IDs</li>
        <li>Paste them above and save</li>
        <li>In the Flutter app, <code>onesignal_flutter</code> is already integrated — it will auto-register subscribers
        </li>
        <li>Use the <a href="notifications.php" style="color:#7c3aed">Notifications page</a> to send pushes and choose
            <strong>OneSignal</strong> as the provider</li>
    </ol>
</div>

<?php require_once __DIR__ . '/_layout_footer.php'; ?>