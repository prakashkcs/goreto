<?php
require_once __DIR__ . '/db_connect.php';

// Clear the cooldown log
$pdo->exec("DELETE FROM nearby_notifications_log");
echo "Cooldown logs cleared.";

?>
