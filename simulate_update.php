<?php
ini_set('display_errors', '1');
error_reporting(E_ALL);
require_once __DIR__ . '/db_connect.php';

// Force create so we can test it directly
$pdo->exec("CREATE TABLE IF NOT EXISTS debug_nearby (id INT AUTO_INCREMENT PRIMARY KEY, msg TEXT, ts DATETIME DEFAULT CURRENT_TIMESTAMP)");

// Simulate an update_location call
$_POST['action'] = 'update_location';
$_POST['user_id'] = 9;
$_POST['lat'] = 27.7;
$_POST['lng'] = 85.3;

// Include the target file so we can see where it errors out
require_once __DIR__ . '/match_profiles.php';
?>
