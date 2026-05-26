<?php
header('Content-Type: text/plain');
if (file_exists('db_connect.php')) {
    $src = file_get_contents('db_connect.php');
    if (preg_match_all('/function\s+([a-zA-Z0-9_]+)\s*\(/', $src, $matches)) {
        print_r($matches[1]);
    } else {
        echo "No functions found in db_connect.php\n";
        echo "Source start: " . substr($src, 0, 100) . "\n";
    }
} else {
    echo "db_connect.php not found";
}
?>
