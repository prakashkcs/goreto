<?php
header('Content-Type: text/plain');
$d = '/home/sharexhu/domains/coinzop.com/public_html/';
if (is_dir($d)) {
    echo "Files in $d:\n";
    print_r(scandir($d));
} else {
    echo "$d is NOT a directory!\n";
}
?>
