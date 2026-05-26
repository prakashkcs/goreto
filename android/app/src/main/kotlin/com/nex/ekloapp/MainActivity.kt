package com.nex.ekloapp

import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val CALL_CHANNEL   = "com.nex.ekloapp/call"
        private const val SPLASH_CHANNEL = "com.nex.ekloapp/splash"
        var pendingCallIntent: Intent? = null
    }

    private var callChannel: MethodChannel? = null
    private var flutterReady = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Dart calls this channel after its first painted frame so we know
        // Flutter's splash is actually on screen before releasing the native splash.
        // FlutterUiDisplayListener fires too early (before runApp / Firebase.init)
        // which caused a black flash.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SPLASH_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "flutterReady") {
                    flutterReady = true
                }
                result.success(null)
            }

        callChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CALL_CHANNEL)
        callChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getPendingCallIntent" -> {
                    val pending = pendingCallIntent
                    if (pending != null) {
                        val action = pending.getStringExtra("action")
                        if (action != null) {
                            val data = mapOf(
                                "action" to action,
                                "call_id" to (pending.getStringExtra("call_id") ?: "0"),
                                "call_uuid" to (pending.getStringExtra("call_uuid") ?: ""),
                                "caller_id" to (pending.getStringExtra("caller_id") ?: ""),
                                "caller_name" to (pending.getStringExtra("caller_name") ?: ""),
                                "caller_avatar" to (pending.getStringExtra("caller_avatar") ?: ""),
                                "type" to (pending.getStringExtra("type") ?: "video"),
                                "is_random" to (pending.getStringExtra("is_random") ?: "false")
                            )
                            pendingCallIntent = null
                            result.success(data)
                        } else {
                            pendingCallIntent = null
                            result.success(null)
                        }
                    } else {
                        result.success(null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        val splashScreen = installSplashScreen()
        // Hold the native splash (plain #05030A background, no icon) until Flutter
        // renders its first frame. Without this, Flutter's first raw black frame
        // flashes between the native splash exit and the Dart splash widget drawing.
        // Exit the native splash on the first vsync. The icon is transparent
        // (splash_blank) so it is invisible. The activity windowBackground
        // (launch_background.xml) shows the app logo immediately instead,
        // and Flutter's SplashScreen picks it up seamlessly.
        splashScreen.setKeepOnScreenCondition { false }
        splashScreen.setOnExitAnimationListener { it.remove() }

        super.onCreate(savedInstanceState)

        window.decorView.setBackgroundColor(Color.parseColor("#05030A"))

        requestFullScreenIntentPermission()
        requestBatteryOptimizationExemption()
        handleCallIntent(intent)
    }

    // Android 14+ requires USE_FULL_SCREEN_INTENT to be granted by the user
    // for the incoming-call full-screen activity to pop up automatically.
    private fun requestFullScreenIntentPermission() {
        if (Build.VERSION.SDK_INT < 34) return
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (nm.canUseFullScreenIntent()) return
        val prefs = getSharedPreferences("app_prefs", Context.MODE_PRIVATE)
        if (prefs.getBoolean("fsi_requested", false)) return
        prefs.edit().putBoolean("fsi_requested", true).apply()
        try {
            startActivity(
                Intent(
                    Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT,
                    Uri.parse("package:$packageName")
                )
            )
        } catch (_: Exception) {}
    }

    private fun requestBatteryOptimizationExemption() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        val pm = getSystemService(Context.POWER_SERVICE) as android.os.PowerManager
        if (pm.isIgnoringBatteryOptimizations(packageName)) return
        val prefs = getSharedPreferences("app_prefs", Context.MODE_PRIVATE)
        if (prefs.getBoolean("battery_opt_requested", false)) return
        prefs.edit().putBoolean("battery_opt_requested", true).apply()
        try {
            startActivity(
                Intent(
                    Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                    Uri.parse("package:$packageName")
                )
            )
        } catch (_: Exception) {}
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleCallIntent(intent)
    }

    private fun handleCallIntent(intent: Intent?) {
        if (intent == null) return
        val action = intent.getStringExtra("action") ?: return

        when (action) {
            "accept_call", "decline_call" -> {
                if (flutterReady && callChannel != null) {
                    val data = mapOf(
                        "action" to action,
                        "call_id" to (intent.getStringExtra("call_id") ?: "0"),
                        "call_uuid" to (intent.getStringExtra("call_uuid") ?: ""),
                        "caller_id" to (intent.getStringExtra("caller_id") ?: ""),
                        "caller_name" to (intent.getStringExtra("caller_name") ?: ""),
                        "caller_avatar" to (intent.getStringExtra("caller_avatar") ?: ""),
                        "type" to (intent.getStringExtra("type") ?: "video"),
                        "is_random" to (intent.getStringExtra("is_random") ?: "false")
                    )
                    callChannel?.invokeMethod("onCallAction", data)
                } else {
                    // Flutter not ready yet — store for Dart's getPendingCallIntent poll
                    pendingCallIntent = intent
                }
            }
        }
    }

    override fun onResume() {
        super.onResume()
    }
}
