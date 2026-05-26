<?php
header('Content-Type: text/plain');
if (file_exists('profile_v19.php')) {
    echo base64_encode(file_get_contents('profile_v19.php'));
} else {
    echo "File not found";
}
?>
