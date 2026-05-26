<?php
header('Content-Type: text/plain');
echo "READING user_actions.php ON SERVER (lines around disconnect_proposal):\n";
$lines = file(__DIR__ . '/user_actions.php');
if ($lines) {
    $found = false;
    foreach ($lines as $i => $line) {
        if (strpos($line, 'disconnect_proposal') !== false) {
            $found = true;
            for ($j = max(0, $i - 10); $j < min(count($lines), $i + 40); $j++) {
                echo ($j + 1) . ": " . $lines[$j];
            }
            break;
        }
    }
    if (!$found) echo "Action 'disconnect_proposal' NOT FOUND in user_actions.php";
} else {
    echo "FILE NOT FOUND OR EMPTY";
}
?>
