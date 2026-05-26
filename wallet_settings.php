<?php
header('Content-Type: application/json; charset=utf-8');
require_once __DIR__ . '/db_connect.php';

// Action: Fetch wallet settings (exchange rate, etc.)
// This can be used for showing the NPR amount on the deposit page.
try {
    // In a real app, these would be in a wallet_settings table.
    // Defaulting to 1 coin = 1 NPR if table missing or settings not found.
    $coinRate = 1.0;

    // Check if table exists
    $st = $pdo->query("SHOW TABLES LIKE 'wallet_settings'");
    if ($st->fetchColumn()) {
        $stSet = $pdo->query("SELECT * FROM wallet_settings WHERE setting_key = 'coin_rate_npr' LIMIT 1");
        $row = $stSet->fetch(PDO::FETCH_ASSOC);
        if ($row)
            $coinRate = floatval($row['setting_value']);
    }

    echo json_encode([
        'status' => true,
        'settings' => [
            'coin_rate_npr' => $coinRate,
            'currency_symbol' => 'c',
            'min_deposit' => 10,
            'max_deposit' => 10000
        ]
    ]);
}
catch (Exception $e) {
    http_response_code(500);
    echo json_encode(['status' => false, 'message' => $e->getMessage()]);
}
