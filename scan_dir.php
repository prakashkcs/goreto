<?php
header('Content-Type: text/plain');
echo "Files in " . getcwd() . ":\n";
print_r(scandir('.'));
if (file_exists('db_connect.php')) {
    echo "db_connect.php exists. Size: " . filesize('db_connect.php') . "\n";
}
?>
