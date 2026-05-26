<?php
header('Content-Type: text/plain');
$dir = __DIR__ . '/../../../';
echo "Listing $dir:\n";
foreach (scandir($dir) as $f) {
    echo "  $f (" . (is_dir($dir.$f) ? "dir" : "file") . ")\n";
}
