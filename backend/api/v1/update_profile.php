<?php
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Content-Type, Authorization');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') exit;

require_once __DIR__ . '/db_connect.php';
require_once __DIR__ . '/auth_middleware.php';

try {
    $viewer = requireUser($pdo);
    $userId = (int) $viewer['id'];

    $allowed = [
        'pay_per_min_enabled' => 'int01',
        'pay_per_min_rate'    => 'intpos',
        'ppm_charge_friends'  => 'int01',
    ];

    $updates = [];
    $params = [];
    foreach ($allowed as $field => $type) {
        if (!isset($_POST[$field])) continue;
        $raw = $_POST[$field];
        if ($type === 'int01') {
            $v = ((int)$raw === 1 || $raw === '1' || $raw === 'true' || $raw === true) ? 1 : 0;
        } elseif ($type === 'intpos') {
            $v = max(0, (int) round((float) $raw));
        } else {
            continue;
        }
        $updates[] = "`$field` = ?";
        $params[] = $v;
    }

    if (empty($updates)) {
        echo json_encode(['status' => 'error', 'message' => 'No updatable fields supplied']);
        exit;
    }

    $params[] = $userId;
    $sql = 'UPDATE users SET ' . implode(', ', $updates) . ' WHERE id = ?';
    $stmt = $pdo->prepare($sql);
    $stmt->execute($params);

    echo json_encode(['status' => 'success', 'updated' => count($updates)]);
} catch (Throwable $e) {
    http_response_code(500);
    echo json_encode(['status' => 'error', 'message' => $e->getMessage()]);
}
