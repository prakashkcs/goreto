package com.nex.ekloapp

import android.app.Application

class MainApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        // Create notification channels early so FCM notification+data messages
        // display correctly even when the app is fully killed (Android shows them
        // directly without calling onMessageReceived, using the channel_id from
        // the FCM payload — which must already exist in the system).
        CallFirebaseMessagingService.createAllChannels(this)
    }
}
