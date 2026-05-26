<?php
require_once __DIR__ . '/_core.php';
admin_require_login();

$pageTitle = 'App Store & Landing Page Links';
$activeNav = 'app_store_settings';

$defaults = [
    'playstore_url' => '',
    'appstore_url' => '',
    'landing_tagline' => 'Meet. Connect. Earn.',
    'landing_desc' => 'Goreto is Nepal\'s #1 social dating app with random video calls, live streaming, and real earning opportunities.',
];

$settings = admin_get_settings($pdo, 'app_settings', $defaults);

$saved = false;
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $values = [];
    foreach ($defaults as $k => $_) {
        $values[$k] = trim($_POST[$k] ?? '');
    }
    admin_upsert_settings($pdo, 'app_settings', $values);
    $settings = array_merge($settings, $values);
    $saved = true;
}

require __DIR__ . '/_layout_header.php';
?>
<style>
    .form-group {
        margin-bottom: 18px;
    }

    .form-group label {
        display: block;
        font-size: 13px;
        opacity: .8;
        margin-bottom: 6px;
    }

    .form-group input,
    .form-group textarea {
        width: 100%;
        padding: 10px 14px;
        background: rgba(15, 27, 51, .6);
        border: 1px solid #223a66;
        border-radius: 8px;
        color: #e2e8f0;
        font-size: 14px;
        box-sizing: border-box;
    }

    .form-group textarea {
        min-height: 80px;
        resize: vertical;
    }

    .form-group input:focus,
    .form-group textarea:focus {
        outline: none;
        border-color: #7c3aed;
    }

    .save-banner {
        background: rgba(16, 185, 129, .15);
        border: 1px solid #10b981;
        border-radius: 8px;
        padding: 10px 16px;
        margin-bottom: 18px;
        color: #10b981;
        font-size: 14px;
    }

    .hint {
        font-size: 11px;
        opacity: .55;
        margin-top: 4px;
    }
</style>

<div class="section">
    <div class="head">
        <b>App Store &amp; Landing Page Settings</b>
        <small>These links appear on the goreto.org landing page download buttons</small>
    </div>
    <div class="body">
        <?php if ($saved): ?>
            <div class="save-banner">✓ Settings saved successfully.</div>
        <?php endif; ?>

        <form method="POST">
            <div class="form-group">
                <label>Google Play Store URL</label>
                <input type="url" name="playstore_url" value="<?= htmlspecialchars($settings['playstore_url'] ?? '') ?>"
                    placeholder="https://play.google.com/store/apps/details?id=com.nex.ekloapp">
                <div class="hint">Full URL to your Play Store listing</div>
            </div>

            <div class="form-group">
                <label>Apple App Store URL</label>
                <input type="url" name="appstore_url" value="<?= htmlspecialchars($settings['appstore_url'] ?? '') ?>"
                    placeholder="https://apps.apple.com/app/goreto/id...">
                <div class="hint">Full URL to your App Store listing</div>
            </div>

            <div class="form-group">
                <label>Landing Page Tagline</label>
                <input type="text" name="landing_tagline"
                    value="<?= htmlspecialchars($settings['landing_tagline'] ?? 'Meet. Connect. Earn.') ?>"
                    placeholder="Meet. Connect. Earn.">
                <div class="hint">Short hero tagline shown on the landing page</div>
            </div>

            <div class="form-group">
                <label>Landing Page Description</label>
                <textarea name="landing_desc"><?= htmlspecialchars($settings['landing_desc'] ?? '') ?></textarea>
                <div class="hint">Short paragraph below the tagline</div>
            </div>

            <button type="submit" class="btn"
                style="background:#7c3aed;border:none;cursor:pointer;padding:10px 28px;border-radius:8px;color:#fff;font-weight:700;">
                Save Settings
            </button>
        </form>
    </div>
</div>

<?php require __DIR__ . '/_layout_footer.php'; ?>