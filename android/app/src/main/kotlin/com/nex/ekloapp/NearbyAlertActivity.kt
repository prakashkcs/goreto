package com.nex.ekloapp

import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.Vibrator
import android.os.VibratorManager
import android.speech.tts.TextToSpeech
import android.view.WindowManager
import android.widget.Button
import android.widget.ImageView
import android.widget.TextView
import android.app.Activity
import java.net.URL
import java.util.Locale
import java.util.concurrent.Executors

class NearbyAlertActivity : Activity() {

    companion object {
        const val EXTRA_SENDER_ID     = "sender_id"
        const val EXTRA_SENDER_NAME   = "sender_name"
        const val EXTRA_SENDER_AVATAR = "sender_avatar"

        const val EXTRA_DISTANCE = "sender_distance"

        fun createIntent(context: Context, data: Map<String, String>): Intent {
            return Intent(context, NearbyAlertActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_NO_USER_ACTION or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP
                putExtra(EXTRA_SENDER_ID,     data["sender_id"]     ?: "")
                putExtra(EXTRA_SENDER_NAME,   data["sender_name"]   ?: "Someone")
                putExtra(EXTRA_SENDER_AVATAR, data["sender_avatar"] ?: "")
                putExtra(EXTRA_DISTANCE,      data["distance"]      ?: data["sender_distance"] ?: "")
            }
        }
    }

    private val executor = Executors.newSingleThreadExecutor()
    private val handler  = Handler(Looper.getMainLooper())
    private var ringPlayer: MediaPlayer? = null
    private var tts: TextToSpeech? = null

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
        val distance     = intent.getStringExtra(EXTRA_DISTANCE)      ?: ""

        findViewById<TextView>(R.id.tvSenderName).text = senderName

        // Show distance in subtitle when available
        val distView = findViewById<TextView>(R.id.tvDistance)
        distView.text = when {
            distance.isNotEmpty() -> "is $distance away from you"
            else                  -> "is near you right now"
        }

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

        // "Say Hi" — full-width green pill button
        findViewById<Button>(R.id.btnConnect).setOnClickListener {
            stopRing()
            stopVoice()
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

        // "Not now" — outlined secondary pill
        findViewById<Button>(R.id.btnIgnore).setOnClickListener {
            stopRing()
            stopVoice()
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
                stopRing()
                dismissNotification()
                finish()
            }
        }, 30_000)

        // Ring once we're fully on-screen
        startRing()

        // Announce the person's name out loud (works even when the app is
        // killed / the device is locked — this is a native Activity, not Dart).
        startVoiceAnnouncement(senderName)
    }

    /**
     * Speaks "<name> tapai ko najik hununcha" (romanized Nepali for "<name> is
     * near you") using the device's native TTS engine. Runs over the lock
     * screen with the app fully killed. Spoken twice with a short gap so a
     * sleeping/just-woken user catches the name.
     */
    private fun startVoiceAnnouncement(name: String) {
        val phrase = "$name tapai ko najik hununcha"
        try {
            tts = TextToSpeech(applicationContext) { status ->
                if (status != TextToSpeech.SUCCESS) return@TextToSpeech
                val engine = tts ?: return@TextToSpeech
                try {
                    // English voice pronounces the romanized Nepali phrase
                    // phonetically; most devices lack a Nepali (Devanagari) voice.
                    engine.language = Locale.ENGLISH
                    // Route speech through the ringtone stream so it is audible
                    // on the lock screen even when media volume is muted.
                    engine.setAudioAttributes(
                        AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                            .build()
                    )
                    engine.setSpeechRate(0.95f)
                    engine.speak(phrase, TextToSpeech.QUEUE_FLUSH, null, "nearby_voice_1")
                    engine.playSilentUtterance(700, TextToSpeech.QUEUE_ADD, "nearby_voice_gap")
                    engine.speak(phrase, TextToSpeech.QUEUE_ADD, null, "nearby_voice_2")
                } catch (_: Exception) {}
            }
        } catch (_: Exception) {}
    }

    private fun stopVoice() {
        try {
            tts?.stop()
            tts?.shutdown()
        } catch (_: Exception) {}
        tts = null
    }

    private fun startRing() {
        try {
            val attrs = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
            ringPlayer = MediaPlayer().apply {
                setAudioAttributes(attrs)
                val afd = resources.openRawResourceFd(R.raw.nearby)
                setDataSource(afd.fileDescriptor, afd.startOffset, afd.length)
                afd.close()
                isLooping = true
                // Lower the ring so the spoken name stays intelligible over it.
                setVolume(0.4f, 0.4f)
                prepare()
                start()
            }
            // Companion vibrate pattern
            val vib = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                (getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager).defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            }
            val pattern = longArrayOf(0, 250, 100, 250, 100, 250)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vib.vibrate(android.os.VibrationEffect.createWaveform(pattern, -1))
            } else {
                @Suppress("DEPRECATION")
                vib.vibrate(pattern, -1)
            }
        } catch (_: Exception) {}
    }

    private fun stopRing() {
        try {
            ringPlayer?.takeIf { it.isPlaying }?.stop()
            ringPlayer?.release()
        } catch (_: Exception) {}
        ringPlayer = null
    }

    private fun dismissNotification() {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.cancel(CallFirebaseMessagingService.NEARBY_NOTIFICATION_ID)
    }

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        stopRing()
        stopVoice()
        super.onDestroy()
        executor.shutdown()
    }
}
