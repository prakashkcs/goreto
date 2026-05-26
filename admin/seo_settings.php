<?php
require_once __DIR__ . '/_core.php';
admin_only();

$pdo = get_db();

// Handle save
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $fields = [
        'seo_title',
        'seo_description',
        'seo_keywords',
        'og_title',
        'og_description',
        'og_image',
        'twitter_card',
        'twitter_title',
        'twitter_description',
        'twitter_image',
        'playstore_url',
        'appstore_url',
        'landing_tagline',
        'landing_desc',
        'ga_tracking_id',
        'fb_pixel_id',
    ];
    foreach ($fields as $key) {
        $val = trim($_POST[$key] ?? '');
        $st = $pdo->prepare("INSERT INTO app_settings (setting_key, setting_value) VALUES (?,?) ON DUPLICATE KEY UPDATE setting_value=?");
        $st->execute([$key, $val, $val]);
    }
    $success = 'SEO settings saved successfully.';
}

// Load current values
function gs($pdo, $key, $default = '')
{
    $st = $pdo->prepare("SELECT setting_value FROM app_settings WHERE setting_key=?");
    $st->execute([$key]);
    return $st->fetchColumn() ?: $default;
}

$v = [];
foreach ([
    'seo_title',
    'seo_description',
    'seo_keywords',
    'og_title',
    'og_description',
    'og_image',
    'twitter_card',
    'twitter_title',
    'twitter_description',
    'twitter_image',
    'playstore_url',
    'appstore_url',
    'landing_tagline',
    'landing_desc',
    'ga_tracking_id',
    'fb_pixel_id'
] as $k) {
    $v[$k] = gs($pdo, $k);
}
?>
<?php include __DIR__ . '/_layout_header.php'; ?>
<div class="container-fluid py-4">
    <div class="row justify-content-center">
        <div class="col-lg-9">
            <div class="card shadow-sm">
                <div class="card-header bg-primary text-white d-flex align-items-center gap-2">
                    <i class="bi bi-search fs-5"></i>
                    <h5 class="mb-0">SEO &amp; Social Sharing Settings</h5>
                </div>
                <div class="card-body">
                    <?php if (!empty($success)): ?>
                        <div class="alert alert-success"><?= htmlspecialchars($success) ?></div>
                    <?php endif; ?>
                    <form method="POST" enctype="multipart/form-data">

                        <!-- Basic SEO -->
                        <h6 class="text-muted fw-bold mb-3 mt-2"><i class="bi bi-globe me-1"></i> Basic SEO</h6>
                        <div class="mb-3">
                            <label class="form-label">Page Title <small class="text-muted">(50–60 chars
                                    ideal)</small></label>
                            <input type="text" name="seo_title" class="form-control" maxlength="120"
                                value="<?= htmlspecialchars($v['seo_title'] ?: 'Goreto – Meet. Connect. Earn.') ?>">
                        </div>
                        <div class="mb-3">
                            <label class="form-label">Meta Description <small class="text-muted">(150–160 chars
                                    ideal)</small></label>
                            <textarea name="seo_description" class="form-control" rows="2"
                                maxlength="320"><?= htmlspecialchars($v['seo_description'] ?: "Nepal's #1 social app with random video calls, live streaming, dating matches, and real earning opportunities.") ?></textarea>
                        </div>
                        <div class="mb-4">
                            <label class="form-label">Keywords <small class="text-muted">(comma
                                    separated)</small></label>
                            <input type="text" name="seo_keywords" class="form-control"
                                value="<?= htmlspecialchars($v['seo_keywords'] ?: 'goreto, nepal dating app, video call nepal, live streaming nepal, earn money nepal') ?>">
                        </div>

                        <hr>
                        <!-- Open Graph -->
                        <h6 class="text-muted fw-bold mb-3"><i class="bi bi-facebook me-1"></i> Open Graph (Facebook /
                            WhatsApp / LinkedIn)</h6>
                        <div class="mb-3">
                            <label class="form-label">OG Title</label>
                            <input type="text" name="og_title" class="form-control"
                                value="<?= htmlspecialchars($v['og_title'] ?: 'Goreto – Meet. Connect. Earn.') ?>">
                        </div>
                        <div class="mb-3">
                            <label class="form-label">OG Description</label>
                            <textarea name="og_description" class="form-control"
                                rows="2"><?= htmlspecialchars($v['og_description'] ?: "Nepal's #1 social app. Random video calls, live streaming, dating & real earnings.") ?></textarea>
                        </div>
                        <div class="mb-4">
                            <label class="form-label">OG Image URL <small class="text-muted">(1200×630px
                                    recommended)</small></label>
                            <input type="url" name="og_image" class="form-control"
                                placeholder="https://goreto.org/og-image.jpg"
                                value="<?= htmlspecialchars($v['og_image']) ?>">
                            <?php if ($v['og_image']): ?>
                                <div class="mt-2"><img src="<?= htmlspecialchars($v['og_image']) ?>"
                                        style="max-height:120px;border-radius:8px;border:1px solid #dee2e6"></div>
                            <?php endif; ?>
                        </div>

                        <hr>
                        <!-- Twitter Card -->
                        <h6 class="text-muted fw-bold mb-3"><i class="bi bi-twitter-x me-1"></i> Twitter / X Card</h6>
                        <div class="mb-3">
                            <label class="form-label">Card Type</label>
                            <select name="twitter_card" class="form-select">
                                <option value="summary_large_image"
                                    <?= $v['twitter_card'] === 'summary_large_image' ? 'selected' : '' ?>>summary_large_image
                                    (recommended)</option>
                                <option value="summary" <?= $v['twitter_card'] === 'summary' ? 'selected' : '' ?>>summary
                                </option>
                            </select>
                        </div>
                        <div class="mb-3">
                            <label class="form-label">Twitter Title</label>
                            <input type="text" name="twitter_title" class="form-control"
                                value="<?= htmlspecialchars($v['twitter_title'] ?: 'Goreto – Meet. Connect. Earn.') ?>">
                        </div>
                        <div class="mb-3">
                            <label class="form-label">Twitter Description</label>
                            <textarea name="twitter_description" class="form-control"
                                rows="2"><?= htmlspecialchars($v['twitter_description'] ?: "Nepal's #1 social app. Random video calls, live streaming, dating & real earnings.") ?></textarea>
                        </div>
                        <div class="mb-4">
                            <label class="form-label">Twitter Image URL <small class="text-muted">(1200×628px
                                    recommended)</small></label>
                            <input type="url" name="twitter_image" class="form-control"
                                placeholder="https://goreto.org/twitter-card.jpg"
                                value="<?= htmlspecialchars($v['twitter_image']) ?>">
                        </div>

                        <hr>
                        <!-- App Store Links -->
                        <h6 class="text-muted fw-bold mb-3"><i class="bi bi-phone me-1"></i> App Download Links</h6>
                        <div class="mb-3">
                            <label class="form-label"><i class="bi bi-google-play me-1 text-success"></i> Google Play
                                URL</label>
                            <input type="url" name="playstore_url" class="form-control"
                                placeholder="https://play.google.com/store/apps/details?id=..."
                                value="<?= htmlspecialchars($v['playstore_url']) ?>">
                        </div>
                        <div class="mb-4">
                            <label class="form-label"><i class="bi bi-apple me-1"></i> App Store URL</label>
                            <input type="url" name="appstore_url" class="form-control"
                                placeholder="https://apps.apple.com/app/..."
                                value="<?= htmlspecialchars($v['appstore_url']) ?>">
                        </div>

                        <hr>
                        <!-- Landing Page Copy -->
                        <h6 class="text-muted fw-bold mb-3"><i class="bi bi-layout-text-window me-1"></i> Landing Page
                            Copy</h6>
                        <div class="mb-3">
                            <label class="form-label">Hero Tagline</label>
                            <input type="text" name="landing_tagline" class="form-control"
                                value="<?= htmlspecialchars($v['landing_tagline'] ?: 'Meet. Connect. Earn.') ?>">
                        </div>
                        <div class="mb-4">
                            <label class="form-label">Hero Sub-description</label>
                            <textarea name="landing_desc" class="form-control"
                                rows="2"><?= htmlspecialchars($v['landing_desc'] ?: "Nepal's #1 social app with random video calls, live streaming, dating matches, and real earning opportunities.") ?></textarea>
                        </div>

                        <hr>
                        <!-- Analytics -->
                        <h6 class="text-muted fw-bold mb-3"><i class="bi bi-bar-chart me-1"></i> Analytics &amp;
                            Tracking</h6>
                        <div class="mb-3">
                            <label class="form-label">Google Analytics Tracking ID <small class="text-muted">(e.g.
                                    G-XXXXXXXXXX)</small></label>
                            <input type="text" name="ga_tracking_id" class="form-control" placeholder="G-XXXXXXXXXX"
                                value="<?= htmlspecialchars($v['ga_tracking_id']) ?>">
                        </div>
                        <div class="mb-4">
                            <label class="form-label">Facebook Pixel ID</label>
                            <input type="text" name="fb_pixel_id" class="form-control" placeholder="123456789012345"
                                value="<?= htmlspecialchars($v['fb_pixel_id']) ?>">
                        </div>

                        <div class="d-flex gap-2">
                            <button type="submit" class="btn btn-primary px-4">
                                <i class="bi bi-save me-1"></i> Save Settings
                            </button>
                            <a href="dashboard.php" class="btn btn-outline-secondary">Cancel</a>
                        </div>
                    </form>
                </div>
            </div>
        </div>
    </div>
</div>
<?php include __DIR__ . '/_layout_footer.php'; ?>