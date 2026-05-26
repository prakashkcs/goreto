<?php require "db_connect.php";
echo $pdo->query("SELECT api_token FROM users WHERE api_token != '' LIMIT 1")->fetchColumn(); ?>
