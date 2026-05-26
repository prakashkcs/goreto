<?php
// fcm_v1.php
// A completely standalone, dependency-free PHP class to send FCM HTTP v1 Push Notifications
// using a Firebase Service Account JSON file.

class PushNotificationFCM
{
    private $serviceAccountPath;

    public function __construct($serviceAccountPath)
    {
        $this->serviceAccountPath = $serviceAccountPath;
    }

    private function base64UrlEncode($text)
    {
        return str_replace(['+', '/', '='], ['-', '_', ''], base64_encode($text));
    }

    private function getAccessToken()
    {
        if (!file_exists($this->serviceAccountPath)) {
            error_log("FCM Error: Service account JSON file not found at " . $this->serviceAccountPath);
            return false;
        }

        $jsonKey = json_decode(file_get_contents($this->serviceAccountPath), true);
        if (!$jsonKey) {
            error_log("FCM Error: Invalid Service account JSON");
            return false;
        }

        $clientEmail = $jsonKey['client_email'];
        $privateKey = $jsonKey['private_key'];

        $header = json_encode([
            'alg' => 'RS256',
            'typ' => 'JWT'
        ]);

        $now = time();
        $payload = json_encode([
            'iss' => $clientEmail,
            'scope' => 'https://www.googleapis.com/auth/firebase.messaging',
            'aud' => 'https://oauth2.googleapis.com/token',
            'exp' => $now + 3600,
            'iat' => $now
        ]);

        $base64UrlHeader = $this->base64UrlEncode($header);
        $base64UrlPayload = $this->base64UrlEncode($payload);

        $signature = '';
        openssl_sign($base64UrlHeader . "." . $base64UrlPayload, $signature, $privateKey, 'sha256WithRSAEncryption');
        $base64UrlSignature = $this->base64UrlEncode($signature);

        $jwt = $base64UrlHeader . "." . $base64UrlPayload . "." . $base64UrlSignature;

        $postData = http_build_query([
            'grant_type' => 'urn:ietf:params:oauth:grant-type:jwt-bearer',
            'assertion' => $jwt
        ]);

        $ch = curl_init('https://oauth2.googleapis.com/token');
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_POST, true);
        curl_setopt($ch, CURLOPT_POSTFIELDS, $postData);
        curl_setopt($ch, CURLOPT_HTTPHEADER, ['Content-Type: application/x-www-form-urlencoded']);

        $response = curl_exec($ch);
        curl_close($ch);

        $data = json_decode($response, true);

        if (isset($data['access_token'])) {
            return $data['access_token'];
        }

        error_log("FCM Error: Failed to get access token - " . $response);
        return false;
    }

    public function sendCallNotification($fcmToken, $projectId, $callerName, $callerId, $callUuid, $callId, $type = 'video')
    {
        $data = [
            'action' => 'incoming_call',
            'type' => $type,
            'call_uuid' => $callUuid,
            'call_id' => $callId,
            'caller_id' => $callerId,
            'caller_name' => $callerName,
            'title' => 'Incoming ' . ucfirst($type) . ' Call',
            'body' => $callerName . ' is calling you...'
        ];
        // For calls, we want DATA-ONLY to ensure onBackgroundMessage is triggered reliably for custom tray
        return $this->sendDataMessage($fcmToken, $projectId, $data, null, true);
    }

    public function sendDataMessage($fcmToken, $projectId, $dataPayload, $notificationPayload = null, $forceDataOnly = true)
    {
        $accessToken = $this->getAccessToken();
        if (!$accessToken) {
            return false;
        }

        $url = 'https://fcm.googleapis.com/v1/projects/' . $projectId . '/messages:send';

        $message = [
            'message' => [
                'token' => $fcmToken,
                'data' => $dataPayload,
                'android' => [
                    'priority' => 'high'
                ],
                'apns' => [
                    'headers' => [
                        'apns-priority' => '10'
                    ]
                ]
            ]
        ];

        // Fallback: If notificationPayload is missing but data contains title/body, auto-create it (UNLESS forceDataOnly)
        if (!$forceDataOnly && !$notificationPayload && isset($dataPayload['title']) && isset($dataPayload['body'])) {
            $notificationPayload = [
                'title' => (string)$dataPayload['title'],
                'body' => (string)$dataPayload['body']
            ];
        }

        if ($notificationPayload && !$forceDataOnly) {
            $message['message']['notification'] = $notificationPayload;
            $message['message']['android']['notification'] = [
                'sound' => 'default',
                'click_action' => 'FLUTTER_NOTIFICATION_CLICK',
                'channel_id' => 'high_importance_channel_v3',
                'notification_priority' => 'PRIORITY_MAX',
                'default_vibrate_timings' => true,
                'default_sound' => true
            ];
        }

        // Ensure all data values are strictly STRINGS (FCM requirement for data payloads)
        foreach ($message['message']['data'] as $key => $val) {
            $message['message']['data'][$key] = (string)$val;
        }

        $headers = [
            'Authorization: Bearer ' . $accessToken,
            'Content-Type: application/json'
        ];

        $ch = curl_init();
        curl_setopt($ch, CURLOPT_URL, $url);
        curl_setopt($ch, CURLOPT_POST, true);
        curl_setopt($ch, CURLOPT_HTTPHEADER, $headers);
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
        curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($message));

        $result = curl_exec($ch);
        $info = curl_getinfo($ch);
        curl_close($ch);

        // Logging for debug
        $logFile = __DIR__ . '/uploads/fcm_v1_debug.log';
        if (!file_exists(__DIR__ . '/uploads')) {
            mkdir(__DIR__ . '/uploads', 0777, true);
        }
        $logMsg = date('[Y-m-d H:i:s] ') . "FCM HTTP Status: " . ($info['http_code'] ?? 'N/A') . "\n";
        $logMsg .= "Payload: " . json_encode($message) . "\n";
        $logMsg .= "Response: " . $result . "\n\n";
        file_put_contents($logFile, $logMsg, FILE_APPEND);

        return $result;
    }

    public function sendChatMessage($fcmToken, $projectId, $senderName, $messageText, $senderId)
    {
        $data = [
            'action' => 'chat',
            'type' => 'chat',
            'sender_id' => $senderId,
            'title' => 'New message from ' . $senderName,
            'body' => $messageText
        ];
        return $this->sendDataMessage($fcmToken, $projectId, $data);
    }

    public function sendFollowNotification($fcmToken, $projectId, $followerName, $followerId)
    {
        $data = [
            'action' => 'follow',
            'type' => 'follow',
            'sender_id' => $followerId,
            'title' => 'New Follower',
            'body' => $followerName . ' started following you!'
        ];
        return $this->sendDataMessage($fcmToken, $projectId, $data);
    }

    public function sendProposalNotification($fcmToken, $projectId, $proposerName, $proposerId)
    {
        $data = [
            'action' => 'proposal',
            'type' => 'proposal',
            'sender_id' => $proposerId,
            'title' => 'New Proposal',
            'body' => $proposerName . ' sent you a proposal ❤️'
        ];
        return $this->sendDataMessage($fcmToken, $projectId, $data);
    }

    public function sendCallPickupNotification($fcmToken, $projectId, $receiverName)
    {
        $data = [
            'action' => 'notification',
            'type' => 'call_pickup',
            'title' => 'Call Answered',
            'body' => $receiverName . ' picked up the call!'
        ];
        return $this->sendDataMessage($fcmToken, $projectId, $data);
    }
}
?>
