<?php
require_once __DIR__ . '/db_connect.php';
$stmt = $pdo->query("SELECT * FROM video_providers");
echo json_encode($stmt->fetchAll(PDO::FETCH_ASSOC), JSON_PRETTY_PRINT);
?>
