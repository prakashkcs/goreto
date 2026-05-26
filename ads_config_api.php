<?php
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Content-Type, Authorization');
header('Access-Control-Allow-Methods: GET, OPTIONS');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

require_once __DIR__ . '/db_connect.php';

function out(array $arr, int $code = 200): void {
    http_response_code($code);
    echo json_encode($arr);
    exit;
}

// Create table if not exists
try {
    $pdo->exec("CREATE TABLE IF NOT EXISTS ad_settings (
        id INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
        setting_key VARCHAR(80) NOT NULL UNIQUE,
        setting_value TEXT NULL,
        updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
} catch (Exception $e) {}

$defaults = [
    'ads_enabled'              => '1',
    'density'                  => 'balanced',
    'feed_frequency'           => '5',
    'interstitial_frequency'   => '5',
    'banner_ad_unit_id'        => '',
    'interstitial_ad_unit_id'  => '',
    'estimated_rpm'            => '0.50',
];

$rows = $pdo->query("SELECT setting_key, setting_value FROM ad_settings")
    ->fetchAll(PDO::FETCH_KEY_PAIR);
$settings = array_merge($defaults, $rows);

out(['status' => 'success', 'settings' => $settings]);
