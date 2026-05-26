<?php
// Debug: check what avatar values are stored in chat_groups
require_once __DIR__ . '/db_connect.php';
$rows = $pdo->query("SELECT id, name, avatar FROM chat_groups LIMIT 10")->fetchAll(PDO::FETCH_ASSOC);
echo json_encode($rows, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES);
