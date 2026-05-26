<?php
require_once __DIR__ . '/_core.php';
admin_require_login();
$pageTitle = 'Ads & Revenue';
$activeNav = 'ads_settings';

$pdo->exec("CREATE TABLE IF NOT EXISTS ad_settings (
    id INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    setting_key VARCHAR(80) NOT NULL UNIQUE,
    setting_value TEXT NULL,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

$defaults = [
    'ads_enabled'              => '1',
    'density'                  => 'balanced',
    'feed_frequency'           => '5',
    'interstitial_frequency'   => '5',
    'banner_ad_unit_id'        => '',
    'interstitial_ad_unit_id'  => '',
    'android_app_id'           => '',
    'ios_app_id'               => '',
    'estimated_rpm'            => '0.50',
    'notes'                    => '',
];

$msg = '';
$err = '';
$settings = admin_get_settings($pdo, 'ad_settings', $defaults);

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    try {
        $density = $_POST['density'] ?? 'balanced';
        if (!in_array($density, ['maximize', 'balanced', 'minimize'])) $density = 'balanced';

        admin_upsert_settings($pdo, 'ad_settings', [
            'ads_enabled'             => !empty($_POST['ads_enabled']) ? '1' : '0',
            'density'                 => $density,
            'feed_frequency'          => (string) max(1, (int) ($_POST['feed_frequency'] ?? 5)),
            'interstitial_frequency'  => (string) max(1, (int) ($_POST['interstitial_frequency'] ?? 5)),
            'banner_ad_unit_id'       => trim($_POST['banner_ad_unit_id'] ?? ''),
            'interstitial_ad_unit_id' => trim($_POST['interstitial_ad_unit_id'] ?? ''),
            'android_app_id'          => trim($_POST['android_app_id'] ?? ''),
            'ios_app_id'              => trim($_POST['ios_app_id'] ?? ''),
            'estimated_rpm'           => number_format((float) ($_POST['estimated_rpm'] ?? 0.5), 2, '.', ''),
            'notes'                   => trim($_POST['notes'] ?? ''),
        ]);
        $settings = admin_get_settings($pdo, 'ad_settings', $defaults);
        $msg = 'Ad settings saved. Changes will sync to the app within minutes.';
    } catch (Throwable $e) {
        $err = $e->getMessage();
    }
}

// Earnings estimates
$totalUsers       = (int) ($pdo->query("SELECT COUNT(*) FROM users")->fetchColumn());
$dau              = (int) round($totalUsers * 0.25);
$rpm              = (float) ($settings['estimated_rpm'] ?? 0.5);
$feedFreq         = max(1, (int) $settings['feed_frequency']);
$adsPerSession    = max(1, (int) round(10 / $feedFreq));
$dailyEarnings    = round(($dau * $adsPerSession * $rpm) / 1000, 2);
$monthlyEarnings  = round($dailyEarnings * 30, 2);

require_once __DIR__ . '/_layout_header.php';
?>

<style>
.ad-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(170px, 1fr)); gap: 14px; margin-bottom: 28px; }
.ad-stat {
  padding: 20px 16px; border-radius: 16px; text-align: center;
  background: linear-gradient(135deg,rgba(255,0,127,.10),rgba(0,229,255,.05));
  border: 1px solid rgba(255,0,127,.22);
}
.ad-stat.c { background: linear-gradient(135deg,rgba(0,229,255,.10),rgba(124,58,237,.05)); border-color: rgba(0,229,255,.22); }
.ad-stat.p { background: linear-gradient(135deg,rgba(124,58,237,.10),rgba(255,0,127,.05)); border-color: rgba(124,58,237,.22); }
.ad-stat.g { background: linear-gradient(135deg,rgba(16,185,129,.10),rgba(0,229,255,.05)); border-color: rgba(16,185,129,.22); }
.ad-num { font-size: 26px; font-weight: 900; color: #ff007f; }
.ad-num.c { color: #00e5ff; }
.ad-num.p { color: #a78bfa; }
.ad-num.g { color: #10b981; }
.ad-lbl { font-size: 10px; color: rgba(255,255,255,.45); margin-top: 4px; text-transform: uppercase; letter-spacing: .6px; }
.density-row { display: flex; gap: 10px; flex-wrap: wrap; }
.density-opt input { display: none; }
.density-opt label {
  display: flex; flex-direction: column; align-items: center; gap: 5px;
  cursor: pointer; padding: 14px 18px; border-radius: 14px; min-width: 96px;
  border: 1.5px solid rgba(255,255,255,.10); background: rgba(255,255,255,.04);
  transition: all .2s;
}
.density-opt input:checked + label {
  border-color: #ff007f;
  background: rgba(255,0,127,.12);
  box-shadow: 0 0 0 3px rgba(255,0,127,.18);
}
.density-opt label .di { font-size: 22px; }
.density-opt label .dn { font-size: 12px; font-weight: 700; color: #fff; }
.density-opt label .ds { font-size: 10px; color: rgba(255,255,255,.4); }
.two-col { display: grid; grid-template-columns: 1fr 1fr; gap: 16px; }
@media(max-width:580px){ .two-col { grid-template-columns: 1fr; } }
.setup-list { list-style: none; padding: 0; margin: 0; }
.setup-list li { display: flex; gap: 14px; align-items: flex-start; padding: 12px 0; border-bottom: 1px solid rgba(255,255,255,.06); }
.setup-list li:last-child { border-bottom: none; }
.snum { flex-shrink:0; width:28px; height:28px; border-radius:50%; background:rgba(255,0,127,.14); border:1.5px solid rgba(255,0,127,.38); display:flex; align-items:center; justify-content:center; font-size:12px; font-weight:800; color:#ff007f; }
.stxt { font-size:13px; color:rgba(255,255,255,.75); line-height:1.55; }
.stxt strong { color:#fff; }
.stxt a { color:#00e5ff; text-decoration:none; }
.stxt a:hover { text-decoration:underline; }
.stxt code { background:rgba(255,255,255,.08); padding:2px 6px; border-radius:4px; font-size:11px; }
.warn-chip { display:inline-flex; align-items:center; gap:6px; background:rgba(251,191,36,.14); border:1px solid rgba(251,191,36,.30); border-radius:8px; padding:4px 10px; font-size:11px; font-weight:700; color:#fbbf24; }
</style>

<!-- Earnings Overview -->
<div class="ad-grid">
  <div class="ad-stat">
    <div class="ad-num">$<?= number_format($dailyEarnings, 2) ?></div>
    <div class="ad-lbl">Est. Daily Earnings</div>
  </div>
  <div class="ad-stat g">
    <div class="ad-num g">$<?= number_format($monthlyEarnings, 2) ?></div>
    <div class="ad-lbl">Est. Monthly Earnings</div>
  </div>
  <div class="ad-stat c">
    <div class="ad-num c"><?= number_format($dau) ?></div>
    <div class="ad-lbl">Daily Active Users (est. 25%)</div>
  </div>
  <div class="ad-stat p">
    <div class="ad-num p"><?= $adsPerSession ?></div>
    <div class="ad-lbl">Avg Ad Impressions / Session</div>
  </div>
</div>

<?php if ($msg): ?>
  <div class="alert success" style="margin-bottom:20px"><?= htmlspecialchars($msg) ?></div>
<?php endif ?>
<?php if ($err): ?>
  <div class="alert danger" style="margin-bottom:20px"><?= htmlspecialchars($err) ?></div>
<?php endif ?>

<form method="post">

  <!-- Master Switch -->
  <div class="card" style="margin-bottom:18px">
    <div class="card-header"><b>📢 Ad Master Switch</b></div>
    <div style="padding:20px;display:flex;align-items:center;justify-content:space-between;flex-wrap:wrap;gap:14px">
      <div>
        <div style="font-size:15px;font-weight:700;color:#fff">Enable Advertisements</div>
        <div style="font-size:12px;color:rgba(255,255,255,.45);margin-top:3px">Turning off stops all ads instantly — no rebuild required</div>
      </div>
      <label style="display:flex;align-items:center;gap:10px;cursor:pointer">
        <input type="checkbox" name="ads_enabled" value="1" <?= $settings['ads_enabled'] === '1' ? 'checked' : '' ?>>
        <span style="font-weight:700;font-size:14px;color:<?= $settings['ads_enabled'] === '1' ? '#10b981' : '#6b7280' ?>">
          <?= $settings['ads_enabled'] === '1' ? '✅ Ads ON' : '⛔ Ads OFF' ?>
        </span>
      </label>
    </div>
  </div>

  <!-- Density Mode -->
  <div class="card" style="margin-bottom:18px">
    <div class="card-header"><b>⚡ Ad Density Mode</b></div>
    <div style="padding:20px">
      <div class="density-row">
        <?php foreach ([
          ['maximize', '💰', 'Maximize', 'Max revenue', 3, 2],
          ['balanced', '⚖️', 'Balanced', 'Recommended', 5, 5],
          ['minimize', '🌿', 'Minimize', 'Better UX',  10, 10],
        ] as [$val, $icon, $label, $sub, $ff, $if]): ?>
          <div class="density-opt">
            <input type="radio" name="density" id="d_<?= $val ?>" value="<?= $val ?>"
              <?= $settings['density'] === $val ? 'checked' : '' ?>>
            <label for="d_<?= $val ?>">
              <span class="di"><?= $icon ?></span>
              <span class="dn"><?= $label ?></span>
              <span class="ds"><?= $sub ?></span>
              <span class="ds" style="color:rgba(255,255,255,.25)">Feed: every <?= $ff ?> posts</span>
            </label>
          </div>
        <?php endforeach ?>
      </div>
    </div>
  </div>

  <!-- Fine-Tune Frequency -->
  <div class="card" style="margin-bottom:18px">
    <div class="card-header"><b>🎛️ Fine-Tune Frequency</b></div>
    <div style="padding:20px">
      <div class="two-col">
        <div>
          <label class="label">Feed Ad Frequency (every N posts)</label>
          <input type="number" name="feed_frequency" class="input" min="1" max="50"
            value="<?= (int) $settings['feed_frequency'] ?>">
          <div style="font-size:11px;color:rgba(255,255,255,.4);margin-top:4px">
            1 ad appears after every <b><?= $settings['feed_frequency'] ?></b> posts in the home feed
          </div>
        </div>
        <div>
          <label class="label">Interstitial Frequency (every N navigations)</label>
          <input type="number" name="interstitial_frequency" class="input" min="1" max="50"
            value="<?= (int) $settings['interstitial_frequency'] ?>">
          <div style="font-size:11px;color:rgba(255,255,255,.4);margin-top:4px">
            Full-screen ad triggers after every <b><?= $settings['interstitial_frequency'] ?></b> screen changes
          </div>
        </div>
      </div>
    </div>
  </div>

  <!-- Ad Unit IDs -->
  <div class="card" style="margin-bottom:18px">
    <div class="card-header">
      <b>🔑 AdMob App &amp; Ad Unit IDs</b>
      <span class="warn-chip">⚠️ App using TEST IDs — replace before production</span>
    </div>
    <div style="padding:20px">
      <div class="two-col" style="margin-bottom:18px">
        <div>
          <label class="label">Android App ID</label>
          <input type="text" name="android_app_id" class="input" placeholder="ca-app-pub-XXXXXXXX~XXXXXXXXXX"
            value="<?= htmlspecialchars($settings['android_app_id']) ?>">
          <div style="font-size:11px;color:rgba(255,255,255,.3);margin-top:3px">AndroidManifest.xml → APPLICATION_ID meta-data</div>
        </div>
        <div>
          <label class="label">iOS App ID</label>
          <input type="text" name="ios_app_id" class="input" placeholder="ca-app-pub-XXXXXXXX~XXXXXXXXXX"
            value="<?= htmlspecialchars($settings['ios_app_id']) ?>">
          <div style="font-size:11px;color:rgba(255,255,255,.3);margin-top:3px">Info.plist → GADApplicationIdentifier</div>
        </div>
        <div>
          <label class="label">Banner Ad Unit ID</label>
          <input type="text" name="banner_ad_unit_id" class="input" placeholder="ca-app-pub-XXXXXXXX/XXXXXXXXXX"
            value="<?= htmlspecialchars($settings['banner_ad_unit_id']) ?>">
        </div>
        <div>
          <label class="label">Interstitial Ad Unit ID</label>
          <input type="text" name="interstitial_ad_unit_id" class="input" placeholder="ca-app-pub-XXXXXXXX/XXXXXXXXXX"
            value="<?= htmlspecialchars($settings['interstitial_ad_unit_id']) ?>">
        </div>
      </div>
      <div style="max-width:220px">
        <label class="label">Estimated RPM (USD / 1000 impressions)</label>
        <input type="number" name="estimated_rpm" class="input" step="0.01" min="0"
          value="<?= htmlspecialchars($settings['estimated_rpm']) ?>">
        <div style="font-size:11px;color:rgba(255,255,255,.35);margin-top:3px">Used for earnings estimates above. Check AdMob dashboard for real RPM.</div>
      </div>
    </div>
  </div>

  <!-- Notes -->
  <div class="card" style="margin-bottom:20px">
    <div class="card-header"><b>📝 Notes</b></div>
    <div style="padding:16px">
      <textarea name="notes" class="input" rows="3"
        placeholder="Internal notes (campaign details, A/B test info…)"><?= htmlspecialchars($settings['notes']) ?></textarea>
    </div>
  </div>

  <button type="submit" class="btn primary" style="font-size:15px;padding:12px 36px">💾 Save Ad Settings</button>
</form>

<!-- Setup Guide -->
<div class="card" style="margin-top:28px">
  <div class="card-header"><b>🚀 AdMob Setup — Step by Step</b></div>
  <div style="padding:20px">
    <ul class="setup-list">
      <li>
        <div class="snum">1</div>
        <div class="stxt"><strong>Create AdMob Account</strong><br>
          Visit <a href="https://admob.google.com" target="_blank">admob.google.com</a> → sign in with your Google account → accept terms.
        </div>
      </li>
      <li>
        <div class="snum">2</div>
        <div class="stxt"><strong>Add Your App to AdMob</strong><br>
          Apps → Add app → Android → enter name <strong>"Goreto"</strong> → copy the <strong>App ID</strong> (format: <code>ca-app-pub-XXXX~XXXX</code>) and paste above.
        </div>
      </li>
      <li>
        <div class="snum">3</div>
        <div class="stxt"><strong>Create Ad Units</strong><br>
          Apps → Goreto → Ad units → Create ad unit:<br>
          • <strong>Banner</strong> — copy ID → paste in Banner Ad Unit ID above<br>
          • <strong>Interstitial</strong> — copy ID → paste in Interstitial Ad Unit ID above
        </div>
      </li>
      <li>
        <div class="snum">4</div>
        <div class="stxt"><strong>Update AndroidManifest.xml</strong><br>
          In <code>android/app/src/main/AndroidManifest.xml</code> replace the test App ID:<br>
          <code>android:name="com.google.android.gms.ads.APPLICATION_ID"<br>android:value="YOUR_REAL_APP_ID"</code>
        </div>
      </li>
      <li>
        <div class="snum">5</div>
        <div class="stxt"><strong>Switch to Production Mode in Flutter</strong><br>
          In <code>lib/config/ad_config.dart</code> set <code>static const bool useTestAds = false;</code><br>
          Fill in <code>_prodAndroidBannerId</code> and <code>_prodAndroidInterstitialId</code> with your real unit IDs.
        </div>
      </li>
      <li>
        <div class="snum">6</div>
        <div class="stxt"><strong>Publish &amp; Wait for Review</strong><br>
          Build release APK → submit to Play Store → AdMob starts showing real ads once the app is approved (usually 24–48h after first install).
        </div>
      </li>
    </ul>
  </div>
</div>

<?php require_once __DIR__ . '/_layout_footer.php'; ?>
