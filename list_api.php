<?php
echo "--- Directory Listing api/v1 ---\n";
foreach (scandir(__DIR__) as $file) {
    if ($file != "." && $file != "..") {
        echo $file . "\n";
    }
}
?>
