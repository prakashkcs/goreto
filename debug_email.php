<?php
$cfg = include __DIR__ . '/config/config.php';
echo "Config type: " . gettype($cfg) . "\n";
echo "Is array: " . (is_array($cfg) ? 'yes' : 'no') . "\n";
echo "Has smtp: " . (isset($cfg['smtp']) ? 'yes' : 'no') . "\n";
if (isset($cfg['smtp'])) {
    echo "SMTP keys: " . implode(', ', array_keys($cfg['smtp'])) . "\n";
    echo "SMTP password set: " . (isset($cfg['smtp']['password']) ? 'yes' : 'no') . "\n";
    echo "SMTP password empty: " . (empty($cfg['smtp']['password']) ? 'yes' : 'no') . "\n";
    echo "SMTP password value: '" . ($cfg['smtp']['password'] ?? 'N/A') . "'\n";
}
require_once __DIR__ . '/email_helper.php';
$email = new EmailHelper();
$ref = new ReflectionClass($email);
$host = $ref->getProperty('smtpHost');
$host->setAccessible(true);
echo "smtpHost: " . $host->getValue($email) . "\n";
$pass = $ref->getProperty('smtpPass');
$pass->setAccessible(true);
echo "smtpPass: '" . $pass->getValue($email) . "'\n";
