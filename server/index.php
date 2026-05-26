<?php
/**
 * goreto.org — Post deep-link landing page
 * URL: https://goreto.org/{username}/{postId}
 *
 * Shows a post preview card with "Open in App" button.
 * Auto-redirects to goreto://post/{postId} on mobile.
 */

// ── Parse URL ───────────────────────────────────────────────────────────────
$path     = trim(parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH), '/');
$segments = array_values(array_filter(explode('/', $path)));

if (!empty($segments) && $segments[0] === 'ekloadmin') {
    header('Location: /ekloadmin/');
    exit;
}
if (count($segments) < 2) {
    header('Location: https://goreto.org/');
    exit;
}

$rawPostId  = $segments[1];
$rawUser    = $segments[0];
$postId     = (int) $rawPostId;
$username   = htmlspecialchars($rawUser, ENT_QUOTES, 'UTF-8');
$appLink    = 'goreto://post/' . rawurlencode($rawPostId);

$ua        = strtolower($_SERVER['HTTP_USER_AGENT'] ?? '');
$isAndroid = str_contains($ua, 'android');
$isIOS     = str_contains($ua, 'iphone') || str_contains($ua, 'ipad');
$isMobile  = $isAndroid || $isIOS;

$storeUrl  = $isIOS
    ? 'https://apps.apple.com/app/goreto/id000000000'
    : 'https://play.google.com/store/apps/details?id=com.nex.ekloapp';

// ── Fetch post from DB ───────────────────────────────────────────────────────
$post      = null;
$postUser  = null;

try {
    $cfgPath = '/var/www/html/ekloadmin/config/config.php';
    if (!file_exists($cfgPath)) {
        $cfgPath = __DIR__ . '/../ekloadmin/config/config.php';
    }
    $cfg = file_exists($cfgPath) ? require $cfgPath : null;

    if ($cfg && isset($cfg['db'])) {
        $db  = $cfg['db'];
        $pdo = new PDO(
            "mysql:host={$db['host']};dbname={$db['name']};charset=utf8mb4",
            $db['user'], $db['pass'],
            [PDO::ATTR_ERRMODE => PDO::ERRMODE_SILENT,
             PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC]
        );

        // Detect which media column exists
        $colsStmt = $pdo->query("SHOW COLUMNS FROM posts");
        $cols = $colsStmt ? array_column($colsStmt->fetchAll(), 'Field') : [];
        $mediaCol = in_array('media_url', $cols) ? 'media_url'
                  : (in_array('file_url', $cols) ? 'file_url' : 'media_url');
        $typeCol  = in_array('media_type', $cols) ? 'media_type'
                  : (in_array('type', $cols) ? 'type' : 'media_type');
        $likeCol  = in_array('likes_count', $cols) ? 'likes_count'
                  : (in_array('like_count', $cols) ? 'like_count' : null);
        $cmtCol   = in_array('comments_count', $cols) ? 'comments_count'
                  : (in_array('comment_count', $cols) ? 'comment_count' : null);

        $likeSel     = $likeCol ? "p.$likeCol AS likes_count," : "0 AS likes_count,";
        $cmtSel      = $cmtCol  ? "p.$cmtCol AS comments_count," : "0 AS comments_count,";
        $thumbSel    = in_array('thumbnail_url', $cols) ? "p.thumbnail_url," : "NULL AS thumbnail_url,";

        $stmt = $pdo->prepare("
            SELECT p.id, p.caption,
                   p.$mediaCol AS media_url,
                   p.$typeCol  AS media_type,
                   $thumbSel
                   $likeSel
                   $cmtSel
                   p.created_at,
                   u.name, u.username, u.profile_pic
            FROM posts p
            JOIN users u ON u.id = p.user_id
            WHERE p.id = ?
            LIMIT 1
        ");
        $stmt->execute([$postId]);
        $row = $stmt->fetch();
        if ($row) {
            $post     = $row;
            $username = htmlspecialchars($row['username'] ?? $username, ENT_QUOTES, 'UTF-8');
        }
    }
} catch (Throwable $_e) {
    // DB unavailable — degrade gracefully, page still shows
}

// ── Normalize media URL ──────────────────────────────────────────────────────
$base         = 'https://goreto.org/ekloadmin/';
$mediaUrl     = '';
$thumbnailUrl = '';
$isVideo      = false;

if ($post) {
    $raw = $post['media_url'] ?? '';
    if (!empty($raw)) {
        $mediaUrl = preg_match('~^https?://~i', $raw) ? $raw : $base . ltrim($raw, '/');
    }
    $rawThumb = $post['thumbnail_url'] ?? '';
    if (!empty($rawThumb)) {
        $thumbnailUrl = preg_match('~^https?://~i', $rawThumb) ? $rawThumb : $base . ltrim($rawThumb, '/');
    }
    $mt      = strtolower($post['media_type'] ?? '');
    $isVideo = str_contains($mt, 'video') || str_contains($mt, 'reel');
}

$caption    = $post ? htmlspecialchars($post['caption'] ?? '', ENT_QUOTES, 'UTF-8') : '';
$authorName = $post ? htmlspecialchars($post['name'] ?? $username, ENT_QUOTES, 'UTF-8') : $username;
$likesCount = $post ? (int)($post['likes_count'] ?? 0) : 0;
$cmtsCount  = $post ? (int)($post['comments_count'] ?? 0) : 0;

$rawAvatar  = $post['profile_pic'] ?? '';
$avatarUrl  = !empty($rawAvatar)
    ? (preg_match('~^https?://~i', $rawAvatar) ? $rawAvatar : $base . ltrim($rawAvatar, '/'))
    : '';

// OG image: prefer post image or reel thumbnail, fall back to app icon
$ogImage = !empty($thumbnailUrl) ? $thumbnailUrl
         : (!empty($mediaUrl) && !$isVideo ? $mediaUrl : 'https://goreto.org/icon-512.png');
$ogTitle = $post ? "Post by @$username on Goreto" : "Goreto — Open in App";
$ogDesc  = !empty($caption) ? $caption : "View this post on Goreto — Nepal's social app.";

?><!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title><?= $ogTitle ?></title>

<!-- Open Graph -->
<meta property="og:type"        content="article">
<meta property="og:url"         content="https://goreto.org/<?= $username ?>/<?= $postId ?>">
<meta property="og:title"       content="<?= htmlspecialchars($ogTitle, ENT_QUOTES) ?>">
<meta property="og:description" content="<?= htmlspecialchars($ogDesc,  ENT_QUOTES) ?>">
<meta property="og:image"       content="<?= htmlspecialchars($ogImage, ENT_QUOTES) ?>">
<meta property="og:image:width" content="1200">
<meta property="og:site_name"   content="Goreto">
<meta name="twitter:card"       content="summary_large_image">
<meta name="twitter:title"      content="<?= htmlspecialchars($ogTitle, ENT_QUOTES) ?>">
<meta name="twitter:description"content="<?= htmlspecialchars($ogDesc,  ENT_QUOTES) ?>">
<meta name="twitter:image"      content="<?= htmlspecialchars($ogImage, ENT_QUOTES) ?>">

<link rel="icon" href="https://goreto.org/favicon.ico">

<style>
*, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
:root {
  --pink: #F2028A; --purple: #D946EF; --dark: #05030A;
  --card: #110E1B; --border: rgba(255,255,255,0.08);
  --muted: rgba(255,255,255,0.45); --text: #F0ECF8;
}
html { scroll-behavior: smooth; }
body {
  background: var(--dark);
  color: var(--text);
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
  min-height: 100vh;
  display: flex;
  flex-direction: column;
}

/* ── NAV ── */
nav {
  position: sticky; top: 0; z-index: 100;
  display: flex; align-items: center; justify-content: space-between;
  padding: 14px 20px;
  background: rgba(5,3,10,0.85);
  backdrop-filter: blur(16px);
  border-bottom: 1px solid var(--border);
}
.nav-logo {
  display: flex; align-items: center; gap: 9px;
  text-decoration: none;
}
.nav-logo img {
  width: 34px; height: 34px;
  border-radius: 8px;
  object-fit: contain;
  padding: 2px;
}
.nav-logo span {
  font-size: 20px; font-weight: 900;
  background: linear-gradient(135deg, var(--pink), var(--purple));
  -webkit-background-clip: text; -webkit-text-fill-color: transparent;
}
.nav-cta {
  background: linear-gradient(135deg, var(--pink), var(--purple));
  color: #fff; border: none; border-radius: 50px;
  padding: 9px 20px; font-size: 13px; font-weight: 700;
  text-decoration: none; cursor: pointer;
  box-shadow: 0 0 18px rgba(242,2,138,0.35);
  transition: transform .15s, box-shadow .15s;
}
.nav-cta:hover { transform: scale(1.04); box-shadow: 0 0 28px rgba(242,2,138,0.6); }

/* ── MAIN ── */
main {
  flex: 1;
  display: flex;
  flex-direction: column;
  align-items: center;
  padding: 28px 16px 48px;
  gap: 0;
}

/* ── POST CARD ── */
.card {
  width: 100%;
  max-width: 480px;
  background: var(--card);
  border: 1px solid var(--border);
  border-radius: 20px;
  overflow: hidden;
  box-shadow: 0 8px 40px rgba(0,0,0,0.5);
}

/* Post header: avatar + name */
.post-header {
  display: flex; align-items: center; gap: 12px;
  padding: 14px 16px;
}
.avatar {
  width: 40px; height: 40px; border-radius: 50%;
  object-fit: cover;
  border: 2px solid var(--pink);
  flex-shrink: 0;
  background: #1e1630;
}
.avatar-placeholder {
  width: 40px; height: 40px; border-radius: 50%;
  background: linear-gradient(135deg, var(--pink), var(--purple));
  display: flex; align-items: center; justify-content: center;
  font-size: 17px; font-weight: 700; color: #fff;
  flex-shrink: 0;
}
.post-meta { display: flex; flex-direction: column; gap: 1px; }
.post-author { font-size: 14px; font-weight: 700; }
.post-handle { font-size: 12px; color: var(--muted); }

/* Media area */
.post-media {
  width: 100%;
  aspect-ratio: 1 / 1;
  background: #0a0814;
  position: relative;
  overflow: hidden;
}
.post-media img {
  width: 100%; height: 100%;
  object-fit: cover;
  display: block;
}
.post-media .video-thumb {
  width: 100%; height: 100%;
  background: #0a0814;
  display: flex; flex-direction: column;
  align-items: center; justify-content: center;
  gap: 10px; color: var(--muted);
  font-size: 13px;
}
.play-icon {
  width: 56px; height: 56px; border-radius: 50%;
  background: rgba(242,2,138,0.18);
  border: 2px solid rgba(242,2,138,0.4);
  display: flex; align-items: center; justify-content: center;
}
.play-icon svg { margin-left: 4px; }
.no-media {
  width: 100%; height: 100%;
  display: flex; align-items: center; justify-content: center;
  background: linear-gradient(135deg, rgba(242,2,138,0.08), rgba(217,70,239,0.06));
}
.no-media .caption-big {
  padding: 24px; font-size: 18px; font-weight: 600;
  line-height: 1.5; text-align: center; color: var(--text);
}

/* Post body */
.post-body { padding: 12px 16px 4px; }
.caption {
  font-size: 14px; line-height: 1.55; color: var(--text);
  display: -webkit-box; -webkit-line-clamp: 3;
  -webkit-box-orient: vertical; overflow: hidden;
}
.stats {
  display: flex; gap: 18px;
  padding: 10px 16px 14px;
  font-size: 13px; color: var(--muted);
}
.stat { display: flex; align-items: center; gap: 5px; }

/* ── CTA AREA ── */
.cta-area {
  width: 100%;
  max-width: 480px;
  padding: 20px 0 0;
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 10px;
}
.cta-hint { font-size: 13px; color: var(--muted); margin-bottom: 4px; }

.btn-open {
  display: flex; align-items: center; justify-content: center; gap: 10px;
  width: 100%;
  background: linear-gradient(135deg, var(--pink), var(--purple));
  color: #fff; text-decoration: none;
  padding: 15px 24px; border-radius: 14px;
  font-size: 16px; font-weight: 800;
  box-shadow: 0 4px 24px rgba(242,2,138,0.4);
  transition: transform .15s, box-shadow .15s;
  letter-spacing: 0.2px;
}
.btn-open:hover { transform: translateY(-1px); box-shadow: 0 8px 32px rgba(242,2,138,0.55); }
.btn-open:active { transform: scale(0.98); }

.btn-store {
  display: flex; align-items: center; justify-content: center; gap: 8px;
  width: 100%;
  background: rgba(255,255,255,0.06);
  border: 1px solid var(--border);
  color: rgba(255,255,255,0.7); text-decoration: none;
  padding: 13px 24px; border-radius: 14px;
  font-size: 14px; font-weight: 600;
  transition: background .15s;
}
.btn-store:hover { background: rgba(255,255,255,0.1); }

/* Countdown pill */
.countdown-wrap {
  font-size: 12px; color: var(--muted);
  display: flex; align-items: center; gap: 6px;
  margin-top: 4px;
}
.dot { width: 6px; height: 6px; border-radius: 50%; background: var(--pink); animation: pulse 1s infinite; }
@keyframes pulse { 0%,100%{opacity:1;transform:scale(1)} 50%{opacity:.4;transform:scale(.7)} }

.divider { width: 100%; max-width: 480px; height: 1px; background: var(--border); margin: 8px 0; }

.footer-note {
  font-size: 11px; color: rgba(255,255,255,0.2);
  text-align: center; padding-top: 8px;
}

/* ── MOBILE BANNER (shown only if app IS installed, 0→show after redirect attempt) ── */
.install-banner {
  display: none;
  width: 100%; max-width: 480px;
  background: rgba(242,2,138,0.08);
  border: 1px solid rgba(242,2,138,0.25);
  border-radius: 14px;
  padding: 14px 16px;
  text-align: center;
  font-size: 13px; color: rgba(255,255,255,0.7);
  margin-top: 4px;
}
</style>
</head>
<body>

<!-- NAV -->
<nav>
  <a class="nav-logo" href="https://goreto.org/">
    <img src="https://goreto.org/icon-192.png" alt="Goreto">
    <span>Goreto</span>
  </a>
  <a class="nav-cta" href="<?= htmlspecialchars($appLink) ?>">Open App</a>
</nav>

<!-- MAIN -->
<main>

  <!-- POST CARD -->
  <div class="card">

    <!-- Header -->
    <div class="post-header">
      <?php if (!empty($avatarUrl)): ?>
        <img class="avatar" src="<?= htmlspecialchars($avatarUrl) ?>" alt="<?= $authorName ?>" loading="lazy">
      <?php else: ?>
        <div class="avatar-placeholder"><?= mb_strtoupper(mb_substr($authorName, 0, 1)) ?></div>
      <?php endif; ?>
      <div class="post-meta">
        <span class="post-author"><?= $authorName ?></span>
        <span class="post-handle">@<?= $username ?></span>
      </div>
    </div>

    <!-- Media -->
    <div class="post-media">
      <?php if (!empty($mediaUrl) && !$isVideo): ?>
        <img src="<?= htmlspecialchars($mediaUrl) ?>" alt="Post image" loading="lazy">
      <?php elseif ($isVideo && !empty($thumbnailUrl)): ?>
        <!-- Reel/video with thumbnail -->
        <img src="<?= htmlspecialchars($thumbnailUrl) ?>" alt="Reel thumbnail" loading="lazy"
             style="width:100%;height:100%;object-fit:cover;display:block;">
        <div style="position:absolute;inset:0;display:flex;flex-direction:column;align-items:center;justify-content:center;background:rgba(0,0,0,0.28);">
          <div class="play-icon">
            <svg width="26" height="26" viewBox="0 0 24 24" fill="none">
              <path d="M8 5.14v13.72L19 12 8 5.14z" fill="rgba(255,255,255,0.95)"/>
            </svg>
          </div>
        </div>
      <?php elseif ($isVideo): ?>
        <div class="video-thumb">
          <div class="play-icon">
            <svg width="22" height="22" viewBox="0 0 24 24" fill="none">
              <path d="M8 5.14v13.72L19 12 8 5.14z" fill="rgba(242,2,138,0.9)"/>
            </svg>
          </div>
          <span>Reel · Open in App to watch</span>
        </div>
      <?php elseif (!empty($caption)): ?>
        <div class="no-media">
          <div class="caption-big">"<?= $caption ?>"</div>
        </div>
      <?php else: ?>
        <div class="no-media">
          <div class="caption-big" style="color:var(--muted)">Open in Goreto App</div>
        </div>
      <?php endif; ?>
    </div>

    <!-- Caption -->
    <?php if (!empty($caption) && (!empty($mediaUrl) || $isVideo)): ?>
    <div class="post-body">
      <p class="caption"><?= $caption ?></p>
    </div>
    <?php endif; ?>

    <!-- Stats -->
    <?php if ($likesCount > 0 || $cmtsCount > 0): ?>
    <div class="stats">
      <?php if ($likesCount > 0): ?>
      <span class="stat">
        <svg width="15" height="15" viewBox="0 0 24 24" fill="none">
          <path d="M12 21.35l-1.45-1.32C5.4 15.36 2 12.28 2 8.5 2 5.42 4.42 3 7.5 3c1.74 0 3.41.81 4.5 2.09C13.09 3.81 14.76 3 16.5 3 19.58 3 22 5.42 22 8.5c0 3.78-3.4 6.86-8.55 11.54L12 21.35z" fill="rgba(242,2,138,0.85)"/>
        </svg>
        <?= number_format($likesCount) ?>
      </span>
      <?php endif; ?>
      <?php if ($cmtsCount > 0): ?>
      <span class="stat">
        <svg width="15" height="15" viewBox="0 0 24 24" fill="none">
          <path d="M20 2H4c-1.1 0-2 .9-2 2v18l4-4h14c1.1 0 2-.9 2-2V4c0-1.1-.9-2-2-2z" fill="rgba(255,255,255,0.4)"/>
        </svg>
        <?= number_format($cmtsCount) ?> comments
      </span>
      <?php endif; ?>
    </div>
    <?php endif; ?>

  </div><!-- /card -->

  <!-- CTA -->
  <div class="cta-area">
    <p class="cta-hint">View the full post in the Goreto app</p>

    <a class="btn-open" id="btnOpen" href="<?= htmlspecialchars($appLink) ?>">
      <svg width="20" height="20" viewBox="0 0 24 24" fill="none">
        <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-1 14H9V8h2v8zm4 0h-2V8h2v8z" fill="white" opacity="0"/>
        <path d="M10 16.5l6-4.5-6-4.5v9z" fill="white"/>
        <circle cx="12" cy="12" r="10" stroke="white" stroke-width="1.5" fill="none"/>
      </svg>
      Open in Goreto App
    </a>

    <div class="countdown-wrap" id="countdownWrap">
      <span class="dot"></span>
      <span id="countdownText">Opening app automatically…</span>
    </div>

    <div class="install-banner" id="installBanner">
      App not installed? Download Goreto free below.
    </div>

    <div class="divider"></div>

    <a class="btn-store" href="<?= htmlspecialchars($storeUrl) ?>">
      <?php if ($isIOS): ?>
        <svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor"><path d="M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.8-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M13 3.5c.73-.83 1.94-1.46 2.94-1.5.13 1.17-.34 2.35-1.04 3.19-.69.85-1.83 1.51-2.95 1.42-.15-1.15.41-2.35 1.05-3.11z"/></svg>
        Download on App Store
      <?php else: ?>
        <svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor"><path d="M3.18 23.76c.22.13.48.17.73.12L13.27 12 3.91.12C3.66.07 3.4.11 3.18.24 2.7.5 2.4 1.05 2.4 1.7v20.6c0 .65.3 1.2.78 1.46zM16.9 8.7l2.17-1.25c.9-.52.9-1.38 0-1.9l-2.17-1.25L14.36 12l2.54 3.3.0001 0L16.9 15.3zM4.55 1.27l9.32 10.73L4.55 22.73V1.27zM14.36 12l2.54-3.3-9.27-5.34L14.36 12zm0 0l-6.73 8.64 9.27-5.34L14.36 12z"/></svg>
        Get on Google Play
      <?php endif; ?>
    </a>
  </div>

  <p class="footer-note">goreto.org &bull; post #<?= $postId ?></p>

</main>

<script>
(function () {
  var appLink   = <?= json_encode($appLink) ?>;
  var isMobile  = <?= $isMobile ? 'true' : 'false' ?>;
  var storeUrl  = <?= json_encode($storeUrl) ?>;
  var countdown = document.getElementById('countdownWrap');
  var banner    = document.getElementById('installBanner');

  if (!isMobile) {
    // Desktop: hide countdown pill, user taps manually
    if (countdown) countdown.style.display = 'none';
    return;
  }

  // Auto-attempt app open after 800ms (lets page render first)
  var attempted = false;
  function tryOpen() {
    if (attempted) return;
    attempted = true;
    window.location.href = appLink;
  }
  setTimeout(tryOpen, 800);

  // After 3s: if still on page, show "not installed" hint + highlight store btn
  setTimeout(function () {
    if (document.hidden) return;
    if (countdown) countdown.style.display = 'none';
    if (banner) banner.style.display = 'block';
    var storeBtn = document.querySelector('.btn-store');
    if (storeBtn) {
      storeBtn.style.background   = 'linear-gradient(135deg,#F2028A,#D946EF)';
      storeBtn.style.borderColor  = 'transparent';
      storeBtn.style.color        = '#fff';
    }
  }, 3000);
})();
</script>
</body>
</html>
