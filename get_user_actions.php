<?php
$f = "user_actions.php";
if (file_exists($f)) {
    echo file_get_contents($f);
} else {
    echo "NOT FOUND";
}
?>
