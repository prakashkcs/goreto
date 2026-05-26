import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:love_vibe_pro/config/app_env.dart';

class BackgroundLocationService {
  static final BackgroundLocationService _instance = BackgroundLocationService._internal();

  factory BackgroundLocationService() {
    return _instance;
  }

  BackgroundLocationService._internal();

  Future<void> initializeService() async {
    final service = FlutterBackgroundService();

    // Request battery optimization exemption on Android 13+/15
    // This MUST run before the isRunning check so it triggers on every app launch
    // We use a direct Android ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS intent
    // because permission_handler silently succeeds without actually prompting
    if (Platform.isAndroid) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final alreadyAsked = prefs.getBool('battery_optimization_asked') ?? false;
        if (!alreadyAsked) {
          // Use process to launch the battery settings intent
          // This opens the system dialog "Allow app to always run in background?"
          await _requestBatteryOptimizationExemption();
          await prefs.setBool('battery_optimization_asked', true);
        }
      } catch (e) {
      }
    }

    // Ensure we are not initializing multiple times
    final isRunning = await service.isRunning();
    if (isRunning) return;

    // Optional: configuration for local notification channel
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'location_service',
      'Location Tracking',
      description: 'Tracks user location to provide nearby notifications even when the app is closed.',
      importance: Importance.low,
    );

    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
        FlutterLocalNotificationsPlugin();

    if (DateTime.now().year > 2000) { // Just a dummy check, we should ensure the platform is Android
       try {
           await flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.createNotificationChannel(channel);
       } catch (e) {
       }
    }

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: true,
        isForegroundMode: true,
        autoStartOnBoot: true,
        notificationChannelId: 'location_service',
        initialNotificationTitle: 'Love Vibe',
        initialNotificationContent: 'Connecting to nearby locals...',
        foregroundServiceNotificationId: 888,
        foregroundServiceTypes: [AndroidForegroundType.location],
      ),
      iosConfiguration: IosConfiguration(
        autoStart: true,
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
    );
    
    // Start the service
    service.startService();
  }

  /// Fires the native Android ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS intent
  /// This shows the system dialog: "Allow this app to always run in background?"
  Future<void> _requestBatteryOptimizationExemption() async {
    try {
      const intent = AndroidIntent(
        action: 'android.settings.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS',
        data: 'package:com.nex.ekloapp',
      );
      await intent.launch();
    } catch (e) {
    }
  }
}

// iOS specific background fetch handler
@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  return true;
}

// Entry point for the background service
@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  WidgetsFlutterBinding.ensureInitialized();

  // Listen to UI-to-Service requests if needed
  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });

    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
  }

  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  // Set up a location stream to dispatch immediately when user moves ~15 meters
  const LocationSettings locationSettings = LocationSettings(
    accuracy: LocationAccuracy.high,
    distanceFilter: 15,
  );

  Geolocator.getPositionStream(locationSettings: locationSettings).listen(
    (Position position) async {
      await _performBackgroundLocationPingWithPos(position);
    },
  );

  // Execute a fallback location update every 2 minutes in background
  Timer.periodic(const Duration(minutes: 2), (timer) async {
    await _performBackgroundLocationPing();
  });
  
  // Also kick off an initial ping right on start
  await _performBackgroundLocationPing();
}

Future<void> _performBackgroundLocationPingWithPos(Position pos) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    if (token == null || token.isEmpty) return; // Not logged in

    final dio = Dio();
    dio.options.headers['Authorization'] = 'Bearer $token';

    final response = await dio.post(
      '${AppEnv.liveBaseUrl}/match_profiles.php',
      queryParameters: {'action': 'update_location'},
      data: {
        'lat': pos.latitude,
        'lng': pos.longitude,
      },
      options: Options(
        responseType: ResponseType.plain,
        sendTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
      ),
    );

  } catch (e) {
  }
}

Future<void> _performBackgroundLocationPing() async {
  try {
    
    // 1. Is service enabled?
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    // 2. Check permission
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
      return;
    }

    // 3. Fetch token from storage
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    if (token == null || token.isEmpty) {
      return; // Not logged in
    }

    // 4. Get Position
    final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.medium);
    
    // 5. Send to Server via Dio directly
    final dio = Dio();
    dio.options.headers['Authorization'] = 'Bearer $token';

    final response = await dio.post(
      '${AppEnv.liveBaseUrl}/match_profiles.php',
      queryParameters: {'action': 'update_location'},
      data: {
        'lat': pos.latitude,
        'lng': pos.longitude,
      },
      options: Options(
        responseType: ResponseType.plain,
        sendTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
      ),
    );

  } catch (e) {
  }
}
