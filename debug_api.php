<?php
error_reporting(E_ALL);
ini_set('display_errors', 1);
echo "DEBUG_START <br>";
$p = 'api/v1/db_connect.php';
if (file_exists($p)) {
    echo "Found $p <br>";
    require_once $p;
    echo "DB_OK <br>";
    if (isset($pdo))
        echo "PDO_INIT SUCCESS <br>";
}
else {
    echo "FAILED: $p not found <br>";
}
?>
