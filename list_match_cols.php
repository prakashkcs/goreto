<?php
require_once __DIR__ . '/db_connect.php';
try {
    $stmt = $pdo->query("SHOW COLUMNS FROM match_profiles");
    $cols = [];
    while ($r = $stmt->fetch(PDO::FETCH_ASSOC))
        $cols[] = $r['Field'];
    echo json_encode($cols);
}
catch (Throwable $e) {
    echo json_encode(['error' => $e->getMessage()]);
}
