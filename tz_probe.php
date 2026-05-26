<?php
// Temporary timezone diagnostic - delete after use
header('Content-Type: application/json');

$config = require __DIR__ . '/../config/config.php';
$db = $config['db'];
$dsn = "mysql:host={$db['host']};dbname={$db['name']};charset=utf8mb4";
$pdo = new PDO($dsn, $db['user'], $db['pass']);

$pdo->exec("SET time_zone = '+00:00'");

$r = $pdo->query("SELECT NOW() as mysql_now, @@global.time_zone as global_tz, @@session.time_zone as session_tz")->fetch(PDO::FETCH_ASSOC);

echo json_encode([
    'php_date' => date('Y-m-d H:i:s'),
    'php_timezone' => date_default_timezone_get(),
    'mysql_now' => $r['mysql_now'],
    'mysql_global_tz' => $r['global_tz'],
    'mysql_session_tz' => $r['session_tz'],
    'utc_now' => gmdate('Y-m-d H:i:s'),
]);
