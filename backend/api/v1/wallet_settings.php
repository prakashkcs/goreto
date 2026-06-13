<?php
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Content-Type, Authorization');
header('Access-Control-Allow-Methods: GET, OPTIONS');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    echo json_encode(['status' => true]);
    exit;
}

require_once __DIR__ . '/db_connect.php';

try {
    // Try to read settings from wallet_settings table
    $settings = [
        'coin_rate_npr' => 1,
        'currency_symbol' => 'c',
        'currency_code' => 'NPR',
        'min_deposit' => 100,
        'max_deposit' => 100000,
        'min_withdraw' => 100,
        'coins_per_currency' => 1,
    ];

    // Check if wallet_settings table exists, read from it
    try {
        $st = $pdo->query("SELECT setting_key, setting_value FROM wallet_settings");
        while ($row = $st->fetch(PDO::FETCH_ASSOC)) {
            $settings[$row['setting_key']] = $row['setting_value'];
        }
    }
    catch (Throwable $e) {
    // table may not exist yet; use defaults
    }

    echo json_encode([
        'status' => 'success',
        'settings' => $settings,
    ]);

}
catch (Throwable $e) {
    http_response_code(500);
    echo json_encode([
        'status' => 'error',
        'message' => 'Server error',
        'detail' => $e->getMessage(),
    ]);
}
