<?php
/**
 * legal.php — Public, browsable legal pages for App Store / Play Store listings.
 * Reads the same content the app shows (legal_pages table) and renders clean HTML.
 *   /ekloadmin/legal.php?doc=privacy | terms | content_policy | child_safety
 */
require_once __DIR__ . '/api/v1/db_connect.php';

$docs = [
  'privacy'        => 'Privacy Policy',
  'terms'          => 'Terms & Conditions',
  'content_policy' => 'Community & Content Policy',
  'child_safety'   => 'Child Safety Standards',
];

$doc = $_GET['doc'] ?? '';
$row = null;
if (isset($docs[$doc])) {
  try {
    $st = $pdo->prepare("SELECT title, content, updated_at FROM legal_pages WHERE page_key = ?");
    $st->execute([$doc]);
    $row = $st->fetch(PDO::FETCH_ASSOC);
  } catch (Throwable $e) { $row = null; }
}

header('Content-Type: text/html; charset=utf-8');
$title = $row ? $row['title'] : 'Goreto — Legal';
?>
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title><?= htmlspecialchars($title) ?> · Goreto</title>
<style>
  :root { color-scheme: light dark; }
  body { margin:0; font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif; line-height:1.6; color:#1a1a1a; background:#fafafa; }
  .wrap { max-width:780px; margin:0 auto; padding:28px 20px 80px; }
  header { border-bottom:2px solid #FF007F; padding-bottom:14px; margin-bottom:24px; }
  h1 { font-size:26px; margin:0 0 4px; color:#FF007F; }
  .updated { color:#888; font-size:13px; }
  .content { font-size:15px; }
  .content h1,.content h2,.content h3 { color:#222; margin-top:28px; }
  .content a { color:#FF007F; }
  nav { margin-bottom:24px; font-size:14px; }
  nav a { color:#666; margin-right:14px; text-decoration:none; }
  nav a:hover { color:#FF007F; }
  footer { margin-top:48px; padding-top:18px; border-top:1px solid #ddd; color:#999; font-size:13px; }
  @media (prefers-color-scheme: dark){ body{background:#0d0d0d;color:#e8e8e8} .content h1,.content h2,.content h3{color:#fff} .updated,footer{color:#888} }
</style>
</head>
<body>
<div class="wrap">
  <nav>
    <a href="?doc=privacy">Privacy</a>
    <a href="?doc=terms">Terms</a>
    <a href="?doc=content_policy">Content Policy</a>
    <a href="?doc=child_safety">Child Safety</a>
  </nav>
<?php if ($row): ?>
  <header>
    <h1><?= htmlspecialchars($row['title']) ?></h1>
    <div class="updated">Last updated: <?= htmlspecialchars(date('F j, Y', strtotime($row['updated_at'] ?? 'now'))) ?></div>
  </header>
  <div class="content"><?= $row['content'] /* trusted admin-authored HTML */ ?></div>
<?php else: ?>
  <header><h1>Goreto — Legal</h1></header>
  <p>Please choose a document:</p>
  <ul>
    <?php foreach ($docs as $k => $t): ?>
      <li><a href="?doc=<?= $k ?>"><?= htmlspecialchars($t) ?></a></li>
    <?php endforeach; ?>
  </ul>
<?php endif; ?>
  <footer>
    Goreto · Contact: <a href="mailto:support@goreto.org">support@goreto.org</a> ·
    Child-safety concerns: <a href="mailto:childsafety@goreto.org">childsafety@goreto.org</a>
  </footer>
</div>
</body>
</html>
