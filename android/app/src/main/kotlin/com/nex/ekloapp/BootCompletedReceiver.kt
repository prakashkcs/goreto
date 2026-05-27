package com.nex.ekloapp

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.google.firebase.FirebaseApp
import com.google.firebase.messaging.FirebaseMessaging

/**
 * Boot-completed receiver — wakes the app out of Android's "stopped" state
 * after device restart so the first incoming-call FCM is actually delivered.
 *
 * Without this, Android holds FCM messages for stopped apps until the user
 * manually launches the app, which is why callers were getting "no answer"
 * after the receiver's phone rebooted.
 *
 * Implementation is intentionally minimal: we initialize Firebase and touch
 * the FCM token. That's enough to move the app from STOPPED to a regular
 * background state on most Android versions; FirebaseMessagingService then
 * gets woken normally by the next incoming push.
 *
 * On aggressive OEMs (Realme/Oppo/Xiaomi), Auto-Start permission must also
 * be enabled by the user — no Android API can bypass that.
 */
class BootCompletedReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        if (action != Intent.ACTION_BOOT_COMPLETED &&
            action != Intent.ACTION_LOCKED_BOOT_COMPLETED &&
            action != Intent.ACTION_MY_PACKAGE_REPLACED &&
            action != "android.intent.action.QUICKBOOT_POWERON" &&
            action != "com.htc.intent.action.QUICKBOOT_POWERON"
        ) return

        try {
            FirebaseApp.initializeApp(context)
            FirebaseMessaging.getInstance().token
            CallFirebaseMessagingService.createAllChannels(context)
            // Re-register the Telecom phone account so calls can route through
            // the system UI before the user has launched the app post-reboot.
            EkloConnectionService.register(context)
        } catch (_: Exception) {}
    }
}
