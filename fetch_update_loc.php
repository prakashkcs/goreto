<?php
header('Content-Type: text/plain');
if (file_exists('update_location.php')) {
    echo file_get_contents('update_location.php');
} else {
    echo "File not found";
}
?>
