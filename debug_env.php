<?php
header('Content-Type: application/json');
require_once __DIR__ . '/db_connect.php';
$res = [
    'dir' => __DIR__,
    'db' => $pdo->query('SELECT DATABASE()')->fetchColumn(),
    'all_providers' => $pdo->query("SELECT id, provider_name, is_active, last_error_time FROM video_providers")->fetchAll(PDO::FETCH_ASSOC),
    'active_count' => (int)$pdo->query("SELECT COUNT(*) FROM video_providers WHERE is_active = 1")->fetchColumn(),
    'filtered_active' => $pdo->query("SELECT id FROM video_providers WHERE is_active = 1 AND (auto_rotate = 0 OR last_error_time IS NULL OR last_error_time < DATE_SUB(NOW(), INTERVAL 5 MINUTE))")->fetchAll(PDO::FETCH_ASSOC),
];
echo json_encode($res);
?>
