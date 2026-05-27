package com.nex.ekloapp

import android.app.Notification
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat

/**
 * Short-lived foreground service started by [CallFirebaseMessagingService] when
 * an incoming-call FCM arrives. It exists purely to:
 *
 *   1. Promote the FCM-handling process from cached-background to foreground,
 *      so the OS doesn't kill us mid-handle on aggressive OEMs.
 *   2. Hold a partial wake lock for ~65 s so the device stays awake long
 *      enough for [IncomingCallActivity] to actually render on a sleeping
 *      screen, ring out, and for the user to react.
 *
 * On Android 14+ this service declares the `phoneCall` foreground type, which
 * is the only category that's allowed to start from a background broadcast
 * (FCM receive) without ForegroundServiceStartNotAllowedException.
 *
 * Self-stops after [TIMEOUT_MS] (matching the notification's setTimeoutAfter
 * value) so we never linger past the call's natural lifetime.
 */
class IncomingCallForegroundService : Service() {

    companion object {
        private const val TIMEOUT_MS = 65_000L
        private const val WAKE_LOCK_TAG = "Goreto:IncomingCall"
        const val EXTRA_NOTIFICATION = "notification"
    }

    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // The notification was already built by CallFirebaseMessagingService;
        // we re-use its content by re-posting via NotificationManager rather
        // than rebuilding here. The foreground spec just needs *some* ongoing
        // notification — we hand it a minimal placeholder bound to the same
        // call channel so Android shows nothing extra.
        val placeholder: Notification = NotificationCompat.Builder(this, CallFirebaseMessagingService.CALL_CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_goreto)
            .setContentTitle("Incoming call")
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                CallFirebaseMessagingService.CALL_NOTIFICATION_ID,
                placeholder,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_PHONE_CALL,
            )
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                CallFirebaseMessagingService.CALL_NOTIFICATION_ID,
                placeholder,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_PHONE_CALL,
            )
        } else {
            startForeground(CallFirebaseMessagingService.CALL_NOTIFICATION_ID, placeholder)
        }

        // Partial wake lock keeps the CPU running while the user reacts to the
        // ring — without it, doze can sleep the device mid-ringtone on some
        // OEMs and the user never hears it.
        try {
            val pm = getSystemService(POWER_SERVICE) as PowerManager
            wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, WAKE_LOCK_TAG).apply {
                setReferenceCounted(false)
                acquire(TIMEOUT_MS)
            }
        } catch (_: Exception) {}

        // Auto-stop after the timeout window so we never overstay our welcome.
        android.os.Handler(mainLooper).postDelayed({
            stopSelf()
        }, TIMEOUT_MS)

        return START_NOT_STICKY
    }

    override fun onDestroy() {
        try {
            wakeLock?.takeIf { it.isHeld }?.release()
        } catch (_: Exception) {}
        wakeLock = null
        super.onDestroy()
    }
}
