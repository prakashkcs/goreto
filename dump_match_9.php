<?php
require_once __DIR__ . '/db_connect.php';
$stmt = $pdo->query("SELECT * FROM match_profiles WHERE user_id = 9");
echo json_encode($stmt->fetch(PDO::FETCH_ASSOC));
