<?php require "db_connect.php"; echo $pdo->query("SELECT api_token FROM users WHERE api_token IS NOT NULL LIMIT 1")->fetchColumn(); ?>
