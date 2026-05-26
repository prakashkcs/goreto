<?php
$content = file_get_contents('income_review.php');
$content = str_replace("require_once __DIR__ . '/api/v1/notification_helper.php';", "require_once __DIR__ . '/api/v1/notification_helper.php';", $content); // It actually is correct as api/v1 since notification_helper was uploaded there!
file_put_contents('income_review.php', $content);
echo "Replaced";
?>
