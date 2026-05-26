<?php
header('Content-Type: text/plain');
function listDir($dir)
{
    if (!is_dir($dir))
        return;
    $files = scandir($dir);
    foreach ($files as $file) {
        if ($file === '.' || $file === '..')
            continue;
        $path = $dir . DIRECTORY_SEPARATOR . $file;
        echo $path . (is_dir($path) ? " (DIR)" : "") . "\n";
    }
}
echo "--- Root Listing ---\n";
listDir(__DIR__ . "/../..");
echo "\n--- api/v1 Listing ---\n";
listDir(__DIR__);
?>
