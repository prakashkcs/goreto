<?php
header('Content-Type: text/plain');
header('Access-Control-Allow-Origin: *');

// Try to find the error log
$logFiles = [
    ini_get('error_log'),
    '/var/log/apache2/error.log',
    '/var/log/httpd/error_log',
    '/var/log/nginx/error.log',
    'error_log',
    '../error_log',
    '../../error_log',
    '/home/sharexhu/domains/coinzop.com/public_html/error_log',
    '/home/sharexhu/domains/coinzop.com/public_html/ekloadmin/error_log',
    '/home/sharexhu/domains/coinzop.com/public_html/ekloadmin/api/v1/error_log'
];

echo "Checking PHP Error Logs:\n\n";

foreach ($logFiles as $file) {
    if ($file && file_exists($file) && is_readable($file)) {
        echo "Found log at: $file\n";
        echo "Last 50 lines:\n";
        $lines = array_slice(file($file), -50);
        echo implode("", $lines);
        echo "\n----------------------------------------\n\n";
    }
}
echo "Done checking error logs.\n";
