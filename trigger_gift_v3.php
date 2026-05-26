<?php
header('Content-Type: text/plain');

$url = "https://coinzop.com/ekloadmin/api/v1/gifts.php?action=send";
$token = "55f5a36057fbdbb8e5b807a68f79bd2291234c909779aa135b9c1c8ad3a015fa";

$payload = [
    'gift_id' => 1,
    'to_user_id' => 10,
    'context_type' => 'test',
    'context_id' => 'test_id',
    'message' => 'Real test message'
];

$ch = curl_init($url);
curl_setopt($ch, CURLOPT_POST, true);
curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($payload));
curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
curl_setopt($ch, CURLOPT_HTTPHEADER, [
    'Authorization: Bearer ' . $token,
    'Content-Type: application/json'
]);

echo "Sending request to $url...\n";
$response = curl_exec($ch);
$status = curl_getinfo($ch, CURLINFO_HTTP_CODE);
curl_close($ch);

echo "HTTP STATUS: $status\n";
echo "RESPONSE: $response\n";
