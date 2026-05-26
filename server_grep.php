<?php
$dirs = ['../../', '../../../'];
foreach ($dirs as $dir) {
    echo "Searching in $dir ...\n";
    $output = shell_exec("grep -r '98782439' " . $dir . " --exclude-dir=api/v1 --exclude-dir=uploads");
    echo $output . "\n";
}
?>
