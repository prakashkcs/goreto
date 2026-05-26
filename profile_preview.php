<?php
// profile_preview.php — User profile social-share preview page
// URL: https://goreto.org/ekloadmin/profile_preview.php?id=USER_ID
// Serves Open Graph / Twitter Card meta-tags so FB, Telegram, WhatsApp etc.
// show a rich preview. Also provides a mobile-friendly landing page.

$userId   = isset($_GET['id']) ? (int)$_GET['id'] : 0;
$baseUrl  = 'https://goreto.org/ekloadmin';

$name        = 'Goreto User';
$username    = '';
$bio         = 'Join me on Goreto!';
$avatarUrl   = $baseUrl . '/assets/logo.png';

if ($userId > 0) {
    try {
        // db_connect.php sets Content-Type: application/json; we'll override below
        require_once __DIR__ . '/db_connect.php';
        $stmt = $pdo->prepare(
            "SELECT name, username, bio, profile_pic FROM users WHERE id = ? LIMIT 1"
        );
        $stmt->execute([$userId]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);
        if ($row) {
            $name     = $row['name']     ?? 'Goreto User';
            $username = $row['username'] ?? '';
            $bio      = $row['bio']      ?? 'Join me on Goreto!';
            $pic      = $row['profile_pic'] ?? '';
            if ($pic) {
                $avatarUrl = (strpos($pic, 'http') === 0)
                    ? $pic
                    : $baseUrl . '/uploads/' . ltrim($pic, '/');
            }
        }
    } catch (Exception $e) {
        // fall through to defaults
    }
}

// Override to HTML — must come before any output
header('Content-Type: text/html; charset=utf-8');

$pageUrl     = $baseUrl . '/u.php?id=' . $userId;
$ogTitle     = $username ? "@{$username} on Goreto" : "{$name} on Goreto";
$ogDesc      = $bio ?: "Follow {$name} on Goreto – connect, share & explore.";
$deepLink    = 'goreto://profile/' . $userId;

function h($s) { return htmlspecialchars($s, ENT_QUOTES, 'UTF-8'); }
?><!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8"/>
  <meta name="viewport" content="width=device-width,initial-scale=1"/>
  <title><?= h($ogTitle) ?></title>

  <!-- Open Graph -->
  <meta property="og:type"        content="profile"/>
  <meta property="og:url"         content="<?= h($pageUrl) ?>"/>
  <meta property="og:title"       content="<?= h($ogTitle) ?>"/>
  <meta property="og:description" content="<?= h($ogDesc)  ?>"/>
  <meta property="og:image"       content="<?= h($avatarUrl) ?>"/>
  <meta property="og:image:width" content="400"/>
  <meta property="og:image:height"content="400"/>
  <meta property="og:site_name"   content="Goreto"/>

  <!-- Twitter Card -->
  <meta name="twitter:card"        content="summary"/>
  <meta name="twitter:title"       content="<?= h($ogTitle) ?>"/>
  <meta name="twitter:description" content="<?= h($ogDesc)  ?>"/>
  <meta name="twitter:image"       content="<?= h($avatarUrl) ?>"/>

  <style>
    *{margin:0;padding:0;box-sizing:border-box}
    body{background:#0a0a0f;color:#fff;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;
         display:flex;align-items:center;justify-content:center;min-height:100vh;padding:24px}
    .card{text-align:center;max-width:360px;width:100%}
    .avatar{width:96px;height:96px;border-radius:50%;object-fit:cover;
            border:3px solid #FF007F;margin-bottom:16px}
    h1{font-size:22px;font-weight:700;margin-bottom:4px}
    .handle{color:#FF007F;font-size:14px;margin-bottom:10px}
    .bio{color:#aaa;font-size:13px;line-height:1.5;margin-bottom:28px}
    .btn{display:block;background:linear-gradient(135deg,#FF007F,#D946EF);
         color:#fff;text-decoration:none;padding:14px 32px;border-radius:30px;
         font-size:15px;font-weight:600;margin-bottom:10px}
    .sub{color:#555;font-size:12px;margin-top:18px}
    .sub a{color:#FF007F;text-decoration:none}
  </style>
</head>
<body>
<div class="card">
  <img class="avatar"
       src="<?= h($avatarUrl) ?>"
       alt="<?= h($name) ?>"
       onerror="this.src='<?= h($baseUrl) ?>/assets/logo.png'"/>
  <h1><?= h($name) ?></h1>
  <?php if ($username): ?>
    <div class="handle">@<?= h($username) ?></div>
  <?php endif; ?>
  <p class="bio"><?= h($ogDesc) ?></p>
  <a class="btn" href="<?= h($deepLink) ?>">Open in Goreto App</a>
  <p class="sub">Don't have the app?
    <a href="https://play.google.com/store">Download on Android</a>
  </p>
</div>
<script>
  // Attempt to open the app; if it fails the page stays visible.
  setTimeout(function(){ window.location.href = '<?= h($deepLink) ?>'; }, 300);
</script>
</body>
</html>
