<?php
require_once __DIR__ . '/db_connect.php';
$stmt = $pdo->query("SELECT u.id, u.name, m.gender FROM users u JOIN match_profiles m ON u.id = m.user_id WHERE u.id != 9 AND m.gender = 'female' LIMIT 5");
$users = $stmt->fetchAll(PDO::FETCH_ASSOC);
echo json_encode($users);
?>
