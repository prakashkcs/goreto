<?php
$ch = curl_init();
curl_setopt($ch, CURLOPT_URL, "https://goreto.b-cdn.net/test_bunny.txt");
curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
$response = curl_exec($ch);
file_put_contents('cdn_test_body.txt', $response);
echo "Body saved to cdn_test_body.txt\n";
curl_close($ch);
?>
