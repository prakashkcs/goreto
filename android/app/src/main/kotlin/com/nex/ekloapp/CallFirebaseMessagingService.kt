package com.nex.ekloapp

import android.app.ActivityManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.media.AudioAttributes
import android.net.Uri
import android.os.Build
import androidx.core.app.NotificationCompat
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import java.net.URL
import java.util.concurrent.Executors

/**
 * Native FCM service — intercepts ALL incoming FCM messages so notifications
 * appear even when the app is fully killed (Flutter's background isolate is
 * not reliable on OEM devices).
 *
 * Routing:
 *   incoming_call  → full-screen IncomingCallActivity + ringtone
 *   nearby         → high-priority tray notification (nearby channel)
 *   anything else  → high-priority tray notification (general channel)
 *
 * When the app is in the foreground Flutter's onMessage handler shows the
 * in-app banner, so we skip the tray for non-call types to avoid duplicates.
 */
class CallFirebaseMessagingService : FirebaseMessagingService() {

    companion object {
        const val CALL_CHANNEL_ID    = "call_v1"
        const val NEARBY_CHANNEL_ID  = "nearby_v1"
        const val GENERAL_CHANNEL_ID = "general_v1"
        const val CALL_NOTIFICATION_ID    = 999999
        const val NEARBY_NOTIFICATION_ID  = 999998
        const val GENERAL_NOTIFICATION_ID = 999997
        // Calls older than this are dropped silently — the caller has long since
        // hung up and ringing the receiver now would be misleading.
        const val STALE_CALL_THRESHOLD_MS = 60_000L

        /** Call this from Application.onCreate() so channels exist before any FCM notification arrives. */
        fun createAllChannels(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

            // Call channel
            if (nm.getNotificationChannel(CALL_CHANNEL_ID) == null) {
                val ringtoneUri = Uri.parse("android.resource://${context.packageName}/raw/ringtone")
                val audioAttr = AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
                NotificationChannel(CALL_CHANNEL_ID, "Incoming Calls", NotificationManager.IMPORTANCE_HIGH).apply {
                    description = "Full-screen incoming call alerts"
                    enableVibration(true)
                    vibrationPattern = longArrayOf(0, 500, 200, 500, 200, 500)
                    setSound(ringtoneUri, audioAttr)
                    lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                }.also { nm.createNotificationChannel(it) }
            }

            // General notifications channel
            if (nm.getNotificationChannel(GENERAL_CHANNEL_ID) == null) {
                val audioAttr = AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
                NotificationChannel(GENERAL_CHANNEL_ID, "Notifications", NotificationManager.IMPORTANCE_HIGH).apply {
                    description = "General Goreto notifications"
                    enableVibration(true)
                    vibrationPattern = longArrayOf(0, 250, 100, 250)
                    setSound(Uri.parse("android.resource://${context.packageName}/raw/notify"), audioAttr)
                    lockscreenVisibility = Notification.VISIBILITY_PRIVATE
                }.also { nm.createNotificationChannel(it) }
            }

            // Nearby alerts channel
            if (nm.getNotificationChannel(NEARBY_CHANNEL_ID) == null) {
                val audioAttr = AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
                NotificationChannel(NEARBY_CHANNEL_ID, "Nearby Alerts", NotificationManager.IMPORTANCE_HIGH).apply {
                    description = "Alerts when someone is nearby"
                    enableVibration(true)
                    vibrationPattern = longArrayOf(0, 250, 100, 250)
                    setSound(Uri.parse("android.resource://${context.packageName}/raw/nearby"), audioAttr)
                    lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                }.also { nm.createNotificationChannel(it) }
            }
        }
    }

    private val executor = Executors.newSingleThreadExecutor()

    override fun onMessageReceived(remoteMessage: RemoteMessage) {
        val data   = remoteMessage.data
        val type   = data["type"]
        val action = data["action"]

        val isCall = (type == "incoming_call" || action == "incoming_call")
        if (isCall) {
            // Drop calls that arrived too late to be relevant. OEM battery
            // restrictions (especially Realme/Oppo/Xiaomi) can delay data-only
            // FCM delivery by minutes — showing a "ringing" UI for a call the
            // caller hung up on long ago is worse than no UI at all.
            val age = System.currentTimeMillis() - remoteMessage.sentTime
            if (remoteMessage.sentTime > 0 && age > STALE_CALL_THRESHOLD_MS) {
                return
            }
            handleCallMessage(data)
            return
        }

        // Dismiss the incoming-call notification and signal IncomingCallActivity to finish.
        val isCancelled = (type == "call_cancelled" || action == "call_cancelled")
        if (isCancelled) {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.cancel(CALL_NOTIFICATION_ID)
            // Broadcast so IncomingCallActivity can finish itself
            val broadcast = Intent("com.nex.ekloapp.CALL_CANCELLED").apply {
                putExtra("call_id", data["call_id"] ?: "")
                setPackage(packageName)
            }
            sendBroadcast(broadcast)
            return
        }

        // Non-call: only show tray when app is not in foreground.
        // Flutter's onMessage already handles the in-app banner.
        if (!isAppInForeground()) {
            handleRegularMessage(data, type ?: "notification")
        }
    }

    // ──────────────────────────────────────────────────────────────
    // Foreground check
    // ──────────────────────────────────────────────────────────────

    private fun isAppInForeground(): Boolean {
        val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val processes = am.runningAppProcesses ?: return false
        return processes.any {
            it.importance == ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND &&
                    it.processName == packageName
        }
    }

    // ──────────────────────────────────────────────────────────────
    // Incoming call
    // ──────────────────────────────────────────────────────────────

    private fun handleCallMessage(data: Map<String, String>) {
        ensureCallChannel()

        val callerName  = data["caller_full_name"] ?: data["caller_name"] ?: "Unknown"
        val callerAvatar = data["caller_avatar"] ?: ""
        val callType    = data["type"]      ?: "video"
        val callId      = data["call_id"]   ?: "0"
        val callUuid    = data["call_uuid"] ?: ""
        val callerId    = data["caller_id"] ?: ""
        val isRandom    = data["is_random"] ?: "false"

        val callIntent = IncomingCallActivity.createIntent(
            this,
            mapOf(
                "caller_name"   to callerName,
                "caller_avatar" to callerAvatar,
                "type"          to callType,
                "call_id"       to callId,
                "call_uuid"     to callUuid,
                "caller_id"     to callerId,
                "is_random"     to isRandom
            )
        )

        val flags = pendingIntentFlags()
        val fullScreenPi  = PendingIntent.getActivity(this, CALL_NOTIFICATION_ID,     callIntent, flags)
        val contentPi     = PendingIntent.getActivity(this, CALL_NOTIFICATION_ID + 1, callIntent, flags)

        val declineIntent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            putExtra("action",  "decline_call")
            putExtra("call_id", callId)
        } ?: Intent(this, MainActivity::class.java).apply {
            putExtra("action",  "decline_call")
            putExtra("call_id", callId)
        }
        val declinePi = PendingIntent.getActivity(this, CALL_NOTIFICATION_ID + 2, declineIntent, flags)

        val builder = NotificationCompat.Builder(this, CALL_CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_goreto)
            .setContentTitle(callerName)
            .setContentText(if (callType == "audio") "Incoming Audio Call" else "Incoming Video Call")
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setAutoCancel(false)
            .setSound(Uri.parse("android.resource://$packageName/raw/ringtone"))
            .setVibrate(longArrayOf(0, 500, 200, 500, 200, 500))
            .setFullScreenIntent(fullScreenPi, true)
            .setContentIntent(contentPi)
            .addAction(R.drawable.ic_call_accept, "Accept",  fullScreenPi)
            .addAction(R.drawable.ic_call_end,    "Decline", declinePi)
            .setTimeoutAfter(60_000)

        // Show immediately so the notification never misses its window.
        // OEM battery managers can kill the service process seconds after
        // onMessageReceived() returns — waiting for a network avatar download
        // risks a silent miss.
        showNotification(CALL_NOTIFICATION_ID, builder.build())

        // Update large icon with the caller's avatar in the background (best-effort).
        if (callerAvatar.isNotEmpty()) {
            executor.execute {
                try {
                    val bmp = BitmapFactory.decodeStream(URL(callerAvatar).openStream())
                    builder.setLargeIcon(bmp)
                    showNotification(CALL_NOTIFICATION_ID, builder.build())
                } catch (_: Exception) {}
            }
        }
    }

    // ──────────────────────────────────────────────────────────────
    // Regular notifications (nearby / chat / follow / etc.)
    // ──────────────────────────────────────────────────────────────

    private fun handleRegularMessage(data: Map<String, String>, type: String) {
        val title = data["title"] ?: when (type) {
            "nearby"           -> "Someone is nearby!"
            "chat", "message"  -> "New Message"
            else               -> "Goreto"
        }
        val body         = data["body"]          ?: ""
        val senderAvatar = data["sender_avatar"] ?: ""

        val isNearby  = (type == "nearby")
        val channelId = if (isNearby) NEARBY_CHANNEL_ID  else GENERAL_CHANNEL_ID
        val soundName = if (isNearby) "nearby"           else "notify"
        val notifId   = if (isNearby) NEARBY_NOTIFICATION_ID else GENERAL_NOTIFICATION_ID

        ensureRegularChannels()

        // Nearby: full-screen overlay (same mechanism as incoming calls)
        if (isNearby) {
            val nearbyIntent = NearbyAlertActivity.createIntent(this, data)
            val nearbyPi = PendingIntent.getActivity(this, notifId, nearbyIntent, pendingIntentFlags())

            val builder = NotificationCompat.Builder(this, channelId)
                .setSmallIcon(R.drawable.ic_stat_goreto)
                .setContentTitle(title)
                .setContentText(body)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setAutoCancel(true)
                .setFullScreenIntent(nearbyPi, true)
                .setContentIntent(nearbyPi)
                .setVibrate(longArrayOf(0, 250, 100, 250))

            // Show notification immediately (activates full-screen intent)
            showNotification(notifId, builder.build())

            // Also launch the activity directly for devices where FSI may not fire
            try { startActivity(nearbyIntent) } catch (_: Exception) {}

            // Update large icon in background (best-effort)
            if (senderAvatar.isNotEmpty()) {
                executor.execute {
                    try {
                        val bmp = BitmapFactory.decodeStream(URL(senderAvatar).openStream())
                        builder.setLargeIcon(bmp)
                        showNotification(notifId, builder.build())
                    } catch (_: Exception) {}
                }
            }
            return
        }

        // Non-nearby: standard tray notification
        val tapIntent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            this.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("notification_type", type)
        } ?: Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
        }

        val tapPi = PendingIntent.getActivity(this, notifId, tapIntent, pendingIntentFlags())

        val builder = NotificationCompat.Builder(this, channelId)
            .setSmallIcon(R.drawable.ic_stat_goreto)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setAutoCancel(true)
            .setSound(Uri.parse("android.resource://$packageName/raw/$soundName"))
            .setVibrate(longArrayOf(0, 250, 100, 250))
            .setContentIntent(tapPi)

        if (senderAvatar.isNotEmpty()) {
            executor.execute {
                try {
                    val bmp = BitmapFactory.decodeStream(URL(senderAvatar).openStream())
                    builder.setLargeIcon(bmp)
                } catch (_: Exception) {}
                showNotification(notifId, builder.build())
            }
        } else {
            showNotification(notifId, builder.build())
        }
    }

    // ──────────────────────────────────────────────────────────────
    // Helpers
    // ──────────────────────────────────────────────────────────────

    private fun pendingIntentFlags() =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S)
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        else
            PendingIntent.FLAG_UPDATE_CURRENT

    private fun showNotification(id: Int, notification: Notification) {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(id, notification)
    }

    private fun ensureCallChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (nm.getNotificationChannel(CALL_CHANNEL_ID) != null) return

        val ringtoneUri = Uri.parse("android.resource://$packageName/raw/ringtone")
        val audioAttr = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()

        NotificationChannel(CALL_CHANNEL_ID, "Incoming Calls", NotificationManager.IMPORTANCE_HIGH).apply {
            description = "Full-screen incoming call alerts"
            enableVibration(true)
            vibrationPattern = longArrayOf(0, 500, 200, 500, 200, 500)
            setSound(ringtoneUri, audioAttr)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        }.also { nm.createNotificationChannel(it) }
    }

    private fun ensureRegularChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        val audioAttr = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_NOTIFICATION)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()

        if (nm.getNotificationChannel(GENERAL_CHANNEL_ID) == null) {
            NotificationChannel(GENERAL_CHANNEL_ID, "Notifications", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "General Goreto notifications"
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 250, 100, 250)
                setSound(Uri.parse("android.resource://$packageName/raw/notify"), audioAttr)
                lockscreenVisibility = Notification.VISIBILITY_PRIVATE
            }.also { nm.createNotificationChannel(it) }
        }

        if (nm.getNotificationChannel(NEARBY_CHANNEL_ID) == null) {
            NotificationChannel(NEARBY_CHANNEL_ID, "Nearby Alerts", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Alerts when someone is nearby"
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 250, 100, 250)
                setSound(Uri.parse("android.resource://$packageName/raw/nearby"), audioAttr)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }.also { nm.createNotificationChannel(it) }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        executor.shutdown()
    }
}
