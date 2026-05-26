import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';
import 'package:love_vibe_pro/services/api_service.dart';
import 'package:love_vibe_pro/config/app_env.dart';
import 'package:love_vibe_pro/services/fcm_service.dart';

/// Wraps OneSignal SDK initialisation and player-ID sync to the backend.
/// Call [OneSignalService.init] once after Firebase is ready (in main.dart).
class OneSignalService {
  static final OneSignalService _instance = OneSignalService._internal();
  factory OneSignalService() => _instance;
  OneSignalService._internal();

  bool _initialized = false;

  /// Fetches the OneSignal App ID from the backend then calls [init].
  Future<void> initFromBackend() async {
    try {
      final baseUrl = await AppEnv.getBaseUrlAsync();
      final dio = Dio(BaseOptions(
          baseUrl: baseUrl, connectTimeout: const Duration(seconds: 8)));
      final resp = await dio.get('api_notifications_config.php');
      final appId = (resp.data is Map ? resp.data['onesignal_app_id'] : null)
              as String? ??
          '';
      await init(appId);
    } catch (_) {}
  }

  /// [appId] is fetched from the backend notification_settings table at runtime.
  /// Pass an empty string to skip initialisation (OneSignal not configured yet).
  Future<void> init(String appId) async {
    if (appId.isEmpty || _initialized) return;

    OneSignal.Debug.setLogLevel(OSLogLevel.none);
    OneSignal.initialize(appId);

    // Request notification permission (Android 13+ / iOS)
    await OneSignal.Notifications.requestPermission(true);

    // Listen for subscription changes and sync player ID to backend
    OneSignal.User.pushSubscription.addObserver((state) {
      final playerId = state.current.id;
      if (playerId != null && playerId.isNotEmpty) {
        _syncPlayerIdToServer(playerId);
      }
    });

    // Sync immediately if already subscribed
    final playerId = OneSignal.User.pushSubscription.id;
    if (playerId != null && playerId.isNotEmpty) {
      await _syncPlayerIdToServer(playerId);
    }

    // Handle notification tapped (from system tray — app in background or killed)
    OneSignal.Notifications.addClickListener((event) {
      final raw = event.notification.additionalData;
      if (raw == null || raw.isEmpty) return;

      // Normalise to Map<String, dynamic>
      final data = Map<String, dynamic>.from(raw);

      // Merge title/body so routing helpers can read them if needed
      data['title'] ??= event.notification.title ?? '';
      data['body'] ??= event.notification.body ?? '';

      // Reuse the exact same routing logic as FCM
      handleNotificationData(data, isFromTap: true);
    });

    // Handle notification received while app is in foreground
    OneSignal.Notifications.addForegroundWillDisplayListener((event) {
      // Let OneSignal display it in the tray even when app is open,
      // then also route it in-app via the existing FCM handler.
      event.notification.display();
      final raw = event.notification.additionalData;
      if (raw != null && raw.isNotEmpty) {
        final data = Map<String, dynamic>.from(raw);
        data['title'] ??= event.notification.title ?? '';
        data['body'] ??= event.notification.body ?? '';
        handleNotificationData(data, isFromTap: false);
      }
    });

    _initialized = true;
  }

  Future<void> _syncPlayerIdToServer(String playerId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final authToken =
          prefs.getString('auth_token') ?? prefs.getString('app_token');
      if (authToken == null || authToken.isEmpty) return;

      final dio = await ApiService().getDioClient();
      await dio.post(
        'api_auth.php',
        data: {
          'action': 'update_onesignal_player_id',
          'player_id': playerId,
        },
        options: Options(
          headers: {'Authorization': 'Bearer $authToken'},
          responseType: ResponseType.plain,
        ),
      );
    } catch (_) {}
  }

  /// Call after login to re-sync the player ID with the newly authenticated user.
  Future<void> syncAfterLogin() async {
    final playerId = OneSignal.User.pushSubscription.id;
    if (playerId != null && playerId.isNotEmpty) {
      await _syncPlayerIdToServer(playerId);
    }
  }

  /// Opt the user out of OneSignal notifications (e.g. on logout).
  void optOut() {
    try {
      OneSignal.User.pushSubscription.optOut();
    } catch (_) {}
  }

  /// Opt back in (e.g. on login).
  void optIn() {
    try {
      OneSignal.User.pushSubscription.optIn();
    } catch (_) {}
  }
}
