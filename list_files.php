<?php
header('Content-Type: text/plain');
echo "DIR CONTENT:\n";
\ = scandir(__DIR__);
foreach(\ as \) {
    if (\ === '.' || \ === '..') { continue; }
    echo \ . (is_dir(__DIR__ . '/' . \) ? '/' : '') . "\n";
}
