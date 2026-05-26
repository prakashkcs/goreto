<?php
require_once __DIR__ . '/db_connect.php';
// Temporary: Make User 13 Female
$pdo->exec("UPDATE match_profiles SET gender = 'female' WHERE user_id = 13");
echo "User 13 is now female. ";
?>
