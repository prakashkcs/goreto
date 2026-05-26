<?php
header('Content-Type: application/json');
echo json_encode([
    'php_version' => PHP_VERSION,
    'str_contains_exists' => function_exists('str_contains'),
    'str_starts_with_exists' => function_exists('str_starts_with'),
]);
