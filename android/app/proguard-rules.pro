# Flutter engine
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# Kotlin
-keep class kotlin.** { *; }
-keep class kotlin.Metadata { *; }
-dontwarn kotlin.**
-keepclassmembers class **$WhenMappings { <fields>; }
-keepclassmembers class kotlin.Metadata {
    public <methods>;
}

# App classes (FCM service, call activity, etc.)
-keep class com.nex.ekloapp.** { *; }

# Firebase / Google Play Services
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# OkHttp / Okio (used by Dio under the hood on some paths)
-dontwarn okhttp3.**
-dontwarn okio.**
-keep class okhttp3.** { *; }
-keep class okio.** { *; }

# WebRTC
-keep class org.webrtc.** { *; }
-dontwarn org.webrtc.**

# Agora RTC
-keep class io.agora.** { *; }
-dontwarn io.agora.**

# Zego
-keep class im.zego.** { *; }
-dontwarn im.zego.**

# SQLite / SQLCipher (sqflite)
-keep class net.sqlcipher.** { *; }
-dontwarn net.sqlcipher.**

# flutter_secure_storage (Android Keystore backed)
-keep class com.it_nomads.fluttersecurestorage.** { *; }

# Strip verbose logs from release
-assumenosideeffects class android.util.Log {
    public static boolean isLoggable(java.lang.String, int);
    public static int v(...);
    public static int d(...);
    public static int i(...);
    public static int w(...);
    public static int e(...);
}
