import 'dart:async';
import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:love_vibe_pro/core/theme.dart';
import 'package:love_vibe_pro/screens/start_screen.dart';
import 'package:love_vibe_pro/providers/auth_provider.dart';
import 'package:love_vibe_pro/services/settings_store.dart';
import 'package:love_vibe_pro/services/user_prefs_cache.dart';
import 'package:love_vibe_pro/services/onesignal_service.dart';
import 'package:love_vibe_pro/services/call_channel_service.dart';
import 'package:love_vibe_pro/services/deep_link_service.dart';
import 'package:love_vibe_pro/screens/auth/login_screen.dart';
import 'package:love_vibe_pro/services/wallet_service.dart';
import 'package:love_vibe_pro/services/fcm_service.dart';
import 'package:love_vibe_pro/services/ad_service.dart';
import 'package:love_vibe_pro/services/analytics_service.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      // Register call channel handler immediately so native invoke from
      // cold-start notification isn't dropped before the 5s deferred init.
      CallChannelService.init();

      // Deep link handler must be initialised as early as possible — before
      // the first frame — so the initial link from a cold-start browser tap is
      // still in the AppLinks queue when we call getInitialLink(). Deferring
      // this (e.g. with a 4-second delay) causes the link to expire, and the
      // app opens to the home screen instead of the target post/profile.
      // The navigator key is registered here even though the navigator isn't
      // mounted yet; DeepLinkService queues the URI and retries each frame
      // until currentState is non-null.
      DeepLinkService.instance.init(navigatorKey);

      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarIconBrightness: Brightness.light,
        ),
      );

      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

      PaintingBinding.instance.imageCache.maximumSize = 80;
      PaintingBinding.instance.imageCache.maximumSizeBytes = 25 << 20;

      // Start Firebase init in parallel — don't block the first frame.
      final firebaseFuture = Firebase.initializeApp();

      // Render the first frame immediately so the native splash transitions
      // to Flutter's splash with zero black gap.
      runApp(const LoveVibeProApp());

      // Release the native splash only after the first GPU frame is on screen.
      // addPostFrameCallback fires after Dart build but before GPU commit,
      // leaving a 1-2 frame black gap. waitUntilFirstFrameRasterized waits
      // for the actual rasterization so the transition is seamless.
      WidgetsBinding.instance.waitUntilFirstFrameRasterized.then((_) {
        if (defaultTargetPlatform == TargetPlatform.android) {
          const MethodChannel('com.nex.ekloapp/splash')
              .invokeMethod<void>('flutterReady');
        }
      });

      // Wire navigator key to AuthProvider after first frame so background
      // token invalidation can redirect to /login.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = navigatorKey.currentContext;
        if (ctx != null) {
          try {
            Provider.of<AuthProvider>(ctx, listen: false)
                .setNavigatorKey(navigatorKey);
          } catch (_) {}
        }
      });

      // Register the FCM background handler once Firebase finishes.
      // This completes well within the Flutter splash duration so FCM
      // is ready before the user can interact with the app.
      firebaseFuture.then((_) {
        FirebaseMessaging.onBackgroundMessage(fcmBackgroundMessageHandler);
      }).catchError((_) {});

      // Defer non-critical startup work after first frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(milliseconds: 500), () async {
          try {
            await UserPrefsCache.instance.init();
          } catch (_) {}
          AdService.instance.init().catchError((_) {});
          AnalyticsService.instance.init();
          _deferBackgroundInit();
        });
      });
    },
    (error, stack) {
      // Silently swallow stale keep-alive connection errors from dart:io HttpClient.
      if (error is HttpException &&
          error.message.contains('Unexpected response')) {
        return;
      }
      FlutterError.reportError(
        FlutterErrorDetails(exception: error, stack: stack),
      );
    },
  );
}

void _deferBackgroundInit() {
  Future.delayed(const Duration(seconds: 4), _initServices);
}

void _initServices() async {
  // Note: CallChannelService and DeepLinkService are already initialised in
  // main() before the first frame to avoid cold-start race conditions.

  try {
    final settings = await SettingsStore.getInstance();
    settings.fetchAndCacheSettings();
  } catch (_) {}

  Future.delayed(const Duration(seconds: 1), () async {
    try {
      await OneSignalService().initFromBackend();
    } catch (_) {}
  });

  // Log daily app open for referral activity tracking (fire-and-forget)
  WalletService().logDailyActivity().catchError((_) {});
}

class LoveVibeProApp extends StatelessWidget {
  const LoveVibeProApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
      ],
      child: MaterialApp(
        navigatorKey: navigatorKey,
        title: 'Goreto',
        debugShowCheckedModeBanner: false,
        theme: GalacticTheme.themeData,
        color: const Color(0xFF05030A),
        builder: (context, child) => MediaQuery(
          data:
              MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
          child: child!,
        ),
        home: const StartScreen(),
        routes: {'/login': (context) => const LoginScreen()},
      ),
    );
  }
}
