package com.nex.ekloapp

import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.WindowManager
import android.widget.Button
import android.widget.ImageView
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import java.net.URL
import java.util.concurrent.Executors

class NearbyAlertActivity : AppCompatActivity() {

    companion object {
        const val EXTRA_SENDER_ID     = "sender_id"
        const val EXTRA_SENDER_NAME   = "sender_name"
        const val EXTRA_SENDER_AVATAR = "sender_avatar"

        fun createIntent(context: Context, data: Map<String, String>): Intent {
            return Intent(context, NearbyAlertActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_NO_USER_ACTION or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP
                putExtra(EXTRA_SENDER_ID,     data["sender_id"]     ?: "")
                putExtra(EXTRA_SENDER_NAME,   data["sender_name"]   ?: "Someone")
                putExtra(EXTRA_SENDER_AVATAR, data["sender_avatar"] ?: "")
            }
        }
    }

    private val executor = Executors.newSingleThreadExecutor()
    private val handler  = Handler(Looper.getMainLooper())

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Show over lock screen and wake the display
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                        WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                        WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
            )
        }

        setContentView(R.layout.activity_nearby_alert)

        val senderId     = intent.getStringExtra(EXTRA_SENDER_ID)     ?: ""
        val senderName   = intent.getStringExtra(EXTRA_SENDER_NAME)   ?: "Someone"
        val senderAvatar = intent.getStringExtra(EXTRA_SENDER_AVATAR) ?: ""

        findViewById<TextView>(R.id.tvSenderName).text = senderName

        // Load avatar in background
        if (senderAvatar.isNotEmpty()) {
            executor.execute {
                try {
                    val bmp = BitmapFactory.decodeStream(URL(senderAvatar).openStream())
                    handler.post {
                        findViewById<ImageView>(R.id.ivSenderAvatar).setImageBitmap(bmp)
                        findViewById<ImageView>(R.id.ivBackground).setImageBitmap(bmp)
                    }
                } catch (_: Exception) {}
            }
        }

        // "View Profile & Connect" → open app and navigate to NearbyAlertScreen
        findViewById<Button>(R.id.btnConnect).setOnClickListener {
            val mainIntent = Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP
                putExtra("action",         "open_nearby_alert")
                putExtra("sender_id",      senderId)
                putExtra("sender_name",    senderName)
                putExtra("sender_avatar",  senderAvatar)
            }
            startActivity(mainIntent)
            dismissNotification()
            finish()
        }

        // "Ignore" → dismiss
        findViewById<Button>(R.id.btnIgnore).setOnClickListener {
            dismissNotification()
            finish()
        }

        // Close button (top-left)
        findViewById<android.widget.FrameLayout>(R.id.btnClose).setOnClickListener {
            dismissNotification()
            finish()
        }

        // Auto-dismiss after 30 s
        handler.postDelayed({
            if (!isFinishing) {
                dismissNotification()
                finish()
            }
        }, 30_000)
    }

    private fun dismissNotification() {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.cancel(CallFirebaseMessagingService.NEARBY_NOTIFICATION_ID)
    }

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        super.onDestroy()
        executor.shutdown()
    }
}
