<?php
/**
 * Shared-post landing page.
 *
 * Reached through the share links the app builds:
 *   /ekloadmin/view_post.php?id={postId}
 *   /ekloadmin/api/v1/view_post.php?id={postId}
 * Both are one-line shims that require this file from the document root.
 *
 * Its job is to be what a recipient opens in a browser: Open Graph tags so the
 * link previews in WhatsApp/Messenger, the media itself, and a button that
 * hands off to the app via goreto://post/{id} (the scheme DeepLinkService
 * already handles).
 */

declare(strict_types=1);

$config  = @require '/var/www/html/ekloadmin/config/config.php';
$baseUrl = rtrim((string) ($config['base_url'] ?? 'https://goreto.org/ekloadmin'), '/');
$siteUrl = preg_replace('~/ekloadmin/?$~', '', $baseUrl) ?: 'https://goreto.org';

$postId = (int) ($_GET['id'] ?? 0);

$post = null;
if ($postId > 0 && is_array($config) && !empty($config['db'])) {
    try {
        $db  = $config['db'];
        $pdo = new PDO(
            "mysql:host={$db['host']};dbname={$db['name']};charset=utf8mb4",
            $db['user'],
            $db['pass'],
            [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION, PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC]
        );
        $st = $pdo->prepare("
            SELECT p.id, p.caption, p.type, p.file_url, p.thumbnail_url,
                   p.likes_count, p.comments_count, p.created_at,
                   u.name AS author_name, u.username AS author_username,
                   u.profile_pic AS author_avatar
            FROM posts p
            JOIN users u ON u.id = p.user_id
            WHERE p.id = ? AND p.is_flagged = 0
            LIMIT 1
        ");
        $st->execute([$postId]);
        $post = $st->fetch() ?: null;
    } catch (Throwable $e) {
        // Fall through to the not-found page rather than showing a stack trace.
        $post = null;
    }
}

/** Make a stored path absolute; stored values may already be full URLs. */
function abs_url(?string $url, string $baseUrl): string
{
    $url = trim((string) $url);
    if ($url === '') return '';
    if (preg_match('~^https?://~i', $url)) return $url;
    return rtrim($baseUrl, '/') . '/' . ltrim($url, '/');
}

function e(?string $s): string
{
    return htmlspecialchars((string) $s, ENT_QUOTES, 'UTF-8');
}

if (!$post) {
    http_response_code(404);
    $title = 'Post not found — Goreto';
    $desc  = 'This post is no longer available.';
} else {
    $author = $post['author_name'] ?: ($post['author_username'] ?: 'Someone');
    $title  = $author . ' on Goreto';
    $desc   = trim((string) $post['caption']);
    if ($desc === '') $desc = 'See this post on Goreto.';
    if (mb_strlen($desc) > 160) $desc = mb_substr($desc, 0, 157) . '…';
}

$media  = $post ? abs_url($post['file_url'] ?? '', $baseUrl) : '';
$thumb  = $post ? abs_url($post['thumbnail_url'] ?? '', $baseUrl) : '';
$avatar = $post ? abs_url($post['author_avatar'] ?? '', $baseUrl) : '';
$isVideo = $post && in_array(strtolower((string) $post['type']), ['video', 'reel'], true);
$preview = $thumb !== '' ? $thumb : ($isVideo ? '' : $media);
$pageUrl = $siteUrl . '/ekloadmin/view_post.php?id=' . $postId;
$appLink = 'goreto://post/' . $postId;
?>
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title><?= e($title) ?></title>
<meta name="description" content="<?= e($desc) ?>">

<meta property="og:site_name" content="Goreto">
<meta property="og:type" content="<?= $isVideo ? 'video.other' : 'article' ?>">
<meta property="og:title" content="<?= e($title) ?>">
<meta property="og:description" content="<?= e($desc) ?>">
<meta property="og:url" content="<?= e($pageUrl) ?>">
<?php if ($preview !== ''): ?>
<meta property="og:image" content="<?= e($preview) ?>">
<?php endif; ?>
<?php if ($isVideo && $media !== ''): ?>
<meta property="og:video" content="<?= e($media) ?>">
<?php endif; ?>
<meta name="twitter:card" content="<?= $preview !== '' ? 'summary_large_image' : 'summary' ?>">

<link rel="icon" href="/favicon.ico">
<style>
  :root { color-scheme: dark; }
  * { box-sizing: border-box; }
  body {
    margin: 0; min-height: 100vh;
    font-family: system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
    background: #0b0714; color: #fff;
    display: flex; flex-direction: column; align-items: center;
    padding: 24px 16px 40px;
  }
  .brand { font-size: 26px; font-weight: 800; letter-spacing: -.5px; margin-bottom: 20px;
           background: linear-gradient(90deg,#ff2d55,#b86bff,#00e5ff);
           -webkit-background-clip: text; background-clip: text; color: transparent; }
  .card { width: 100%; max-width: 460px; background: #15101f;
          border: 1px solid rgba(255,255,255,.08); border-radius: 16px; overflow: hidden; }
  .head { display: flex; align-items: center; gap: 10px; padding: 14px 16px; }
  .avatar { width: 38px; height: 38px; border-radius: 50%; object-fit: cover;
            background: #2a2140; flex: none; }
  .who { min-width: 0; }
  .name { font-weight: 700; font-size: 15px; }
  .handle { color: rgba(255,255,255,.45); font-size: 13px; }
  .media { width: 100%; display: block; background: #000; max-height: 70vh; object-fit: contain; }
  .caption { padding: 14px 16px; font-size: 15px; line-height: 1.5; white-space: pre-wrap; word-wrap: break-word; }
  .stats { padding: 0 16px 14px; color: rgba(255,255,255,.45); font-size: 13px; }
  .cta { display: block; max-width: 460px; width: 100%; margin-top: 18px; padding: 15px 20px;
         text-align: center; text-decoration: none; font-weight: 700; font-size: 15px;
         color: #fff; border-radius: 30px; background: linear-gradient(135deg,#ff2d55,#b86bff); }
  .alt { margin-top: 12px; color: rgba(255,255,255,.4); font-size: 13px; text-decoration: none; }
  .empty { max-width: 460px; text-align: center; padding: 48px 20px; color: rgba(255,255,255,.6); }
</style>
</head>
<body>
  <div class="brand">Goreto</div>

<?php if (!$post): ?>
  <div class="empty">
    <p style="font-size:17px;color:#fff;font-weight:600;">Post not found</p>
    <p>It may have been deleted or made private.</p>
  </div>
  <a class="cta" href="<?= e($siteUrl) ?>/">Go to Goreto</a>
<?php else: ?>
  <div class="card">
    <div class="head">
      <?php if ($avatar !== ''): ?>
        <img class="avatar" src="<?= e($avatar) ?>" alt="">
      <?php else: ?>
        <div class="avatar"></div>
      <?php endif; ?>
      <div class="who">
        <div class="name"><?= e($post['author_name']) ?></div>
        <?php if (!empty($post['author_username'])): ?>
          <div class="handle">@<?= e($post['author_username']) ?></div>
        <?php endif; ?>
      </div>
    </div>

    <?php if ($isVideo && $media !== ''): ?>
      <video class="media" controls playsinline preload="metadata"
             <?= $thumb !== '' ? 'poster="' . e($thumb) . '"' : '' ?>>
        <source src="<?= e($media) ?>">
      </video>
    <?php elseif ($media !== ''): ?>
      <img class="media" src="<?= e($media) ?>" alt="">
    <?php endif; ?>

    <?php if (trim((string) $post['caption']) !== ''): ?>
      <div class="caption"><?= e($post['caption']) ?></div>
    <?php endif; ?>

    <div class="stats">
      <?= (int) $post['likes_count'] ?> likes · <?= (int) $post['comments_count'] ?> comments
    </div>
  </div>

  <a class="cta" href="<?= e($appLink) ?>">Open in the Goreto app</a>
  <a class="alt" href="<?= e($siteUrl) ?>/">Don't have the app? Get Goreto</a>
<?php endif; ?>
</body>
</html>
