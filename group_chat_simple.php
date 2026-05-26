<?php
header('Content-Type: application/json; charset=utf-8');
error_reporting(E_ALL);
ini_set('display_errors', 1);

$action = $_GET['action'] ?? '';

if ($action === 'ping') {
    echo json_encode(['status' => 'ok', 'message' => 'group_chat works']);
    exit;
}

echo json_encode(['status' => 'error', 'message' => 'Invalid action']);
