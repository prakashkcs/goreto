<?php
require_once __DIR__ . '/_core.php';
admin_require_login();

$pageTitle = 'Legal Pages';
$activeNav = 'legal';

// FTP credentials
define('FTP_HOST', 'goreto.org');
define('FTP_USER', 'ekloadmin@goreto.org');
define('FTP_PASS', 'Prakas12@');
// FTP root = ekloadmin/ on the server
// Live file path = ekloadmin/api/v1/api_legal.php
// Local source file in this project = /api_legal.php
$FTP_REMOTE_PATHS = [
    'api/v1/api_legal.php',
];
$LOCAL_API_LEGAL = dirname(__DIR__) . '/api_legal.php';

// Ensure table
try {
    $pdo->exec("CREATE TABLE IF NOT EXISTS legal_pages (
        id INT AUTO_INCREMENT PRIMARY KEY,
        page_key VARCHAR(50) NOT NULL UNIQUE,
        title VARCHAR(255) NOT NULL,
        content LONGTEXT NOT NULL,
        updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci");
} catch (Throwable $e) {
}

// ── FTP deploy helper ────────────────────────────────────────────────────────
function ftp_deploy_file(string $localFile, array $remotePaths): array
{
    if (!function_exists('ftp_connect')) {
        return ['ok' => false, 'msg' => 'PHP FTP extension not available on this server.'];
    }
    if (!file_exists($localFile)) {
        return ['ok' => false, 'msg' => "Local file not found: $localFile"];
    }

    $conn = @ftp_connect(FTP_HOST, 21, 10);
    if (!$conn) {
        return ['ok' => false, 'msg' => 'Could not connect to FTP server: ' . FTP_HOST];
    }
    if (!@ftp_login($conn, FTP_USER, FTP_PASS)) {
        ftp_close($conn);
        return ['ok' => false, 'msg' => 'FTP login failed. Check credentials.'];
    }
    ftp_pasv($conn, true);

    $lastErr = '';
    foreach ($remotePaths as $remotePath) {
        if (@ftp_put($conn, $remotePath, $localFile, FTP_BINARY)) {
            ftp_close($conn);
            return ['ok' => true, 'msg' => "Deployed to $remotePath on " . FTP_HOST];
        }
        $lastErr = $remotePath;
    }

    ftp_close($conn);
    return ['ok' => false, 'msg' => "FTP upload failed. Last tried: $lastErr"];
}

// ── Handle actions ───────────────────────────────────────────────────────────
$saved = '';
$saveError = '';
$deployMsg = '';
$deployOk = false;

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $action = $_POST['_action'] ?? 'save';

    // ── Save content ──────────────────────────────────────────────────────────
    if ($action === 'save') {
        $key = in_array($_POST['page_key'] ?? '', ['terms', 'privacy']) ? $_POST['page_key'] : '';
        $title = trim($_POST['title'] ?? '');
        $content = trim($_POST['content'] ?? '');
        if ($key && $title && $content) {
            $pdo->prepare("INSERT INTO legal_pages (page_key, title, content) VALUES (?,?,?)
                ON DUPLICATE KEY UPDATE title=VALUES(title), content=VALUES(content), updated_at=NOW()")
                ->execute([$key, $title, $content]);
            $saved = $key;
        } else {
            $saveError = 'All fields are required.';
        }
    }

    // ── Deploy api_legal.php via FTP ──────────────────────────────────────────
    if ($action === 'deploy') {
        $result = ftp_deploy_file($LOCAL_API_LEGAL, $FTP_REMOTE_PATHS);
        $deployOk = $result['ok'];
        $deployMsg = $result['msg'];
    }
}

// Load both pages
function load_page($pdo, $key)
{
    $stmt = $pdo->prepare("SELECT title, content, updated_at FROM legal_pages WHERE page_key = ?");
    $stmt->execute([$key]);
    return $stmt->fetch(PDO::FETCH_ASSOC);
}

$terms = load_page($pdo, 'terms');
$privacy = load_page($pdo, 'privacy');

// Default content
$defaultTerms = <<<HTML
<h2>Terms of Service</h2>
<p><strong>Last updated: January 1, 2025</strong></p>
<p>Welcome to <strong>Love Vibe</strong> ("App", "we", "us", or "our"). By downloading, installing, or using our application, you agree to be bound by these Terms of Service ("Terms"). Please read them carefully.</p>

<h3>1. Eligibility</h3>
<p>You must be at least <strong>18 years of age</strong> to use Love Vibe. By using the App, you represent and warrant that you are 18 or older. We do not knowingly allow minors to use the App. If we discover a user is under 18, their account will be immediately terminated.</p>

<h3>2. Account Registration</h3>
<p>You agree to provide accurate, current, and complete information during registration. You are responsible for maintaining the confidentiality of your account credentials. You are fully responsible for all activities that occur under your account.</p>

<h3>3. Acceptable Use</h3>
<p>You agree NOT to post illegal, harmful, or abusive content; impersonate others; upload CSAM (strictly prohibited and reported to law enforcement); harass or threaten users; use bots or scrapers; sell or transfer your account; or engage in fraud.</p>

<h3>4. User Content</h3>
<p>You retain ownership of content you post. By posting, you grant Love Vibe a license to display and distribute your content within the App. We reserve the right to remove content that violates these Terms.</p>

<h3>5. Virtual Currency &amp; Payments</h3>
<p>All purchases are final and non-refundable unless required by law. Virtual currency has no real-world monetary value.</p>

<h3>6. Subscriptions</h3>
<p>Subscriptions auto-renew unless cancelled before renewal. Manage subscriptions through your device's app store settings.</p>

<h3>7. KYC &amp; Identity Verification</h3>
<p>We may require identity verification for certain features. All documents are handled per our Privacy Policy.</p>

<h3>8. Disclaimers</h3>
<p>THE APP IS PROVIDED "AS IS" WITHOUT WARRANTIES. WE ARE NOT RESPONSIBLE FOR USER INTERACTIONS.</p>

<h3>9. Limitation of Liability</h3>
<p>TO THE MAXIMUM EXTENT PERMITTED BY LAW, LOVE VIBE SHALL NOT BE LIABLE FOR ANY INDIRECT OR CONSEQUENTIAL DAMAGES.</p>

<h3>10. Termination</h3>
<p>We reserve the right to suspend or terminate accounts for violations of these Terms.</p>

<h3>11. Contact Us</h3>
<p>Questions? Contact us at: <strong>support@lovevibe.app</strong></p>
HTML;

$defaultPrivacy = <<<HTML
<h2>Privacy Policy</h2>
<p><strong>Last updated: January 1, 2025</strong></p>
<p>Love Vibe is committed to protecting your privacy. This policy explains how we collect, use, and safeguard your information.</p>

<h3>1. Information We Collect</h3>
<p>We collect account info (name, email, phone, DOB, gender), profile data (photos, bio, location), KYC documents, financial data, messages, device info, usage data, location (GPS), and push notification tokens.</p>

<h3>2. How We Use Your Information</h3>
<p>To provide the App, match nearby users, process payments, verify identity, send notifications, prevent fraud, and comply with legal obligations.</p>

<h3>3. Location Data</h3>
<p>Location is used for nearby features and shown to others only as approximate distance (km). You can disable location in device settings.</p>

<h3>4. Sharing Your Information</h3>
<p>We do <strong>not</strong> sell your data. We share only with service providers (hosting, payments, Firebase/FCM, CDN), law enforcement when required, and in business transfers.</p>

<h3>5. Data Retention</h3>
<p>Data is retained while your account is active. You may request deletion through App settings.</p>

<h3>6. Security</h3>
<p>We use HTTPS/TLS encryption, secure password hashing, and access controls. No system is 100% secure.</p>

<h3>7. Children's Privacy</h3>
<p>Love Vibe is strictly 18+. We do not knowingly collect data from minors.</p>

<h3>8. Your Rights</h3>
<p>You may access, correct, delete, or export your data. Contact us at <strong>privacy@lovevibe.app</strong></p>

<h3>9. Contact Us</h3>
<p>Privacy questions: <strong>privacy@lovevibe.app</strong></p>
HTML;

require_once __DIR__ . '/_layout_header.php';
?>

<style>
    .legal-tabs {
        display: flex;
        gap: 8px;
        margin-bottom: 24px;
    }

    .legal-tab {
        padding: 10px 24px;
        border-radius: 10px;
        border: none;
        cursor: pointer;
        font-weight: 700;
        font-size: 14px;
        background: #1e1e2e;
        color: #8e8e93;
        transition: .2s;
    }

    .legal-tab.active {
        background: linear-gradient(135deg, #7c3aed, #a855f7);
        color: #fff;
    }

    .legal-panel {
        display: none;
    }

    .legal-panel.active {
        display: block;
    }

    .legal-card {
        background: #161625;
        border: 1px solid #2a2a4a;
        border-radius: 16px;
        padding: 28px;
    }

    .legal-card h3 {
        color: #fff;
        font-size: 16px;
        margin: 0 0 6px;
    }

    .legal-card .meta {
        color: #8e8e93;
        font-size: 12px;
        margin-bottom: 20px;
    }

    .field-label {
        color: #ccc;
        font-size: 13px;
        font-weight: 600;
        margin-bottom: 6px;
        display: block;
    }

    .field-input {
        width: 100%;
        padding: 10px 14px;
        background: #0e0e1a;
        border: 1px solid #2a2a4a;
        border-radius: 10px;
        color: #fff;
        font-size: 14px;
        box-sizing: border-box;
    }

    .field-input:focus {
        outline: none;
        border-color: #7c3aed;
    }

    .field-textarea {
        width: 100%;
        padding: 12px 14px;
        background: #0e0e1a;
        border: 1px solid #2a2a4a;
        border-radius: 10px;
        color: #fff;
        font-size: 13px;
        font-family: monospace;
        line-height: 1.6;
        box-sizing: border-box;
        resize: vertical;
        min-height: 420px;
    }

    .field-textarea:focus {
        outline: none;
        border-color: #7c3aed;
    }

    .btn-row {
        display: flex;
        gap: 10px;
        margin-top: 16px;
        flex-wrap: wrap;
        align-items: center;
    }

    .save-btn {
        padding: 12px 32px;
        background: linear-gradient(135deg, #7c3aed, #a855f7);
        color: #fff;
        border: none;
        border-radius: 10px;
        font-weight: 700;
        font-size: 14px;
        cursor: pointer;
    }

    .save-btn:hover {
        opacity: .9;
    }

    .deploy-btn {
        padding: 12px 28px;
        background: linear-gradient(135deg, #0ea5e9, #2563eb);
        color: #fff;
        border: none;
        border-radius: 10px;
        font-weight: 700;
        font-size: 14px;
        cursor: pointer;
        display: flex;
        align-items: center;
        gap: 8px;
    }

    .deploy-btn:hover {
        opacity: .9;
    }

    .deploy-btn:disabled {
        opacity: .5;
        cursor: not-allowed;
    }

    .alert-success {
        background: rgba(48, 209, 88, .12);
        border: 1px solid rgba(48, 209, 88, .3);
        color: #30d158;
        padding: 12px 16px;
        border-radius: 10px;
        margin-bottom: 16px;
        font-weight: 600;
    }

    .alert-error {
        background: rgba(255, 69, 58, .12);
        border: 1px solid rgba(255, 69, 58, .3);
        color: #ff453a;
        padding: 12px 16px;
        border-radius: 10px;
        margin-bottom: 16px;
        font-weight: 600;
    }

    .alert-info {
        background: rgba(14, 165, 233, .12);
        border: 1px solid rgba(14, 165, 233, .3);
        color: #38bdf8;
        padding: 12px 16px;
        border-radius: 10px;
        margin-bottom: 16px;
        font-weight: 600;
    }

    .preview-btn {
        padding: 8px 18px;
        background: #1e1e2e;
        border: 1px solid #2a2a4a;
        color: #8e8e93;
        border-radius: 8px;
        font-size: 13px;
        cursor: pointer;
        margin-left: 12px;
    }

    .preview-box {
        background: #0e0e1a;
        border: 1px solid #2a2a4a;
        border-radius: 10px;
        padding: 20px 24px;
        margin-top: 16px;
        color: #ccc;
        font-size: 14px;
        line-height: 1.8;
        display: none;
        max-height: 400px;
        overflow-y: auto;
    }

    .preview-box h2,
    .preview-box h3,
    .preview-box h4 {
        color: #fff;
    }

    .preview-box ul {
        padding-left: 20px;
    }

    .toolbar {
        display: flex;
        gap: 6px;
        margin-bottom: 8px;
        flex-wrap: wrap;
    }

    .toolbar button {
        padding: 5px 10px;
        background: #1e1e2e;
        border: 1px solid #2a2a4a;
        color: #ccc;
        border-radius: 6px;
        font-size: 12px;
        cursor: pointer;
    }

    .toolbar button:hover {
        background: #2a2a4a;
        color: #fff;
    }

    .deploy-section {
        margin-top: 28px;
        padding: 20px;
        background: #0e0e1a;
        border: 1px solid #1e3a5f;
        border-radius: 12px;
    }

    .deploy-section h4 {
        color: #38bdf8;
        margin: 0 0 8px;
        font-size: 14px;
    }

    .deploy-section p {
        color: #8e8e93;
        font-size: 12px;
        margin: 0 0 14px;
    }

    .spinner {
        display: none;
        width: 16px;
        height: 16px;
        border: 2px solid rgba(255, 255, 255, .3);
        border-top-color: #fff;
        border-radius: 50%;
        animation: spin .7s linear infinite;
    }

    @keyframes spin {
        to {
            transform: rotate(360deg);
        }
    }
</style>

<?php if ($saved): ?>
    <div class="alert-success">✅ <?= $saved === 'terms' ? 'Terms of Service' : 'Privacy Policy' ?> saved successfully.</div>
<?php endif; ?>
<?php if ($saveError): ?>
    <div class="alert-error">❌ <?= htmlspecialchars($saveError) ?></div>
<?php endif; ?>
<?php if ($deployMsg): ?>
    <div class="<?= $deployOk ? 'alert-success' : 'alert-error' ?>">
        <?= $deployOk ? '🚀' : '❌' ?>     <?= htmlspecialchars($deployMsg) ?>
    </div>
<?php endif; ?>

<!-- Deploy to Live Server card -->
<div class="deploy-section" style="margin-bottom:24px;">
    <h4>🚀 Deploy API to Live Server</h4>
    <p>Uploads <code>api_legal.php</code> from this project to <strong>goreto.org/ekloadmin/</strong> via FTP.
        Run this after saving content changes so the live app picks them up immediately.</p>
    <form method="POST" onsubmit="startDeploy(this)">
        <input type="hidden" name="_action" value="deploy">
        <button type="submit" class="deploy-btn" id="deploy-btn">
            <span class="spinner" id="deploy-spinner"></span>
            <span id="deploy-label">🚀 Upload api_legal.php to Live Server</span>
        </button>
    </form>
</div>

<div class="legal-tabs">
    <button class="legal-tab <?= ($saved !== 'privacy') ? 'active' : '' ?>" onclick="switchTab('terms')">📄 Terms of
        Service</button>
    <button class="legal-tab <?= ($saved === 'privacy') ? 'active' : '' ?>" onclick="switchTab('privacy')">🔒 Privacy
        Policy</button>
</div>

<!-- TERMS TAB -->
<div class="legal-panel <?= ($saved !== 'privacy') ? 'active' : '' ?>" id="tab-terms">
    <div class="legal-card">
        <h3>Terms of Service</h3>
        <div class="meta">
            <?php if ($terms && $terms['updated_at']): ?>
                Last updated: <?= htmlspecialchars($terms['updated_at']) ?>
            <?php else: ?>
                Not yet saved — using default content
            <?php endif; ?>
        </div>

        <form method="POST">
            <input type="hidden" name="_action" value="save">
            <input type="hidden" name="page_key" value="terms">
            <div style="margin-bottom:16px">
                <label class="field-label">Page Title</label>
                <input class="field-input" name="title"
                    value="<?= htmlspecialchars($terms['title'] ?? 'Terms of Service') ?>" required>
            </div>
            <div>
                <label class="field-label">
                    Content (HTML supported)
                    <button type="button" class="preview-btn" onclick="togglePreview('terms')">👁 Preview</button>
                </label>
                <div class="toolbar">
                    <button type="button" onclick="wrap('terms-content','<h3>','</h3>')">H3</button>
                    <button type="button" onclick="wrap('terms-content','<p>','</p>')">P</button>
                    <button type="button" onclick="wrap('terms-content','<strong>','</strong>')">Bold</button>
                    <button type="button" onclick="wrap('terms-content','<ul>\n  <li>','</li>\n</ul>')">List</button>
                    <button type="button" onclick="wrap('terms-content','<li>','</li>')">Item</button>
                    <button type="button" onclick="insertDefault('terms-content','terms')">↩ Reset to Default</button>
                </div>
                <textarea class="field-textarea" name="content" id="terms-content"
                    oninput="updatePreview('terms')"><?= htmlspecialchars($terms['content'] ?? $defaultTerms) ?></textarea>
                <div class="preview-box" id="terms-preview"></div>
            </div>
            <div class="btn-row">
                <button type="submit" class="save-btn">💾 Save Terms of Service</button>
                <span style="color:#8e8e93;font-size:12px;">Save first, then deploy ↑</span>
            </div>
        </form>
    </div>
</div>

<!-- PRIVACY TAB -->
<div class="legal-panel <?= ($saved === 'privacy') ? 'active' : '' ?>" id="tab-privacy">
    <div class="legal-card">
        <h3>Privacy Policy</h3>
        <div class="meta">
            <?php if ($privacy && $privacy['updated_at']): ?>
                Last updated: <?= htmlspecialchars($privacy['updated_at']) ?>
            <?php else: ?>
                Not yet saved — using default content
            <?php endif; ?>
        </div>

        <form method="POST">
            <input type="hidden" name="_action" value="save">
            <input type="hidden" name="page_key" value="privacy">
            <div style="margin-bottom:16px">
                <label class="field-label">Page Title</label>
                <input class="field-input" name="title"
                    value="<?= htmlspecialchars($privacy['title'] ?? 'Privacy Policy') ?>" required>
            </div>
            <div>
                <label class="field-label">
                    Content (HTML supported)
                    <button type="button" class="preview-btn" onclick="togglePreview('privacy')">👁 Preview</button>
                </label>
                <div class="toolbar">
                    <button type="button" onclick="wrap('privacy-content','<h3>','</h3>')">H3</button>
                    <button type="button" onclick="wrap('privacy-content','<p>','</p>')">P</button>
                    <button type="button" onclick="wrap('privacy-content','<strong>','</strong>')">Bold</button>
                    <button type="button" onclick="wrap('privacy-content','<ul>\n  <li>','</li>\n</ul>')">List</button>
                    <button type="button" onclick="wrap('privacy-content','<li>','</li>')">Item</button>
                    <button type="button" onclick="insertDefault('privacy-content','privacy')">↩ Reset to
                        Default</button>
                </div>
                <textarea class="field-textarea" name="content" id="privacy-content"
                    oninput="updatePreview('privacy')"><?= htmlspecialchars($privacy['content'] ?? $defaultPrivacy) ?></textarea>
                <div class="preview-box" id="privacy-preview"></div>
            </div>
            <div class="btn-row">
                <button type="submit" class="save-btn">💾 Save Privacy Policy</button>
                <span style="color:#8e8e93;font-size:12px;">Save first, then deploy ↑</span>
            </div>
        </form>
    </div>
</div>

<script>
    function switchTab(tab) {
        document.querySelectorAll('.legal-tab').forEach((t, i) =>
            t.classList.toggle('active', (i === 0 && tab === 'terms') || (i === 1 && tab === 'privacy')));
        document.querySelectorAll('.legal-panel').forEach(p => p.classList.remove('active'));
        document.getElementById('tab-' + tab).classList.add('active');
    }

    function togglePreview(key) {
        const box = document.getElementById(key + '-preview');
        const ta = document.getElementById(key + '-content');
        if (box.style.display === 'block') { box.style.display = 'none'; return; }
        box.innerHTML = ta.value;
        box.style.display = 'block';
    }

    function updatePreview(key) {
        const box = document.getElementById(key + '-preview');
        if (box.style.display === 'block')
            box.innerHTML = document.getElementById(key + '-content').value;
    }

    function wrap(id, before, after) {
        const ta = document.getElementById(id);
        const s = ta.selectionStart, e = ta.selectionEnd;
        const sel = ta.value.substring(s, e);
        ta.value = ta.value.substring(0, s) + before + sel + after + ta.value.substring(e);
        ta.focus();
        ta.selectionStart = s + before.length;
        ta.selectionEnd = s + before.length + sel.length;
    }

    const defaults = {
        terms: <?= json_encode($defaultTerms) ?>,
        privacy: <?= json_encode($defaultPrivacy) ?>
    };

    function insertDefault(id, key) {
        if (!confirm('Reset to default content? This will overwrite your current text.')) return;
        document.getElementById(id).value = defaults[key];
    }

    function startDeploy(form) {
        const btn = document.getElementById('deploy-btn');
        const spinner = document.getElementById('deploy-spinner');
        const label = document.getElementById('deploy-label');
        btn.disabled = true;
        spinner.style.display = 'inline-block';
        label.textContent = 'Uploading…';
        // Let the form submit normally; PHP handles it
    }
</script>

<?php require_once __DIR__ . '/_layout_footer.php'; ?>