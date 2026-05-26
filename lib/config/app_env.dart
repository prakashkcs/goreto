import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppEnvironment { local, live }

class AppEnv {
  // ─── SWITCH ENVIRONMENT HERE ──────────────────────────────────────────────
  static const AppEnvironment _currentEnv = AppEnvironment.live;

  // Replace with your machine's LAN IP if running on a real device
  static const String _lanIp = '192.168.1.100';

  // ──────────────────────────────────────────────────────────────────────────

  /// Default local URL for Android Emulator (uses 10.0.2.2 for localhost)
  static const String emulatorBaseUrl = 'https://goreto.org/ekloadmin/api/v1/';

  /// Default local URL for iOS Simulator / Web
  static const String localBaseUrl = 'http://localhost/ekloadmin/api/v1/';

  /// Live production URL
  static const String liveBaseUrl = 'https://goreto.org/ekloadmin/api/v1/';

  /// Key for SharedPreferences to store custom base URL
  static const String customBaseUrlKey = 'api_base_url';

  /// Get base URL - checks SharedPreferences first, then falls back to environment config
  /// This is a synchronous getter that returns the default URL.
  /// Use getBaseUrlAsync() for async loading of custom URL from SharedPreferences.
  static String get baseUrl {
    return getDefaultUrl();
  }

  /// Async version that checks SharedPreferences for custom URL
  static Future<String> getBaseUrlAsync() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final customUrl = prefs.getString(customBaseUrlKey);
      if (customUrl != null && customUrl.isNotEmpty) {
        return customUrl;
      }
    } catch (_) {}
    return getDefaultUrl();
  }

  /// Synchronous default URL (for initial app load before async prefs)
  static String getDefaultUrl() {
    switch (_currentEnv) {
      case AppEnvironment.local:
        if (kIsWeb) return localBaseUrl;
        if (defaultTargetPlatform == TargetPlatform.android) {
          return emulatorBaseUrl;
        }
        return localBaseUrl;

      case AppEnvironment.live:
        return liveBaseUrl;
    }
  }

  /// Set custom base URL (useful for testing on real device)
  static Future<void> setCustomBaseUrl(String url) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(customBaseUrlKey, url);
    } catch (_) {}
  }

  /// Clear custom base URL and revert to default
  static Future<void> clearCustomBaseUrl() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(customBaseUrlKey);
    } catch (_) {}
  }
}
