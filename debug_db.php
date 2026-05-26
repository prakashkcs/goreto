<?php
error_reporting(E_ALL);
ini_set('display_errors', 1);
header('Content-Type: text/plain');
echo "Starting...\n";
if (!file_exists('db_connect.php')) {
    die("db_connect.php not found");
}
require_once 'db_connect.php';
echo "Included db_connect.php\n";
try {
    $c = connect();
    echo "Connected!\n";
    echo "Type: " . gettype($c) . "\n";
    if (is_object($c)) echo "Class: " . get_class($c) . "\n";
} catch (Exception $e) {
    echo "Error: " . $e->getMessage() . "\n";
}
?>
