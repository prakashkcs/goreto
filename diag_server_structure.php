<?php
header('Content-Type: text/plain');

function find_file($dir, $filename) {
    if (!is_dir($dir)) return null;
    $it = new RecursiveDirectoryIterator($dir);
    foreach (new RecursiveIteratorIterator($it) as $file) {
        if ($file->getFilename() === $filename) {
            return $file->getPathname();
        }
    }
    return null;
}

echo "Searching for _core.php...\n";
$root = realpath(__DIR__ . '/../../../');
$path = find_file($root, '_core.php');
if ($path) {
    echo "Found at: $path\n";
    echo "Contents:\n" . file_get_contents($path) . "\n";
} else {
    echo "Not found in $root\n";
}

echo "\nListing current directory:\n";
foreach (scandir(__DIR__) as $f) {
    echo "  $f\n";
}

echo "\nListing parent directory:\n";
foreach (scandir(__DIR__ . '/../') as $f) {
    echo "  $f\n";
}

echo "\nListing grandparent directory:\n";
foreach (scandir(__DIR__ . '/../../') as $f) {
    echo "  $f\n";
}
