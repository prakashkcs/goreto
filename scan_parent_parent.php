<?php
header('Content-Type: text/plain');
$d = '../..';
echo "Files in $d:\n";
$files = scandir($d);
print_r($files);
if (in_array('config.php', $files)) {
    echo "config.php FOUND in $d\n";
} else {
    echo "config.php NOT in $d\n";
}
?>
