<?php
header('Content-Type: text/plain');
echo "--- DIRECTORY LISTING: uploads/ ---\n";
foreach (scandir('uploads') as $file) {
    if ($file === '.' || $file === '..') continue;
    $path = 'uploads/' . $file;
    echo "$file (" . filesize($path) . " bytes)\n";
}
echo "\n";

foreach (glob('uploads/*.log') as $file) {
    echo "--- FILE: $file ---\n";
    echo file_get_contents($file);
    echo "\n\n";
}
