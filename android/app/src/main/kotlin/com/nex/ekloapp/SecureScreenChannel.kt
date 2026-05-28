package com.nex.ekloapp

import android.app.Activity
import android.view.WindowManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * MethodChannel bridge for toggling FLAG_SECURE on the window. Flutter calls
 * `setSecure(true)` while a subscriber-only post is visible to a paying
 * subscriber and `setSecure(false)` when the user navigates away.
 *
 * FLAG_SECURE is a per-window flag — adding it stops screenshots, screen
 * recording, and prevents the app's surfaces from showing on non-secure
 * external displays. Removing it restores normal behavior immediately.
 *
 * The flag is reference-counted on the Dart side because multiple subscriber
 * widgets can be on-screen at once. We just trust whatever the Dart side
 * sends; reverting on every visible-content disappearance keeps the OFF state
 * sticky if a stale ON request races a screen change.
 */
object SecureScreenChannel {

    private const val CHANNEL = "com.nex.ekloapp/secure"

    fun register(engine: FlutterEngine, activity: Activity) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setSecure" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        activity.runOnUiThread {
                            try {
                                if (enabled) {
                                    activity.window.addFlags(
                                        WindowManager.LayoutParams.FLAG_SECURE,
                                    )
                                } else {
                                    activity.window.clearFlags(
                                        WindowManager.LayoutParams.FLAG_SECURE,
                                    )
                                }
                                result.success(true)
                            } catch (e: Exception) {
                                result.error("SECURE_FAILED", e.message, null)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
