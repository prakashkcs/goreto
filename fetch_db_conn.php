<?php
header('Content-Type: text/plain');
if (file_exists('db_connect.php')) {
    echo file_get_contents('db_connect.php');
} else {
    echo "File not found";
}
?>
