<?php
header('Content-Type: text/plain');
$f = '../../../config.php';
echo "is_file($f): " . (is_file($f) ? 'YES' : 'NO') . "\n";
echo "open_basedir: " . ini_get('open_basedir') . "\n";
?>
