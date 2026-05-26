<?php
require_once __DIR__ . '/db_connect.php';

echo "SERVER FILE LIST (api/v1):\n";
foreach (glob("*") as $filename) {
    echo "- $filename\n";
}

echo "\nChecking proposals table columns...\n";
try {
    $st = $pdo->query("DESCRIBE proposals");
    $columns = $st->fetchAll(PDO::FETCH_ASSOC);
    foreach ($columns as $col) {
        echo "- {$col['Field']} ({$col['Type']})\n";
    }
} catch (Exception $e) {
    echo "ERROR DESCRIBING: " . $e->getMessage() . "\n";
}

echo "\nChecking a sample user (id=9):\n";
try {
    $st = $pdo->prepare("SELECT id, name FROM users WHERE id = ?");
    $st->execute([9]);
    $u = $st->fetch();
    if ($u) {
        echo "User 9: ID={$u['id']}, Name='{$u['name']}'\n";
    } else {
        echo "User 9 not found.\n";
    }
} catch (Exception $e) {
    echo "ERROR FETCHING USER: " . $e->getMessage() . "\n";
}
?>
