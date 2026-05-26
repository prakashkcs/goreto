<?php
header('Content-Type: text/plain');
$files = scandir('.');
print_r($files);
if (in_array('config.php', $files)) {
    echo "config.php FOUND in .\n";
} else {
    echo "config.php NOT in .\n";
}
?>
