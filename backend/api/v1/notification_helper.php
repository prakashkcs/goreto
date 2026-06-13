<?php
// notification_helper.php
// Helper functions for sending in-app notifications and FCM push notifications.

require_once __DIR__ . '/fcm_v1.php'; // Ensure fcm_v1 is available

/**
 * Sends an in-app notification and an FCM push notification.
 *
 * @param PDO $pdo The PDO database connection
 * @param int $userId The ID of the user receiving the notification
 * @param int $senderId The ID of the user sending the notification (0 for system)
 * @param string $type The type of notification (e.g., 'follow', 'system', 'deposit_accept', 'kyc_reject')
 * @param string $title The notification title
 * @param string $body The notification message body
 * @param int|null $referenceId An optional reference ID (e.g., post ID, gift ID)
 * @param bool $forceDataOnly Deprecated — kept for signature compatibility, ignored for non-call types
 * @return bool True on success, false on failure
 */
function send_app_notification($pdo, $userId, $senderId, $type, $title, $body, $referenceId = null, $forceDataOnly = true, $extraData = [])
{
    if (!$userId)
        return false;

    // Brand admin/system notifications as "Goreto"
    if ((int) $senderId === 0 && ($type === 'system' || $type === 'admin')) {
        $title = str_ireplace('Admin', 'Goreto', $title);
        if (stripos($title, 'Goreto') === false) {
            $title = 'Goreto: ' . $title;
        }
    }

    // 1. Insert into notifications table (skip chat — push-only, no in-app record)
    if ($type !== 'chat') {
        try {
            // For nearby: replace any existing notification from same sender
            // so the user only sees the latest one, not a growing stack.
            if ($type === 'nearby' && $senderId > 0) {
                $pdo->prepare("DELETE FROM notifications WHERE user_id=? AND sender_id=? AND type='nearby'")
                    ->execute([$userId, $senderId]);
            }
            $stmt = $pdo->prepare("INSERT INTO notifications (user_id, sender_id, type, title, message, reference_id) VALUES (?, ?, ?, ?, ?, ?)");
            $stmt->execute([$userId, $senderId, $type, $title, $body, $referenceId]);
        } catch (PDOException $e) {
            error_log("Failed to insert notification into DB: " . $e->getMessage());
            // Continue to push even if DB insert fails
        }
    }

    // 2. Fetch the user's FCM token
    try {
        $stmt = $pdo->prepare("SELECT fcm_token FROM users WHERE id = ?");
        $stmt->execute([$userId]);
        $user = $stmt->fetch(PDO::FETCH_ASSOC);

        if ($user && !empty($user['fcm_token'])) {
            $fcmToken = $user['fcm_token'];

            // 3. Send FCM Push Notification
            $serviceAccountPath = '/var/www/private/service_account.json';
            if (file_exists($serviceAccountPath)) {
                $jsonAccount = json_decode(file_get_contents($serviceAccountPath), true);
                $projectId = $jsonAccount['project_id'] ?? '';

                if (!empty($projectId)) {
                    $fcmClient = new PushNotificationFCM($serviceAccountPath);
                    $fcmPayload = [
                        'action' => 'notification',
                        'type' => $type,
                        'title' => $title,
                        'body' => $body,
                        'reference_id' => (string) $referenceId,
                        // For data-only call/nearby messages, expose the human-
                        // facing strings under custom keys so OneSignal's FCM
                        // receiver doesn't auto-render its own heads-up on top
                        // of our full-screen NearbyAlertActivity. Our native
                        // handleRegularMessage reads notif_title/notif_body as
                        // a fallback when title/body are absent.
                        'notif_title' => $title,
                        'notif_body' => $body,
                        'sender_id' => (string) $senderId
                    ];
                    // Merge any extra data fields (e.g. distance for nearby)
                    $fcmPayload = array_merge($fcmPayload, $extraData);

                    // Fetch sender name/avatar for tray enrichment if senderId > 0
                    if ($senderId > 0) {
                        try {
                            $sSt = $pdo->prepare("SELECT name, username, profile_pic FROM users WHERE id = ?");
                            $sSt->execute([$senderId]);
                            $sDat = $sSt->fetch(PDO::FETCH_ASSOC);
                            if ($sDat) {
                                $fcmPayload['sender_name'] = $sDat['name'] ?: $sDat['username'] ?: 'User';
                                if (!empty($sDat['profile_pic'])) {
                                    $pPic = $sDat['profile_pic'];
                                    // Normalize URL if not absolute
                                    if (!preg_match('~^https?://~i', $pPic)) {
                                        $fcmPayload['sender_avatar'] = 'https://goreto.org/ekloadmin/' . ltrim($pPic, '/');
                                    } else {
                                        $fcmPayload['sender_avatar'] = $pPic;
                                    }
                                }
                            }
                        } catch (Throwable $e) {
                        }
                    }

                    // Calls must stay data-only (handled by CallFirebaseMessagingService natively).
                    // All other types use notification payload so FCM shows them even when app is killed.
                    $isCall = ($type === 'incoming_call');
                    $isNearby = ($type === 'nearby');
                    $useDataOnly = $isCall || $isNearby;
                    // For data-only types, OneSignal's broadcast receiver
                    // inspects the data and shows its own notification if
                    // it sees title/body. Strip them; the native handler
                    // reads notif_title/notif_body instead.
                    if ($useDataOnly) {
                        unset($fcmPayload['title']);
                        unset($fcmPayload['body']);
                    }


                    $fcmNotification = $useDataOnly ? null : [
                        'title' => $title,
                        'body' => $body
                    ];

                    try {
                        $fcmClient->sendDataMessage($fcmToken, $projectId, $fcmPayload, $fcmNotification, $useDataOnly);
                    } catch (Throwable $e) {
                        error_log("FCM Push failed: " . $e->getMessage());
                    }
                }
            } else {
                error_log("FCM service_account.json not found for notifications.");
            }
        }
    } catch (PDOException $e) {
        error_log("Failed to fetch FCM token for notification: " . $e->getMessage());
    }

    return true;
}
?>