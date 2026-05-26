<?php
header('Content-Type: text/plain');
$adminDir = __DIR__ . '/../../../admin/';
if (is_dir($adminDir)) {
    echo "Listing $adminDir:\n";
    foreach (scandir($adminDir) as $f) {
        echo "  $f\n";
    }
} else {
    echo "Root admin directory not found\n";
}

$includesDir = __DIR__ . '/../../../includes/';
if (is_dir($includesDir)) {
    echo "\nListing $includesDir:\n";
    foreach (scandir($includesDir) as $f) {
        echo "  $f\n";
    }
}
