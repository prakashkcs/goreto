<?php
require_once 'db_connect.php';
$stmt = $pdo->query('DESCRIBE users');
$columns = $stmt->fetchAll(PDO::FETCH_ASSOC);
header('Content-Type: application/json');
echo json_encode($columns, JSON_PRETTY_PRINT);
?>
