<?php
/**
 * Carries out account deletions that were scheduled 30 days earlier.
 *
 * account.php promises the user "Account scheduled for deletion" and writes
 * delete_scheduled_at = NOW() + 30 days. Nothing read that column back, and
 * the server ran no job for it, so the date passed and the account stayed --
 * a promise the product made and never kept.
 *
 * Run from a systemd timer, once a day:
 *   php /var/www/html/ekloadmin/admin/cron_process_deletions.php
 *
 * Add --dry-run to list what would be deleted and change nothing. Pass
 * --limit=N to cap one run; the default of 200 keeps a single pass bounded
 * if a backlog ever builds up, and the next run picks up the rest.
 *
 * Financial history is retained -- see cascade_delete_user().
 */

if (PHP_SAPI !== 'cli') {
    http_response_code(404);
    exit;
}

require_once __DIR__ . '/_cascade.php';

$config = require '/var/www/html/ekloadmin/config/config.php';
$dbc    = $config['db'];

$dry   = in_array('--dry-run', $argv, true);
$limit = 200;
foreach ($argv as $arg) {
    if (strpos($arg, '--limit=') === 0) {
        $limit = max(1, (int) substr($arg, 8));
    }
}

$pdo = new PDO(
    "mysql:host={$dbc['host']};dbname={$dbc['name']};charset=utf8mb4",
    $dbc['user'],
    $dbc['pass'],
    [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION, PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC]
);

$stamp = date('c');
$due = $pdo->prepare(
    'SELECT id, delete_scheduled_at
       FROM users
      WHERE delete_scheduled_at IS NOT NULL
        AND delete_scheduled_at <= NOW()
      ORDER BY delete_scheduled_at ASC
      LIMIT ' . (int) $limit
);
$due->execute();
$rows = $due->fetchAll();

if (!$rows) {
    echo "[$stamp] nothing due\n";
    exit(0);
}

echo '[' . $stamp . '] ' . count($rows) . ' account(s) due' . ($dry ? ' (dry run)' : '') . "\n";

$ok = 0;
$failed = 0;
foreach ($rows as $row) {
    $id = (int) $row['id'];

    if ($dry) {
        $preview = cascade_preview($pdo, 'user', $id);
        $total = array_sum($preview);
        echo "  user $id (due {$row['delete_scheduled_at']}): would remove $total row(s)\n";
        foreach ($preview as $where => $n) {
            echo "      $where: $n\n";
        }
        continue;
    }

    try {
        $removed = cascade_delete_user($pdo, $id, 'user_requested');
        $ok++;
        echo '  user ' . $id . ': removed ' . array_sum($removed) . " row(s)\n";
    } catch (Throwable $e) {
        // Nothing was written for this user; the next run retries it.
        $failed++;
        $msg = '[cron_process_deletions] user ' . $id . ' failed: ' . $e->getMessage();
        echo "  $msg\n";
        error_log($msg);
    }
}

if (!$dry) {
    echo "[$stamp] done: $ok deleted, $failed failed\n";
}

// A failure must show up in the timer's status rather than passing silently.
exit($failed > 0 ? 1 : 0);
