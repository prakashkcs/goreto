<?php
// profile_v19.php - DEBUG v2
error_reporting(E_ALL);
ini_set('display_errors', 1);

require_once '../../config.php';
require_once 'db_connect.php';

echo "Connect exists: " . (function_exists('connect') ? 'YES' : 'NO') . "\n";
if (function_exists('connect')) {
    echo "Calling connect...\n";
    $db = connect();
    echo "Success! Type: " . get_class($db) . "\n";
}
?>
