<?php
require_once __DIR__ . '/db_connect.php';
$stmt = $pdo->query("SHOW COLUMNS FROM users");
$cols = [];
while ($r = $stmt->fetch(PDO::FETCH_ASSOC))
    $cols[] = $r['Field'];
echo json_encode($cols);
