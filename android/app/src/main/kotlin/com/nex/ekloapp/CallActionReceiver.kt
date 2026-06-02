package com.nex.ekloapp

import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.telecom.DisconnectCause
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import java.net.URL
import javax.net.ssl.HttpsURLConnection

/**
 * BroadcastReceiver for notification action buttons (Accept / Decline).
 *
 * Using a BroadcastReceiver instead of startActivity means:
 *   • Decline fires instantly without opening the app
 *   • The user stays on whatever screen they were on
 *   • Accept opens the app only for the active-answer path
 */
class CallActionReceiver : BroadcastReceiver() {

    companion object {
        const val ACTION_DECLINE = "com.nex.ekloapp.DECLINE_CALL"
        const val ACTION_ACCEPT  = "com.nex.ekloapp.ACCEPT_CALL"
        const val EXTRA_CALL_ID   = "call_id"
        const val EXTRA_CALL_UUID = "call_uuid"
        const val EXTRA_CALLER_ID = "caller_id"
        const val EXTRA_CALLER_NAME = "caller_name"
        const val EXTRA_CALLER_AVATAR = "caller_avatar"
        const val EXTRA_CALL_TYPE = "call_type"
        const val EXTRA_IS_RANDOM = "is_random"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val callId   = intent.getStringExtra(EXTRA_CALL_ID) ?: return
        val action   = intent.action ?: return

        // Cancel the notification immediately so the user sees visual feedback
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.cancel(CallFirebaseMessagingService.CALL_NOTIFICATION_ID)

        // Tear down the Telecom connection
        try {
            EkloConnectionService.activeIncoming?.let { conn ->
                conn.setDisconnected(DisconnectCause(DisconnectCause.REJECTED))
                conn.destroy()
            }
            EkloConnectionService.activeIncoming = null
        } catch (_: Exception) {}

        // Broadcast CALL_CANCELLED so IncomingCallActivity dismisses itself
        context.sendBroadcast(Intent("com.nex.ekloapp.CALL_CANCELLED").apply {
            putExtra("call_id", callId)
            setPackage(context.packageName)
        })

        if (action == ACTION_DECLINE) {
            // Fire backend decline silently in the background — no UI opened
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val token = prefs.getString("flutter.app_token", null)
                ?: prefs.getString("flutter.auth_token", null)
            val baseUrl = prefs.getString("flutter.api_base_url", "https://goreto.org/ekloadmin/api/v1/")
                ?: "https://goreto.org/ekloadmin/api/v1/"

            if (!token.isNullOrEmpty()) {
                CoroutineScope(Dispatchers.IO).launch {
                    try {
                        val url = URL("${baseUrl.trimEnd('/')}/signaling.php?action=decline_call&call_id=$callId")
                        val conn = url.openConnection() as HttpsURLConnection
                        conn.requestMethod = "POST"
                        conn.setRequestProperty("Authorization", "Bearer $token")
                        conn.connectTimeout = 5_000
                        conn.readTimeout = 5_000
                        conn.connect()
                        conn.disconnect()
                    } catch (_: Exception) {}
                }
            }
        } else if (action == ACTION_ACCEPT) {
            // For Accept we still need to open the app (starts the WebRTC call)
            val mainIntent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
                putExtra("action", "accept_call")
                putExtra(EXTRA_CALL_ID,      callId)
                putExtra(EXTRA_CALL_UUID,    intent.getStringExtra(EXTRA_CALL_UUID) ?: "")
                putExtra(EXTRA_CALLER_ID,    intent.getStringExtra(EXTRA_CALLER_ID) ?: "")
                putExtra(EXTRA_CALLER_NAME,  intent.getStringExtra(EXTRA_CALLER_NAME) ?: "")
                putExtra(EXTRA_CALLER_AVATAR,intent.getStringExtra(EXTRA_CALLER_AVATAR) ?: "")
                putExtra("type",             intent.getStringExtra(EXTRA_CALL_TYPE) ?: "video")
                putExtra("is_random",        intent.getStringExtra(EXTRA_IS_RANDOM) ?: "false")
            }
            context.startActivity(mainIntent)
        }
    }
}
