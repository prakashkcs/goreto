package com.nex.ekloapp

import android.app.KeyguardManager
import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.BitmapFactory
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.WindowManager
import android.widget.ImageButton
import android.widget.ImageView
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors

class IncomingCallActivity : AppCompatActivity() {

    companion object {
        const val EXTRA_CALLER_NAME = "caller_name"
        const val EXTRA_CALLER_AVATAR = "caller_avatar"
        const val EXTRA_CALL_TYPE = "call_type"
        const val EXTRA_CALL_ID = "call_id"
        const val EXTRA_CALL_UUID = "call_uuid"
        const val EXTRA_CALLER_ID = "caller_id"
        const val EXTRA_IS_RANDOM = "is_random"

        fun createIntent(context: Context, data: Map<String, String>): Intent {
            return Intent(context, IncomingCallActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_NO_USER_ACTION or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP
                putExtra(EXTRA_CALLER_NAME, data["caller_name"] ?: data["caller_full_name"] ?: "Unknown")
                putExtra(EXTRA_CALLER_AVATAR, data["caller_avatar"] ?: "")
                putExtra(EXTRA_CALL_TYPE, data["type"] ?: "video")
                putExtra(EXTRA_CALL_ID, data["call_id"] ?: "0")
                putExtra(EXTRA_CALL_UUID, data["call_uuid"] ?: "")
                putExtra(EXTRA_CALLER_ID, data["caller_id"] ?: "")
                putExtra(EXTRA_IS_RANDOM, data["is_random"] ?: "false")
            }
        }
    }

    private val executor = Executors.newSingleThreadExecutor()
    private val handler = Handler(Looper.getMainLooper())

    // Receives the broadcast sent by CallFirebaseMessagingService when the caller ends the call.
    private val cancelReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            dismissAndFinish()
        }
    }

    private fun dismissAndFinish() {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.cancel(CallFirebaseMessagingService.CALL_NOTIFICATION_ID)
        finish()
    }

    // Polls the server every 2 s so we self-dismiss if the broadcast was missed
    // (e.g. Doze, process restart) and the call is no longer ringing.
    private val statusPoller = object : Runnable {
        override fun run() {
            if (!isFinishing) checkCallStatusAsync()
        }
    }

    private fun checkCallStatusAsync() {
        val callId = intent.getStringExtra(EXTRA_CALL_ID) ?: return
        executor.execute {
            try {
                val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                var baseUrl = prefs.getString("flutter.api_base_url", "https://goreto.org/ekloadmin/api/v1/") ?: "https://goreto.org/ekloadmin/api/v1/"
                if (!baseUrl.endsWith("/")) baseUrl = "$baseUrl/"
                val token = prefs.getString("flutter.app_token", null)
                    ?: prefs.getString("flutter.auth_token", null)
                if (token.isNullOrEmpty()) {
                    scheduleNextPoll()
                    return@execute
                }
                val conn = URL("${baseUrl}signaling.php?action=call_status&call_id=$callId")
                    .openConnection() as HttpURLConnection
                conn.setRequestProperty("Authorization", "Bearer $token")
                conn.setRequestProperty("Accept", "application/json")
                conn.connectTimeout = 3_000
                conn.readTimeout = 3_000
                val body = conn.inputStream.bufferedReader().readText()
                conn.disconnect()
                val status = JSONObject(body).optJSONObject("call")?.optString("status") ?: ""
                if (status.isNotEmpty() && status != "ringing") {
                    handler.post { dismissAndFinish() }
                } else {
                    scheduleNextPoll()
                }
            } catch (_: Exception) {
                scheduleNextPoll()
            }
        }
    }

    private fun scheduleNextPoll() {
        if (!isFinishing) handler.postDelayed(statusPoller, 2_000)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Show over lock screen and turn on screen
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                        WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                        WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                        WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD
            )
        }

        // Dismiss keyguard
        val keyguardManager = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            keyguardManager.requestDismissKeyguard(this, null)
        }

        setContentView(R.layout.activity_incoming_call)

        val callerName = intent.getStringExtra(EXTRA_CALLER_NAME) ?: "Unknown"
        val callerAvatar = intent.getStringExtra(EXTRA_CALLER_AVATAR) ?: ""
        val callType = intent.getStringExtra(EXTRA_CALL_TYPE) ?: "video"
        val callId = intent.getStringExtra(EXTRA_CALL_ID) ?: "0"
        val callUuid = intent.getStringExtra(EXTRA_CALL_UUID) ?: ""
        val callerId = intent.getStringExtra(EXTRA_CALLER_ID) ?: ""
        val isRandom = intent.getStringExtra(EXTRA_IS_RANDOM) ?: "false"

        // Set caller info
        findViewById<TextView>(R.id.tvCallerName).text = callerName
        findViewById<TextView>(R.id.tvCallType).text =
            if (callType == "audio") "Incoming Audio Call" else "Incoming Video Call"

        // Load avatar in background
        if (callerAvatar.isNotEmpty()) {
            executor.execute {
                try {
                    val bitmap = BitmapFactory.decodeStream(URL(callerAvatar).openStream())
                    handler.post {
                        val avatarView = findViewById<ImageView>(R.id.ivCallerAvatar)
                        avatarView?.setImageBitmap(bitmap)
                        // Also set as blurred background
                        val bgView = findViewById<ImageView>(R.id.ivBackground)
                        bgView?.setImageBitmap(bitmap)
                    }
                } catch (e: Exception) {
                    // Keep default avatar
                }
            }
        }

        // Accept button
        findViewById<ImageButton>(R.id.btnAccept).setOnClickListener {
            val mainIntent = Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP
                putExtra("action", "accept_call")
                putExtra("call_id", callId)
                putExtra("call_uuid", callUuid)
                putExtra("caller_id", callerId)
                putExtra("caller_name", callerName)
                putExtra("caller_avatar", callerAvatar)
                putExtra("type", callType)
                putExtra("is_random", isRandom)
            }
            startActivity(mainIntent)
            finish()
        }

        // Decline button
        findViewById<ImageButton>(R.id.btnDecline).setOnClickListener {
            val mainIntent = Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP
                putExtra("action", "decline_call")
                putExtra("call_id", callId)
            }
            startActivity(mainIntent)
            finish()
        }

        // Auto-dismiss after 60 seconds (call timeout)
        handler.postDelayed({ finish() }, 60_000)

        // Start status polling so we self-dismiss if the caller cancels
        scheduleNextPoll()
    }

    override fun onResume() {
        super.onResume()
        // Register broadcast receiver for instant dismissal when caller ends the call
        val filter = IntentFilter("com.nex.ekloapp.CALL_CANCELLED")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(cancelReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(cancelReceiver, filter)
        }
    }

    override fun onPause() {
        super.onPause()
        try { unregisterReceiver(cancelReceiver) } catch (_: Exception) {}
    }

    override fun onDestroy() {
        handler.removeCallbacks(statusPoller)
        super.onDestroy()
        executor.shutdown()
    }
}
