<?php
header('Content-Type: text/plain');
require_once '../../config.php';
require_once 'db_connect.php';
echo "User functions:\n";
$funcs = get_defined_functions()['user'];
sort($funcs);
foreach ($funcs as $f) {
    echo "- $f\n";
}
?>
