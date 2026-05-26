<?php
header('Content-Type: text/plain');
$dir = __DIR__ . '/../../admin/';
$search = 'kyc_status';

function search_in_dir($dir, $search) {
    $files = scandir($dir);
    foreach ($files as $f) {
        if ($f === '.' || $f === '..') continue;
        $path = $dir . $f;
        if (is_file($path) && pathinfo($path, PATHINFO_EXTENSION) === 'php') {
            $content = file_get_contents($path);
            if (strpos($content, $search) !== false) {
                echo "FOUND '$search' in: $path\n";
                // Show lines containing it
                $lines = explode("\n", $content);
                foreach ($lines as $ln => $line) {
                    if (strpos($line, $search) !== false) {
                        echo "  Line " . ($ln+1) . ": " . trim($line) . "\n";
                    }
                }
            }
        }
    }
}

search_in_dir($dir, $search);
echo "\nSearching for 'kyc_verifications'...\n";
search_in_dir($dir, 'kyc_verifications');
echo "\nSearching for 'kyc_submissions'...\n";
search_in_dir($dir, 'kyc_submissions');
echo "\nSearching for 'user_kyc'...\n";
search_in_dir($dir, 'user_kyc');
