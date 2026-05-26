<?php
require_once 'db_connect.php';
$stmt = $pdo->query("SHOW TABLES");
echo json_encode($stmt->fetchAll(PDO::FETCH_COLUMN));
?>
