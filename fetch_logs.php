<?php
header('Content-Type: text/plain');
ini_set('display_errors', '1');
error_reporting(E_ALL);

$logFile = '/usr/local/lsws/logs/error.log'; // common LiteSpeed log
if (file_exists($logFile)) {
    echo "Tail of $logFile:\n\n";
    echo shell_exec('tail -n 50 ' . escapeshellarg($logFile));
}
else {
    echo "Log file $logFile not found. Try generic error_log:\n\n";
    $genericLog = ini_get('error_log');
    if ($genericLog && file_exists($genericLog)) {
        echo shell_exec('tail -n 50 ' . escapeshellarg($genericLog));
    }
    else {
        echo "No configured error_log found.";
    }
}
?>
