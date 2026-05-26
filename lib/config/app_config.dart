import 'package:shared_preferences/shared_preferences.dart';

enum ApiMode {
  emulator,
  device,
  live,
}

class AppConfig {
  static const String _apiModeKey = 'api_mode';

  static const String emulatorBaseUrl = 'https://goreto.org/ekloadmin/api/v1';
  // IMPORTANT: Replace with your actual LAN IP for device testing
  static const String deviceBaseUrl =
      'http://<YOUR_LAN_IP_HERE>/ekloadmin/api/v1';
  static const String liveBaseUrl = 'https://goreto.org/ekloadmin/api/v1';

  static Future<ApiMode> _getApiMode() async {
    final prefs = await SharedPreferences.getInstance();
    final apiModeString =
        prefs.getString(_apiModeKey) ?? ApiMode.live.toString();
    return ApiMode.values.firstWhere(
      (e) => e.toString() == apiModeString,
      orElse: () => ApiMode.live,
    );
  }

  static Future<String> getBaseUrl() async {
    final apiMode = await _getApiMode();
    switch (apiMode) {
      case ApiMode.emulator:
        return emulatorBaseUrl;
      case ApiMode.device:
        return deviceBaseUrl;
      case ApiMode.live:
        return liveBaseUrl;
    }
  }

  static Future<void> setApiMode(ApiMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_apiModeKey, mode.toString());
  }
}
