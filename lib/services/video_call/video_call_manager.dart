import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api_service.dart';
import 'providers/video_call_provider.dart';

// Import providers (to be implemented)
import 'providers/zego_provider.dart';
import 'providers/agora_provider.dart';
import 'providers/dyte_provider.dart';
import 'providers/twilio_provider.dart';

class VideoCallManager {
  static final VideoCallManager _instance = VideoCallManager._internal();
  factory VideoCallManager() => _instance;
  VideoCallManager._internal();

  VideoCallProvider? activeProvider;
  Map<String, dynamic>? activeConfig;

  /// Last error text reported by an SDK (e.g. "Zego code:1002001 LoginFailed").
  /// The live view's onProviderError is a VoidCallback, so the SDK's own
  /// message would otherwise be lost and the server would only ever record a
  /// generic failure. Providers stash the real text here and [reinitialize]
  /// sends it to the admin panel, which is what makes the cause diagnosable
  /// without attaching a phone.
  String? lastProviderError;

  /// Fetches the active video provider from the remote API and initializes it.
  /// [serviceType] is 'call' (1:1/random voice+video calls, the default) or
  /// 'live' (Go Live broadcast) -- each is configured independently in the
  /// admin panel and is very often a different SDK project entirely.
  Future<bool> initialize({
    required String currentUserId,
    required String currentUserName,
    String serviceType = 'call',
  }) async {
    try {
      final apiService = ApiService();
      final dio = await apiService.getDioClient();

      // Base URL is .../ekloadmin/api/v1
      // We need a leading slash if the base URL doesn't have a trailing slash
      final response = await dio.get(
        'api_video_providers.php',
        queryParameters: {'action': 'get_active', 'service_type': serviceType},
        options: Options(responseType: ResponseType.plain),
      );

      // Response received

      dynamic data = response.data;
      if (data is String) {
        data = jsonDecode(data);
      }

      if (data is Map<String, dynamic> && data['status'] == 'success') {
        final providerData = data['provider'];
        if (providerData is! Map<String, dynamic>) {
          return false;
        }

        final providerName = providerData['name']?.toString();
        final appId = providerData['app_id']?.toString();
        final appSign = providerData['app_sign']?.toString();
        final serverSecret = providerData['server_secret']?.toString();

        // Robustly parse config to avoid "type 'List<dynamic>' is not a subtype of type 'Map<String, dynamic>?'"
        final rawConfig = providerData['config'];
        final Map<String, dynamic> config = (rawConfig is Map)
            ? Map<String, dynamic>.from(rawConfig)
            : <String, dynamic>{};

        config['app_id'] = appId;
        config['app_sign'] = appSign; // 64 hex chars for client SDK
        config['server_secret'] = serverSecret; // 32 chars for server API
        config['service_type'] = serviceType; // so providers know which token/config scope to use server-side

        activeConfig = config;

        // Instantiate the correct provider based on server response
        switch (providerName) {
          case 'zego':
            activeProvider = ZegoProvider();
            break;
          case 'agora':
            activeProvider = AgoraProvider();
            break;
          case 'dyte':
            activeProvider = DyteProvider();
            break;
          case 'twilio':
            activeProvider = TwilioProvider();
            break;
          default:
            return false;
        }

        if (activeProvider != null) {
          await activeProvider!.initialize(
            config: config,
            currentUserId: currentUserId,
            currentUserName: currentUserName,
          );
          return true;
        }
      } else {
        // API error handled
      }
      return false;
    } catch (e) {
      if (e is DioException) {}
      return false;
    }
  }

  /// Reports the current provider as failed, requests auto-rotation on the
  /// backend, then re-initializes with the new (or same) provider.
  Future<bool> reinitialize({
    required String currentUserId,
    required String currentUserName,
    String serviceType = 'call',
  }) async {
    if (activeProvider == null) {
      return initialize(
        currentUserId: currentUserId,
        currentUserName: currentUserName,
        serviceType: serviceType,
      );
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      var baseUrl = prefs.getString('api_base_url') ?? 'https://goreto.org/ekloadmin/api/v1/';
      if (!baseUrl.endsWith('/')) baseUrl = '$baseUrl/';
      final dio = Dio(BaseOptions(baseUrl: baseUrl));
      final token = prefs.getString('app_token') ?? prefs.getString('auth_token');
      if (token != null) dio.options.headers['Authorization'] = 'Bearer $token';

      final realError = lastProviderError;
      lastProviderError = null;

      final resp = await dio.get('api_video_providers.php', queryParameters: {
        'action':       'report_error',
        'provider':     activeProvider!.name,
        'error':        realError ?? 'SDK connection failed - requesting rotation',
        'auto_rotate':  '1',
        'service_type': serviceType,
      });

      dynamic data = resp.data;
      if (data is String) data = jsonDecode(data);

      if (data is Map && data['rotated'] == true && data['provider'] is Map) {
        final pd = Map<String, dynamic>.from(data['provider'] as Map);
        return _initFromProviderData(
          providerData:    pd,
          currentUserId:   currentUserId,
          currentUserName: currentUserName,
          serviceType:     serviceType,
        );
      }
    } catch (_) {}

    activeProvider = null;
    activeConfig = null;
    return initialize(
      currentUserId: currentUserId,
      currentUserName: currentUserName,
      serviceType: serviceType,
    );
  }

  Future<bool> _initFromProviderData({
    required Map<String, dynamic> providerData,
    required String currentUserId,
    required String currentUserName,
    String serviceType = 'call',
  }) async {
    final providerName = providerData['name']?.toString();
    final Map<String, dynamic> config = {
      'app_id':        providerData['app_id']?.toString(),
      'app_sign':      providerData['app_sign']?.toString(),
      'server_secret': providerData['server_secret']?.toString(),
      'service_type':  serviceType,
      ...((providerData['config'] is Map)
          ? Map<String, dynamic>.from(providerData['config'] as Map)
          : <String, dynamic>{}),
    };

    VideoCallProvider? provider;
    switch (providerName) {
      case 'zego':   provider = ZegoProvider();   break;
      case 'agora':  provider = AgoraProvider();  break;
      case 'dyte':   provider = DyteProvider();   break;
      case 'twilio': provider = TwilioProvider(); break;
      default: return false;
    }

    await provider.initialize(
      config: config, currentUserId: currentUserId, currentUserName: currentUserName,
    );
    activeProvider = provider;
    activeConfig = config;
    return true;
  }

  /// Called from the client when joining a call fails unexpectedly.
  /// Logs the error on the server so the admin panel shows it.
  Future<void> reportProviderError({
    String error = 'SDK login/connection failed',
    String serviceType = 'call',
  }) async {
    if (activeProvider == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final baseUrl = prefs.getString('api_base_url') ??
          'https://goreto.org/ekloadmin/api/v1/';

      final dio = Dio(BaseOptions(baseUrl: baseUrl));
      final token =
          prefs.getString('app_token') ?? prefs.getString('auth_token');
      if (token != null) {
        dio.options.headers['Authorization'] = 'Bearer $token';
      }

      await dio.get(
        'api_video_providers.php',
        queryParameters: {
          'action':       'report_error',
          'provider':     activeProvider!.name,
          'error':        error,
          'service_type': serviceType,
        },
      );
    } catch (_) {}
  }
}
