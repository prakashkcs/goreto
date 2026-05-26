<?php
header('Content-Type: text/plain');
$f = '/home/sharexhu/domains/coinzop.com/public_html/config.php';
echo "is_file($f): " . (is_file($f) ? 'YES' : 'NO') . "\n";
echo "file_exists($f): " . (file_exists($f) ? 'YES' : 'NO') . "\n";
$f2 = '../../config.php';
echo "is_file($f2): " . (is_file($f2) ? 'YES' : 'NO') . "\n";
?>
