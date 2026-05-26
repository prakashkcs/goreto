<?php
header('Content-Type: text/plain');
$adminDir = __DIR__ . '/../../admin/';
if (is_dir($adminDir)) {
    echo "Listing $adminDir:\n";
    foreach (scandir($adminDir) as $f) {
        if ($f === '.' || $f === '..') continue;
        $path = $adminDir . $f;
        echo "  $f (" . (is_dir($path) ? "dir" : "file") . ")\n";
    }
} else {
    echo "Admin directory not found at $adminDir\n";
}
