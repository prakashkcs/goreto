<?php
function listFiles($dir, $depth = 0)
{
    if ($depth > 2)
        return;
    $files = glob($dir . '/*');
    foreach ($files as $f) {
        echo str_repeat("  ", $depth) . basename($f) . (is_dir($f) ? "/" : "") . "\n";
        if (is_dir($f))
            listFiles($f, $depth + 1);
    }
}
echo "FILE LISTING FOR " . __DIR__ . ":\n";
listFiles(__DIR__);
?>
