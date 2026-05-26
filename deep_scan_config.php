<?php
header('Content-Type: text/plain');
echo "CWD: " . getcwd() . "\n";
$f = '../../config.php';
echo "Testing $f...\n";
if (file_exists($f)) {
    echo "Exists! Real: " . realpath($f) . "\n";
} else {
    echo "Does NOT exist.\n";
    echo "Scanning ..\n";
    print_r(scandir('..'));
    echo "Scanning ../..\n";
    print_r(scandir('../..'));
}
?>
