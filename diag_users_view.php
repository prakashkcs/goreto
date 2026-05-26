<?php
require_once __DIR__ . '/db_connect.php';
$stmt = $pdo->query("SELECT u.id, u.name, u.username, mp.age, mp.location, mp.interests FROM users u LEFT JOIN match_profiles mp ON mp.user_id = u.id ORDER BY u.id DESC LIMIT 5");
echo json_encode($stmt->fetchAll(PDO::FETCH_ASSOC));
