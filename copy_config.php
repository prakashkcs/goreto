<?php
header('Content-Type: text/plain');
if (file_exists('config.php')) {
    if (copy('config.php', 'config_temp.txt')) {
        echo "Copy successful\n";
    } else {
        echo "Copy failed\n";
    }
} else {
    echo "config.php not found\n";
}
?>
