<?php
require_once __DIR__ . '/db_connect.php';
$pdo->exec("UPDATE match_profiles SET gender = 'male' WHERE user_id = 13");
echo "Restored User 13 to male.";
?>
