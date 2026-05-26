<?php
// post_preview.php — Post/Reel social-share preview page
// URL: https://goreto.org/ekloadmin/post_preview.php?id=POST_ID
// Serves Open Graph meta-tags so FB, Telegram, WhatsApp etc. show a rich preview.

$postId  = isset($_GET['id']) ? (int)$_GET['id'] : 0;
$baseUrl = 'https://goreto.org/ekloadmin';

$caption    = 'Check out this post on Goreto!';
$authorName = 'Goreto User';
$thumbUrl   = $baseUrl . '/assets/logo.png';

if ($postId > 0) {
    try {
        require_once __DIR__ . '/db_connect.php';
        $stmt = $pdo->prepare(
            "SELECT p.caption, p.thumbnail_url, p.file_url,
                    u.name AS author_name, u.username AS author_username
             FROM posts p
             LEFT JOIN users u ON u.id = p.user_id
             WHERE p.id = ? LIMIT 1"
        );
        $stmt->execute([$postId]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);
        if ($row) {
            $caption    = $row['caption']          ?: 'Check out this post on Goreto!';
            $authorName = $row['author_name']       ?? ($row['author_username'] ?? 'Goreto User');
            $thumb      = $row['thumbnail_url']     ?? $row['file_url'] ?? '';
            if ($thumb) {
                $thumbUrl = (strpos($thumb, 'http') === 0)
                    ? $thumb
                    : $baseUrl . '/uploads/' . ltrim($thumb, '/');
            }
        }
    } catch (Exception $e) {
        // fall through to defaults
    }
}

header('Content-Type: text/html; charset=utf-8');

$pageUrl  = $baseUrl . '/post_preview.php?id=' . $postId;
$ogTitle  = "{$authorName} on Goreto";
$ogDesc   = $caption;
$deepLink = 'goreto://post/' . $postId;

function h($s) { return htmlspecialchars($s, ENT_QUOTES, 'UTF-8'); }
?><!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8"/>
  <meta name="viewport" content="width=device-width,initial-scale=1"/>
  <title><?= h($ogTitle) ?></title>

  <!-- Open Graph -->
  <meta property="og:type"         content="article"/>
  <meta property="og:url"          content="<?= h($pageUrl) ?>"/>
  <meta property="og:title"        content="<?= h($ogTitle) ?>"/>
  <meta property="og:description"  content="<?= h($ogDesc)  ?>"/>
  <meta property="og:image"        content="<?= h($thumbUrl) ?>"/>
  <meta property="og:image:width"  content="720"/>
  <meta property="og:image:height" content="1280"/>
  <meta property="og:site_name"    content="Goreto"/>

  <!-- Twitter Card -->
  <meta name="twitter:card"        content="summary_large_image"/>
  <meta name="twitter:title"       content="<?= h($ogTitle) ?>"/>
  <meta name="twitter:description" content="<?= h($ogDesc)  ?>"/>
  <meta name="twitter:image"       content="<?= h($thumbUrl) ?>"/>

  <style>
    *{margin:0;padding:0;box-sizing:border-box}
    body{background:#0a0a0f;color:#fff;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;
         display:flex;align-items:center;justify-content:center;min-height:100vh;padding:24px}
    .card{text-align:center;max-width:360px;width:100%}
    .thumb{width:100%;max-height:280px;object-fit:cover;border-radius:16px;
           margin-bottom:18px;border:2px solid #FF007F}
    h1{font-size:15px;font-weight:600;margin-bottom:6px;color:#aaa}
    .caption{font-size:18px;font-weight:700;margin-bottom:24px;line-height:1.4}
    .btn{display:block;background:linear-gradient(135deg,#FF007F,#D946EF);
         color:#fff;text-decoration:none;padding:14px 32px;border-radius:30px;
         font-size:15px;font-weight:600;margin-bottom:10px}
    .sub{color:#555;font-size:12px;margin-top:18px}
    .sub a{color:#FF007F;text-decoration:none}
  </style>
</head>
<body>
<div class="card">
  <img class="thumb"
       src="<?= h($thumbUrl) ?>"
       alt="Post thumbnail"
       onerror="this.src='<?= h($baseUrl) ?>/assets/logo.png'"/>
  <h1>by <?= h($authorName) ?></h1>
  <p class="caption"><?= h($caption) ?></p>
  <a class="btn" href="<?= h($deepLink) ?>">Open in Goreto App</a>
  <p class="sub">Don't have the app?
    <a href="https://play.google.com/store">Download on Android</a>
  </p>
</div>
<script>
  setTimeout(function(){ window.location.href = '<?= h($deepLink) ?>'; }, 300);
</script>
</body>
</html>
