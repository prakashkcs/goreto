package com.nex.ekloapp

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.telecom.Connection
import android.telecom.ConnectionRequest
import android.telecom.ConnectionService
import android.telecom.DisconnectCause
import android.telecom.PhoneAccount
import android.telecom.PhoneAccountHandle
import android.telecom.TelecomManager

/**
 * Telecom ConnectionService — registers Goreto as a phone account so incoming
 * calls can be presented through the native Android call UI instead of a
 * custom in-app activity.
 *
 * Why this matters: regular notifications + full-screen intents are subject to
 * doze, app-standby buckets, and OEM "kill background" policies. A call routed
 * through TelecomManager.addNewIncomingCall is treated by the OS as a
 * first-class telephony event — the same code path WhatsApp/Messenger use to
 * survive aggressive battery managers.
 *
 * Requires:
 *   - Manifest permission MANAGE_OWN_CALLS
 *   - Service declared in manifest with BIND_TELECOM_CONNECTION_SERVICE
 *     permission and TELECOM_CONNECTION_SERVICE intent filter
 *   - Phone account registered via [register] (idempotent; safe to call on
 *     every app launch)
 *   - User has explicitly enabled the phone account in Settings → Phone →
 *     Calling Accounts (or the equivalent Telecom screen on the OEM)
 *
 * Falls back gracefully: if [addIncomingCall] fails for any reason (account
 * not enabled, OEM bug, denied permission), the caller can revert to the
 * notification+IncomingCallActivity path.
 */
class EkloConnectionService : ConnectionService() {

    override fun onCreateIncomingConnection(
        connectionManagerPhoneAccount: PhoneAccountHandle?,
        request: ConnectionRequest?
    ): Connection {
        val extras = request?.extras ?: Bundle()
        // Telecom hands us the *outer* extras Bundle. The per-call payload we
        // packed into EXTRA_INCOMING_CALL_EXTRAS lives one level deeper.
        val inner = extras.getBundle(TelecomManager.EXTRA_INCOMING_CALL_EXTRAS) ?: extras
        val callerName = inner.getString(EXTRA_CALLER_NAME) ?: "Unknown"
        val callerAvatar = inner.getString(EXTRA_CALLER_AVATAR) ?: ""
        val callId = inner.getString(EXTRA_CALL_ID) ?: "0"
        val callUuid = inner.getString(EXTRA_CALL_UUID) ?: ""
        val callerId = inner.getString(EXTRA_CALLER_ID) ?: ""
        val callType = inner.getString(EXTRA_CALL_TYPE) ?: "video"
        val isRandom = inner.getString(EXTRA_IS_RANDOM) ?: "false"

        val connection = EkloConnection(
            applicationContext,
            callerName = callerName,
            callerAvatar = callerAvatar,
            callId = callId,
            callUuid = callUuid,
            callerId = callerId,
            callType = callType,
            isRandom = isRandom,
        ).also {
            it.setRinging()
            it.setCallerDisplayName(callerName, TelecomManager.PRESENTATION_ALLOWED)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                it.connectionProperties = Connection.PROPERTY_SELF_MANAGED
            }
        }

        // Self-managed Telecom connections don't get a system call UI — the
        // app is responsible for showing one. Launch IncomingCallActivity now
        // so the user sees a ringing screen the moment Telecom accepts the
        // incoming-call notification. This is the same screen the legacy
        // notification fallback path would launch.
        try {
            val activityIntent = IncomingCallActivity.createIntent(
                applicationContext,
                mapOf(
                    "caller_name" to callerName,
                    "caller_avatar" to callerAvatar,
                    "type" to callType,
                    "call_id" to callId,
                    "call_uuid" to callUuid,
                    "caller_id" to callerId,
                    "is_random" to isRandom,
                ),
            )
            applicationContext.startActivity(activityIntent)
        } catch (_: Exception) {
            // If the OS blocked the background activity launch (rare on
            // Telecom-routed calls because the Connection itself is a
            // foreground signal), the user can still answer via the
            // headset / notification surface that the OS draws on its own.
        }

        return connection
    }

    override fun onCreateIncomingConnectionFailed(
        connectionManagerPhoneAccount: PhoneAccountHandle?,
        request: ConnectionRequest?
    ) {
        // Telecom rejected the incoming call. Caller will fall back to the
        // notification path on the next FCM (we just log and let go here).
    }

    companion object {
        // Bundle keys for the extras handed to addNewIncomingCall.
        const val EXTRA_CALLER_NAME = "com.nex.ekloapp.CALLER_NAME"
        const val EXTRA_CALLER_AVATAR = "com.nex.ekloapp.CALLER_AVATAR"
        const val EXTRA_CALL_ID = "com.nex.ekloapp.CALL_ID"
        const val EXTRA_CALL_UUID = "com.nex.ekloapp.CALL_UUID"
        const val EXTRA_CALLER_ID = "com.nex.ekloapp.CALLER_ID"
        const val EXTRA_CALL_TYPE = "com.nex.ekloapp.CALL_TYPE"
        const val EXTRA_IS_RANDOM = "com.nex.ekloapp.IS_RANDOM"

        private const val PHONE_ACCOUNT_ID = "goreto_self_managed"
        private const val PHONE_ACCOUNT_LABEL = "Goreto"

        /**
         * Build the [PhoneAccountHandle] this app uses. Same id every call so
         * registration is idempotent and Telecom can resolve us by handle.
         */
        fun phoneAccountHandle(context: Context): PhoneAccountHandle {
            return PhoneAccountHandle(
                ComponentName(context, EkloConnectionService::class.java),
                PHONE_ACCOUNT_ID,
            )
        }

        /**
         * Register the Goreto phone account with the system. Safe to call
         * repeatedly — Telecom de-dupes on the handle. Self-managed accounts
         * (Android 8.1+) don't require the user to flip a Settings toggle;
         * the OS just trusts the registration and routes calls to us.
         */
        fun register(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O_MR1) return
            try {
                val tm = context.getSystemService(Context.TELECOM_SERVICE) as TelecomManager
                val handle = phoneAccountHandle(context)
                val account = PhoneAccount.builder(handle, PHONE_ACCOUNT_LABEL)
                    .setCapabilities(
                        PhoneAccount.CAPABILITY_SELF_MANAGED or
                            PhoneAccount.CAPABILITY_VIDEO_CALLING or
                            PhoneAccount.CAPABILITY_SUPPORTS_VIDEO_CALLING
                    )
                    .setShortDescription("Goreto voice & video calls")
                    .build()
                tm.registerPhoneAccount(account)
            } catch (_: Exception) {
                // Some OEMs throw SecurityException even with the right permission;
                // we fall through and rely on the notification fallback.
            }
        }

        /**
         * Hand the incoming call to Telecom. Returns true if Telecom accepted
         * the request; false means the caller should fall back to its own
         * notification flow.
         */
        fun addIncomingCall(context: Context, data: Map<String, String>): Boolean {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O_MR1) return false
            return try {
                val tm = context.getSystemService(Context.TELECOM_SERVICE) as TelecomManager
                val extras = Bundle().apply {
                    val callerId = data["caller_id"] ?: ""
                    // Telecom requires a Uri to address the call; we synthesize
                    // one from the caller id since we're self-managed.
                    putParcelable(
                        TelecomManager.EXTRA_INCOMING_CALL_ADDRESS,
                        Uri.fromParts("goreto", callerId, null),
                    )
                    val callerData = Bundle().apply {
                        putString(EXTRA_CALLER_NAME, data["caller_name"] ?: data["caller_full_name"] ?: "Unknown")
                        putString(EXTRA_CALLER_AVATAR, data["caller_avatar"] ?: "")
                        putString(EXTRA_CALL_ID, data["call_id"] ?: "0")
                        putString(EXTRA_CALL_UUID, data["call_uuid"] ?: "")
                        putString(EXTRA_CALLER_ID, callerId)
                        putString(EXTRA_CALL_TYPE, data["type"] ?: "video")
                        putString(EXTRA_IS_RANDOM, data["is_random"] ?: "false")
                    }
                    putBundle(TelecomManager.EXTRA_INCOMING_CALL_EXTRAS, callerData)
                }
                tm.addNewIncomingCall(phoneAccountHandle(context), extras)
                true
            } catch (_: SecurityException) {
                false
            } catch (_: Exception) {
                false
            }
        }
    }
}

/**
 * Per-call Telecom Connection. Bridges Telecom's accept/decline events back
 * into Goreto's flow by launching [MainActivity] with the same accept_call /
 * decline_call extras the notification path uses, so Dart sees a single
 * unified event regardless of which UI surfaced the call.
 */
private class EkloConnection(
    private val context: Context,
    private val callerName: String,
    private val callerAvatar: String,
    private val callId: String,
    private val callUuid: String,
    private val callerId: String,
    private val callType: String,
    private val isRandom: String,
) : Connection() {

    init {
        setConnectionProperties(PROPERTY_SELF_MANAGED)
        audioModeIsVoip = true
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            connectionCapabilities = CAPABILITY_HOLD or CAPABILITY_MUTE
        }
    }

    override fun onAnswer() {
        forwardToFlutter("accept_call")
        setActive()
    }

    override fun onAnswer(videoState: Int) {
        forwardToFlutter("accept_call")
        setActive()
    }

    override fun onReject() {
        forwardToFlutter("decline_call")
        setDisconnected(DisconnectCause(DisconnectCause.REJECTED))
        destroy()
    }

    override fun onDisconnect() {
        setDisconnected(DisconnectCause(DisconnectCause.LOCAL))
        destroy()
    }

    override fun onAbort() {
        setDisconnected(DisconnectCause(DisconnectCause.OTHER))
        destroy()
    }

    private fun forwardToFlutter(action: String) {
        try {
            val intent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP
                putExtra("action", action)
                putExtra("call_id", callId)
                putExtra("call_uuid", callUuid)
                putExtra("caller_id", callerId)
                putExtra("caller_name", callerName)
                putExtra("caller_avatar", callerAvatar)
                putExtra("type", callType)
                putExtra("is_random", isRandom)
            }
            context.startActivity(intent)
        } catch (_: Exception) {}
    }
}
