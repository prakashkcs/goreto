<?php
/**
 * Daily read-only reference-integrity check (integrity audit item G).
 *
 * Counts records whose parent no longer exists and saves the result for
 * admin/integrity.php. Changes no data. Logs a warning to the journal when
 * any orphan is found, so a regression shows up the next morning.
 *
 * Run from a systemd timer (goreto-integrity.timer):
 *   php /var/www/html/ekloadmin/admin/cron_integrity_check.php
 */

if (PHP_SAPI !== 'cli') {
    http_response_code(404);
    exit;
}

require_once __DIR__ . '/_integrity.php';

$config = require '/var/www/html/ekloadmin/config/config.php';
$dbc    = $config['db'];
$pdo = new PDO(
    "mysql:host={$dbc['host']};dbname={$dbc['name']};charset=utf8mb4",
    $dbc['user'],
    $dbc['pass'] ?? ($dbc['password'] ?? ''),
    [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]
);
$pdo->exec('SET SESSION TRANSACTION READ ONLY');

$result = integrity_run($pdo);
integrity_save($result);

echo "[integrity] {$result['checked_at']}: {$result['relationships']} relationships, "
   . "{$result['orphans_total']} orphan records\n";
foreach ($result['results'] as $r) {
    if ($r['orphans'] > 0) {
        fwrite(STDERR, "[integrity] WARNING {$r['ref']} -> {$r['parent']}: {$r['orphans']} orphan(s)\n");
    }
}
exit($result['orphans_total'] > 0 ? 2 : 0);
