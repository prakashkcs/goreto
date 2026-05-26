<?php
/**
 * /profile.php  — public profile preview page
 * Served at goreto.org/{username}  or  goreto.org/profile.php?id=X
 *
 * Also acts as JSON resolver when ?format=json is passed
 * (used by the Flutter app's deep-link service to resolve username → userId).
 */

// ── DB connection (re-use ekloadmin config) ───────────────────────────────────
$config = require __DIR__ . '/ekloadmin/config/config.php';
$db = $config['db'];
try {
    $pdo = new PDO(
        "mysql:host={$db['host']};dbname={$db['name']};charset=utf8mb4",
        $db['user'], $db['pass'],
        [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
         PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC]
    );
} catch (Throwable $e) {
    $pdo = null;
}

$format = $_GET['format'] ?? 'html';
if ($format === 'json') {
    header('Content-Type: application/json; charset=utf-8');
    header('Access-Control-Allow-Origin: *');
}

// ── Resolve user ──────────────────────────────────────────────────────────────
$user = null;
if ($pdo) {
    try {
        if (!empty($_GET['id'])) {
            $s = $pdo->prepare('SELECT id, name, username, profile_pic, bio FROM users WHERE id = ? LIMIT 1');
            $s->execute([(int)$_GET['id']]);
            $user = $s->fetch();
        } elseif (!empty($_GET['username'])) {
            $s = $pdo->prepare('SELECT id, name, username, profile_pic, bio FROM users WHERE username = ? LIMIT 1');
            $s->execute([trim($_GET['username'])]);
            $user = $s->fetch();
        }
    } catch (Throwable $e) {}
}

// ── JSON mode ─────────────────────────────────────────────────────────────────
if ($format === 'json') {
    if (!$user) {
        http_response_code(404);
        echo json_encode(['status' => 'error', 'message' => 'User not found']);
    } else {
        echo json_encode(['status' => 'success', 'user_id' => (string)$user['id']]);
    }
    exit;
}

// ── Stats ─────────────────────────────────────────────────────────────────────
$followers = 0; $following = 0; $posts = 0;
if ($user && $pdo) {
    try {
        $s = $pdo->prepare('SELECT COUNT(*) FROM follows WHERE following_id = ?');
        $s->execute([$user['id']]); $followers = (int)$s->fetchColumn();

        $s = $pdo->prepare('SELECT COUNT(*) FROM follows WHERE follower_id = ?');
        $s->execute([$user['id']]); $following = (int)$s->fetchColumn();

        $s = $pdo->prepare('SELECT COUNT(*) FROM posts WHERE user_id = ?');
        $s->execute([$user['id']]); $posts = (int)$s->fetchColumn();
    } catch (Throwable $e) {}
}

// ── HTML vars ─────────────────────────────────────────────────────────────────
$userId    = $user ? (int)$user['id'] : 0;
$name      = $user ? htmlspecialchars($user['name'] ?? 'Goreto User', ENT_QUOTES) : 'Goreto User';
$uname     = $user ? htmlspecialchars($user['username'] ?? '', ENT_QUOTES) : '';
$bio       = $user ? htmlspecialchars($user['bio'] ?? '', ENT_QUOTES) : '';
$rawPic    = $user ? ($user['profile_pic'] ?? '') : '';
$avatar    = $rawPic
    ? (str_starts_with($rawPic, 'http') ? $rawPic : 'https://coinzop.com/ekloadmin/uploads/' . ltrim($rawPic, '/'))
    : '';
$handle    = $uname ? "@$uname" : '';
$pageUrl   = 'https://goreto.org/' . ($uname ?: "?id=$userId");
$appUrl    = "goreto://profile/$userId";
$storeUrl  = 'https://play.google.com/store/apps/details?id=com.nex.ekloapp';
?><!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1"/>
<title><?= $name ?> — Goreto</title>

<!-- Open Graph -->
<meta property="og:type"        content="profile"/>
<meta property="og:site_name"   content="Goreto"/>
<meta property="og:title"       content="<?= $name ?> on Goreto"/>
<meta property="og:description" content="<?= $bio ?: "$name is on Goreto. Follow to see their posts and stories." ?>"/>
<?php if ($avatar): ?><meta property="og:image" content="<?= htmlspecialchars($avatar, ENT_QUOTES) ?>"/><?php endif; ?>
<meta property="og:url"         content="<?= htmlspecialchars($pageUrl, ENT_QUOTES) ?>"/>

<!-- Twitter card -->
<meta name="twitter:card"        content="summary"/>
<meta name="twitter:title"       content="<?= $name ?> on Goreto"/>
<meta name="twitter:description" content="<?= $bio ?: "$name is on Goreto." ?>"/>
<?php if ($avatar): ?><meta name="twitter:image" content="<?= htmlspecialchars($avatar, ENT_QUOTES) ?>"/><?php endif; ?>

<style>
*{box-sizing:border-box;margin:0;padding:0}
body{background:#0a0a0f;color:#fff;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;min-height:100vh;display:flex;flex-direction:column;align-items:center;padding:0 16px 48px}

/* Logo */
.logo{margin-top:36px;font-size:30px;font-weight:900;background:linear-gradient(135deg,#d946ef,#06b6d4);-webkit-background-clip:text;-webkit-text-fill-color:transparent;background-clip:text;letter-spacing:-0.5px}
.tagline{margin-top:4px;font-size:13px;color:rgba(255,255,255,.3);letter-spacing:.5px}

/* Card */
.card{width:100%;max-width:400px;margin-top:32px;background:#111118;border-radius:28px;border:1px solid rgba(217,70,239,.2);box-shadow:0 0 60px rgba(217,70,239,.1),0 20px 40px rgba(0,0,0,.5);padding:36px 24px;display:flex;flex-direction:column;align-items:center}

/* Avatar */
.avatar-wrap{position:relative;width:104px;height:104px}
.avatar{width:104px;height:104px;border-radius:50%;object-fit:cover;border:3px solid transparent;background:linear-gradient(#111118,#111118) padding-box,linear-gradient(135deg,#d946ef,#a855f7) border-box;box-shadow:0 0 24px rgba(217,70,239,.45)}
.avatar-ph{width:104px;height:104px;border-radius:50%;background:linear-gradient(135deg,#1e1e2e,#2a1a3e);border:3px solid #d946ef;display:flex;align-items:center;justify-content:center;font-size:40px}

/* Profile info */
.name{margin-top:18px;font-size:24px;font-weight:700;color:#fff;text-align:center;letter-spacing:-.3px}
.handle{margin-top:5px;font-size:15px;color:#a855f7;text-align:center}
.bio{margin-top:12px;font-size:14px;color:rgba(255,255,255,.6);text-align:center;line-height:1.6;max-width:300px}

/* Stats */
.stats{display:flex;width:100%;margin-top:24px;border-radius:18px;overflow:hidden;border:1px solid rgba(255,255,255,.07);background:rgba(255,255,255,.03)}
.stat{flex:1;padding:16px 8px;text-align:center}
.stat+.stat{border-left:1px solid rgba(255,255,255,.07)}
.stat-n{font-size:20px;font-weight:700;color:#fff}
.stat-l{font-size:11px;color:rgba(255,255,255,.4);margin-top:3px;text-transform:uppercase;letter-spacing:.5px}

/* CTA */
.open-btn{margin-top:28px;width:100%;padding:17px;border-radius:50px;background:linear-gradient(135deg,#d946ef 0%,#a855f7 100%);border:none;color:#fff;font-size:17px;font-weight:700;cursor:pointer;text-align:center;text-decoration:none;display:block;box-shadow:0 8px 24px rgba(168,85,247,.4);letter-spacing:.2px;transition:transform .1s,box-shadow .1s}
.open-btn:active{transform:scale(.97);box-shadow:0 4px 12px rgba(168,85,247,.3)}
.store-row{margin-top:16px;font-size:13px;color:rgba(255,255,255,.35);text-align:center}
.store-row a{color:#a855f7;text-decoration:none;font-weight:500}

/* Not found */
.not-found{margin-top:100px;text-align:center}
.not-found h2{font-size:22px;margin-bottom:10px;color:rgba(255,255,255,.9)}
.not-found p{font-size:14px;color:rgba(255,255,255,.4)}
</style>
</head>
<body>

<div class="logo">Goreto</div>
<div class="tagline">Connect · Share · Discover</div>

<?php if (!$user): ?>
<div class="not-found">
  <h2>Profile not found</h2>
  <p>This user may not exist or their account was removed.</p>
</div>
<?php else: ?>

<div class="card">
  <?php if ($avatar): ?>
    <div class="avatar-wrap">
      <img class="avatar" src="<?= htmlspecialchars($avatar, ENT_QUOTES) ?>" alt="<?= $name ?>"
           onerror="this.replaceWith(document.getElementById('avph'))"/>
      <div class="avatar-ph" id="avph" style="display:none">👤</div>
    </div>
  <?php else: ?>
    <div class="avatar-ph">👤</div>
  <?php endif; ?>

  <div class="name"><?= $name ?></div>
  <?php if ($handle): ?><div class="handle"><?= $handle ?></div><?php endif; ?>
  <?php if ($bio): ?><div class="bio"><?= $bio ?></div><?php endif; ?>

  <div class="stats">
    <div class="stat"><div class="stat-n"><?= number_format($followers) ?></div><div class="stat-l">Followers</div></div>
    <div class="stat"><div class="stat-n"><?= number_format($following) ?></div><div class="stat-l">Following</div></div>
    <div class="stat"><div class="stat-n"><?= number_format($posts) ?></div><div class="stat-l">Posts</div></div>
  </div>

  <a class="open-btn" id="openBtn" href="<?= htmlspecialchars($appUrl, ENT_QUOTES) ?>">Open in Goreto App</a>

  <div class="store-row">
    Don't have Goreto? <a href="<?= $storeUrl ?>" target="_blank">Download free</a>
  </div>
</div>

<script>
document.getElementById('openBtn').addEventListener('click', function(e) {
  e.preventDefault();
  window.location.href = <?= json_encode($appUrl) ?>;
  // If app isn't installed, go to Play Store after 1.5 s
  setTimeout(function() {
    window.location.href = <?= json_encode($storeUrl) ?>;
  }, 1500);
});
</script>

<?php endif; ?>
</body>
</html>
