<?php
header('Content-Type: text/plain');
if (file_exists('db_connect.php')) {
    $src = file_get_contents('db_connect.php');
    if (preg_match('/function\s+connect\s*\(.*?\)\s*\{(?:[^{}]*|\{(?:[^{}]*|\{[^{}]*\})*\})*\}/s', $src, $match)) {
        echo $match[0];
    } else {
        echo "Could not extract connect function\n";
        echo "First 500 chars:\n" . substr($src, 0, 500);
    }
}
?>
